//
//  PenglaiInstall.swift
//  Squirrel
//
//  自己安裝：從 DMG（或任何不是輸入法資料夾的地方）打開貂毫時，問要不要裝到 ~/Library/Input Methods，
//  裝好之後註冊、啟用、切換過去。輸入法程序本身是系統從輸入法資料夾叫起來的，不會走到這裡。
//  步驟：關掉正在跑的貂毫 → 複製成 Sable.app.new 再換掉舊的（學習紀錄、設定在 ~/Library/Rime，不動）→ 拿掉下載標記
//  → TISRegisterInputSource → 上一層（bundle id）和 .Hant 都啟用（只啟用 .Hant 會選不到，回 -50）→ 選取。
//
//  第一次在這台 Mac 啟用（macOS 27 起；11/5 在 Parallels 的乾淨 macOS 27.2 實測）：TISEnableInputSource 回 noErr，
//  但系統先打開「系統設定 › 鍵盤」，跳出「要允許『貂毫』啟用『貂毫』嗎？」，使用者按「允許」才真的啟用（寫進
//  com.apple.inputsources，那個網域只有系統設定寫得進去）。1.0.0、1.0.1 在這時用自己的對話框把那個詢問蓋住了，
//  使用者看不到要按允許，1.0.0 還說「沒有裝好」叫人去「＋」找。所以：安裝前先講會被問、要按允許；送出啟用之後
//  不跳任何視窗，讓事件迴圈照常轉、等使用者按（預設最多 120 秒）；等到了就選取，沒等到才教人自己到「＋」加入。
//  這台 Mac 以前允許過的話，啟用馬上就好、不會再問。
//
//  bundle id、輸入模式、安裝的檔名都從 App 自己的 Info.plist 讀：tools/install_test.sh 在虛擬機裡跑真正的安裝流程。
//
//  `Sable --self-install [--to <資料夾>] [--yes] [--no-tis] [--no-select] [--wait <秒>]`：測試用。--to 換安裝資料夾，
//  --yes 不問直接裝，--no-tis 不關貂毫、不註冊、不啟用（只測複製），--no-select 啟用但不切換過去，
//  --wait 等使用者按「允許」最多幾秒（預設 120）。結果印在標準輸出。
//  結束碼：裝好、啟用了 0；裝好但沒啟用（沒按允許、逾時）3；失敗 1。
//

import AppKit
import InputMethodKit

enum PenglaiInstall {
  static let bundleID = Bundle.main.bundleIdentifier ?? "im.penglai.inputmethod.Sable"
  /// Info.plist 列的輸入模式（貂毫只有 .Hant）
  static let modeIDs: [String] = {
    let dict = Bundle.main.object(forInfoDictionaryKey: "ComponentInputModeDict") as? [String: Any]
    let modes = dict?["tsVisibleInputModeOrderedArrayKey"] as? [String] ?? []
    return modes.isEmpty ? [bundleID + ".Hant"] : modes
  }()
  /// 裝成什麼檔名：bundle id 最後一段（正式是 Sable.app），不照打開的這份叫什麼（Finder 可能複製成「Sable 2」）
  static let appName = (bundleID.split(separator: ".").last.map(String.init) ?? "Sable") + ".app"

  static let exitNotEnabled: Int32 = 3
  static let keyboardSettings = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!

  static var homeInputMethods: URL {
    let home = getpwuid(getuid()).map { String(cString: $0.pointee.pw_dir) } ?? NSHomeDirectory()
    return URL(fileURLWithPath: home, isDirectory: true).appending(components: "Library", "Input Methods")
  }

  /// 這一份是不是已經在輸入法資料夾（使用者的或整台的）
  static func isInstalled(_ app: URL) -> Bool {
    let dir = app.resolvingSymlinksInPath().deletingLastPathComponent().standardizedFileURL.path
    return [homeInputMethods.path, "/Library/Input Methods"].contains { dir == URL(fileURLWithPath: $0).standardizedFileURL.path }
  }

  struct Options {
    var destDir = homeInputMethods, ask = true, tis = true, select = true, wait: TimeInterval = 120
  }

