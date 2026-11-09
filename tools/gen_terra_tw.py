"""蓬萊注音的詞典 penglai_zhuyin.dict.yaml：先建原始讀音表（收什麼讀音），再照比重政策產生詞典（怎麼排）。

usage: python3 -I tools/gen_terra_tw.py [--rime DIR] [--upstream FILE] [--static taiwan|equal|mainland]
                                         [--readings FILE] [--report FILE] [--schema FILE] [--glue-ratio X]
  預設寫到 ~/Library/Rime/penglai_zhuyin.dict.yaml，地球拼音、essay 讀 versions.env 鎖的版本（tools/upstream.py）。
  改完要重新部署（貂毫 Sable --reload；切換前 Squirrel --reload）。
  詞典一份帶三種比重政策（10/29）：weight 欄是臺灣優先，weight@reading_zhongzhou、weight@reading_jianshou 欄是大陸優先、
    兩岸同等。畫面上的名稱是蓬萊音（預設）、中州音、兼收並蓄，方案選項 reading_penglai／reading_zhongzhou／reading_jianshou
    （蓬萊改過的 librime 部署時各多編一張表，打字時照選項挑表，切換不用重新部署，見 docs/zhuyin-root.md「讀音政策打字時切換」）。
    變體欄空著＝跟 weight 欄一樣；那個政策照 essay 詞頻（weight 欄空著的意思）時寫 100%，部署出來的比重跟空著完全相同。
  --static：只輸出一種政策的靜態詞典（weight 欄＝那個政策，沒有變體欄），給基準對照用，正式環境不用。
    --static taiwan 跟 10/29 之前的預設輸出逐位元組相同。
  --readings：原始讀音表，預設 rime-config/penglai_zhuyin.readings.tsv。每次都從來源重建，內容變了才寫回，並印出差幾行。
  --report：把任何一種政策跟地球拼音原本不同的讀音寫成 TSV（類別、字詞、碼、來源、地球拼音比重、三種政策的比重）。
  --schema、--glue-ratio：罕用黏合音節（docs/optimization.md 第 4 項第 4 條 4C）。聲母接零聲母音節剛好也拼得成一個音節
    （ㄐ＋ㄩㄥˋ＝ㄐㄩㄥˋ「䅃」），而且用量不到零聲母那個的 GLUE_RATIO 時，引擎切音節時把它改成簡拼類型，簡拼的切法才留得住。
    清單寫在方案檔（預設 rime-config/penglai_zhuyin.schema.yaml）標記之間的 translator/glue_syllables，內容變了才寫回、
    印出多了少了哪些。用量照蓬萊音的比重算，三種讀音共用一份方案檔。音節裡有字的這個讀音有人在用（essay 有、比重 > 0）就不列，
    不然只打完整注音的人打那個字會排到後面。打法是 full（translator/typing_style，librime 0041）時引擎不改。
    10/31 晚上以前清單寫成 speller/algebra 的三條規則（abbrev → erase → xform），librime 0041 搬進引擎，結果逐位元組相同。

路線 C（docs/zhuyin-root.md「路線」）：注音為根、兩邊都收、比重是政策。
- 原始表（格式寫在表的檔頭）：一行一個讀音、存注音，附來源標籤：moe 教育部讀音（重編國語辭典修訂本，萌典資料）、
  mcb 臺灣語音（小麥注音）、terra 大陸審音（地球拼音，讀音來自 CC-CEDICT）、add 手加的臺灣用語。
  字詞照地球拼音（扣掉 rime-config/terra_pinyin.remove.txt，加上 rime-config/penglai_zhuyin.add.txt），
  讀音是三個來源的聯集，不拿掉任何一邊。教育部、小麥注音的注音直接用，不再轉成拼音再轉回來；
  地球拼音照 zhuyin.yaml 的規則轉成注音（tools/zhuyin.py），轉完同字同音的（𥦷 weng4／wong4）併成一行。
  萌典把兒化併成一個音節（天兒 ㄊㄧㄢㄦ），拆成「本字＋ㄦ˙」（跟地球拼音的 r5 一樣）；小麥注音的ㄧㄜ（意 ㄧㄜˋ）當ㄧㄝ。
- 比重政策只決定比重，三種政策的讀音集合完全相同（產生器每次都比對，不同就停）。
  政策不排的讀音一律 0%：收著、打全碼查得到，但排最後。不用 1%：加進來的讀音會把字的比重總和撐大，
  librime 替沒標讀音的詞自動編碼只用比重 ≥ 總和 5% 的讀音（entry_collector.cc），原本剛好 5% 的讀音（數 ㄕㄨㄛˋ）就會掉出去。

臺灣優先（taiwan，預設；畫面上叫蓬萊音）：延續 10/28 的規則，地球拼音原有的讀音比重跟路線 A 相同，加進來的讀音另外排。
1. 單字讀音比重：內建來自大陸的 CC-CEDICT，「柏」是 ㄅㄞˇ 90%、ㄅㄛˊ 10%。
   - 臺灣讀音＝教育部單字讀音 ∪ 小麥注音 BPMFBase。地球拼音有、臺灣讀音沒有的（大陸才有）降到 1%。
   - 換第一讀音要證據很明確：教育部辭典的多字詞（按 essay 詞頻加權）裡，內建排第一的讀音用量不到最常見讀音的 5%
     （柏 ㄅㄞˇ 0 對 ㄅㄛˊ 19059、期 ㄑㄧ 0 對 ㄑㄧˊ 439596、任 ㄖㄣˊ 對 ㄖㄣˋ 3.9%）。換掉的讀音留 10%。
     單字單用的詞頻算給小麥注音 heterophony1.list 的讀音（「都」單用ㄉㄡ 40 萬，只看詞會被首都、都市拉成ㄉㄨ）。
     只改小麥注音標成 Big5 的字；內建標 ≤ 1% 的讀音，只有在被換掉的第一讀音是大陸才有的時候才拉上來。
     教育部這份資料有些是 2012 審訂前的讀音（市場 ㄕˋ ㄔㄤˊ），單字用量讓「場」的ㄔㄤˇ留在第一。
     不照比例重算：試過全部照用詞比例，「給」被供給、給予拉成ㄐㄧˇ，「切」被一切拉成ㄑㄧㄝˋ，「個」「子」被拉成輕聲，
     單字單用的讀音不一定是詞裡最常見的那個。輕聲讀音不動。用詞證據合計 < 50 的字只降大陸讀音。
   - 地球拼音沒有的臺灣讀音：證據夠、該排第一的（上一條換第一時，最常見的讀音地球拼音沒有）給原本第一的比重，其餘 0%。
   - 語氣詞 ㄟ（PARTICLE_PCT）：臺灣打的是「欸」（有欸、好欸），「誒」幾乎不用（三萬多則口語語料只有 9 次）。
     「誒」在地球拼音只有 ㄟ 一個讀音（大陸才有，教育部、小麥注音是 ㄒㄧ、ㄝˋ、ㄞ、ㄞˋ），上面的規則只處理兩個讀音以上的字，
     碰不到；essay 詞頻「誒」4279 又比「欸」74 高，首符號 ㄟ 一直出「誒」（ㄩㄟ 用誒、ㄧㄟ 有誒）。
     欸的 ㄟ、ㄟˋ 照 essay 詞頻，誒的 ㄟ 照大陸才有的讀音降到 1%。
   比重會影響兩件事：單字候選的排序，以及沒標讀音的詞怎麼自動編碼。
2. 詞：地球拼音的讀音照舊。地球拼音的讀音都不在教育部的讀音裡時（垃圾 ㄌㄚ ㄐㄧ → ㄌㄜˋ ㄙㄜˋ），教育部的讀音照 essay 詞頻排；
   教育部沒有這個詞、小麥注音有的，只差聲調以外的讀音照 essay 詞頻排（小麥注音常列好幾種讀法，那邊 ㄋㄚˇ 會跟哪邊打架）。
   其他教育部、小麥注音的讀音 0%。地球拼音的讀音不降：教育部常以讀音為準（滑稽 ㄍㄨˇ ㄐㄧ、姊姊 ㄗˇ ㄗ˙），
   大家實際打的語音（ㄏㄨㄚˊ ㄐㄧ、ㄐㄧㄝˇ ㄐㄧㄝ˙）多半就是地球拼音那個。
3. 輕聲字也能用本調打（10/28）：讀音有輕聲的詞，補上輕聲字換成本調的讀音（認識 ㄖㄣˋ ㄕ˙ → ㄖㄣˋ ㄕˋ）。
   讀音集合：每個輕聲字換成那個字音相同（只差聲調）的任何一個非輕聲讀音，或不換，全部組合都收（跟政策無關）。
   比重：輕聲字全部換成這個政策下比重最高的同音本調，那一個照 essay 詞頻排，其他 0%；原本那個讀音政策要排才排。
4. 一、不的變調（11/9，docs/optimization.md 第 8 項；三種政策都做）：「一」接一、二、三聲補 ㄧˋ，接四聲補 ㄧˊ，「不」接四聲補 ㄅㄨˊ，
   接輕聲不補；「一」的前一個字是數字、第、初、統、唯這類（YI_KEEP_AFTER），或後一個字是數字時不補。本調讀音照留，兩種打法都打得到。
   單字「一」的 ㄧˋ、ㄧˊ 各 1%，librime 自動編碼只用 ≥ 5% 的讀音，essay 才有的詞（一隻、一些、一直）原本只有本調 ㄧ，打變調叫不出來。
   這裡只推有讀音的詞（原始表、規則 3 的本調）；沒寫讀音的詞（essay 才有的、擴充詞典裡沒寫讀音的）由 librime 0074
   在自動編碼時照同一條規則補（encoder.cc），公開版設定視窗加的詞也一樣。變調讀音的比重是 essay 詞頻的 SANDHI_PCT
   （原本的讀音政策不排就 0%；引擎那邊是 kSandhiRatio，兩邊要一樣）：全額時「異常」被「一場」、「疑慮」被「一律」搶走，
   打折主要擋這種（數字在 SANDHI_PCT 旁邊）。不放進原始讀音表：跟規則 3 一樣是推出來的。
大陸優先（mainland；畫面上叫中州音）：地球拼音的讀音照地球拼音原本的比重；只有教育部、小麥注音有的讀音 0%（地球拼音沒有這個詞的照 essay 排）。
兩岸同等（equal；畫面上叫兼收並蓄）：每個讀音取臺灣優先、大陸優先兩者比重大的那個（柏 ㄅㄛˊ、ㄅㄞˇ 都是 90%，像唯音的各讀音同頻次，
  但兩邊都壓低的讀音照樣壓低）。
基準（題目來自臺灣使用者的學習紀錄）只測得出臺灣優先；另外兩種準不準，公開前要另外找題目。

為什麼要產生器：當年（2014–15）是另做一套獨立方案修讀音，方案沒人維護就沒了。這裡改成「上游＋規則」，
上游換版本就重跑，規則留在這個 repo。資料來源鎖在 versions.env（MCBOPOMOFO_COMMIT、MOEDICT_COMMIT、TERRA_PINYIN_COMMIT、
ESSAY_COMMIT），第一次跑會下載到 .build/twdata/。10/28 起不再讀已安裝的 Squirrel SharedSupport（換成貂毫之後它只帶 12 個檔）。
"""
import argparse, collections, hashlib, itertools, json, lzma, os, re, sys

W = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(W, "tools"))
import zhuyin
import upstream as up
from upstream import fetch, versions

HAN = re.compile(r"[㐀-鿿\U00020000-\U0002ffff]+")
TONES = zhuyin.TONES
SYL = re.compile(f"[{zhuyin.ZY}]+[{TONES}]?")
ERHUA = re.compile(f"([{zhuyin.ZY}]+?)([{TONES}]?)ㄦ([{TONES}]?)")
SOURCES = ("moe", "mcb", "terra", "add")
POLICIES = {"taiwan": "臺灣優先", "equal": "兩岸同等", "mainland": "大陸優先"}
DEFAULT_POLICY = "taiwan"   # 詞典的 weight 欄；其他政策放在 weight@<方案選項> 欄
# 畫面上的名稱和方案選項（penglai_zhuyin.schema.yaml 的 switches）；選項名稱＝變體欄名。照這個順序（跟方案檔的選項同順序）
NAMES = {"taiwan": ("蓬萊音", "reading_penglai"), "mainland": ("中州音", "reading_zhongzhou"), "equal": ("兼收並蓄", "reading_jianshou")}
MIN_SHARE = 50      # 臺灣用詞證據（加權合計）少於這個就不重算比重
PRC_PCT = 1.0       # 臺灣優先：大陸才有的讀音降到的比重
WEAK = 0.05         # 用詞證據不到最常見讀音的 5%，算「臺灣幾乎不用」
DEMOTED_PCT = 10.0  # 換掉第一之後，原本的讀音最多留 10%（還 ≥ 5%，沒標讀音的詞照樣會用它編碼）
KEEP_PCT = "0%"     # 政策不排的讀音：收著、查得到，排最後（見檔頭）
DEFAULT_READINGS = os.path.join(W, "rime-config", "penglai_zhuyin.readings.tsv")
DEFAULT_SCHEMA = os.path.join(W, "rime-config", "penglai_zhuyin.schema.yaml")
# 罕用黏合音節（docs/optimization.md 第 4 項第 4 條 4C）：聲母＋零聲母音節（同聲調）剛好也是一個音節，
# 用量不到零聲母那個的 GLUE_RATIO 時，引擎切音節時把它改成簡拼類型（方案檔 translator/glue_syllables，見 write_glue）
GLUE_RATIO = 0.001
INITIALS = "ㄅㄆㄇㄈㄉㄊㄋㄌㄍㄎㄏㄐㄑㄒㄓㄔㄕㄖㄗㄘㄙ"
GLUE_BEGIN = "  # >>> 罕用黏合音節（tools/gen_terra_tw.py 產生，不要手改；門檻 GLUE_RATIO）"
GLUE_END = "  # <<< 罕用黏合音節"
# 臺灣優先的單字比重另外指定（檔頭規則 1 最後一條）：語氣詞 ㄟ 要「欸」不要「誒」
PARTICLE_PCT = {("欸", "ㄟ"): "100%", ("欸", "ㄟˋ"): "100%", ("誒", "ㄟ"): f"{PRC_PCT:g}%"}
# 一、不的變調（檔頭規則 4）：數字後面、序數、「統一」「唯一」這類的「一」不變調
NUMERALS = set("〇零一二三四五六七八九十百千萬億兩廿卅")
YI_KEEP_AFTER = NUMERALS | set("第初統唯專單逐獨惟")
# 變調讀音的比重（essay 詞頻的 20%）：11/9 新詞句全碼 100% 改對 131、改錯 14，50% 131／12，20% 130／11，5% 122／9。
# 沒寫讀音的詞由 librime 0074 補（encoder.cc 的 kSandhiRatio），兩邊要一樣
SANDHI_PCT = 20.0


