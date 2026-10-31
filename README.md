# 蓬萊韻

注音為根的 Rime 輸入法。前端是貂毫（Sable，從鼠鬚管改的），引擎是改過的 librime。

官網和說明書：https://penglai.im

這個 repo 正從開發用的 repo 一點一點搬過來，目前只有官網（`site/`）。引擎、前端、詞典產生器和方案之後陸續放上來。

## 官網

純靜態網站，`site/public/` 整個資料夾就是網站，用 Cloudflare Workers 的靜態資源發布（`site/wrangler.jsonc`）。

- 本機看：`npx serve site/public`
- 部署：`cd site && npx wrangler deploy`

說明書的頁面由 `site/wiki/` 的 HTML 片段產生，頁面上的選字窗例子是在只放公開檔案的沙盒裡逐鍵實打錄下來的（`site/wiki/examples.json`）。產生器和錄例子的工具還沒搬過來。