  /// main() 沒帶參數時、啟動輸入法之前叫：在輸入法資料夾就直接回去；不在就走安裝流程，跑完結束程序
  static func runIfNeeded() {
    guard !isInstalled(Bundle.main.bundleURL) else { return }
    exit(run(Options()) == .failed ? 1 : 0)
  }

  /// `--self-install` 的參數
  static func runCommand(_ args: [String]) -> Never {
    var o = Options()
    var i = 0
    while i < args.count {
      switch args[i] {
      case "--to" where i + 1 < args.count: o.destDir = URL(fileURLWithPath: args[i + 1], isDirectory: true); i += 1
      case "--wait" where i + 1 < args.count: o.wait = TimeInterval(args[i + 1]) ?? o.wait; i += 1
      case "--yes": o.ask = false
      case "--no-tis": o.tis = false
      case "--no-select": o.select = false
      default: print("不認得的參數：\(args[i])"); exit(2)
      }
      i += 1
    }
    switch run(o) {
    case .ready: exit(0)
    case .notEnabled: exit(exitNotEnabled)
    case .failed: exit(1)
    }
  }

  static func version(of app: URL) -> String? {
    guard let info = NSDictionary(contentsOf: app.appending(components: "Contents", "Info.plist")) else { return nil }
    return (info["CFBundleShortVersionString"] ?? info["CFBundleVersion"]) as? String
  }

  enum Outcome { case ready, notEnabled, failed }

  private static func run(_ o: Options) -> Outcome {
    let source = Bundle.main.bundleURL
    let dest = o.destDir.appending(component: appName, directoryHint: .isDirectory)
    let newVersion = version(of: source) ?? "?"
    let oldVersion = FileManager.default.fileExists(atPath: dest.path) ? version(of: dest) ?? "?" : nil

    if o.ask {
      let app = NSApplication.shared
      app.setActivationPolicy(.regular)
      app.activate(ignoringOtherApps: true)
      let alert = NSAlert()
      alert.messageText = oldVersion == nil ? "安裝貂毫 \(newVersion)" : "更新貂毫"
      alert.informativeText = oldVersion.map {
        "這台 Mac 已經裝了貂毫 \($0)，要換成 \(newVersion) 嗎？\n\n學習紀錄和設定在「~/Library/Rime」，不會動。"
      } ?? "貂毫會裝到你的輸入法資料夾（~/Library/Input Methods），不用管理員密碼，只裝給目前登入的使用者。\n\n"
        + "按「安裝」之後，macOS 會打開系統設定，問你要不要允許啟用「貂毫」：請按「允許」。之後就會切換到貂毫，可以直接打字。"
      alert.addButton(withTitle: oldVersion == nil ? "安裝" : "更新")
      alert.addButton(withTitle: "取消")
      guard alert.runModal() == .alertFirstButtonReturn else { print("取消安裝"); return .ready }
    }

    var outcome = Outcome.ready
    do {
      if o.tis { quitRunning() }
      try copy(from: source, to: dest)
      print("已複製：\(dest.path)（\(oldVersion.map { "\($0) → " } ?? "")\(newVersion)）")
      if o.tis { outcome = try activate(dest, o) }
    } catch {
      print("安裝失敗：\(error.localizedDescription)")
      if o.ask { report(title: "貂毫沒有裝好", text: error.localizedDescription) }
      return .failed
    }
    // 從 LaunchServices 取消登記打開的這一份（DMG 退出後就不在了；同一個 bundle id 登記好幾份時系統可能解析到錯的那份）
    if o.tis, source.standardizedFileURL != dest.standardizedFileURL {
      _ = runTool("/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister", ["-u", source.path])
    }
    if o.ask {
      switch outcome {
      case .notEnabled:
        if report(title: "貂毫裝好了，還沒加進輸入法",
                  text: "系統設定問要不要允許啟用「貂毫」時，沒有按到「允許」。自己加入一次就好：\n\n"
                    + "打開「系統設定 › 鍵盤 › 輸入方式」，按「編輯⋯」再按左下角的「＋」，在「繁體中文」裡選「貂毫」加入。"
                    + "清單裡找不到的話，登出再登入一次再找。\n\n說明書：https://penglai.im/wiki/install/",
                  extra: "打開鍵盤設定") {
          NSWorkspace.shared.open(keyboardSettings)
        }
      default:
        report(title: oldVersion == nil ? "貂毫裝好了" : "貂毫更新好了",
               text: oldVersion == nil
                 ? "選單列的輸入法選單已經切換到「貂毫」。第一次用會先準備詞典，等幾秒；之後跳出一個小視窗，選好讀音就能開始打字。\n\n用法和設定見說明書：https://penglai.im/wiki/"
                 : "已經換成 \(newVersion)。如果正在打字的視窗沒有反應，切換一次輸入法就好。")
      }
    }
    return outcome
  }