def is_char(text, code):
    return len(text) == 1 and " " not in code


def neutral(s):
    return s.endswith("˙")


def body(s):
    return s.rstrip(TONES)


def toneless(code):
    return " ".join(body(s) for s in code.split())


def pct_of(w):
    """比重字串 → 百分比；沒標（照 essay 詞頻）算 100"""
    return float(w[:-1]) if w.endswith("%") else 100.0


def norm_code(syls, text):
    """注音音節串 → 蓬萊注音碼（輕聲符號放最後）；音節數要等於字數，不合就回 None"""
    out = []
    for s in syls:
        s = s.strip()
        if s.startswith("˙"):
            s = s[1:] + "˙"
        out.append(s)
    if len(out) != len(text):
        # 萌典的兒化：天兒 ㄊㄧㄢㄦ、路兒 ㄌㄨˋㄦ → 本字＋ㄦ˙，拆出來的位置要是「兒」
        sp = []
        for s in out:
            m = ERHUA.fullmatch(s)
            if m and len(sp) + 1 < len(text) and text[len(sp) + 1] == "兒":
                sp += [m.group(1) + (m.group(2) or m.group(3)), "ㄦ˙"]
            else:
                sp.append(s)
        out = sp
    out = [s.replace("ㄧㄜ", "ㄧㄝ") for s in out]   # 標準注音沒有ㄧㄜ（小麥注音「意」ㄧㄜˋ），照拼音 ye 當ㄧㄝ
    if len(out) != len(text) or not all(SYL.fullmatch(s) for s in out):
        return None
    return " ".join(out)


# ── 來源 ──────────────────────────────────────────────

