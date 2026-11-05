"""按鍵層的語言辨識（中英混輸「單字表以外」那段，10/29 晚上的實驗；docs/findings.md〈按鍵層語言辨識〉）。

同一串按鍵，比「當英文字母」跟「當中文注音鍵」的機率：
  中文：字逐字取詞典裡比重最高的讀音，轉成大千按鍵，訓練按鍵 5-gram（Witten-Bell 內插，^ 開頭、$ 結尾）。
  英文：wordfreq 的單字，次數 10^(Zipf−3)，字母 5-gram。
模型（.build/keylid/，不進 repo）：
  models.pkl   (純首符號, 純全碼, 英文)
  zhmix.pkl    混打：四成段落純首符號、一成五純全碼帶調、其餘每個字各自抽 首符號 .6／完整不帶調 .25／完整帶調 .15
  zhmix2.pkl   混打＋句尾語氣詞：兩成段落句尾補一個（喔哦啊吧呢嗎啦耶欸齁囉，口語讀音）。教育部辭典是書面語，
               沒有這個時「好了喔」cxi 的 i（ㄛ）會被當成英文
  --extra=<文字檔>：中文語料另外加一份文字檔（UTF-8，一行一句），輸出檔名加 -extra

usage: python3 -I tools/lm/keylid.py [--extra=<文字檔>] [--dict=<penglai_zhuyin.dict.yaml>]
  讀音預設用 ud-real/penglai_zhuyin.dict.yaml（沙盒快照）；全部約 3 分鐘（純 Python）、高峰約 1 GB。
"""
import collections, lzma, math, os, pickle, random, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
W = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, os.path.join(W, "tools"))
sys.path.insert(0, HERE)
OUT = os.path.join(W, ".build", "keylid")
N = 5
HAN = re.compile(r"[㐀-鿿]+")
PARTICLES = list("喔哦啊吧呢嗎啦耶欸齁囉")
PW = [4, 4, 3, 3, 3, 3, 2, 1, 1, 1, 1]
# 語氣詞照口語讀音（詞典比重最高的讀音不一定是：哦 ㄜˊ、欸 ㄞˇ）
PREAD = dict(zip(PARTICLES, ["ㄛ", "ㄛˊ", "ㄚ˙", "ㄅㄚ˙", "ㄋㄜ˙", "ㄇㄚ˙", "ㄌㄚ˙", "ㄧㄝ", "ㄟˋ", "ㄏㄡ", "ㄌㄨㄛ˙"]))


class NG:
    """字元 n-gram，Witten-Bell 內插；'^' 開頭、'$' 結尾"""

    def __init__(self, n):
        self.n = n
        self.c = collections.Counter()
        self.ctx = collections.Counter()
        self.typ = collections.Counter()
        self.V = set()

    def add(self, s, w=1):
        s = "^" * (self.n - 1) + s + "$"
        for i in range(self.n - 1, len(s)):
            self.V.add(s[i])
            for k in range(0, self.n):
                h = s[i - k:i]
                g = h + s[i]
                if self.c[g] == 0:
                    self.typ[h] += 1
                self.c[g] += w
                self.ctx[h] += w

    def finish(self):
        self.V = len(self.V) + 1

    def lp(self, h, x):
        h = h[-(self.n - 1):] if self.n > 1 else ""
        p = 1.0 / self.V
        for k in range(0, len(h) + 1):
            hh = h[len(h) - k:]
            t = self.ctx.get(hh, 0)
            if t == 0:
                continue
            u = self.typ[hh]
            lam = t / (t + u)
            p = lam * self.c.get(hh + x, 0) / t + (1 - lam) * p
        return math.log(p)


def char_readings(path):
    best = {}
    f = open(path, encoding="utf-8")
    for line in f:
        if line.startswith("..."):
            break
    for line in f:
        p = line.rstrip("\n").split("\t")
        if len(p) < 2 or len(p[0]) != 1:
            continue
        w = float(p[2].rstrip("%")) if len(p) > 2 and p[2] and p[2][0].isdigit() else 0.0
        if p[0] not in best or w > best[p[0]][1]:
            best[p[0]] = (p[1], w)
    return {c: r for c, (r, w) in best.items()}