  /// 關掉正在跑的貂毫（不是自己），最多等 3 秒，還在就強制結束
  private static func quitRunning() {
    let me = ProcessInfo.processInfo.processIdentifier
    let others = { NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).filter { $0.processIdentifier != me } }
    guard !others().isEmpty else { return }
    others().forEach { $0.terminate() }
    for _ in 0..<30 where !others().isEmpty { RunLoop.current.run(until: Date().addingTimeInterval(0.1)) }
    others().forEach { $0.forceTerminate() }
    print("已關掉正在跑的貂毫")
  }

  /// 先複製成 Sable.app.new，成功了才換掉舊的；拿掉下載標記（已經公證過，不用每次叫起輸入法都問）
  private static func copy(from source: URL, to dest: URL) throws {
    let fm = FileManager.default
    try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
    let staging = dest.deletingLastPathComponent().appending(component: appName + ".new", directoryHint: .isDirectory)
    if fm.fileExists(atPath: staging.path) { try fm.removeItem(at: staging) }
    try fm.copyItem(at: source, to: staging)
    _ = runTool("/usr/bin/xattr", ["-dr", "com.apple.quarantine", staging.path])
    if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
    try fm.moveItem(at: staging, to: dest)
  }

  private struct InstallError: LocalizedError {
    let errorDescription: String?
  }

  /// 註冊、啟用上一層和每個模式、選取。第一次啟用要等使用者在系統設定按「允許」：等的時候不跳視窗（會蓋住那個詢問），
  /// 讓事件迴圈照常轉。等不到就回 .notEnabled，不當成失敗
  private static func activate(_ app: URL, _ o: Options) throws -> Outcome {
    let error = TISRegisterInputSource(app as CFURL)
    guard error == noErr else { throw InstallError(errorDescription: "註冊輸入法失敗（\(error)）") }
    print("已註冊：\(app.path)")
    // 沒有 NSApplication 的程序（--yes）收不到系統設定按「允許」之後的變更，輸入法清單一直是舊的（11/5 虛擬機實測）
    if NSApp == nil {
      _ = NSApplication.shared
      NSApp.setActivationPolicy(.accessory)
    }
    var requested = false
    let deadline = Date().addingTimeInterval(max(o.wait, 2))
    var nextNote = Date().addingTimeInterval(5)
    while true {
      let sources = currentSources()
      // 剛註冊完清單不一定馬上看得到；看得到之後啟用只送一次（每送一次系統就可能再問一次）
      if !requested, ([bundleID] + modeIDs).allSatisfy({ sources[$0] != nil }) {
        for id in [bundleID] + modeIDs where !isEnabled(sources[id]) { TISEnableInputSource(sources[id]!) }
        requested = true
      }
      // 模式在沒被加過時也讀得到 enabled=1（Info.plist 的 tsInputModeDefaultStateKey），所以一定要看上一層。
      // 使用者按「允許」之後，這個程序裡的輸入法清單不一定會更新（11/5 虛擬機：系統已經啟用，--yes 跑的這裡一直讀到舊的），
      // 所以也看系統設定寫進去的 com.apple.inputsources
      if requested, ([bundleID] + modeIDs).allSatisfy({ isEnabled(sources[$0]) }) || allowedInPreferences() { break }
      if Date() >= deadline {
        print("沒有啟用：系統設定問要不要允許時沒有按「允許」（等了 \(Int(o.wait)) 秒）")
        return .notEnabled
      }
      if requested, Date() >= nextNote {
        print("等使用者在系統設定按「允許」…")
        nextNote = Date().addingTimeInterval(15)
      }
      RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.5))
    }
    print("已啟用 \(([bundleID] + modeIDs).joined(separator: "、"))")
    if o.select, let mode = modeIDs.first {
      // 這個程序的清單可能是舊的（見上面），選不到就交給新的程序（裝好的那份 --select-input-source）選
      var r = currentSources()[mode].map { TISSelectInputSource($0) } ?? OSStatus(paramErr)
      if r != noErr {
        r = OSStatus(runTool(app.appending(components: "Contents", "MacOS", "Sable").path, ["--select-input-source", mode]))
        if r == noErr, !selectedInFreshProcess(mode) { r = OSStatus(paramErr) }
      }
      print(r == noErr ? "已切換到貂毫" : "切換到貂毫失敗（\(r)），請從選單列的輸入法選單選")
    }
    return .ready
  }

  /// com.apple.inputsources 的 AppleEnabledThirdPartyInputSources 有沒有每個模式（系統設定按「允許」時寫的）。
  /// 用新的 defaults 程序讀：這個程序裡的 CFPreferences 也一直讀到舊值（11/5 虛擬機）。只讀，這個網域寫不進去
  private static func allowedInPreferences() -> Bool {
    let text = freshDefaults(["read", "com.apple.inputsources", "AppleEnabledThirdPartyInputSources"])
    return modeIDs.allSatisfy { text.contains("\"Input Mode\" = \"\($0)\"") }
  }

  /// 用新的程序查目前選的輸入法（這個程序的清單可能是舊的）
  private static func selectedInFreshProcess(_ mode: String) -> Bool {
    freshDefaults(["read", "com.apple.HIToolbox", "AppleSelectedInputSources"]).contains(mode)
  }

  private static func freshDefaults(_ args: [String]) -> String {
    let p = Process(), pipe = Pipe()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
    p.arguments = args
    p.standardOutput = pipe
    p.standardError = FileHandle.nullDevice
    guard (try? p.run()) != nil else { return "" }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return String(data: data, encoding: .utf8) ?? ""
  }

  private static func isEnabled(_ s: TISInputSource?) -> Bool {
    guard let s else { return false }
    return bool(s, kTISPropertyInputSourceIsEnabled)
  }

  private static func currentSources() -> [String: TISInputSource] {
    let list = TISCreateInputSourceList(nil, true).takeRetainedValue() as! [TISInputSource]
    var result = [String: TISInputSource]()
    for s in list {
      if let id = unsafeBitCast(TISGetInputSourceProperty(s, kTISPropertyInputSourceID), to: CFString?.self) as String? { result[id] = s }
    }
    return result
  }

  private static func bool(_ s: TISInputSource, _ key: CFString) -> Bool {
    guard let ref = unsafeBitCast(TISGetInputSourceProperty(s, key), to: CFBoolean?.self) else { return false }
    return CFBooleanGetValue(ref)
  }

  @discardableResult
  private static func runTool(_ path: String, _ args: [String]) -> Int32 {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: path)
    p.arguments = args
    p.standardOutput = FileHandle.nullDevice
    p.standardError = FileHandle.nullDevice
    do { try p.run(); p.waitUntilExit(); return p.terminationStatus } catch { return -1 }
  }

  /// 有 extra 時多一個按鈕，按了回 true
  @discardableResult
  private static func report(title: String, text: String, extra: String? = nil) -> Bool {
    let alert = NSAlert()
    alert.messageText = title
    alert.informativeText = text
    if let extra { alert.addButton(withTitle: extra) }
    alert.addButton(withTitle: "好")
    NSApp.activate(ignoringOtherApps: true)
    return alert.runModal() == .alertFirstButtonReturn && extra != nil
  }
}