def load_sources(upstream):
    v = versions()
    mcb_sha, moe_sha = v["MCBOPOMOFO_COMMIT"], v["MOEDICT_COMMIT"]
    src = {
        "base": fetch("openvanilla/McBopomofo", mcb_sha, "Source/Data/BPMFBase.txt"),
        "maps": fetch("openvanilla/McBopomofo", mcb_sha, "Source/Data/BPMFMappings.txt"),
        "het": fetch("openvanilla/McBopomofo", mcb_sha, "Source/Data/heterophony1.list"),
        "moe": fetch("g0v/moedict-data", moe_sha, "dict-revised.json.xz"),
    }
    moe = collections.defaultdict(set)      # 字詞 → {注音碼}，萌典所有詞（臺灣用詞證據也用它）
    for e in json.loads(lzma.open(src["moe"]).read()):
        t = e["title"]
        if not HAN.fullmatch(t):
            continue
        for h in e["heteronyms"]:
            b = re.sub(r"（[^）]*）", " ", h.get("bopomofo") or "").replace("　", " ").split()
            c = norm_code(b, t) if b else None
            if c:
                moe[t].add(c)
    mcb = collections.defaultdict(set)
    big5 = set()
    for ln in open(src["base"], encoding="utf-8"):
        p = ln.split()
        if len(p) < 2:
            continue
        if p[-1].startswith("big5"):
            big5.add(p[0])
        c = norm_code([p[1]], p[0]) if HAN.fullmatch(p[0]) and len(p[0]) == 1 else None
        if c:
            mcb[p[0]].add(c)
    for ln in open(src["maps"], encoding="utf-8"):
        p = ln.split()
        c = norm_code(p[1:], p[0]) if len(p) >= 2 and HAN.fullmatch(p[0]) else None
        if c:
            mcb[p[0]].add(c)
    het = []
    for ln in open(src["het"], encoding="utf-8"):
        p = ln.split()
        c = norm_code([p[1]], p[0]) if len(p) == 2 else None
        if c:
            het.append((p[0], c))
    essay = {}
    for ln in open(up.path("essay.txt"), encoding="utf-8"):
        p = ln.rstrip("\n").split("\t")
        if len(p) == 2:
            essay[p[0]] = int(p[1])

    lines = open(upstream, encoding="utf-8").read().split("\n")
    at = lines.index("...") + 1
    head = lines[:at]
    remove = {ln for ln in open(os.path.join(W, "rime-config/terra_pinyin.remove.txt"), encoding="utf-8").read().split("\n")
              if ln and not ln.startswith("#")}
    missing = remove - set(lines[at:])
    if missing:
        print(f"⚠️ remove.txt 有 {len(missing)} 行上游已經沒有（上游改版？），略過", file=sys.stderr)
    terra = []
    for ln in lines[at:]:
        if not ln or ln.startswith("#") or ln in remove:
            continue
        p = ln.split("\t")
        terra.append((p[0], zhuyin.code_from_pinyin(p[1]), p[2] if len(p) > 2 else ""))
    add = []
    for ln in open(os.path.join(W, "rime-config/penglai_zhuyin.add.txt"), encoding="utf-8").read().split("\n"):
        if ln and not ln.startswith("#"):
            p = ln.split("\t")
            add.append((p[0], p[1], p[2] if len(p) > 2 else ""))
    return dict(moe=moe, mcb=mcb, big5=big5, het=het, essay=essay, head=head, terra=terra, add=add,
                removed=len(remove) - len(missing), upstream_sha1=hashlib.sha1(open(upstream, "rb").read()).hexdigest(),
                mcb_sha=mcb_sha, moe_sha=moe_sha)


# ── 原始讀音表 ────────────────────────────────────────

def build_readings(S):
    """[(字詞, 注音碼, 來源集合, 地球拼音比重)]。順序：地球拼音原本的順序、手加的、其他來源才有的（依字詞、碼排）"""
    tab = collections.OrderedDict()
    for t, c, w in S["terra"]:
        tab.setdefault((t, c), [set(), w])[0].add("terra")
    for t, c, w in S["add"]:
        tab.setdefault((t, c), [set(), w])[0].add("add")
    vocab = list(dict.fromkeys(t for t, c in tab))
    extra = collections.defaultdict(set)
    for t in vocab:
        for name in ("moe", "mcb"):
            for c in S[name].get(t, ()):
                if (t, c) in tab:
                    tab[(t, c)][0].add(name)
                else:
                    extra[(t, c)].add(name)
    for k in sorted(extra):
        tab[k] = [extra[k], ""]
    return [(t, c, s, w) for (t, c), (s, w) in tab.items()]


def readings_text(rows, S):
    out = [
        "# 蓬萊注音原始讀音表：tools/gen_terra_tw.py 每次從來源重建，不要手改（要刪、加詞改 rime-config/terra_pinyin.remove.txt、",
        "# penglai_zhuyin.add.txt；讀音怎麼收改產生器）。詞典的比重不在這裡，由產生器的三種比重政策決定（產生器檔頭）。",
        "#",
        "# 一行一個讀音：字詞<TAB>注音碼<TAB>來源<TAB>地球拼音比重",
        "#   注音碼：每個字一個音節，空白隔開；一聲不加符號，輕聲符號放在音節最後（ㄕ˙）",
        "#   來源（逗號隔開，同一個讀音可能有好幾個）：",
        "#     moe    教育部讀音：教育部《重編國語辭典修訂本》（萌典 g0v/moedict-data 的 dict-revised.json）。",
        "#            萌典把兒化併成一個音節（天兒 ㄊㄧㄢㄦ），這裡拆成「本字＋ㄦ˙」",
        "#     mcb    臺灣語音：小麥注音（openvanilla/McBopomofo）的 BPMFBase.txt、BPMFMappings.txt。ㄧㄜ寫成ㄧㄝ",
        "#     terra  大陸審音：地球拼音 terra_pinyin.dict.yaml（讀音來自 CC-CEDICT），拼音照 zhuyin.yaml 的規則轉成注音",
        "#     add    臺灣用語：rime-config/penglai_zhuyin.add.txt（手加）",
        "#   地球拼音比重：地球拼音原本標的比重（90%、0%），沒標就空著。只是來源資料，不是詞典的比重",
        "# 收哪些字詞：地球拼音的字詞（扣掉 terra_pinyin.remove.txt）加 penglai_zhuyin.add.txt；",
        "#   讀音是三個來源的聯集，不拿掉任何一邊。順序：地球拼音原本的順序、手加的、其他來源才有的（依字詞、碼排）",
        f"# 來源版本：萌典 {S['moe_sha'][:12]}、小麥注音 {S['mcb_sha'][:12]}（versions.env）；"
        f"地球拼音 terra_pinyin.dict.yaml sha1 {S['upstream_sha1'][:12]}（{S['upstream_from']}）",
        "# 授權：地球拼音 CC BY-SA 3.0（CC-CEDICT）；萌典 CC BY-ND 3.0 TW；小麥注音 MIT（BPMFMappings 由 libtabe tsi.src 簡化，BSD）。",
        "#   三者混在同一份表裡能不能公開散布：未查證（docs/zhuyin-root.md「公開前要處理」）",
    ]
    for t, c, s, w in rows:
        out.append("\t".join([t, c, ",".join(x for x in SOURCES if x in s), w]))
    return "\n".join(out) + "\n"


