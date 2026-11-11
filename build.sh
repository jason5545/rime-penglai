#!/bin/zsh
# 建置貂毫 Sable：依 versions.env 抓上游和 jason5545/librime 的 penglai 分支 → 套 patches/（librime-predict、squirrel）→ 靜態編 librime（含 lua／octagram／predict，
# 加上這個 repo 的 plugins/penglai）
# → Xcode 編 Squirrel 原始碼（patch 0003 改名成 Sable）→ 換成自己的 SharedSupport（20 個檔，docs/sable.md 第 3 節）
# → 用 SIGN_IDENTITY 簽章 → 從 LaunchServices 取消登記 .build/ 底下的副本。只建置，不安裝。
# patches/librime-predict、patches/librime-octagram、patches/squirrel 沒有 patch 時就不套。LIBRIME_LOCAL=1：不抓、不切換 librime，直接建 librime 工作區現在的工作樹（改 librime、還沒 push 時用）。
# librime 工作區預設是 ~/GitHub/librime（fork 的本機 clone，10/31 起），LIBRIME_DIR 可以換一個 clone。
# Squirrel 的 patch：放開修飾鍵前告訴 librime 中間有它沒看到的輸入、
# 蓬萊設定視窗（原始碼在 sable/）、改名成貂毫（bundle id、輸入法 ID、通知、librime 身分，拿掉 Sparkle）。
# 產物：.build/custom-app/Sable.app。需要 Xcode、cmake、ninja、brew 的 boost（只用標頭）。約 1–2 分鐘。
set -euo pipefail
REPO="$(cd "$(dirname "$0")" && pwd)"
source "$REPO/versions.env"
B="$REPO/.build"
L="${LIBRIME_DIR:-$HOME/GitHub/librime}"; [[ -n ${LIBRIME_DIR:-} || -d $L/.git ]] || L="$B/librime"   # LIBRIME_DIR：換一個 librime 的 clone 建（預設 ~/GitHub/librime，沒有就 clone 到 .build/librime）
S="$B/squirrel"; D="$S/download"
mkdir -p "$B"

fetch() {  # fetch <url> <dir> <commit> [branch]
  local -a br=()
  [[ -n "${4:-}" ]] && br=(--branch "$4")
  [[ -d "$2/.git" ]] || git clone -q $br "$1" "$2"
  git -C "$2" cat-file -e "$3^{commit}" 2>/dev/null || git -C "$2" fetch -q origin
  git -C "$2" checkout -q -f "$3"
}

echo "== 抓上游"
# librime 的改動是 jason5545/librime penglai 分支的 commit，釘在 LIBRIME_PENGLAI_COMMIT（detached，不動本機的 penglai 分支）。
# 工作區的 origin 不是 fork 時（例如 10/31 以前從 rime/librime clone 的 .build/librime）：origin 換成 fork，上游留成 upstream（跟上游同步時 rebase 用）
if [[ -n ${LIBRIME_LOCAL:-} ]]; then
  echo "   LIBRIME_LOCAL：照 $L 現在的工作樹建（$(git -C "$L" log --oneline -1 | cut -c1-60)）"
