"""鎖定版本的上游資料（versions.env）：第一次用到時下載到 .build/twdata/<commit 前 12 碼>/，之後直接用。

usage: python3 -I tools/upstream.py <檔名> [...]   每個檔印一行絕對路徑（還沒下載就先下載）
  檔名：terra_pinyin.dict.yaml、essay.txt、default.yaml、key_bindings.yaml、punctuation.yaml、
        stroke.dict.yaml、stroke.schema.yaml、zh-hant-t-essay-bgw.gram、zh-hant-t-essay-bgc.gram、
        predict.db（release 資產，對 PREDICT_DATA_SHA256）、penglai_predict.LICENSE.txt（產生的：說明＋rime-essay 的 LICENSE）、
        penglai_en.txt、penglai_judge.tbl、penglai_keylid.tbl（中英混輸的公開版資料，產生的，對 PENGLAI_*_SHA256）、
        penglai_en.LICENSE.txt（產生的：三個檔的來源和授權）
  default.yaml 是上游原本的；貂毫的 SharedSupport 用 rime-config/default.yaml（只改 schema_list）。
當模組：from upstream import path, fetch, versions。build.sh、gen_terra_tw.py、gram_build.py、replay_prep.py 都從這裡拿，
不再讀已安裝的 Squirrel SharedSupport。

中英混輸的公開版資料（放進貂毫）：repo 不放這 66 MB，第一次用到時在本機產生，產生完對 versions.env 的 sha256，
不同就停（換了產生器、詞典、wordfreq 或 Python 才會不同；確定要換時改 versions.env）。步驟（約 70 秒，要網路裝 wordfreq）：
  1. .build/wordfreq-<WORDFREQ_VERSION>/：venv（有 numpy 的 Python，帶系統套件；PENGLAI_NUMPY_PYTHON 可以指定），pip 裝 wordfreq
  2. en_words.tsv：wordfreq 英文前 30 萬詞取純 a–z 的（檔名固定，判斷表、按鍵表的 info 會記它）
  3. tools/gen_en_lexicon.py、tools/gen_judge.py；tools/gen_terra_tw.py 在暫存資料夾產生詞典（讀音表、方案檔用副本，repo 不動），
     tools/gen_keylid.py --dict=<那份詞典>
  4. 對 sha256，放到 .build/twdata/<sha256 前 12 碼>/
不加 --extra：加了另外語料的那份放使用者資料夾，使用者資料夾有同名檔時引擎用使用者的。
"""
import glob, hashlib, os, re, shutil, subprocess, sys, urllib.request

W = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# 檔名 → (versions.env 的鍵, GitHub repo, repo 裡的路徑)
FILES = {
    "terra_pinyin.dict.yaml": ("TERRA_PINYIN_COMMIT", "rime/rime-terra-pinyin", "terra_pinyin.dict.yaml"),
    "essay.txt": ("ESSAY_COMMIT", "rime/rime-essay", "essay.txt"),
    "default.yaml": ("PRELUDE_COMMIT", "rime/rime-prelude", "default.yaml"),
    "key_bindings.yaml": ("PRELUDE_COMMIT", "rime/rime-prelude", "key_bindings.yaml"),
    "punctuation.yaml": ("PRELUDE_COMMIT", "rime/rime-prelude", "punctuation.yaml"),
    "stroke.dict.yaml": ("STROKE_COMMIT", "rime/rime-stroke", "stroke.dict.yaml"),
    "stroke.schema.yaml": ("STROKE_COMMIT", "rime/rime-stroke", "stroke.schema.yaml"),
    "zh-hant-t-essay-bgw.gram": ("OCTAGRAM_DATA_COMMIT", "lotem/rime-octagram-data", "zh-hant-t-essay-bgw.gram"),
    "zh-hant-t-essay-bgc.gram": ("OCTAGRAM_DATA_COMMIT", "lotem/rime-octagram-data", "zh-hant-t-essay-bgc.gram"),
}

# release 資產：檔名 → (versions.env 的網址鍵, sha256 鍵)
RELEASES = {
    "predict.db": ("PREDICT_DATA_URL", "PREDICT_DATA_SHA256"),
}

# 中英混輸的公開版資料：檔名 → versions.env 的 sha256 鍵（產生的，見檔頭）
GENERATED = {
    "penglai_en.txt": "PENGLAI_EN_SHA256",
    "penglai_judge.tbl": "PENGLAI_JUDGE_SHA256",
    "penglai_keylid.tbl": "PENGLAI_KEYLID_SHA256",
}