def zh_runs(extra):
    from upstream import versions, fetch
    moe = versions()["MOEDICT_COMMIT"]
    path = os.path.join(W, ".build", "twdata", moe[:12], "dict-revised.json.xz")
    if not os.path.exists(path):
        path = fetch("g0v/moedict-data", moe, "dict-revised.json.xz")
    with lzma.open(path, "rt", encoding="utf-8") as f:
        for line in f:
            yield from HAN.findall(line)
    if extra:   # 一行一句（換行跟英文、標點一樣是斷點）
        with open(extra, encoding="utf-8") as f:
            for t in f:
                yield from HAN.findall(t)


def syl_keys(code, style):
    from zhuyin import keys_for
    if style == "i2":
        return keys_for(code, initials="2")
    if style == "nt":
        return keys_for(code, notone=True)
    return keys_for(code).replace("{space}", " ")


def segments(rd, extra):
    """語料裡有讀音的連續片段（≥ 2 字），每段是注音碼 list"""
    for run in zh_runs(extra):
        seg = []
        for c in [rd.get(ch) for ch in run] + [None]:
            if c:
                seg.append(c)
                continue
            if len(seg) >= 2:
                yield seg
            seg = []


def build_pure(rd, extra):
    from zhuyin import keys_for
    zh_i2, zh_full = NG(N), NG(N)
    for seg in segments(rd, extra):
        code = " ".join(seg)
        k2, kf = keys_for(code, initials="2"), keys_for(code)
        if k2:
            zh_i2.add(k2)
        if kf:
            zh_full.add(kf.replace("{space}", " "))
    en = NG(N)
    for line in open(os.path.join(W, ".build", "en_words.tsv"), encoding="utf-8"):
        w, z = line.rstrip("\n").split("\t")
        z = float(z)
        if z < 1.5:
            continue
        en.add(w, 10 ** (z - 3))
    for m in (zh_i2, zh_full, en):
        m.finish()
    return zh_i2, zh_full, en


def build_mix(rd, extra, particles):
    rnd = random.Random(1029)
    m = NG(N)
    for seg in segments(rd, extra):
        if particles and rnd.random() < 0.2:
            seg = seg + [PREAD[rnd.choices(PARTICLES, PW)[0]]]
        x = rnd.random()
        if x < 0.4:
            styles = ["i2"] * len(seg)
        elif x < 0.55:
            styles = ["tone"] * len(seg)
        else:
            styles = [rnd.choices(["i2", "nt", "tone"], [0.6, 0.25, 0.15])[0] for _ in seg]
        m.add("".join(syl_keys(s, st) for s, st in zip(seg, styles)))
    m.finish()
    return m


def load(name):
    """name：models（三個的 tuple）、zhmix、zhmix2（加 -extra 是加了另外語料的版本）"""
    return pickle.load(open(os.path.join(OUT, name + ".pkl"), "rb"))


def main():
    flags = dict((f[2:].split("=", 1) + [""])[:2] for f in sys.argv[1:] if f.startswith("--"))
    extra = flags.get("extra") or None
    suffix = "-extra" if extra else ""
    rd = char_readings(flags.get("dict") or os.path.join(W, "ud-real", "penglai_zhuyin.dict.yaml"))
    os.makedirs(OUT, exist_ok=True)
    pickle.dump(build_pure(rd, extra), open(os.path.join(OUT, f"models{suffix}.pkl"), "wb"))
    pickle.dump(build_mix(rd, extra, False), open(os.path.join(OUT, f"zhmix{suffix}.pkl"), "wb"))
    pickle.dump(build_mix(rd, extra, True), open(os.path.join(OUT, f"zhmix2{suffix}.pkl"), "wb"))
    print(f"{OUT}：models{suffix}、zhmix{suffix}、zhmix2{suffix}", file=sys.stderr)


if __name__ == "__main__":
    import keylid   # 讓 pickle 記成 keylid.NG（直接執行時類別在 __main__）
    keylid.main()
