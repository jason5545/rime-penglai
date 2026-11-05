// 輸入法狀態小工具（Carbon TIS），切換、退回、安裝腳本和 tools/install_test.sh 用。
// 編譯：swiftc -O tools/tis.swift -o .build/tis（腳本會自己編；改了這個檔要刪掉 .build/tis 重編）
// usage: tis list               列出 ABC、鼠鬚管、貂毫的輸入法：ID enabled=0/1 selected=0/1
//        tis current            目前選中的輸入法 ID
//        tis state <ID>         印 enabled=0/1 selected=0/1；系統裡沒有這個 ID 就印 missing、結束碼 2
//   下面四個會改系統狀態，只在切換、退路、安裝腳本裡用：
//        tis register <App>     TISRegisterInputSource（重複呼叫沒關係）
//        tis enable <ID>        TISEnableInputSource（上一層 bundle id 和 .Hant 都要啟用，只啟用 .Hant 選不到，回 -50）
//        tis disable <ID>       TISDisableInputSource
//        tis select <ID>        TISSelectInputSource（上一層和自己都要已經啟用）
// 不用鼠鬚管、貂毫自己的 --register-input-source：它看到有模式已經啟用就不註冊（10/28 正式切換踩到，docs/sable.md）。
// 結束碼：成功 0、系統裡沒有這個 ID 2、TIS 回錯誤 1（印出錯誤碼）。
import Carbon

func prop(_ src: TISInputSource, _ key: CFString) -> AnyObject? {
  guard let p = TISGetInputSourceProperty(src, key) else { return nil }
  return Unmanaged<AnyObject>.fromOpaque(p).takeUnretainedValue()
}
func id(_ src: TISInputSource) -> String { prop(src, kTISPropertyInputSourceID) as? String ?? "" }
func flag(_ src: TISInputSource, _ key: CFString) -> Int { (prop(src, key) as? Bool ?? false) ? 1 : 0 }
func state(_ src: TISInputSource) -> String {
  "enabled=\(flag(src, kTISPropertyInputSourceIsEnabled)) selected=\(flag(src, kTISPropertyInputSourceIsSelected))"
}
func all() -> [TISInputSource] { TISCreateInputSourceList(nil, true).takeRetainedValue() as! [TISInputSource] }

let args = CommandLine.arguments
switch (args.count > 1 ? args[1] : "", args.count > 2 ? args[2] : nil) {
case ("list", nil):
  for src in all() {
    let i = id(src)
    if i == "com.apple.keylayout.ABC" || i.hasPrefix("im.rime.inputmethod.") || i.hasPrefix("im.penglai.inputmethod.") {
      print(i, state(src))
    }
  }
case ("current", nil):
  print(id(TISCopyCurrentKeyboardInputSource().takeRetainedValue()))
case ("state", let target?):
  guard let src = all().first(where: { id($0) == target }) else { print("missing"); exit(2) }
  print(state(src))
case ("register", let path?):
  let err = TISRegisterInputSource(URL(fileURLWithPath: path) as CFURL)
  print(err == noErr ? "registered \(path)" : "register \(path) failed: \(err)")
  exit(err == noErr ? 0 : 1)
case (let op, let target?) where ["enable", "disable", "select"].contains(op):
  guard let src = all().first(where: { id($0) == target }) else { print("missing \(target)"); exit(2) }
  let err = op == "enable" ? TISEnableInputSource(src) : op == "disable" ? TISDisableInputSource(src) : TISSelectInputSource(src)
  print(err == noErr ? "\(op) \(target): ok" : "\(op) \(target) failed: \(err)")
  exit(err == noErr ? 0 : 1)
default:
  print("usage: tis list | current | state <ID> | register <App> | enable <ID> | disable <ID> | select <ID>")
  exit(64)
}
