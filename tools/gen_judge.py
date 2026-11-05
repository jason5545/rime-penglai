"""產生蓬萊韻「中英混輸判斷」用的表 penglai_judge.tbl（translator/english_judge，librime patch 0004）。

判斷照 tools/lm/judge3.py（離線模擬的參考實作），做成引擎直接 mmap 的排序陣列：
  中文：字三元語言模型，內插 Kneser-Ney（D=0.75），英文段和標點當斷點。字的 id 直接用 Unicode 碼位（21 位元）。
  英文：字母三元模型，wordfreq 訓練（次數 = 10^(Zipf−3)），內插 0.7／0.2／0.1；查表存好每一步的 log 機率。
  句子分數 = 中文每個字的 log 機率 ＋ 每段英文的字母 log 機率（引擎：src/rime/gear/english_judge.cc）。
  引擎的候選文字是臺灣字形轉換前的（爲、着），語料是臺灣字形（為、著）：表裡附 OpenCC TWVariants 的單字對照，引擎先換再查。

usage: <有 numpy 的 python> tools/gen_judge.py <en_words.tsv> [out] [--extra=<文字檔>]
  out 預設 .build/penglai_judge.tbl；裝的時候放 ~/Library/Rime/penglai_judge.tbl
  （副檔名不能用 .bin：Rime 部署時會把使用者資料夾根目錄的 *.bin 當舊版編譯檔搬進 trash/）。
  --extra：中文語料另外加一份文字檔（UTF-8，一行一句，例如自己平常打的字）。App 附的公開版不加。
  --check=<cands.tsv>,<judge3 的輸出>：用產生的表重算 judge3 的分數，逐筆比對（驗證表的格式）。
  en_words.tsv：「單字<TAB>Zipf」，wordfreq 3.1.1 的英文前 30 萬詞取純 a–z 的（產生方法見 tools/lm/ntc.py 檔頭）。
  例如 Homebrew 的 python3.14（numpy 2.3）。教育部辭典約 4–5 秒、高峰約 1 GB。

授權：教育部重編國語辭典修訂本（萌典資料，versions.env 的 MOEDICT_COMMIT）CC BY-ND 3.0 TW；wordfreq 資料 CC BY-SA 4.0。
表不進 repo。公開版（不加 --extra）放進貂毫的 SharedSupport：tools/upstream.py 第一次用到時用這支產生、對 versions.env 的
PENGLAI_JUDGE_SHA256（輸入檔名要叫 en_words.tsv，info 會記檔名）。教育部辭典的釋義、引文也算進語料，表裡只有字三元次數，
不是原文。使用者資料夾有同名檔時引擎用使用者的：加了 --extra 的表放使用者資料夾（~/Library/Rime），不要放進 App。

檔案格式（little-endian；引擎 src/rime/gear/english_judge.cc 照這個讀）。字的 id 是碼位，都在 16 位元內（斷點 = 0）：
  0    8 bytes  "PLJUDGE2"
  8    double   D
  16   uint64   NB（二元種類數，KN 的一元分母）
  24   13 段 ×（uint64 offset, uint64 count），每段 8 位元組對齊：
       0 uni_key u32   1 uni_cont u32                         一元：N1+(•c)
       2 b_key u32     3 b_cont u32   4 b_off u32（n+1 個）   N1+(•b•)；b 後面接的字在 bc 的 [b_off[i], b_off[i+1])
       5 bc_c u16      6 bc_cont u32                          N1+(•bc)（N1+(b•) = 範圍長度）
       7 ab_key u32    8 ab_cnt u32   9 ab_off u32（n+1 個）  key = a<<16|b，N(ab•)；第三個字在 tri 的範圍
       10 tri_c u16    11 tri_cnt u32                         N(abc)（N1+(ab•) = 範圍長度）
       12 map u32 ×2 交錯（from, to）                          TWVariants 單字對照（照 from 排序）
  再接兩段（同樣 offset, count）：
       13 en f64 [28×28×28]  字母三元的 log 機率：[前前][前][這個]，0 = ^，1–26 = a–z，27 = $
       14 info（UTF-8 文字）  來源與版本
  句首的前文 = 0,0；句尾 = 接 0。
"""
import array, collections, hashlib, lzma, math, os, re, struct, sys
import numpy as np

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
args = [a for a in sys.argv[1:] if not a.startswith("--")]
flags = dict((f[2:].split("=", 1) + [None])[:2] for f in sys.argv[1:] if f.startswith("--"))
if not args:
    sys.exit(__doc__)
