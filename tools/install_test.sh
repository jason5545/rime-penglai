#!/bin/zsh
# usage: zsh tools/install_test.sh [Sable.app]   自己安裝（sable/PenglaiInstall.swift）在「沒裝過貂毫的 Mac」上跑一次。
#   不給路徑就測 .build/custom-app/Sable.app；要測 DMG 就掛起來給它 /Volumes/…/Sable.app。逐項印 PASS／FAIL，有一項沒過結束碼 1。
#
# 為什麼這樣測：這台已經加過貂毫，系統什麼都認得，裝起來一定順（11/5 公開版 1.0.0 在這台按「安裝」是好的，
# 別人的 Mac 卻找不到輸入法）。所以每次換一個系統沒見過的 bundle id（im.penglai.inputmethod.SableInstallTest<時間>），
# 複製一份改 Info.plist、重新簽章，跑真正的 `--self-install --yes --no-select`，等於第一次在這台裝。
# macOS 27.2 上第一次裝的輸入法 TISEnableInputSource 不生效，要登出再登入（11/5 實測），所以接受兩種結果：
#   結束碼 0：上一層和 .Hant 真的都啟用了；結束碼 3：都沒啟用，而且有說要登出再登入。
#   其他（說裝好了卻沒啟用、說要登出卻其實好了、失敗、蓋到正式的 Sable.app、關掉正式的貂毫）都算錯。
# --no-select：不切換過去，測試版不會被叫起來，不碰 ~/Library/Rime。跑完把測試版刪掉、從 LaunchServices 取消登記。
set -uo pipefail
W="$(cd "$(dirname "$0")/.." && pwd)"
SRC="${1:-$W/.build/custom-app/Sable.app}"; SRC="${SRC%/}"
IM="$HOME/Library/Input Methods"
PROD="$IM/Sable.app"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
TS=$(date +%Y%m%d%H%M%S)
NAME="SableInstallTest$TS"
BID="im.penglai.inputmethod.$NAME"
WORK="$W/.build/install-test/$TS"
TEST_APP="$WORK/$NAME.app"
DEST="$IM/$NAME.app"
fails=0; n=0
ok()  { n=$((n+1)); print -r -- "PASS $1"; }
bad() { n=$((n+1)); fails=$((fails+1)); print -r -- "FAIL $1"; }
check() { local name=$1; shift; if "$@"; then ok "$name"; else bad "$name"; fi; }
said() { print -r -- "$out" | grep -q -- "$1"; }
not_said() { ! said "$1"; }
cleanup() {
  [[ -d $DEST ]] && { "$LSREGISTER" -u "$DEST" 2>/dev/null; rm -rf "$DEST"; }
  rm -rf "$IM/$NAME.app.new"
  [[ -d $TEST_APP ]] && "$LSREGISTER" -u "$TEST_APP" 2>/dev/null
  rm -rf "$WORK"; rmdir "$W/.build/install-test" 2>/dev/null
  true
}
trap cleanup EXIT

[[ -x $SRC/Contents/MacOS/Sable ]] || { echo "FAIL 找不到 $SRC/Contents/MacOS/Sable"; exit 1; }
# 舊版（1.0.0）寫死裝成 Sable.app、關掉 im.penglai.inputmethod.Sable：拿它跑會蓋掉正式環境，不跑
"$SRC/Contents/MacOS/Sable" --help 2>/dev/null | grep -q -- '--no-select' \
  || { echo "FAIL $SRC 是 --no-select 之前的版本（會蓋掉正式的 Sable.app），不測"; exit 1; }

TIS="$W/.build/tis"
[[ -x $TIS && $TIS -nt $W/tools/tis.swift ]] || swiftc -O "$W/tools/tis.swift" -o "$TIS" || exit 1
source "$W/versions.env"
sign=-; security find-identity -v -p codesigning 2>/dev/null | grep -qF "\"$SIGN_IDENTITY\"" && sign="$SIGN_IDENTITY"

echo "== $SRC → $NAME（$BID，簽章 ${sign/-/ad-hoc}）"
mkdir -p "$WORK" && ditto "$SRC" "$TEST_APP" || exit 1
python3 -I - "$TEST_APP/Contents/Info.plist" "$BID" <<'EOF' || exit 1
import plistlib, sys
path, bid = sys.argv[1], sys.argv[2]
p = plistlib.load(open(path, "rb"))
old = p["CFBundleIdentifier"]
p["CFBundleIdentifier"] = p["TISInputSourceID"] = bid
p["InputMethodConnectionName"] = bid.rsplit(".", 1)[1] + "_Connection"
c = p["ComponentInputModeDict"]
c["tsInputModeListKey"] = {k.replace(old, bid): {**v, "TISInputSourceID": v["TISInputSourceID"].replace(old, bid)}
                           for k, v in c["tsInputModeListKey"].items()}
c["tsVisibleInputModeOrderedArrayKey"] = [k.replace(old, bid) for k in c["tsVisibleInputModeOrderedArrayKey"]]
plistlib.dump(p, open(path, "wb"))
EOF
codesign --force --deep -s "$sign" "$TEST_APP" 2>/dev/null || { echo "FAIL 簽章失敗"; exit 1; }

prod_hash() { [[ -d $PROD ]] && codesign -dvvv "$PROD" 2>&1 | grep '^CDHash=' || echo none; }
prod_pid() { pgrep -f "^$PROD/Contents/MacOS/Sable\$" || echo none; }
hash0=$(prod_hash); pid0=$(prod_pid); cur0=$("$TIS" current)
check "測試版 bundle id 系統沒見過" test "$("$TIS" state "$BID"; echo $?)" = $'missing\n2'

out=$("$TEST_APP/Contents/MacOS/Sable" --self-install --yes --no-select 2>&1); code=$?
print -r -- "$out" | sed 's/^/    | /'
bstate=$("$TIS" state "$BID"); mstate=$("$TIS" state "$BID.Hant")
echo "    結束碼 $code；上一層 $bstate；.Hant $mstate"

check "裝到 $DEST" test -x "$DEST/Contents/MacOS/Sable"
check "沒留下 $NAME.app.new" test ! -e "$IM/$NAME.app.new"
check "拿掉了下載標記" sh -c "! xattr -r '$DEST' 2>/dev/null | grep -q com.apple.quarantine"
check "正式的 Sable.app 沒被換掉" test "$(prod_hash)" = "$hash0"
check "正式的貂毫沒被關掉（PID $pid0）" test "$(prod_pid)" = "$pid0"
check "--no-select 沒切換輸入法（還是 $cur0）" test "$("$TIS" current)" = "$cur0"
case $code in
  0) check "結束碼 0：上一層真的啟用了" test "${bstate%% *}" = enabled=1
     check "結束碼 0：.Hant 真的啟用了" test "${mstate%% *}" = enabled=1
     check "結束碼 0：有說已啟用" said '^已啟用' ;;
  3) check "結束碼 3：上一層確實沒啟用（不是誤報）" test "${bstate%% *}" = enabled=0
     check "結束碼 3：有說要登出再登入" said '要登出再登入'
     check "結束碼 3：沒說已啟用" not_said '^已啟用' ;;
  *) bad "結束碼 $code（只接受 0 已啟用、3 要登出）" ;;
esac
echo "== $((n - fails)) 過、$fails 沒過（$([[ $code == 3 ]] && echo '這台：第一次裝要登出再登入' || echo '這台：裝好就能用')）"
(( fails == 0 ))