else
  if [[ -d $L/.git ]] && [[ $(git -C "$L" remote get-url origin) != "$LIBRIME_REPO" ]]; then
    git -C "$L" remote get-url upstream >/dev/null 2>&1 || git -C "$L" remote add upstream "$(git -C "$L" remote get-url origin)"
    git -C "$L" remote set-url origin "$LIBRIME_REPO"
  fi
  if [[ -d $L/.git ]] && ! git -C "$L" diff --quiet HEAD; then
    echo "⛔ $L 有沒 commit 的改動，切到釘住的 commit 會清掉：先 commit（或 git stash），要建這份就加 LIBRIME_LOCAL=1"; exit 1
  fi
  fetch "$LIBRIME_REPO" "$L" "$LIBRIME_PENGLAI_COMMIT"
  # 本機 penglai 分支就是釘住的 commit 時切回分支，不留 detached：detached 時接著改、commit 的東西不在分支上，
  # git push origin penglai 會說 up-to-date、什麼都沒推（11/9 0073 就這樣漏推一次）。分支不是這個 commit 時照舊 detached，印出來提醒
  pin=$(git -C "$L" rev-parse "$LIBRIME_PENGLAI_COMMIT^{commit}")
  if [[ $(git -C "$L" rev-parse -q --verify refs/heads/penglai 2>/dev/null) == "$pin" ]]; then
    git -C "$L" checkout -q penglai
  else
    echo "   ⚠ $L 停在 ${pin:0:8}（detached），本機 penglai 分支不是這個 commit；要改 librime 先 git -C $L checkout penglai"
  fi
  git -C "$L" remote get-url upstream >/dev/null 2>&1 || git -C "$L" remote add upstream https://github.com/rime/librime.git
  git -C "$L" merge-base --is-ancestor "$LIBRIME_COMMIT" HEAD || { echo "⛔ LIBRIME_PENGLAI_COMMIT 不是從 LIBRIME_COMMIT 長出來的"; exit 1; }