EN = args[0]
OUT = args[1] if len(args) > 1 else os.path.join(REPO, ".build", "penglai_judge.tbl")
D = 0.75
SH = 21
HAN = re.compile("[\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff]+")   # 同 judge3.py；用跳脫寫，免得編輯器把相容字 U+F900 正規化成 U+8C48


def versions():
    v = {}
    for line in open(os.path.join(REPO, "versions.env"), encoding="utf-8"):
        m = re.match(r"(\w+)=(\S+)", line)
        if m:
            v[m.group(1)] = m.group(2)
    return v


# ---- 中文：字三元 ----
seq = array.array("q")          # 每段 [0, 0, c1 … cn, 0, -1]（-1 分隔段落）
nchars = 0


def add_runs(text):
    global nchars
    for run in HAN.findall(text):
        seq.extend((0, 0))
        seq.extend(map(ord, run))
        seq.extend((0, -1))
        nchars += len(run)


info = []
moe = versions()["MOEDICT_COMMIT"]
path = os.path.join(REPO, ".build", "twdata", moe[:12], "dict-revised.json.xz")
if not os.path.exists(path):   # 照 versions.env 下載（upstream.py 的命令列不認得這個檔名，要用 fetch）
    sys.path.insert(0, os.path.join(REPO, "tools"))
    from upstream import fetch
    path = fetch("g0v/moedict-data", moe, "dict-revised.json.xz")
with lzma.open(path, "rt", encoding="utf-8") as f:
    for line in f:
        add_runs(line)
info.append(f"教育部重編國語辭典修訂本 {moe[:12]}（{nchars} 字）")
if flags.get("extra"):   # 另外加的中文語料：一行一句（換行跟英文、標點一樣是斷點）
    before = nchars
    with open(flags["extra"], encoding="utf-8") as f:
        for t in f:
            add_runs(t)
    info.append(f"另外的語料 {os.path.basename(flags['extra'])}（{nchars - before} 字）")

S = np.frombuffer(seq, dtype=np.int64)
a, b, c3 = S[:-2], S[1:-1], S[2:]
ok = (a >= 0) & (b >= 0) & (c3 >= 0) & ~((b == 0) & (c3 == 0))
tri = (a[ok] << (2 * SH)) | (b[ok] << SH) | c3[ok]
del S, a, b, c3, ok, seq
T, TN = np.unique(tri, return_counts=True)
del tri
AB = T >> SH
ab_keys, ab_idx, ab_types = np.unique(AB, return_index=True, return_counts=True)
ab_cnt = np.add.reduceat(TN, ab_idx)
del AB, ab_idx
BC = T & ((1 << (2 * SH)) - 1)
bc_keys, bc_cont = np.unique(BC, return_counts=True)
del BC
Bm = bc_keys >> SH
b_keys, b_idx, b_types = np.unique(Bm, return_index=True, return_counts=True)
b_cont = np.add.reduceat(bc_cont, b_idx)
del Bm, b_idx
Cc = bc_keys & ((1 << SH) - 1)
c_keys, c_cont = np.unique(Cc, return_counts=True)
del Cc
NB = len(bc_keys)
for name, arr in (("TN", TN), ("ab_cnt", ab_cnt), ("b_cont", b_cont)):
    assert arr.max() < 2 ** 32, name

# ---- 臺灣字形對照（OpenCC TWVariants，取第一個值） ----
tw = {}
for line in open(os.path.join(REPO, "bench-data", "TWVariants.txt"), encoding="utf-8"):
    if line.startswith("#") or "\t" not in line:
        continue
    k, v = line.rstrip("\n").split("\t")
    v = v.split()[0]
    if len(k) == 1 and len(v) == 1 and k != v:
        tw[ord(k)] = ord(v)
