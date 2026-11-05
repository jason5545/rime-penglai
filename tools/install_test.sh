#!/bin/zsh
# usage: zsh tools/install_test.sh [Sable.app 或 Sable-x.y.z.dmg]
#   在 Parallels 的「macOS 27.2 測試機」裡測自己安裝（sable/PenglaiInstall.swift），從乾淨快照開始，等於第一次在一台 Mac 上裝。
#   不給路徑就測 .build/custom-app/Sable.app。逐項印 PASS／FAIL，有一項沒過結束碼 1。prlctl 要在 Claude Code 的沙盒外跑。
#
# 為什麼在虛擬機：第一次啟用一個輸入法時，macOS 會打開系統設定問「要允許『貂毫』啟用『貂毫』嗎？」，按了「允許」
# 才真的啟用（11/5 在虛擬機找到；1.0.0、1.0.1 用自己的對話框把它蓋住了）。這台 Mac 早就允許過貂毫，測不到；
# 在這台換一個 bundle id 測，又會在開發用的這台 Mac 畫面上跳出系統設定的詢問。
#
# 三種情境（每種前面都退回快照「乾淨（沒裝過貂毫）」，最後也退回去）：
#   A 第一次裝、按「允許」：結束碼 0、有切換、上一層和 .Hant 都啟用、輸入法程序從 ~/Library/Input Methods 跑
#   B 同一台再裝一次（更新）：系統不再問，10 秒內結束碼 0
#   C 第一次裝、按「不允許」：結束碼 3、說沒有啟用、上一層沒啟用
# 「允許」「不允許」用 prlctl send-key-event 送 Return、Escape 給系統設定的詢問（預設按鈕是「允許」）；
# 送之前截一張畫面存在 .build/install-test/<時間>/，FAIL 時看這些圖。
# App 用臨時 HTTP 伺服器傳進虛擬機：只綁 Parallels 共用網路的主機位址 10.211.55.2，區網連不到，測完就關。
set -uo pipefail
W="$(cd "$(dirname "$0")/.." && pwd)"
SRC="${1:-$W/.build/custom-app/Sable.app}"; SRC="${SRC%/}"
VM="macOS 27.2 測試機"
SNAP="{2cbc1ed7-b033-4c86-8ede-a828bc67c0fd}"
HOST=10.211.55.2; PORT=18765
OUT="$W/.build/install-test/$(date +%Y%m%d-%H%M%S)"; SERVE="$OUT/serve"
fails=0; n=0
ok()  { n=$((n+1)); print -r -- "PASS $1"; }
bad() { n=$((n+1)); fails=$((fails+1)); print -r -- "FAIL $1"; }
check() { local name=$1; shift; if "$@"; then ok "$name"; else bad "$name"; fi; }
# prlctl exec 偶爾無聲失敗（PrlJob_Get… 或開不了工作階段），重試到成功為止（最多 5 次）
vm() {
  local out i
  for i in {1..5}; do
    out=$(prlctl exec "$VM" "$1" 2>&1)
    [[ $out == *PrlJob_Get* || $out == *"Unable to open new session"* ]] || break
    sleep 2
  done
  print -r -- "$out" | grep -v -E 'PrlJob_Get|^$'
}
asuser() { vm "launchctl asuser \$(id -u vm) sudo -H -u vm $1"; }
key() { prlctl send-key-event "$VM" --scancode $1 >/dev/null 2>&1; }   # 28 Return、1 Escape
shot() { prlctl capture "$VM" --file "$OUT/$1.png" >/dev/null 2>&1; }
server_pid=
cleanup() {
  [[ -n $server_pid ]] && kill $server_pid 2>/dev/null
  prlctl snapshot-switch "$VM" -i "$SNAP" >/dev/null 2>&1
  rm -rf "$SERVE"
}
trap cleanup EXIT

