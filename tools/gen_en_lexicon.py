"""產生蓬萊韻「英文單字進整句」用的單字表 penglai_en.txt（translator/english_lexicon，librime patch 0003）。

usage: python3 -I tools/gen_en_lexicon.py <en_words.tsv> [out]   （預設輸出 .build/penglai_en.txt）
  en_words.tsv：「單字<TAB>Zipf」，wordfreq 3.1.1 的英文前 30 萬詞（產生方法見 tools/lm/ntc.py 檔頭）。
  只留純小寫 a–z、2 個字母以上、Zipf >= 3 的詞；長度、Zipf 的門檻引擎再照設定篩一次
  （english_min_length、english_min_zipf，載入時就丟掉，不佔記憶體）。

授權：wordfreq 程式 Apache-2.0，資料 CC BY-SA 4.0（另含 Google Books Ngrams、SUBTLEX、OpenSubtitles 等來源的署名條件）。
單字表不進 repo。11/1 起貂毫的 SharedSupport 附這份（tools/upstream.py 第一次用到時用這支產生、對 versions.env 的 PENGLAI_EN_SHA256）；
使用者資料夾有同名檔時引擎用使用者的。
"""
import os, re, sys

MIN_ZIPF, MIN_LEN = 3.0, 2
REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
src = sys.argv[1]
out = sys.argv[2] if len(sys.argv) > 2 else os.path.join(REPO, ".build", "penglai_en.txt")
words = []
for line in open(src, encoding="utf-8"):
    w, z = line.rstrip("\n").split("\t")
    if re.fullmatch("[a-z]+", w) and len(w) >= MIN_LEN and float(z) >= MIN_ZIPF:
        words.append((w, float(z)))
with open(out, "w", encoding="utf-8") as f:
    f.write("# 蓬萊韻英文單字表：單字<TAB>Zipf（log10 每十億詞出現次數）。tools/gen_en_lexicon.py 產生，不要手改\n")
    f.write("# 資料：wordfreq 3.1.1（https://github.com/rspeer/wordfreq），CC BY-SA 4.0\n")
    for w, z in words:
        f.write(f"{w}\t{z:.2f}\n")
print(f"{out}：{len(words)} 個詞（a–z、>= {MIN_LEN} 個字母、Zipf >= {MIN_ZIPF}）")