def read_readings(path):
    rows = []
    for ln in open(path, encoding="utf-8").read().split("\n"):
        if not ln or ln.startswith("#"):
            continue
        p = ln.split("\t")
        rows.append((p[0], p[1], set(p[2].split(",")), p[3] if len(p) > 3 else ""))
    return rows


# ── 比重政策 ──────────────────────────────────────────

def evidence(S):
    """臺灣用詞證據：字 → 讀音 → 用量（萌典多字詞照 essay 詞頻加權；小麥注音 heterophony1 的單字單用讀音加上單字詞頻）"""
    share = collections.defaultdict(collections.Counter)
    for t, rs in S["moe"].items():
        if len(t) < 2:
            continue
        w = (S["essay"].get(t, 0) + 1) / len(rs)
        for c in rs:
            for ch, s in zip(t, c.split()):
                share[ch][s] += w
    for ch, c in S["het"]:
        if ch in S["essay"]:
            share[ch][c] += S["essay"][ch]
    return share


def chars_taiwan(rows, share, big5):
    """臺灣優先的單字比重（檔頭規則 1）：{(字, 碼): 比重字串}"""
    by = collections.OrderedDict()
    for t, c, s, w in rows:
        if is_char(t, c):
            by.setdefault(t, []).append((c, s, w))
    out = {}
    for ch, rs in by.items():
        base = [(c, w) for c, s, w in rs if s & {"terra", "add"}]
        valid = {c for c, s, w in rs if s & {"moe", "mcb"}}
        res = dict(base)
        extra = None
        if len(base) >= 2 and ch in big5 and any(c in valid for c, _ in base):
            pct = {c: pct_of(w) for c, w in base}
            prc = [c for c in pct if c not in valid and not neutral(c)]
            ev = {c: share[ch].get(c, 0.0) for c in sorted(valid) if not neutral(c)}
            best = max(ev, key=ev.get) if ev and max(ev.values()) >= MIN_SHARE else None
            new = dict(pct)
            for c in prc:
                if pct[c] >= 5:
                    new[c] = PRC_PCT
            if best:
                weak = [c for c in ev if c != best and ev[c] <= WEAK * ev[best]]
                rivals = [c for c in pct if c != best and pct[c] >= pct.get(best, 0) and (c in prc or c in weak)]
                # 內建標 ≤ 1% 的讀音是刻意壓低的（万 ㄇㄛˋ 1%：万俟），只有被換掉的全是大陸讀音時才拉上來（識 ㄕˊ → ㄕˋ）
                top_now = [c for c in pct if pct[c] == max(pct.values())]
                if rivals and pct.get(best, 0) <= PRC_PCT and not all(c in prc for c in top_now):
                    rivals = []
                if rivals:                       # 內建排在前面的讀音，臺灣幾乎不用：換第一
                    top_pct = max(pct.values())
                    if best in pct:
                        new[best] = top_pct
                    else:
                        extra = (best, top_pct)
                    for c in weak:
                        if c in pct:
                            new[c] = min(pct[c], DEMOTED_PCT)
            elif any(pct[c] == max(pct.values()) for c in prc):   # 沒有用詞證據，第一是大陸讀音：最大比重給臺灣讀音裡比重最高的
                b2 = max((c for c in pct if c in valid), key=pct.get)
                new[b2] = max(pct.values())
            if new != pct:
                res = {c: f"{new[c]:g}%" for c in new}
        for c, s, w in rs:
            if c not in res:
                res[c] = f"{extra[1]:g}%" if extra and extra[0] == c else KEEP_PCT
        for c, w in res.items():
            out[(ch, c)] = PARTICLE_PCT.get((ch, c), w)
    return out


def chars_mainland(rows):
    return {(t, c): (w if "terra" in s else KEEP_PCT) for t, c, s, w in rows if is_char(t, c)}


def phrases_taiwan(rows):
    """臺灣優先的詞（檔頭規則 2）：{(詞, 碼): 排不排}"""
    by = collections.OrderedDict()
    for t, c, s, w in rows:
        if not is_char(t, c):
            by.setdefault(t, []).append((c, s))
    out = {}
    for t, rs in by.items():
        base = {c for c, s in rs if s & {"terra", "add"}}
        moe = {c for c, s in rs if "moe" in s}
        mcb = {c for c, s in rs if "mcb" in s}
        rank = set(base)
        if moe:
            if not base & moe:
                rank |= moe
        elif mcb:
            tl = {toneless(c) for c in base}
            rank |= {c for c in mcb if toneless(c) not in tl}
        for c, s in rs:
            out[(t, c)] = c in rank
    return out