command -v prlctl >/dev/null || { echo "FAIL 沒有 prlctl"; exit 1; }
prlctl list -a | grep -q -- "$VM" || { echo "FAIL 找不到虛擬機「$VM」"; exit 1; }
mkdir -p "$SERVE"
TIS="$W/.build/tis"; [[ -x $TIS && $TIS -nt $W/tools/tis.swift ]] || swiftc -O -target arm64-apple-macos13 "$W/tools/tis.swift" -o "$TIS" || exit 1
cp "$TIS" "$SERVE/tis"
cat > "$SERVE/poll.sh" <<'EOF'
for i in {1..90}; do
  echo "$(date +%T) $(/usr/local/bin/tis state im.penglai.inputmethod.Sable | tr -d '\n') 設定裡=$(defaults read com.apple.inputsources 2>/dev/null | grep -c Sable.Hant)"
  sleep 1
done
EOF
case $SRC in
  *.dmg) cp "$SRC" "$SERVE/Sable.dmg" ;;
  *.app) hdiutil create -quiet -volname SableTest -srcfolder "$SRC" -ov -format UDZO "$SERVE/Sable.dmg" || exit 1 ;;
  *) echo "FAIL 要給 .app 或 .dmg：$SRC"; exit 1 ;;
esac
python3 -I -m http.server $PORT --bind $HOST --directory "$SERVE" >/dev/null 2>&1 & server_pid=$!
sleep 1
echo "== $SRC → $VM（截圖在 $OUT）"

