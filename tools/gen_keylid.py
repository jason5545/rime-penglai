"""產生蓬萊韻「中英混輸：按鍵層語言辨識」用的表 penglai_keylid.tbl（translator/english_keylid，librime patch 0013）。

模型照 tools/lm/keylid.py（離線實驗的參考實作，docs/findings.md〈按鍵層語言辨識〉）：
  中文：教育部辭典的字逐字取詞典裡比重最高的讀音，轉成大千按鍵，混打（首符號／不帶調／帶調）＋句尾語氣詞，按鍵 5-gram。
  英文：wordfreq 的單字（次數 10^(Zipf−3)），字母 5-gram。
  都是 Witten-Bell 內插，'^' 開頭、'$' 結尾。引擎（src/rime/gear/english_keylid.cc）拿同一串按鍵比兩個模型，
  兩狀態分段 Viterbi 找英文段，產生切點候選（tools/lm/keylid_vit.py 的做法）。

usage: python3 -I tools/gen_keylid.py <en_words.tsv> [out] [--extra=<文字檔>] [--dict=<penglai_zhuyin.dict.yaml>] [--prune=2]
                                       [--pickle] [--check[=N]]
  out 預設 .build/penglai_keylid.tbl（--extra 時 .build/penglai_keylid-extra.tbl）；裝的時候放 ~/Library/Rime/penglai_keylid.tbl。
  --extra：中文語料另外加一份文字檔（UTF-8，一行一句，例如自己平常打的字）。App 附的公開版不加。
  --dict：讀音來源（蓬萊注音詞典，tools/gen_terra_tw.py 的輸出；tools/upstream.py 會自己產生、傳進來），預設 ud-real/ 底下那份。
  --prune：中文模型剪枝，出現不到這麼多次的 5-gram 和 4 鍵前文不收（查的時候退回短一階，像沒看過一樣）；1 = 不剪。英文不剪。
  --pickle：不重建模型，讀 tools/lm/keylid.py 存好的 .build/keylid/zhmix2[-extra].pkl、models.pkl（開發時省幾十秒）。
  --check[=N]：用產生的表重算 N 組（預設 20 萬）隨機的「前文＋下一鍵」，跟模型直接算的比，印出最大差；不剪枝時應該 < 1e-5。
  en_words.tsv：「單字<TAB>Zipf」，wordfreq 3.1.1 的英文前 30 萬詞取純 a–z 的（產生方法見 tools/lm/ntc.py 檔頭）。
  從頭建約 1 分鐘（純 Python）。

授權：教育部重編國語辭典修訂本（萌典資料，versions.env 的 MOEDICT_COMMIT）CC BY-ND 3.0 TW；wordfreq 資料 CC BY-SA 4.0。
表不進 repo。公開版（不加 --extra）放進貂毫的 SharedSupport：tools/upstream.py 第一次用到時用這支產生、對 versions.env 的
PENGLAI_KEYLID_SHA256（輸入檔名要叫 en_words.tsv，info 會記檔名；info 記讀音詞典的 sha1，不記產生時間，同樣的輸入逐位元組相同）。
使用者資料夾有同名檔時引擎用使用者的：加了 --extra 的表放使用者資料夾（~/Library/Rime），不要放進 App。

檔案格式（little-endian；引擎 src/rime/gear/english_keylid.cc 照這個讀）：
  符號 id 1–63（0 不用），一串最多 5 個符號，每個 6 位元打包成 uint32（前面的符號在高位）；因為 id 不是 0，長度不同的串不會撞。
  0    8 bytes   "PLKEYLD1"
  8    char[64]  id → 按鍵字元（'^' = 1、'$' = 2）
  72   兩個模型（中文、英文）各 48 bytes：
         uint64 gram_offset, uint64 gram_count       n-gram：key u32 排序，接著（8 位元組對齊）同樣個數的 logp f32
         uint64 ctx_offset,  uint64 ctx_count        前文（長度 1–4）：key u32 排序，接著（對齊）同樣個數的 logbo f32
         float  log_v（log 1/V）, float bo_empty（空前文的 log(1 − λ)）, 8 bytes 保留
  168  uint64 info_offset, uint64 info_count       來源與版本（UTF-8）
  每段 8 位元組對齊。
  logp(g) 是 g 最後一個符號接在前面那幾個後面的內插機率（log）；logbo(h) = log(1 − λ_h)，λ_h = t/(t+u)。
  查 (h, x)：從最長的前文往短找，g = h 的後 k 個 + x 有收就回「累積的 logbo ＋ logp(g)」，沒有就加上 logbo(h 的後 k 個)
  （前文沒收就不加），k = 0 也沒有時回「累積 ＋ bo_empty ＋ log_v」。跟 keylid.py 的 NG.lp 算法相同（不剪枝時逐位相同到 float 精度）。
"""
import array, hashlib, math, os, random, struct, sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(REPO, "tools", "lm"))
sys.path.insert(0, os.path.join(REPO, "tools"))
import keylid  # noqa: E402