# 公開版聯想資料的授權說明（SharedSupport 的 penglai_predict.LICENSE.txt），後面接 rime-essay 的 LICENSE 全文
PREDICT_NOTICE = """penglai_predict.db（貂毫附的聯想資料）

來源：rime/librime-predict release data-1.0 的 predict.db（lotem，2023-10-31），只改檔名
  {url}
  sha256 {sha}
release 寫的是「prediction database made from essay + octagram」，沒有另外寫授權。
兩個來源的授權都是 GNU LGPL-3.0：
  rime/rime-essay           https://github.com/rime/rime-essay
  lotem/rime-octagram-data  https://github.com/lotem/rime-octagram-data
使用者資料夾裡有同名的 penglai_predict.db 時，輸入法用使用者的那份。

以下是 rime-essay 附的授權全文（{essay}）：

"""


# 中英混輸資料的授權說明（SharedSupport 的 penglai_en.LICENSE.txt）。wordfreq 那段是套件 METADATA 的 License 段原文
EN_NOTICE = """penglai_en.txt、penglai_judge.tbl、penglai_keylid.tbl（貂毫附的中英混輸資料）

三個檔都是蓬萊韻的產生器從下面的資料算出來的統計表，不含原始文字（產生器在原始碼的 tools/：
gen_en_lexicon.py、gen_judge.py、gen_keylid.py；來源版本和三個檔的 sha256 鎖在 versions.env）：
  penglai_en.txt      英文單字和詞頻（Zipf），只收純小寫 a–z、2 個字母以上、Zipf ≥ 3 的詞
  penglai_judge.tbl   中文字三元的次數、英文字母三元的 log 機率，加上 OpenCC TWVariants 的單字對照
  penglai_keylid.tbl  中文注音按鍵 5-gram、英文字母 5-gram 的 log 機率
使用者資料夾裡有同名的檔時，輸入法用使用者的那份。

英文：wordfreq {wordfreq}（Robyn Speer，https://github.com/rspeer/wordfreq）
  用 top_n_list('en', 300000) 取純 a–z 的詞，配 zipf_frequency。wordfreq 的資料以 CC BY-SA 4.0
  （https://creativecommons.org/licenses/by-sa/4.0/）授權；penglai_en.txt 和另外兩個檔裡的英文字母模型是從它算出來的，
  照同一授權散布。以下是 wordfreq {wordfreq} 套件說明（METADATA）License 段的原文：

{wordfreq_license}
中文：教育部《重編國語辭典修訂本》，經 g0v/moedict-data（{moe}）的 dict-revised.json
  判斷表、按鍵表取整份辭典的漢字（詞條、釋義、例句、引文），只存字三元次數和按鍵 5-gram 的機率，不存原文。
  辭典本文著作權屬中華民國教育部，以 CC BY-ND 3.0 TW（https://creativecommons.org/licenses/by-nd/3.0/tw/）公眾授權；
  依教育部的解釋，禁止改作限制的是文字資料本身，不限制格式轉換和後續應用。moedict-data 轉換格式的編輯著作由 @kcwu 以 CC0 釋出。
  按鍵 5-gram 用的讀音取自蓬萊注音詞典（tools/gen_terra_tw.py 產生，GNU LGPL-3.0，見 NOTICE.md）。
  判斷表的字形對照取自 OpenCC 的 TWVariants（Apache-2.0）。
"""

WORDFREQ_LICENSE = """`wordfreq` is freely redistributable under the Apache license (see
`LICENSE.txt`), and it includes data files that may be
redistributed under a Creative Commons Attribution-ShareAlike 4.0
license (<https://creativecommons.org/licenses/by-sa/4.0/>).

`wordfreq` contains data extracted from Google Books Ngrams
(<http://books.google.com/ngrams>) and Google Books Syntactic Ngrams
(<http://commondatastorage.googleapis.com/books/syntactic-ngrams/index.html>).
The terms of use of this data are:

    Ngram Viewer graphs and data may be freely used for any purpose, although
    acknowledgement of Google Books Ngram Viewer as the source, and inclusion
    of a link to http://books.google.com/ngrams, would be appreciated.

`wordfreq` also contains data derived from the following Creative Commons-licensed
sources:

- The Leeds Internet Corpus, from the University of Leeds Centre for Translation
  Studies (<http://corpus.leeds.ac.uk/list.html>)

- Wikipedia, the free encyclopedia (<http://www.wikipedia.org>)

- ParaCrawl, a multilingual Web crawl (<https://paracrawl.eu>)

It contains data from OPUS OpenSubtitles 2018
(<http://opus.nlpl.eu/OpenSubtitles.php>), whose data originates from the
OpenSubtitles project (<http://www.opensubtitles.org/>) and may be used with
attribution to OpenSubtitles.

It contains data from various SUBTLEX word lists: SUBTLEX-US, SUBTLEX-UK,
SUBTLEX-CH, SUBTLEX-DE, and SUBTLEX-NL, created by Marc Brysbaert et al.
(see citations below) and available at
<http://crr.ugent.be/programs-data/subtitle-frequencies>.

I (Robyn Speer) have obtained permission by e-mail from Marc Brysbaert to
distribute these wordlists in wordfreq, to be used for any purpose, not just
for academic use, under these conditions:

- Wordfreq and code derived from it must credit the SUBTLEX authors.
- It must remain clear that SUBTLEX is freely available data.

These terms are similar to the Creative Commons Attribution-ShareAlike license.

Some additional data was collected by a custom application that watches the
streaming Twitter API, in accordance with Twitter's Developer Agreement &
Policy. This software gives statistics about words that are commonly used on
Twitter; it does not display or republish any Twitter content.
"""