# 退回乾淨快照、放 tis、掛載 DMG；印出 App 在虛擬機裡的路徑
fresh() {
  prlctl snapshot-switch "$VM" -i "$SNAP" >/dev/null 2>&1 || { echo "FAIL 退回快照失敗" >&2; return 1; }
  # 退回快照後有一段時間 prlctl exec 會無聲失敗：等到使用者的工作階段也叫得動，每一步都確認、不行就重試
  local i r; for i in {1..40}; do sleep 3; [[ $(asuser "id -un") == *vm* ]] && break; done; sleep 5
  for i in {1..5}; do
    r=$(vm "mkdir -p /usr/local/bin && curl -sSf --retry 15 --retry-delay 2 --retry-all-errors http://$HOST:$PORT/tis -o /usr/local/bin/tis && curl -sSf http://$HOST:$PORT/poll.sh -o /usr/local/bin/poll.sh && chmod 755 /usr/local/bin/tis && echo tis-ok")
    [[ $r == *tis-ok* ]] && break; sleep 3
  done
  [[ $r == *tis-ok* ]] || { echo "FAIL 傳不進 tis：$r" >&2; return 1; }
  for i in {1..5}; do
    r=$(asuser "/bin/zsh -c 'mkdir -p /Users/vm/penglai-test && curl -sSf --retry 15 --retry-delay 2 --retry-all-errors http://$HOST:$PORT/Sable.dmg -o /Users/vm/penglai-test/Sable.dmg && hdiutil attach -nobrowse /Users/vm/penglai-test/Sable.dmg 2>&1 | grep /Volumes/'")
    [[ $r == */Volumes/* ]] && break; sleep 3
  done
  [[ $r == */Volumes/* ]] || { echo "FAIL 掛不上 DMG：$r" >&2; return 1; }
  print -r -- "${r#*$'\t'/Volumes/}" | sed 's|^\(.*\)$|/Volumes/\1/Sable.app|' | tail -1
}
# 背景跑 --self-install，結果寫 /tmp/install.out、/tmp/install.code
start_install() {
  local i
  vm "rm -f /tmp/install.out /tmp/install.code"
  for i in {1..5}; do
    # 背景那一段的輸入輸出都要導開，不然 prlctl exec 會等它跑完才回來
    asuser "/bin/zsh -c '( \"$1/Contents/MacOS/Sable\" --self-install --yes --wait $2 > /tmp/install.out 2>&1; echo \$? > /tmp/install.code ) < /dev/null > /dev/null 2>&1 &'"
    sleep 2; [[ -n $(vm "ls /tmp/install.out 2>/dev/null") ]] && return 0
  done
  echo "FAIL 安裝程式叫不起來" >&2; return 1
}
wait_install() { local i; for i in {1..$1}; do sleep 1; vm "cat /tmp/install.code 2>/dev/null" | grep -q '^[0-9]' && return 0; done; return 1; }
code() { vm "cat /tmp/install.code" | tr -d '[:space:]'; }
said() { vm "cat /tmp/install.out" | grep -q -- "$1"; }
state() { asuser "/usr/local/bin/tis state $1" | tr -d '\n'; }

# --- A：第一次裝、按「允許」
APP=$(fresh) || { echo "FAIL A 準備虛擬機失敗"; exit 1; }
[[ -n $APP ]] || { echo "FAIL 虛擬機裡掛不上 DMG"; exit 1; }
asuser "'$APP/Contents/MacOS/Sable' --help" | grep -q -- '--wait' || { echo "FAIL $SRC 是 --wait 之前的版本（1.0.1 以前），不測"; exit 1; }
check "A 這台沒有貂毫" test "$(state im.penglai.inputmethod.Sable)" = missing
asuser "/bin/zsh -c '/bin/zsh /usr/local/bin/poll.sh < /dev/null > /tmp/poll.log 2>&1 &'"
start_install "$APP" 40; sleep 8; shot A1-詢問; echo "    $(date +%T) 送 Return"; key 28; sleep 2; shot A1b-按了允許
check "A 按允許後裝完" wait_install 40
vm "uniq -f1 -c /tmp/poll.log" | sed 's/^/    poll /'
shot A2-結束
vm "cat /tmp/install.out" | grep -v -E 'Keyboard Layouts|TISFileInterrogator' | sed 's/^/    | /'
check "A 結束碼 0（實際 $(code)）" test "$(code)" = 0
check "A 有說已切換" said '已切換到貂毫'
check "A 上一層啟用" test "$(state im.penglai.inputmethod.Sable)" = "enabled=1 selected=0"
check "A .Hant 啟用且選取" test "$(state im.penglai.inputmethod.Sable.Hant)" = "enabled=1 selected=1"
ime_running() { local i; for i in {1..10}; do vm "ps -axo command" | grep -q '^/Users/vm/Library/Input Methods/Sable.app/Contents/MacOS/Sable$' && return 0; sleep 1; done; return 1; }
asuser "open -a TextEdit"; sleep 4; shot A3-文字編輯   # 要有文字框要打字，系統才叫起輸入法程序
check "A 打開文字編輯後輸入法程序從 ~/Library/Input Methods 跑起來" ime_running

# --- B：同一台再裝一次（更新），系統不再問
t0=$(date +%s)
start_install "$APP" 10
check "B 再裝一次 10 秒內結束" wait_install 10
shot B-結束
vm "cat /tmp/install.out" | grep -v -E 'Keyboard Layouts|TISFileInterrogator' | sed 's/^/    | /'
check "B 結束碼 0（實際 $(code)，$(( $(date +%s) - t0 )) 秒）" test "$(code)" = 0
check "B 有說已切換" said '已切換到貂毫'

# --- C：第一次裝、按「不允許」
APP=$(fresh) || { echo "FAIL C 準備虛擬機失敗"; exit 1; }
echo "    C 的 App：$APP"
start_install "$APP" 15; sleep 8; shot C1-詢問; key 1
check "C 等完結束" wait_install 30
shot C2-結束
vm "cat /tmp/install.out 2>&1 || ls -l /tmp /Volumes" | grep -v -E 'Keyboard Layouts|TISFileInterrogator' | sed 's/^/    | /'
check "C 結束碼 3（實際 $(code)）" test "$(code)" = 3
check "C 有說沒有啟用" said '沒有啟用'
check "C 上一層沒啟用" test "$(state im.penglai.inputmethod.Sable)" = "enabled=0 selected=0"

echo "== $((n - fails)) 過、$fails 沒過"
(( fails == 0 ))