def phrases_mainland(rows):
    has_terra = {t for t, c, s, w in rows if "terra" in s}
    return {(t, c): "terra" in s or t not in has_terra for t, c, s, w in rows if not is_char(t, c)}


def best_tones(charw):
    """(字, 無調音) → 這個政策下比重最高的非輕聲讀音（同分取原始表裡先出現的）"""
    best = {}
    for (ch, c), w in charw.items():
        if not neutral(c):
            k = (ch, body(c))
            if k not in best or pct_of(w) > pct_of(charw[(ch, best[k])]):
                best[k] = c
    return best


def tone_variants(t, c, tones):
    """輕聲字的本調讀音（檔頭規則 3）：每個輕聲字換成音相同的任何一個非輕聲讀音，或不換；不含原本那個"""
    syl = c.split()
    if len(syl) != len(t) or not any(neutral(x) for x in syl):
        return []
    opts = [[x] + (tones.get((ch, body(x)), []) if neutral(x) else []) for ch, x in zip(t, syl)]
    return [v for v in (" ".join(p) for p in itertools.product(*opts)) if v != c]


def tone_standard(t, c, best):
    """這個政策要排的那一個本調讀音：輕聲字全部換成比重最高的同音本調"""
    syl = c.split()
    if len(syl) != len(t) or not any(neutral(x) for x in syl):
        return None
    v = " ".join(best.get((ch, body(x)), x) if neutral(x) else x for ch, x in zip(t, syl))
    return v if v != c else None


def weigh(rows, S):
    """三種政策的比重：({政策: {(字詞, 碼): 比重字串}}, [本調讀音 (字詞, 碼)])。比重字串空的就是照 essay 詞頻"""
    share = evidence(S)
    cw = {"taiwan": chars_taiwan(rows, share, S["big5"]), "mainland": chars_mainland(rows)}
    cw["equal"] = {k: max((cw["taiwan"][k], cw["mainland"][k]), key=pct_of) for k in cw["taiwan"]}
    rank = {"taiwan": phrases_taiwan(rows), "mainland": phrases_mainland(rows)}
    rank["equal"] = {k: rank["taiwan"][k] or rank["mainland"][k] for k in rank["taiwan"]}
    tones = collections.defaultdict(list)
    for t, c, s, w in rows:
        if is_char(t, c) and not neutral(c):
            tones[(t, body(c))].append(c)
    have = {(t, c) for t, c, s, w in rows}
    phr = [(t, c) for t, c, s, w in rows if not is_char(t, c)]
    derived = list(dict.fromkeys((t, v) for t, c in phr for v in tone_variants(t, c, tones) if (t, v) not in have))
    std = {}
    for p in ("taiwan", "mainland"):
        best = best_tones(cw[p])
        std[p] = {(t, v) for t, c in phr if rank[p][(t, c)] for v in [tone_standard(t, c, best)] if v}
    std["equal"] = std["taiwan"] | std["mainland"]
    out = {}
    for p in POLICIES:
        wp = {}
        for t, c, s, w in rows:
            k = (t, c)
            if k in cw[p]:
                wp[k] = cw[p][k]
            elif rank[p][k] or k in std[p]:
                wp[k] = w if s & {"terra", "add"} else ""
            else:
                wp[k] = KEEP_PCT
        for k in derived:
            wp[k] = "" if k in std[p] else KEEP_PCT
        out[p] = wp
    keys = [set(v) for v in out.values()]
    if any(k != keys[0] for k in keys):
        sys.exit("三種政策的讀音集合不同（產生器的錯）")
    return out, derived


# ── 一、不的變調（檔頭規則 4）────────────────────────────

def sandhi_code(t, c):
    """一、不的變調讀音：一接一二三聲 → ㄧˋ、接四聲 → ㄧˊ；不接四聲 → ㄅㄨˊ。接輕聲不換。沒得換回 None"""
    syl = c.split()
    if len(syl) != len(t):
        return None
    out = list(syl)
    for i in range(len(t) - 1):
        nxt = syl[i + 1]
        if neutral(nxt):
            continue
        if t[i] == "一" and syl[i] == "ㄧ":
            if t[i + 1] in NUMERALS or (i > 0 and t[i - 1] in YI_KEEP_AFTER):
                continue
            out[i] = "ㄧˊ" if nxt.endswith("ˋ") else "ㄧˋ"
        elif t[i] == "不" and syl[i] == "ㄅㄨˋ" and nxt.endswith("ˋ"):
            out[i] = "ㄅㄨˊ"
    v = " ".join(out)
    return v if v != c else None


def add_sandhi(weights, pct=100.0):
    """把一、不的變調讀音加進三種政策的比重，回傳 (新加的 (字詞, 碼) 清單, 原本 0% 改排的處數)。
    有讀音的詞（原始表、輕聲字的本調）：每個讀音推出變調讀音，原本的讀音政策有排，變調照 essay 詞頻 × pct，沒排就 0%。
    原本就有這個變調讀音、但政策排 0% 的，原本的讀音有排就改成照 essay 詞頻 × pct。
    沒寫讀音的詞（essay 才有的一隻、一些，擴充詞典裡沒寫讀音的）由 librime 0074 在自動編碼時補，這裡不寫。"""
    sw = "" if pct == 100 else f"{pct:g}%"   # 變調讀音的比重（照 essay 詞頻乘上 pct）
    have = set(weights[DEFAULT_POLICY])
    new, raised = {}, 0
    texts = collections.defaultdict(list)
    for t, c in have:
        if not is_char(t, c):
            texts[t].append(c)
    for t in sorted(texts):
        for c in sorted(texts[t]):
            v = sandhi_code(t, c)
            if not v:
                continue
            for p, wp in weights.items():
                ranked = wp[(t, c)] != KEEP_PCT
                if (t, v) in have:
                    if ranked and wp[(t, v)] == KEEP_PCT:
                        wp[(t, v)] = sw
                        raised += 1
                else:
                    d = new.setdefault((t, v), {})
                    if d.get(p, KEEP_PCT) == KEEP_PCT:
                        d[p] = sw if ranked else KEEP_PCT
    for k, ws in new.items():
        for p, wp in weights.items():
            wp[k] = ws.get(p, KEEP_PCT)
    return list(new), raised


