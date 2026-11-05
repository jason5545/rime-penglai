# 授權與來源

2026-10-30 依 `versions.env` 鎖定的上游版本整理。換上游版本時要重查一次：授權會變，像 librime-octagram 鎖的這版是 GPL-3.0，之後的版本改成 BSD-3-Clause。

## 這個 repo 自己的部分

- **程式**：librime 和鼠鬚管的 patch（`patches/`）、蓬萊外掛模組（`plugins/penglai/`）、工具、建置與安裝腳本、設定說明、說明書網站，以 GNU GPL 第 3 版釋出，全文在 `LICENSE`。貂毫 Sable 是鼠鬚管（GPL-3.0）的改作，整個 App 照 GPL-3.0 散布。
- **詞典與讀音資料**：`tools/gen_terra_tw.py` 產生的蓬萊注音詞典、`rime-config/penglai_zhuyin.readings.tsv`、`rime-config/penglai_zhuyin.add.txt`、`rime-config/terra_pinyin.remove.txt`，是從 LGPL-3.0 的 Rime 資料改作的，以 GNU LGPL 第 3 版釋出，全文在 `COPYING.LESSER`（LGPL 是附加在 `LICENSE` 的 GPL 上的條款）。另外要照下面「資料來源」的要求標示出處。

## 程式元件

| 元件（鎖定版本） | 用在哪 | 授權 | 著作權 | 全文 |
|---|---|---|---|---|
| librime 1.17.0（`33e7814`） | 引擎，改動在 `jason5545/librime` 的 `penglai` 分支（`versions.env`） | BSD-3-Clause | Copyright (c) 2014, RIME Developers | `licenses/librime.txt` |
| librime-lua（`ec52e48`） | Lua 外掛 | BSD-3-Clause | Copyright (c) 2021, librime-lua Developers | `licenses/librime-lua.txt` |
| Lua 5.4.9（librime-lua thirdparty `9e5bb71`） | Lua 直譯器 | MIT | Copyright (C) 1994-2026 Lua.org, PUC-Rio | `licenses/lua.txt` |
| librime-octagram（`dfcc151`） | 語言模型 | GPL-3.0 | Copyright RIME Developers | `LICENSE` |
| librime-predict（`920bd41`） | 聯想，打上 `patches/librime-predict` | BSD-3-Clause | Copyright (c) 2023, RIME Developers | `licenses/librime-predict.txt` |
| 鼠鬚管 Squirrel（`46962d2`） | 貂毫的前端，打上 `patches/squirrel` | GPL-3.0 | Copyleft, RIME Developers（式恕堂） | `LICENSE` |
| glog（`7b134a5`） | librime 靜態相依 | BSD-3-Clause | Copyright (c) 2024, Google Inc. | `licenses/glog.txt` |
| LevelDB（`99b3c03`） | librime 靜態相依（學習紀錄） | BSD-3-Clause | Copyright (c) 2011 The LevelDB Authors | `licenses/leveldb.txt` |
| marisa-trie（`3e87d53`） | librime 靜態相依 | BSD-2-Clause 或 LGPL-2.1-or-later（雙授權） | Copyright (c) 2010-2025, Susumu Yata | `licenses/marisa-trie.txt` |
| OpenCC（`556ed22`） | librime 靜態相依、繁簡轉換表 | Apache-2.0 | BYVoid 等 | `licenses/opencc.txt` |
| yaml-cpp（`2f86d13`） | librime 靜態相依 | MIT | Copyright (c) 2008-2015 Jesse Beder | `licenses/yaml-cpp.txt` |
| Boost（只用標頭） | librime 編譯 | BSL-1.0 | 各作者 | `licenses/boost.txt` |

librime 的靜態相依是鼠鬚管 `action-install.sh` 下載的官方 rime-deps 包，版本是 librime 1.17.0 `deps/` 子模組指的 commit。

## 資料來源

| 來源（鎖定版本） | 拿來做什麼 | 授權與標示 |
|---|---|---|
| rime/rime-terra-pinyin（`fa30016`） | 詞典產生器的詞彙和拼音來源 | LGPL-3.0。地球拼音本身參考 CC-CEDICT（MDBG，https://cc-cedict.org/wiki/ ），CC BY-SA 3.0（https://creativecommons.org/licenses/by-sa/3.0/ ）。 |
| rime/rime-essay（`816b9ee`） | 詞頻；App 附 `essay.txt` | LGPL-3.0 |
| rime/rime-prelude（`db691d2`） | App 附 `key_bindings.yaml`、`punctuation.yaml` | LGPL-3.0 |
| rime/rime-stroke（`3a4b0f4`） | App 附 `stroke.dict.yaml`、`stroke.schema.yaml`（筆畫反查） | LGPL-3.0 |
| lotem/rime-octagram-data（`bb8e131`，hant 分支） | 重建個人語言模型的基底，不放進 App | LGPL-3.0 |
| rime/librime-predict release data-1.0 | App 附 `penglai_predict.db`（聯想） | release 沒寫授權；來源是 rime-essay、rime-octagram-data，兩者都是 LGPL-3.0。App 另附 `penglai_predict.LICENSE.txt`。 |
| openvanilla/McBopomofo（`18e2060`） | 臺灣讀音（`BPMFBase.txt`、`BPMFMappings.txt`） | MIT，Copyright (c) 2011-2026 Mengjuei Hsieh et al.，全文 `licenses/mcbopomofo.txt` |
| 教育部《重編國語辭典修訂本》，經 g0v/moedict-data（`a6dc997`） | 臺灣讀音；App 附的中英混輸判斷表 `penglai_judge.tbl`、按鍵語言辨識表 `penglai_keylid.tbl` 的中文語料 | 辭典本文著作權屬教育部，以 CC BY-ND 3.0 TW（https://creativecommons.org/licenses/by-nd/3.0/tw/ ）公眾授權。依教育部的解釋，禁止改作限制的是文字資料本身，不限制格式轉換和後續應用。詞典只取讀音；兩份表取整份辭典的漢字（詞條、釋義、例句、引文），只存字三元次數和按鍵 5-gram 的機率，不存原文。moedict-data 轉換格式的編輯著作由 @kcwu 以 CC0 釋出。 |
| rspeer/wordfreq 3.1.1（PyPI，`versions.env` 的 `WORDFREQ_VERSION`） | App 附的中英混輸單字表 `penglai_en.txt`；判斷表、按鍵語言辨識表的英文字母模型 | 程式 Apache-2.0（不隨 App 散布），資料 CC BY-SA 4.0（https://creativecommons.org/licenses/by-sa/4.0/ ），從它算出來的部分照同一授權散布。wordfreq 的資料另含 Google Books Ngrams、Leeds Internet Corpus、Wikipedia、ParaCrawl、OPUS OpenSubtitles 2018、SUBTLEX（Marc Brysbaert 等人；要標示 SUBTLEX 作者、說明 SUBTLEX 是免費資料）、Twitter 統計等來源的標示條件。App 另附 `penglai_en.LICENSE.txt`，內有套件 METADATA License 段的原文。 |
| OpenCC 轉換表（`TSCharacters`、`TSPhrases`、`TWVariants`） | App 附在 `opencc/` | Apache-2.0，全文 `licenses/opencc.txt` |
