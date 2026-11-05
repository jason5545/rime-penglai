"""注音碼的共用函式：地球拼音 → 注音、注音碼 → 大千按鍵。

蓬萊注音的碼直接存注音（柏 ㄅㄛˊ）：一聲不加符號，輕聲符號放在音節最後（ㄕ˙，跟大千的按鍵順序一樣）。
英文假音節是「注音符號＋~」（ADB → ㄇ~ ㄎ~ ㄖ~，tools/gen_en_dict.py）。
拼音轉注音的規則照 SharedSupport zhuyin.yaml 的 pinyin_to_zhuyin（舊的 bopomofo_tw 在部署時做的就是這個），
再把中間字母換成注音符號；只有詞典產生器（內部還是拼音）、學習紀錄遷移、舊資料要用。
"""
import re

PINYIN_XFORMS = [(r"^m(\d)$", r"mu\1"), (r"^r5$", "er5"), ("iu", "iou"), ("ui", "uei"), ("ong", "ung"),
                 (r"^yi?", "i"), (r"^wu?", "u"), ("iu", "v"), (r"^([jqx])u", r"\1v"), (r"([iuv])n", r"\1en"),
                 (r"^zhi?", "Z"), (r"^chi?", "C"), (r"^shi?", "S"), (r"^([zcsr])i", r"\1"), ("ai", "A"),
                 ("ei", "I"), ("ao", "O"), ("ou", "U"), ("ang", "K"), ("eng", "G"), ("an", "M"), ("en", "N"),
                 ("er", "R"), ("eh", "E"), (r"([iv])e", r"\1E")]
MID = "bpmfdtnlgkhjqxZCSrzcsiuvaoeEAIOUMNKGR"           # zhuyin.yaml 的中間字母，跟下一行一對一
ZY = "ㄅㄆㄇㄈㄉㄊㄋㄌㄍㄎㄏㄐㄑㄒㄓㄔㄕㄖㄗㄘㄙㄧㄨㄩㄚㄛㄜㄝㄞㄟㄠㄡㄢㄣㄤㄥㄦ"
INITIALS = ZY[:21]                                     # 聲母 ㄅ…ㄙ
KEY = "1qaz2wsxedcrfv5tgbyhnujm8ik,9ol.0p;/-"          # 大千鍵位，跟 ZY 一對一
TONE_MARK = {"1": "", "2": "ˊ", "3": "ˇ", "4": "ˋ", "5": "˙"}
TONE_KEY = {"": " ", "ˊ": "6", "ˇ": "3", "ˋ": "4", "˙": "7"}
TONES = "ˊˇˋ˙"
M2Z = str.maketrans(MID, ZY)
Z2M = str.maketrans(ZY, MID)
Z2K = str.maketrans(ZY, KEY)
SYLLABLE = re.compile(f"([{ZY}]+)([{TONES}]?)")


def syllable_from_pinyin(py):
    """一個地球拼音音節（xie4、英文假音節 m~）→ 注音；轉不乾淨回 None"""
    if py.endswith("~"):
        body = py[:-1]
        return body.translate(M2Z) + "~" if body and all(c in MID for c in body) else None
    m = py
    for a, b in PINYIN_XFORMS:
        m = re.sub(a, b, m)
    mm = re.fullmatch(f"([{MID}]+)([1-5])", m)
    if not mm:
        return None
    return mm.group(1).translate(M2Z) + TONE_MARK[mm.group(2)]


def code_from_pinyin(code):
    """以空白分開的拼音碼 → 注音碼；有轉不過去的音節就丟 ValueError"""
    out = []
    for s in code.split():
        z = syllable_from_pinyin(s)
        if z is None:
            raise ValueError(f"轉不過去的音節 {s!r}（{code!r}）")
        out.append(z)
    return " ".join(out)


def is_zhuyin_code(code):
    return all(SYLLABLE.fullmatch(s) for s in code.split()) and bool(code.split())


def keys_for(code, initials=None, notone=False):
    """注音碼 → 大千按鍵（空白鍵寫成 {space}）。initials="2"：每個字只打第一個注音；"1"：只打聲母，
    零聲母字打整個韻母；notone：不打聲調。碼裡有注音以外的東西（英文假音節）回 None。
    舊資料的拼音碼也收：先轉成注音再算（規則同 zhuyin.yaml，按鍵跟舊方案算的逐題相同）"""
    out = []
    for s in code.split():
        m = SYLLABLE.fullmatch(s)
        if not m:
            z = syllable_from_pinyin(s) if re.fullmatch(r"[a-z]+\d", s) else None
            m = SYLLABLE.fullmatch(z) if z else None
            if not m:
                return None
        body, tone = m.groups()
        if initials == "2":
            k = body[0].translate(Z2K)
        elif initials == "1":
            k = (body[0] if body[0] in INITIALS else body).translate(Z2K)
        elif notone:
            k = body.translate(Z2K)
        else:
            k = body.translate(Z2K) + TONE_KEY[tone]
        out.append(k)
    return "".join(out).replace(" ", "{space}") if out else None