# ── 罕用黏合音節（方案檔）──────────────────────────────

def glue_syllables(wp, essay, ratio=GLUE_RATIO):
    """聲母接零聲母音節剛好黏成的音節裡，用量不到零聲母那個 ratio 的（ㄐ＋ㄩㄥˋ＝ㄐㄩㄥˋ「䅃」，ㄩㄥˋ 是「用」）。
    用量＝詞典每一行（字和詞）的 essay 詞頻 × 這個政策的讀音比重（沒標＝100%），加到碼裡的每個音節：
    只看單字會把「謝謝」的 ㄒㄧㄝ˙、「一下」的 ㄒㄧㄚ˙ 這種只在詞裡用的讀音算成 0。
    另外，音節裡只要有一個字的這個讀音有人在用（essay 有這個字、這個讀音比重 > 0），就不列：
    改成簡拼類型之後，只打完整注音的人打這個字會排到後面（糗 ㄑㄧㄡˇ 第 1 → 第 7）。
    回傳 ([(音節, 用量, 零聲母那個的用量)], {因為有字在用而不列的音節: [那些字]})"""
    use = collections.Counter()
    used = collections.defaultdict(list)
    for (t, c), w in wp.items():
        f = essay.get(t, 0) * pct_of(w) / 100
        for s in c.split():
            use[s] += f
        if is_char(t, c) and f > 0:
            used[c].append(t)
    out, skipped = [], {}
    for z in sorted(use):
        rest = z[1:]
        if z[0] in INITIALS and rest and rest[0] not in TONES and rest in use and use[z] < ratio * use[rest]:
            if z in used:
                skipped[z] = sorted(used[z])
                continue
            out.append((z, use[z], use[rest]))
    return out, skipped


def write_glue(schema, glued, ratio):
    """把方案檔標記之間的 translator/glue_syllables 換成這次算的（注音、空白分開，跟詞典的碼一樣）；
    引擎照 speller/algebra 推出每個音節的正常拼法，切音節時把那幾個拼法底下的音節改成簡拼類型（librime 0041）。
    不同才寫回，回傳 (寫了沒, 舊的清單)"""
    text = open(schema, encoding="utf-8").read()
    lines = text.split("\n")
    if GLUE_BEGIN not in lines or GLUE_END not in lines:
        sys.exit(f"{schema} 沒有罕用黏合音節的標記（{GLUE_BEGIN.strip()}）")
    i, j = lines.index(GLUE_BEGIN), lines.index(GLUE_END)
    block = [f"  # {len(glued)} 個（用量不到零聲母那個的 {ratio:g}）",
             '  glue_syllables: "' + " ".join(z for z, _, _ in glued) + '"']
    old = re.findall(r'^\s*glue_syllables: "([^"]*)"', "\n".join(lines[i + 1:j]), re.M)
    if lines[i + 1:j] == block:
        return False, old
    open(schema, "w", encoding="utf-8").write("\n".join(lines[:i + 1] + block + lines[j:]))
    return True, old


# ── 輸出 ──────────────────────────────────────────────