map_from = np.array(sorted(tw), dtype=np.uint32)
map_to = np.array([tw[k] for k in sorted(tw)], dtype=np.uint32)

# ---- 英文：字母三元（同 judge3.py） ----
tri_e = collections.Counter(); bi_e = collections.Counter(); uni = collections.Counter()
en_lines = 0
for line in open(EN, encoding="utf-8"):
    w, z = line.rstrip("\n").split("\t")
    wt = 10 ** (float(z) - 3)
    s = "^^" + w + "$"
    for i in range(2, len(s)):
        tri_e[s[i - 2:i + 1]] += wt; bi_e[s[i - 2:i]] += wt
    for ch in w + "$":
        uni[ch] += wt
    en_lines += 1
U = sum(uni.values())
bi2 = collections.Counter(); bi2c = collections.Counter()
for k, n in tri_e.items():
    bi2[k[1:]] += n; bi2c[k[1]] += n
ALPHA = "^abcdefghijklmnopqrstuvwxyz$"


def en_step(h, ch):
    p3 = tri_e.get(h + ch, 0) / bi_e[h] if bi_e.get(h) else 0
    p2 = bi2.get(h[1] + ch, 0) / bi2c[h[1]] if bi2c.get(h[1]) else 0
    return math.log(0.7 * p3 + 0.2 * p2 + 0.1 * uni.get(ch, 0) / U + 1e-9)


en = np.zeros((28, 28, 28), dtype=np.float64)
for i, x in enumerate(ALPHA):
    for j, y in enumerate(ALPHA):
        for k, ch in enumerate(ALPHA):
            if k > 0:
                en[i, j, k] = en_step(x + y, ch)
en_sha = hashlib.sha1(open(EN, "rb").read()).hexdigest()[:12]
info.append(f"wordfreq 英文詞 {en_lines} 個（{os.path.basename(EN)} sha1 {en_sha}）")

# ---- 寫檔 ----
assert T.max() >> (2 * SH) < 65536 and int(c_keys.max()) < 65536, "碼位超過 16 位元"
b_off = np.append(np.searchsorted(bc_keys >> SH, b_keys), len(bc_keys))
ab_off = np.append(np.searchsorted(T >> SH, ab_keys), len(T))
pairs = np.empty(2 * len(map_from), dtype=np.uint32)
pairs[0::2], pairs[1::2] = map_from, map_to
sections = [
    c_keys.astype(np.uint32), c_cont.astype(np.uint32),
    b_keys.astype(np.uint32), b_cont.astype(np.uint32), b_off.astype(np.uint32),
    (bc_keys & ((1 << SH) - 1)).astype(np.uint16), bc_cont.astype(np.uint32),
    (((ab_keys >> SH) << 16) | (ab_keys & ((1 << SH) - 1))).astype(np.uint32), ab_cnt.astype(np.uint32), ab_off.astype(np.uint32),
    (T & ((1 << SH) - 1)).astype(np.uint16), TN.astype(np.uint32),
    pairs,
    en.reshape(-1),
    np.frombuffer(("；".join(info) + f"；D={D}").encode("utf-8"), dtype=np.uint8),
]
assert np.all(np.diff(b_off) == b_types) and np.all(np.diff(ab_off) == ab_types)
HEADER = 24 + 16 * len(sections)
offsets, pos = [], (HEADER + 7) // 8 * 8
for s in sections:
    offsets.append(pos)
    pos = (pos + s.nbytes + 7) // 8 * 8
tmp = OUT + ".tmp"
with open(tmp, "wb") as f:
    f.write(b"PLJUDGE2" + struct.pack("<dQ", D, NB))
    for off, s in zip(offsets, sections):
        f.write(struct.pack("<QQ", off, len(s)))
    for off, s in zip(offsets, sections):
        f.write(b"\0" * (off - f.tell()))
        f.write(s.astype(s.dtype.newbyteorder("<"), copy=False).tobytes())
os.replace(tmp, OUT)
print(f"{OUT}：{os.path.getsize(OUT) / 1e6:.1f} MB；{'、'.join(info)}；三元 {len(T)} 種、"
      f"二元 {NB} 種、前兩字 {len(ab_keys)} 種", file=sys.stderr)