args = [a for a in sys.argv[1:] if not a.startswith("--")]
flags = dict((f[2:].split("=", 1) + [None])[:2] for f in sys.argv[1:] if f.startswith("--"))
if not args:
    sys.exit(__doc__)
EN = args[0]
EXTRA = flags.get("extra") or None
SUFFIX = "-extra" if EXTRA else ""
OUT = args[1] if len(args) > 1 else os.path.join(REPO, ".build", f"penglai_keylid{SUFFIX}.tbl")
PRUNE = float(flags.get("prune") or 2)
DICT = flags.get("dict") or os.path.join(REPO, "ud-real", "penglai_zhuyin.dict.yaml")
MAGIC = b"PLKEYLD1"
ORDER = 5


def build_en():
    en = keylid.NG(ORDER)
    for line in open(EN, encoding="utf-8"):
        w, z = line.rstrip("\n").split("\t")
        z = float(z)
        if z < 1.5:
            continue
        en.add(w, 10 ** (z - 3))
    en.finish()
    return en


def models():
    if "pickle" in flags:
        zh = keylid.load("zhmix2" + SUFFIX)
        en = keylid.load("models")[2]
        return zh, en
    rd = keylid.char_readings(DICT)
    zh = keylid.build_mix(rd, EXTRA, True)
    return zh, build_en()


def symbols(zh, en):
    chars = set()
    for m in (zh, en):
        for g in m.c:
            chars.update(g)
    chars.discard("^")
    chars.discard("$")
    order = ["^", "$"] + sorted(chars)
    if len(order) > 63:
        sys.exit(f"符號太多（{len(order)}），一個符號只有 6 位元")
    return {ch: i + 1 for i, ch in enumerate(order)}


def pack(s, ids):
    k = 0
    for ch in s:
        k = (k << 6) | ids[ch]
    return k


def tables(m, ids, prune):
    """回 (grams[(key, logp)], ctxs[(key, logbo)], log_v, bo_empty, 剪掉的 5-gram 數, 剪掉的前文數)"""
    grams, ctxs = [], []
    cut_g = cut_h = 0
    for g, c in m.c.items():
        if prune > 1 and len(g) == ORDER and c < prune:
            cut_g += 1
            continue
        grams.append((pack(g, ids), m.lp(g[:-1], g[-1])))
    bo_empty = 0.0
    for h, t in m.ctx.items():
        lam = t / (t + m.typ[h])
        if not h:
            bo_empty = math.log(1 - lam)
            continue
        if prune > 1 and len(h) == ORDER - 1 and t < prune:
            cut_h += 1
            continue
        ctxs.append((pack(h, ids), math.log(1 - lam)))
    grams.sort()
    ctxs.sort()
    return grams, ctxs, math.log(1.0 / m.V), bo_empty, cut_g, cut_h