def variant_weight(x, base):
    """變體欄的值：跟 weight 欄一樣就空著；這個政策照 essay 詞頻（空字串）寫 100%（librime 算出來跟空著相同）"""
    return "" if x == base else (x or "100%")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--rime", default=os.path.expanduser("~/Library/Rime"))
    ap.add_argument("--upstream", help="地球拼音詞典（預設 versions.env 的 TERRA_PINYIN_COMMIT）")
    ap.add_argument("--static", choices=list(POLICIES), help="只輸出一種政策的靜態詞典（基準對照用，正式環境不用）")
    ap.add_argument("--readings", default=DEFAULT_READINGS, help="原始讀音表（每次重建，變了才寫回）")
    ap.add_argument("--report", help="把任何一種政策跟地球拼音原本不同的讀音寫成 TSV")
    ap.add_argument("--schema", default=DEFAULT_SCHEMA, help="方案檔：罕用黏合音節的規則寫在標記之間（變了才寫回）")
    ap.add_argument("--glue-ratio", type=float, default=GLUE_RATIO, help="罕用黏合音節的門檻（試門檻用；0＝不列）")
    ap.add_argument("--sandhi-pct", type=float, default=SANDHI_PCT, help="一、不的變調讀音照 essay 詞頻乘上幾 %%（試比重用）")
    a = ap.parse_args()

    S = load_sources(a.upstream or up.path("terra_pinyin.dict.yaml"))
    S["upstream_from"] = "--upstream 指定的檔" if a.upstream else f"rime/rime-terra-pinyin {versions()['TERRA_PINYIN_COMMIT'][:12]}，versions.env"
    text = readings_text(build_readings(S), S)
    old = open(a.readings, encoding="utf-8").read() if os.path.exists(a.readings) else ""
    if text != old:
        o = {ln for ln in old.split("\n") if ln and not ln.startswith("#")}
        n = {ln for ln in text.split("\n") if ln and not ln.startswith("#")}
        open(a.readings, "w", encoding="utf-8").write(text)
        print(f"{a.readings}：原始表更新，多 {len(n - o)} 行、少 {len(o - n)} 行（共 {len(n)} 行）")
    rows = read_readings(a.readings)
    weights, derived = weigh(rows, S)
    sandhi, raised = add_sandhi(weights, a.sandhi_pct)
    main_policy = a.static or DEFAULT_POLICY
    others = [] if a.static else [p for p in NAMES if p != DEFAULT_POLICY]
    wp = weights[main_policy]

    head = [re.sub(r"^name: terra_pinyin$", "name: penglai_zhuyin", ln) for ln in S["head"]]
    if others:
        head = head[:-1] + ["columns:", "  - text", "  - code", "  - weight"] + [f"  - weight@{NAMES[p][1]}" for p in others] + head[-1:]
        policy_note = (f"讀音：weight 欄是{NAMES[main_policy][0]}（方案選項 {NAMES[main_policy][1]}），"
                       + "、".join(f"weight@{NAMES[p][1]} 欄是{NAMES[p][0]}" for p in others)
                       + "；變體欄空著＝跟 weight 欄一樣，100%＝照 essay 詞頻")
    else:
        policy_note = f"比重政策：{POLICIES[main_policy]}（{main_policy}）"
    note = [f"# 蓬萊注音：由 rime-penglai/tools/gen_terra_tw.py 從原始讀音表 penglai_zhuyin.readings.tsv 產生，不要手改。"
            + policy_note,
            "# 讀音是三個來源的聯集：教育部《重編國語辭典修訂本》（萌典）、小麥注音、地球拼音（下面原本的檔頭，讀音來自 CC-CEDICT）",
            "# 碼是注音（一聲不加符號，輕聲符號放在音節最後）"]

    def line(t, c):
        x = wp[(t, c)]
        cols = [t, c, x] + [variant_weight(weights[p][(t, c)], x) for p in others]
        return "\t".join(cols).rstrip("\t")

    sec = {"terra": [], "add": [], "other": []}
    for t, c, s, w in rows:
        sec["terra" if "terra" in s else "add" if "add" in s else "other"].append(line(t, c))
    body_ = (sec["terra"] + ["", "# 臺灣用語（rime-config/penglai_zhuyin.add.txt）"] + sec["add"]
             + ["", "# 教育部、小麥注音才有的讀音"] + sec["other"]
             + ["", "# 輕聲字的本調讀音"] + [line(t, v) for t, v in derived]
             + ["", "# 一、不的變調讀音（沒寫讀音的詞由 librime 0074 在自動編碼時補）"]
             + [line(t, v) for t, v in sandhi])
    out = os.path.join(a.rime, "penglai_zhuyin.dict.yaml")
    open(out, "w", encoding="utf-8").write("\n".join(head[:1] + note + head[1:] + body_) + "\n")

    terra_w = {(t, c): w for t, c, s, w in rows if "terra" in s}
    for p in [main_policy] + others:
        w = weights[p]
        nch = sum(1 for k in w if is_char(*k))
        changed_chars = {k[0] for k in w if is_char(*k) and k in terra_w and w[k] != terra_w[k]}
        extra = "" if p == main_policy else f"；跟 weight 欄不同 {sum(1 for k in w if w[k] != wp[k])}"
        print(f"{out}（{POLICIES[p]}，{NAMES[p][0]}）：刪 {S['removed']} 行、手加 {len(S['add'])} 行；讀音 {len(w)}（單字 {nch}、詞 {len(w) - nch}，"
              f"其中本調 {len(derived)}）；排最後（{KEEP_PCT}）的 {sum(1 for x in w.values() if x == KEEP_PCT)}；"
              f"單字比重跟地球拼音不同 {len(changed_chars)} 字{extra}")
    print(f"一、不的變調：加 {len(sandhi)} 行，原本 0% 改排 {raised} 處（沒寫讀音的詞由 librime 0074 補）")
    # 罕用黏合音節照蓬萊音（臺灣優先）的比重算，方案檔三種讀音共用一份
    glued, skipped = glue_syllables(weights[DEFAULT_POLICY], S["essay"], a.glue_ratio) if a.glue_ratio > 0 else ([], {})
    changed, old_list = write_glue(a.schema, glued, a.glue_ratio)
    if skipped:
        print(f"罕用黏合音節：有字在用、不列的 {len(skipped)} 個：" + "、".join(f"{z}（{''.join(v)}）" for z, v in sorted(skipped.items())))
    if changed:
        o = set(old_list[0].split()) if old_list else set()
        n = {z for z, _, _ in glued}
        print(f"{a.schema}：罕用黏合音節更新，{len(n)} 個（多 {len(n - o)}：{' '.join(sorted(n - o))}；少 {len(o - n)}：{' '.join(sorted(o - n))}）")
    if a.report:
        src = {(t, c): s for t, c, s, w in rows}
        sandhi_set = set(sandhi)
        with open(a.report, "w", encoding="utf-8") as f:
            f.write("類別\t字詞\t碼\t來源\t地球拼音比重\t" + "\t".join(POLICIES.values()) + "\n")
            for k in wp:
                s = src.get(k)
                xs = [weights[p][k] for p in POLICIES]
                if s is not None and "terra" in s and all(x == terra_w[k] for x in xs):
                    continue
                kind = "變調" if k in sandhi_set else "本調" if s is None else "單字" if is_char(*k) else "詞"
                f.write("\t".join([kind, k[0], k[1], ",".join(y for y in SOURCES if s and y in s) or "-",
                                   terra_w.get(k, "-") or "（沒標）"] + [x or "（essay）" for x in xs]) + "\n")


if __name__ == "__main__":
    main()