# ---- 驗證：用剛寫的表重算 judge3 的分數 ----
if flags.get("check"):
    cands, ref = flags["check"].split(",")
    buf = np.memmap(OUT, dtype=np.uint8, mode="r")
    D_, NB_ = struct.unpack_from("<dQ", buf, 8)
    dt = [np.uint32, np.uint32, np.uint32, np.uint32, np.uint32, np.uint16, np.uint32, np.uint32, np.uint32, np.uint32,
          np.uint16, np.uint32, np.uint32, np.float64, np.uint8]
    sec = []
    for i, t in enumerate(dt):
        off, n = struct.unpack_from("<QQ", buf, 24 + 16 * i)
        sec.append(np.frombuffer(buf, dtype=t, count=n, offset=off).astype(np.int64 if t != np.float64 else t))
    uk, uc, bk, bcn, boff, bcc_c, bcc, abk, abn, aboff, tc_c, tc, mp, enl, _ = sec
    twm = dict(zip(mp[0::2].tolist(), mp[1::2].tolist()))
    enl = enl.reshape(28, 28, 28)

    def find(keys, q, lo=0, hi=None):
        hi = len(keys) if hi is None else hi
        i = lo + int(np.searchsorted(keys[lo:hi], q))
        return i if i < hi and keys[i] == q else -1

    def logp(x, y, z):
        i = find(uk, z)
        cc = int(uc[i]) if i >= 0 else 0
        p1 = cc / NB_ if cc > 0 else 0.5 / NB_
        p2 = p1
        i = find(bk, y)
        if i >= 0:
            lo, hi = int(boff[i]), int(boff[i + 1])
            j = find(bcc_c, z, lo, hi)
            nbc = int(bcc[j]) if j >= 0 else 0
            bc_ = int(bcn[i])
            p2 = max(nbc - D_, 0) / max(bc_, 1) + D_ * (hi - lo) / max(bc_, 1) * p1
        p3 = p2
        i = find(abk, (x << 16) | y)
        if i >= 0:
            lo, hi = int(aboff[i]), int(aboff[i + 1])
            j = find(tc_c, z, lo, hi)
            n3 = int(tc[j]) if j >= 0 else 0
            n_ab = int(abn[i])
            p3 = max(n3 - D_, 0) / max(n_ab, 1) + D_ * (hi - lo) / max(n_ab, 1) * p2
        return math.log(p3)

    def en_lp(w):
        s = [0, 0] + [ord(ch) - 96 for ch in w.lower()] + [27]
        return sum(enl[s[i - 2], s[i - 1], s[i]] for i in range(2, len(s)))

    TOK = re.compile(r"[A-Za-z]+|.", re.S)

    def score(text):
        h1 = h2 = 0
        zh = enp = 0.0
        for t in TOK.findall(text):
            if t[0].isascii() and t[0].isalpha():
                if h2:
                    zh += logp(h1, h2, 0)
                enp += en_lp(t)
                h1 = h2 = 0
            elif HAN.fullmatch(t):
                cid = twm.get(ord(t), ord(t))
                zh += logp(h1, h2, cid)
                h1, h2 = h2, cid
            else:
                if h2:
                    zh += logp(h1, h2, 0)
                h1 = h2 = 0
        if h2:
            zh += logp(h1, h2, 0)
        return enp + zh

    want = {}
    for line in open(ref, encoding="utf-8"):
        _, cand, s = line.rstrip("\n").split("\t")
        want[cand] = float(s)
    n = bad = 0
    worst = 0.0
    for line in open(cands, encoding="utf-8"):
        cand = line.rstrip("\n").split("\t")[1]
        if cand not in want:
            continue
        got = score(cand)
        d = abs(got - want[cand])
        worst = max(worst, d)
        n += 1
        if d > 1e-3:
            bad += 1
            if bad <= 10:
                print(f"  不同：{cand} 表 {got:.4f}、judge3 {want[cand]:.4f}", file=sys.stderr)
    print(f"驗證：{n} 筆，差 > 0.001 的 {bad} 筆，最大差 {worst:.6f}", file=sys.stderr)