def versions():
    v = {}
    for ln in open(os.path.join(W, "versions.env"), encoding="utf-8"):
        m = re.match(r"^(\w+)=(\S+)", ln)
        if m:
            v[m.group(1)] = m.group(2).strip('"')
    return v


def fetch(repo, sha, path):
    d = os.path.join(W, ".build", "twdata", sha[:12])
    os.makedirs(d, exist_ok=True)
    f = os.path.join(d, os.path.basename(path))
    if not os.path.exists(f):
        url = f"https://raw.githubusercontent.com/{repo}/{sha}/{path}"
        print(f"下載 {url}", file=sys.stderr)
        urllib.request.urlretrieve(url, f + ".part")
        os.rename(f + ".part", f)
    return f


def fetch_release(url, sha256):
    d = os.path.join(W, ".build", "twdata", sha256[:12])
    os.makedirs(d, exist_ok=True)
    f = os.path.join(d, os.path.basename(url))
    if not os.path.exists(f):
        print(f"下載 {url}", file=sys.stderr)
        urllib.request.urlretrieve(url, f + ".part")
        got = hashlib.sha256(open(f + ".part", "rb").read()).hexdigest()
        if got != sha256:
            os.remove(f + ".part")
            sys.exit(f"{url} 的 sha256 是 {got}，versions.env 寫的是 {sha256}，停下")
        os.rename(f + ".part", f)
    return f


def predict_license():
    v = versions()
    f = os.path.join(W, ".build", "twdata", v["PREDICT_DATA_SHA256"][:12], "penglai_predict.LICENSE.txt")
    essay = fetch("rime/rime-essay", v["ESSAY_COMMIT"], "LICENSE")
    text = PREDICT_NOTICE.format(url=v["PREDICT_DATA_URL"], sha=v["PREDICT_DATA_SHA256"],
                                 essay=f"rime/rime-essay {v['ESSAY_COMMIT'][:7]}")
    text += open(essay, encoding="utf-8").read()
    os.makedirs(os.path.dirname(f), exist_ok=True)
    with open(f, "w", encoding="utf-8") as out:
        out.write(text)
    return f


def sha256_of(f):
    h = hashlib.sha256()
    with open(f, "rb") as fh:
        for b in iter(lambda: fh.read(1 << 20), b""):
            h.update(b)
    return h.hexdigest()


def wordfreq_python():
    """.build/wordfreq-<版本>/ 的 venv（有 numpy 的 Python、帶系統套件，pip 裝鎖定版本的 wordfreq），回傳它的 python"""
    ver = versions()["WORDFREQ_VERSION"]
    d = os.path.join(W, ".build", f"wordfreq-{ver}")
    py = os.path.join(d, "bin", "python")
    check = "import importlib.metadata as m, numpy, wordfreq; print(m.version('wordfreq'))"
    if os.path.exists(py):
        r = subprocess.run([py, "-I", "-c", check], capture_output=True, text=True)
        if r.returncode == 0 and r.stdout.strip() == ver:
            return py
        shutil.rmtree(d)
    bases = [os.environ.get("PENGLAI_NUMPY_PYTHON"), "/opt/homebrew/opt/python@3.14/bin/python3.14",
             shutil.which("python3.14"), shutil.which("python3.13"), shutil.which("python3")]
    base = next((b for b in bases if b and os.path.exists(b) and subprocess.run(
        [b, "-I", "-c", "import numpy"], capture_output=True).returncode == 0), None)
    if not base:
        sys.exit("找不到有 numpy 的 Python（判斷表要 numpy）：PENGLAI_NUMPY_PYTHON=<python> 指定一個，停下")
    print(f"建 {d}（{base}，pip 裝 wordfreq=={ver}）", file=sys.stderr)
    subprocess.run([base, "-m", "venv", "--system-site-packages", d], check=True)
    subprocess.run([py, "-m", "pip", "install", "--quiet", "--disable-pip-version-check", f"wordfreq=={ver}"], check=True)
    r = subprocess.run([py, "-I", "-c", check], capture_output=True, text=True)
    if r.returncode != 0 or r.stdout.strip() != ver:
        sys.exit(f"{d} 裝不好 wordfreq {ver}：{r.stderr.strip() or r.stdout.strip()}，停下")
    return py