class Table:
    """照引擎的查法用表算 log 機率（--check 用）"""

    def __init__(self, grams, ctxs, log_v, bo_empty):
        self.g = dict(grams)
        self.h = dict(ctxs)
        self.log_v, self.bo_empty = log_v, bo_empty

    def lp(self, hkey, x):
        acc = 0.0
        for k in range(ORDER - 1, -1, -1):
            hh = hkey & ((1 << (6 * k)) - 1)
            v = self.g.get((hh << 6) | x)
            if v is not None:
                return acc + v
            acc += self.h.get(hh, 0.0) if k > 0 else self.bo_empty
        return acc + self.log_v


def check(name, m, tab, ids, n):
    rnd = random.Random(1030)
    grams = [g for g in m.c if len(g) == ORDER]
    alphabet = [ch for ch in ids if ch not in "^$"]
    worst = 0.0
    big = 0
    for i in range(n):
        if i % 2 == 0:
            g = rnd.choice(grams)
            h, x = g[:-1], g[-1]
            if rnd.random() < 0.3:
                x = rnd.choice(alphabet + ["$"])
        else:
            h = "".join(rnd.choice(alphabet + ["^"]) for _ in range(ORDER - 1))
            x = rnd.choice(alphabet + ["$"])
        if x not in ids:
            continue
        a = m.lp(h, x)
        b = tab.lp(pack(h, ids), ids[x])
        d = abs(a - b)
        worst = max(worst, d)
        big += d > 1e-4
    print(f"  {name}：{n} 組，最大差 {worst:.6f}，差 > 0.0001 的 {big} 組", file=sys.stderr)


def align(buf):
    while len(buf) % 8:
        buf.append(0)


def main():
    zh, en = models()
    ids = symbols(zh, en)
    sym = bytearray(64)
    for ch, i in ids.items():
        sym[i] = ord(ch)
    parts = []
    info = []
    for name, m, prune in (("中文", zh, PRUNE), ("英文", en, 1)):
        grams, ctxs, log_v, bo_empty, cut_g, cut_h = tables(m, ids, prune)
        parts.append((grams, ctxs, log_v, bo_empty))
        info.append(f"{name}：n-gram {len(grams)}、前文 {len(ctxs)}，V {m.V}"
                    + (f"；剪枝 < {prune:g}：5-gram 剪掉 {cut_g}、前文剪掉 {cut_h}" if prune > 1 else ""))
        print(info[-1], file=sys.stderr)
        if "check" in flags:
            check(name, m, Table(grams, ctxs, log_v, bo_empty), ids, int(flags.get("check") or 200000))
    sha = hashlib.sha1(open(EN, "rb").read()).hexdigest()[:12]
    info.append(f"wordfreq 英文詞（{os.path.basename(EN)} sha1 {sha}）；中文語料：教育部辭典"
                + (f"＋另外的語料 {os.path.basename(EXTRA)}" if EXTRA else "")
                + ("" if "pickle" in flags else f"；讀音 {os.path.basename(DICT)} sha1 {hashlib.sha1(open(DICT, 'rb').read()).hexdigest()[:12]}"))
    head = bytearray(MAGIC) + sym
    body = bytearray()
    base = len(head) + 48 * 2 + 16
    descs = []
    for grams, ctxs, log_v, bo_empty in parts:
        d = []
        for rows in (grams, ctxs):
            align(body)
            off = base + len(body)
            body += array.array("I", [k for k, _ in rows]).tobytes()
            align(body)
            body += array.array("f", [v for _, v in rows]).tobytes()
            d.append((off, len(rows)))
        descs.append((d, log_v, bo_empty))
    align(body)
    info_off = base + len(body)
    text = "\n".join(info).encode("utf-8")
    body += text
    for (g, h), log_v, bo_empty in descs:
        head += struct.pack("<QQQQff8x", g[0], g[1], h[0], h[1], log_v, bo_empty)
    head += struct.pack("<QQ", info_off, len(text))
    assert len(head) == base
    os.makedirs(os.path.dirname(os.path.abspath(OUT)), exist_ok=True)
    with open(OUT, "wb") as f:
        f.write(head)
        f.write(body)
    print(f"{OUT}：{(len(head) + len(body)) / 1e6:.1f} MB", file=sys.stderr)


if __name__ == "__main__":
    main()