fi
fetch https://github.com/hchunhui/librime-lua.git "$L/plugins/lua" "$LUA_COMMIT"
fetch https://github.com/hchunhui/librime-lua.git "$L/plugins/lua/thirdparty" "$LUA_THIRDPARTY_COMMIT" thirdparty
fetch https://github.com/lotem/librime-octagram.git "$L/plugins/octagram" "$OCTAGRAM_COMMIT"
fetch https://github.com/rime/librime-predict.git "$L/plugins/predict" "$PREDICT_COMMIT"
# 蓬萊外掛模組（快速鍵、數字選字、補標點、重排）：原始碼在這個 repo 的 plugins/penglai，連進去跟其他外掛一起合併
ln -sfn "$REPO/plugins/penglai" "$L/plugins/penglai"
# 外掛的 patch（patches/librime-predict、patches/librime-octagram）：fetch 只 checkout，這裡開 penglai 分支再 am
for plug commit in predict "$PREDICT_COMMIT" octagram "$OCTAGRAM_COMMIT"; do
  git -C "$L/plugins/$plug" am --abort 2>/dev/null || true
  git -C "$L/plugins/$plug" checkout -q -B penglai "$commit"
  pp=("$REPO"/patches/librime-$plug/*.patch(N))
  (( ${#pp} )) && git -C "$L/plugins/$plug" -c user.name=rime-fork -c user.email=rime-fork@localhost am -q $pp
done
fetch https://github.com/rime/squirrel.git "$S" "$SQUIRREL_COMMIT"
git -C "$S" am --abort 2>/dev/null || true
git -C "$S" checkout -q -B penglai "$SQUIRREL_COMMIT"
sp=("$REPO"/patches/squirrel/*.patch(N))
(( ${#sp} )) && git -C "$S" -c user.name=rime-fork -c user.email=rime-fork@localhost am -q $sp
# 蓬萊設定視窗、第一次使用的引導：整份是自己寫的，原始碼在這個 repo 的 sable/，連進 sources/（patch 0002、0012 只在 Xcode 專案登記檔名、接上 App）
for f in "$REPO"/sable/*.swift; do ln -sfn "$f" "$S/sources/${f:t}"; done
# 圖示（patch 0003 的 Xcode 專案指向這兩個路徑）：App 圖示 Sable.icon、選單列 penglai.pdf，來源是 branding/（tools/gen_icon.py 產生）
rm -rf "$S/Sable.icon" && cp -R "$REPO/branding/Sable.icon" "$S/Sable.icon"
cp "$REPO/branding/penglai.pdf" "$S/resources/penglai.pdf"

echo "== Squirrel 相依（官方 librime 標頭、靜態相依、opencc、plum；Sparkle 也會下載，patch 0003 已經不連它）"
(cd "$S" && bash ./action-install.sh > "$B/squirrel-install.log" 2>&1)
mkdir -p "$S/librime/include" && cp "$S"/librime/dist/include/*.h "$S/librime/include/"
ln -sfn "$L/src" "$S/librime/src"   # bridging header 要 librime 原始碼的私有標頭（rime/key_table.h）

echo "== 改過的 librime（靜態連結官方相依）"
# boost 只露出標頭：/opt/homebrew/include 會讓 yaml-cpp 等用到 brew 的新版標頭，跟官方靜態庫混用會 SIGBUS
mkdir -p "$B/boost-only/include" && ln -sfn /opt/homebrew/include/boost "$B/boost-only/include/boost"
# LTO（11/1 起預設開，公開版也開）：librime 和合併進去的外掛（lua、octagram、predict、penglai）跨檔內聯；Squirrel 下載的預編相依
# （yaml-cpp、leveldb、marisa、opencc）進不了 LTO，照常連結。LTO=0 關掉（改 librime 時想連結快一點）。輸出要跟不開時逐位元組相同（docs/findings.md〈LTO〉）
lto=ON; [[ ${LTO:-1} == 0 ]] && lto=OFF
cmake -S "$L" -B "$L/build-static" -G Ninja -DCMAKE_BUILD_TYPE=Release -DBUILD_STATIC=ON -DBUILD_TEST=OFF \
  -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=$lto \
  -DBUILD_MERGED_PLUGINS=ON -DCMAKE_OSX_DEPLOYMENT_TARGET=13.0 -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_PREFIX_PATH="$D" -DCMAKE_FIND_FRAMEWORK=NEVER -DCMAKE_POLICY_DEFAULT_CMP0167=OLD \
  -DBoost_NO_BOOST_CMAKE=ON -DBOOST_ROOT="$B/boost-only" -DBoost_INCLUDE_DIR="$B/boost-only/include" \
  -DCMAKE_DISABLE_FIND_PACKAGE_Gflags=ON > "$B/cmake.log" 2>&1
ninja -C "$L/build-static" > "$B/ninja.log" 2>&1
otool -L "$L/build-static/lib/librime.1.dylib" | grep -q homebrew && { echo "librime 連到了 brew 的函式庫，停下"; exit 1; }
[[ -f $REPO/gram/gram_dump.cc ]] && clang++ -std=c++17 -O2 -I "$L/include" "$REPO/gram/gram_dump.cc" -o "$B/gram_dump"   # 開發用的小工具，不進 App

echo "== Xcode 編貂毫"
# 產物和圖示的中間產物每次重產：Xcode 只會加檔不會刪檔，舊建置的 Rime.icns 會一直留在 App 裡（10/28 從鼠鬚管改名時遇到）
rm -rf "$S/build/Build/Products/Release/Sable.app" \
  "$S/build/Build/Intermediates.noindex/Squirrel.build/Release/Squirrel.build/assetcatalog_output"
(cd "$S" && bash package/add_data_files > /dev/null 2>&1 && \
  xcodebuild -project Squirrel.xcodeproj -configuration Release -scheme Squirrel -derivedDataPath build \
    ARCHS=arm64 ONLY_ACTIVE_ARCH=YES CODE_SIGN_IDENTITY=- build > "$B/xcodebuild.log" 2>&1)

echo "== 組裝程式包"
A="$B/custom-app/Sable.app"
X="$S/build/Build/Products/Release/Sable.app"
rm -rf "$A" && mkdir -p "$B/custom-app" && cp -R "$X" "$B/custom-app/"
cp "$L/build-static/lib/librime.1.dylib" "$A/Contents/Frameworks/librime.1.dylib"   # 符號連結指向 librime.1.<版本>.dylib，cp 會複製實體檔
rm -rf "$A/Contents/Frameworks/rime-plugins"   # 外掛已合併進 librime.1.dylib
# plum 的安裝程式（shell script）不放：蓬萊不用 plum，而且 script 的簽章存在延伸屬性裡，壓成 zip 送公證時會掉，
# Apple 回「The signature of the binary is invalid」（11/5 實測）
rm -f "$A/Contents/MacOS/rime-install"
# 版本號（versions.env 的 SABLE_VERSION）：Finder、設定視窗底下、安裝時的「要換成哪一版」讀 CFBundleShortVersionString。
# 自己建的版本後面加這個 repo 的 commit（「1.1.0 (696bc35)」，工作樹有沒 commit 的改動再加 -dirty），看得出裝的是哪一版；
# 發布（tools/release.sh 設 PENGLAI_RELEASE=1）只寫版本號。CFBundleVersion 一律只寫版本號（librime 的 distribution_version 讀它）
SHORT_VERSION="$SABLE_VERSION"
if [[ -z ${PENGLAI_RELEASE:-} ]]; then
  rev=$(git -C "$REPO" rev-parse --short=7 HEAD 2>/dev/null || true)
  if [[ -n $rev ]]; then
    [[ -z $(git -C "$REPO" status --porcelain 2>/dev/null) ]] || rev="$rev-dirty"
    SHORT_VERSION="$SABLE_VERSION ($rev)"
  fi
fi
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $SABLE_VERSION" "$A/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string $SHORT_VERSION" "$A/Contents/Info.plist" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $SHORT_VERSION" "$A/Contents/Info.plist"
# 命令列工具換成這次自建的：Squirrel 下載的是官方預編檔，直接用 librime 的 C++ 類別，librime patch 改到類別的記憶體配置時就會壞
# （10/31：裝上 0017–0019 之後 App 裡的 rime_dict_manager --export 當掉，rime-backup 匯出失敗、貂毫被關掉沒有重開）。
# 自建的 rpath 指到建置資料夾，換成跟原本那支一樣的 @loader_path/../Frameworks
for t in rime_dict_manager rime_deployer; do
  cp "$L/build-static/bin/$t" "$A/Contents/MacOS/$t"
  for rp in ${(f)"$(otool -l "$A/Contents/MacOS/$t" | awk '/LC_RPATH/{f=1} f && $1 == "path" {print $2; f=0}')"}; do
    install_name_tool -delete_rpath "$rp" "$A/Contents/MacOS/$t"
  done
  install_name_tool -add_rpath @loader_path/../Frameworks "$A/Contents/MacOS/$t"
done
# SharedSupport 換成自己的 20 個檔：plum 抓的是最新資料（跟 1.1.2 不同，還帶拼音、倉頡方案），一律用 versions.env 鎖的版本
# （tools/upstream.py）；default.yaml 用 rime-config/ 那份（只改 schema_list、menu/page_size）；前端設定檔、opencc 用這次建置的 Squirrel checkout
# （前端設定檔是 data/squirrel.yaml 改名 sable.yaml，patch 0004；opencc 是 action-install.sh 下載的 librime 1.17.0 release 附的）。
# 組完對 sharedsupport.sha1：不准多也不准少。
SS="$A/Contents/SharedSupport"
rm -rf "$SS" && mkdir -p "$SS/opencc"
for f in key_bindings.yaml punctuation.yaml essay.txt stroke.dict.yaml stroke.schema.yaml; do
  cp "$(python3 -I "$REPO/tools/upstream.py" $f)" "$SS/$f"
done
cp "$REPO/rime-config/default.yaml" "$SS/default.yaml"
# 蓬萊注音的方案和詞典（公開版第一次用就要有；使用者資料夾有同名檔時 librime 用使用者的）。詞典每次用產生器從 repo 的
# 原始讀音表重產（tools/gen_terra_tw.py，讀 versions.env 鎖的上游）；產生器想改讀音表或方案檔（罕用黏合音節）就停下：
# repo 那份還沒更新，先照 AGENTS.md 重跑產生器、commit
PD="$B/sharedsupport-dict"; rm -rf "$PD" && mkdir -p "$PD"
cp "$REPO/rime-config/penglai_zhuyin.readings.tsv" "$PD/readings.tsv"
cp "$REPO/rime-config/penglai_zhuyin.schema.yaml" "$PD/schema.yaml"
python3 -I "$REPO/tools/gen_terra_tw.py" --rime "$PD" --readings "$PD/readings.tsv" --schema "$PD/schema.yaml" > "$B/gen_terra_tw.log"
cmp -s "$PD/readings.tsv" "$REPO/rime-config/penglai_zhuyin.readings.tsv" && cmp -s "$PD/schema.yaml" "$REPO/rime-config/penglai_zhuyin.schema.yaml" \
  || { echo "產生器改了原始讀音表或方案檔（repo 那份還沒更新），停下"; exit 1; }
cp "$PD/penglai_zhuyin.dict.yaml" "$SS/penglai_zhuyin.dict.yaml"
cp "$REPO/rime-config/penglai_zhuyin.schema.yaml" "$SS/penglai_zhuyin.schema.yaml"
cp "$S/data/squirrel.yaml" "$SS/sable.yaml"
for f in t2s.json t2tw.json TSCharacters.ocd2 TSPhrases.ocd2 TWVariants.ocd2; do cp "$S/data/opencc/$f" "$SS/opencc/$f"; done
# 公開版的聯想資料（librime-predict data-1.0，LGPL-3.0）＋授權說明；使用者資料夾有同名檔時 librime 用使用者的
cp "$(python3 -I "$REPO/tools/upstream.py" predict.db)" "$SS/penglai_predict.db"
cp "$(python3 -I "$REPO/tools/upstream.py" penglai_predict.LICENSE.txt)" "$SS/penglai_predict.LICENSE.txt"
# 公開版的中英混輸資料：單字表、判斷表、按鍵語言辨識表（wordfreq＋教育部辭典，不加其他語料）＋授權說明。
# repo 不放，tools/upstream.py 第一次用到時在本機產生、對 versions.env 的 PENGLAI_*_SHA256，不同就停（從頭約 95 秒，要網路裝 wordfreq）。
# 使用者資料夾有同名檔（例如加了自己語料的那份）時 librime 用使用者的（english_lexicon.cc：先找 user_data_dir 再找 shared_data_dir）
for f in penglai_en.txt penglai_judge.tbl penglai_keylid.tbl penglai_en.LICENSE.txt; do
  src=$(python3 -I "$REPO/tools/upstream.py" $f) || { echo "中英混輸資料 $f 產生不了（上面是原因），停下"; exit 1; }
  cp "$src" "$SS/$f"
done
(cd "$SS" && find . -type f | LC_ALL=C sort | xargs shasum) | diff "$REPO/sharedsupport.sha1" - \
  || { echo "SharedSupport 跟 sharedsupport.sha1 不同（上面 < 是清單、> 是這次組的），停下"; exit 1; }
# 蓬萊設定視窗用的設定目錄：從這次建置的原始碼掃出程式會讀的設定鍵，併上 settings/notes.json 的說明
LIBRIME_DIR="$L" python3 -I "$REPO/tools/gen_settings_catalog.py" "$A/Contents/Resources/penglai-settings.json"
# 鑰匙圈沒有 SIGN_IDENTITY（自己從原始碼建的人）就用 ad-hoc 簽章：只能在建的那台用，要給別人用走 tools/release.sh
sign_id="$SIGN_IDENTITY"
security find-identity -v -p codesigning 2>/dev/null | grep -qF "\"$sign_id\"" || { echo "   鑰匙圈沒有 $sign_id，改用 ad-hoc 簽章"; sign_id=-; }
codesign --force --deep --options runtime --timestamp=none --sign "$sign_id" \
  --entitlements "$S/resources/Squirrel.entitlements" "$A"
codesign --verify --deep --strict "$A"
# 從 LaunchServices 取消登記建置過程留下的副本（Xcode 產物、這份組好的）：同一個 bundle id 登記好幾份時，系統可能解析到
# 錯的副本（Tetherline 遇過，scripts/release.sh）。輸入法只該登記一份：裝好的 ~/Library/Input Methods/Sable.app
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
for app in "$X" "$A"; do "$LSREGISTER" -u "$app" 2>/dev/null || true; done
echo "✅ $A"