def generated_path(name):
    """中英混輸資料放的位置：.build/twdata/<sha256 前 12 碼>/<檔名>（versions.env 沒寫 sha256 時 None）"""
    sha = versions().get(GENERATED[name])
    return os.path.join(W, ".build", "twdata", sha[:12], name) if sha else None


def generate_en():
    """產生三個中英混輸資料檔（見檔頭），對 versions.env 的 sha256 之後放到 generated_path"""
    v = versions()
    py = wordfreq_python()
    work = os.path.join(W, ".build", "twdata", "penglai-en-work")
    shutil.rmtree(work, ignore_errors=True)
    os.makedirs(os.path.join(work, "dict"))
    tools = os.path.join(W, "tools")
    en = os.path.join(work, "en_words.tsv")
    print(f"產生中英混輸資料（wordfreq {v['WORDFREQ_VERSION']}，約 70 秒）：{work}", file=sys.stderr)
    with open(en, "w", encoding="utf-8") as out:
        subprocess.run([py, "-I", "-c",
                        "import re; from wordfreq import top_n_list as t, zipf_frequency as z\n"
                        "for w in t('en', 300000):\n"
                        "    if re.fullmatch('[a-z]+', w): print(f'{w}\\t{z(w, \"en\"):.2f}')"],
                       stdout=out, check=True)
    d = os.path.join(work, "dict")
    shutil.copy(os.path.join(W, "rime-config", "penglai_zhuyin.readings.tsv"), os.path.join(d, "readings.tsv"))
    shutil.copy(os.path.join(W, "rime-config", "penglai_zhuyin.schema.yaml"), os.path.join(d, "schema.yaml"))
    run = lambda *a: subprocess.run([py, "-I", *a], check=True, stdout=subprocess.DEVNULL)
    run(os.path.join(tools, "gen_terra_tw.py"), "--rime", d, "--readings", os.path.join(d, "readings.tsv"),
        "--schema", os.path.join(d, "schema.yaml"))
    run(os.path.join(tools, "gen_en_lexicon.py"), en, os.path.join(work, "penglai_en.txt"))
    run(os.path.join(tools, "gen_judge.py"), en, os.path.join(work, "penglai_judge.tbl"))
    run(os.path.join(tools, "gen_keylid.py"), en, os.path.join(work, "penglai_keylid.tbl"),
        "--dict=" + os.path.join(d, "penglai_zhuyin.dict.yaml"))
    bad = []
    for name, key in GENERATED.items():
        f = os.path.join(work, name)
        got, want = sha256_of(f), v.get(key)
        if got != want:
            bad.append(f"  {key}={got}（versions.env：{want or '沒寫'}）")
            continue
        dst = generated_path(name)
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        os.replace(f, dst)
    if bad:
        sys.exit("中英混輸資料的 sha256 跟 versions.env 不同，停下（產生的檔留在 " + work + "）：\n" + "\n".join(bad)
                 + "\n確定要換（改了產生器、詞典或 wordfreq）就把 versions.env 換成上面的值")
    shutil.rmtree(work)


def en_license():
    v = versions()
    f = os.path.join(W, ".build", "twdata", f"penglai-en-{v['WORDFREQ_VERSION']}", "penglai_en.LICENSE.txt")
    os.makedirs(os.path.dirname(f), exist_ok=True)
    with open(f, "w", encoding="utf-8") as out:
        out.write(EN_NOTICE.format(wordfreq=v["WORDFREQ_VERSION"], moe=v["MOEDICT_COMMIT"][:7],
                                   wordfreq_license=WORDFREQ_LICENSE))
    return f


def path(name):
    if name == "penglai_predict.LICENSE.txt":
        return predict_license()
    if name == "penglai_en.LICENSE.txt":
        return en_license()
    if name in GENERATED:
        f = generated_path(name)
        if not (f and os.path.exists(f) and sha256_of(f) == versions()[GENERATED[name]]):
            generate_en()
        return generated_path(name)
    if name in RELEASES:
        url, sha = RELEASES[name]
        v = versions()
        return fetch_release(v[url], v[sha])
    key, repo, p = FILES[name]
    return fetch(repo, versions()[key], p)


if __name__ == "__main__":
    names = sys.argv[1:]
    bad = [n for n in names if n not in FILES and n not in RELEASES and n not in GENERATED
           and n not in ("penglai_predict.LICENSE.txt", "penglai_en.LICENSE.txt")]
    if not names or bad:
        sys.exit(__doc__ + (f"\n不認得：{bad}" if bad else ""))
    for n in names:
        print(path(n))
