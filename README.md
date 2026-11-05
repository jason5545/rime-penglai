# 蓬萊韻

注音為根的 Rime 輸入法。前端是貂毫（Sable，從鼠鬚管改的），引擎是改過的 librime。

官網和說明書：https://penglai.im

## 下載

macOS 版貂毫：[最新版本](https://github.com/jason5545/rime-penglai/releases/latest)的 DMG（Developer ID 簽章、Apple 公證過）。打開 DMG 裡的貂毫，按「安裝」，它會把自己裝進 `~/Library/Input Methods`、加進輸入法清單、切換過去。只支援 Apple Silicon、macOS 13 以上。安裝、更新、移除見[說明書](https://penglai.im/wiki/install/)。

## 從原始碼建置

```sh
brew install cmake ninja boost
zsh build.sh          # 產物：.build/custom-app/Sable.app（約 2–5 分鐘，第一次要下載上游）
```

需要 Xcode、網路，和一個有 numpy 的 Python 3（中英混輸的表要用；`PENGLAI_NUMPY_PYTHON=<python>` 可以指定）。`build.sh` 照 `versions.env` 鎖定的版本抓上游：

- 引擎：[jason5545/librime](https://github.com/jason5545/librime) 的 `penglai` 分支（`LIBRIME_PENGLAI_COMMIT`），clone 到 `.build/librime`（`LIBRIME_DIR` 可以換）。librime-lua、librime-octagram、librime-predict 三個外掛照鎖定的 commit 抓，套 `patches/librime-*`，跟 `plugins/penglai`（快速鍵、數字選字、補標點、重排）一起靜態合併進 librime。
- 前端：[rime/squirrel](https://github.com/rime/squirrel)（`SQUIRREL_COMMIT`），套 `patches/squirrel`（改名成貂毫、接上設定視窗和安裝流程），`sable/` 是自己寫的設定視窗、第一次使用的引導和安裝流程。
- 資料：方案、詞典、筆畫、八股文、聯想資料、中英混輸的表，放進 App 的 `Contents/SharedSupport`，組完對 `sharedsupport.sha1`。蓬萊注音的詞典由 `tools/gen_terra_tw.py` 從 `rime-config/penglai_zhuyin.readings.tsv`（原始讀音表）產生；中英混輸的三張表由 `tools/upstream.py` 在本機產生，對 `versions.env` 的 sha256。

簽章：鑰匙圈裡有 `versions.env` 的 `SIGN_IDENTITY` 就用它簽，沒有就用 ad-hoc 簽章，只能在建的那台 Mac 用；要用自己的身分就改 `SIGN_IDENTITY`（`security find-identity -v -p codesigning` 列得出來的）。建好之後裝到自己的帳號：`.build/custom-app/Sable.app/Contents/MacOS/Sable --self-install`。

這裡的程式從開發用的 repo 同步過來，每一版的標籤（`v1.0.0`）就是那一版 DMG 建出來的原始碼。


## 官網

純靜態網站，`site/public/` 整個資料夾就是網站，用 Cloudflare Workers 的靜態資源發布（`site/wrangler.jsonc`）。

- 本機看：`npx serve site/public`
- 部署：`cd site && npx wrangler deploy`

說明書的頁面由 `site/wiki/` 的 HTML 片段產生，頁面上的選字窗例子是在只放公開檔案的沙盒裡逐鍵實打錄下來的（`site/wiki/examples.json`）。錄例子的工具還沒搬過來。

## 感謝

- 佛振（[lotem](https://github.com/lotem)）：Rime 的作者。蓬萊韻的引擎和貂毫都是從 Rime 改出來的。
- 瑾昀（[kunki](https://github.com/kunki)）：Rime 注音、地球拼音詞庫的維護者。
- [zhtw2013](https://github.com/zhtw2013)：RIME.TW 粉專的編輯，替地球拼音補過一批臺灣讀音。
- [osfans](https://github.com/osfans)：同文輸入法（Android 上的 Rime 前端）的作者。

## 授權

程式和網站以 GNU GPL 第 3 版釋出，全文在 `LICENSE`。詞典與讀音資料以 GNU LGPL 第 3 版釋出（`COPYING.LESSER`）。各上游元件和資料來源的授權、出處標示見 `NOTICE.md`，授權全文在 `licenses/`。
