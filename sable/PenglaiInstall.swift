//
//  PenglaiInstall.swift
//  Squirrel
//
//  自己安裝：從 DMG（或任何不是輸入法資料夾的地方）打開貂毫時，問要不要裝到 ~/Library/Input Methods，
//  裝好之後註冊、啟用、切換過去。輸入法程序本身是系統從輸入法資料夾叫起來的，不會走到這裡。
//  步驟：關掉正在跑的貂毫 → 複製成 Sable.app.new 再換掉舊的（學習紀錄、設定在 ~/Library/Rime，不動）→ 拿掉下載標記
//  → TISRegisterInputSource → 上一層（bundle id）和 .Hant 都啟用（只啟用 .Hant 會選不到，回 -50）→ 選取。
//
//  沒被使用者加過的輸入法（第一次裝的 Mac）：TISEnableInputSource 回 noErr 但不生效，系統設定的「＋」清單也要
//  登出再登入才看得到，登入後用程式啟用也還是不生效，要使用者自己在「＋」加（11/5 在 macOS 27.2 用沒見過的
//  bundle id 實測，登出前後都試過；青簡 qingjian-team/qingjian#209 同一件事）。
//  這時先自己把兩筆寫進 com.apple.inputsources 的 AppleEnabledThirdPartyInputSources（青簡在 15.3 寫得進去，登入後
//  就是啟用的；27.2 拒絕寫入），還是沒啟用就照實說「登出再登入，再到『＋』加入」，不再叫人去「＋」找一個還不在清單裡的東西。
//
//  bundle id、輸入模式、安裝的檔名都從 App 自己的 Info.plist 讀：tools/install_test.sh 換一個沒見過的 bundle id
//  跑真正的安裝流程，不會關掉、蓋掉正式的 Sable.app。
//
//  `Sable --self-install [--to <資料夾>] [--yes] [--no-tis] [--no-select]`：測試用。--to 換安裝資料夾（不碰正式的），
//  --yes 不問直接裝，--no-tis 不關貂毫、不註冊、不啟用（只測複製），--no-select 啟用但不切換過去（不讓測試版叫起來）。
//  結果印在標準輸出。結束碼：裝好、啟用了 0；裝好但要登出再登入才能用 3；失敗 1。
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

  static let exitNeedsRelogin: Int32 = 3

  static var homeInputMethods: URL {
    let home = getpwuid(getuid()).map { String(cString: $0.pointee.pw_dir) } ?? NSHomeDirectory()
    return URL(fileURLWithPath: home, isDirectory: true).appending(components: "Library", "Input Methods")
  }

  /// 這一份是不是已經在輸入法資料夾（使用者的或整台的）
  static func isInstalled(_ app: URL) -> Bool {
    let dir = app.resolvingSymlinksInPath().deletingLastPathComponent().standardizedFileURL.path
    return [homeInputMethods.path, "/Library/Input Methods"].contains { dir == URL(fileURLWithPath: $0).standardizedFileURL.path }
  }

  /// main() 沒帶參數時、啟動輸入法之前叫：在輸入法資料夾就直接回去；不在就走安裝流程，跑完結束程序
  static func runIfNeeded() {
    guard !isInstalled(Bundle.main.bundleURL) else { return }
    exit(run(destDir: homeInputMethods, ask: true, tis: true, select: true) == .failed ? 1 : 0)
  }

  /// `--self-install` 的參數
  static func runCommand(_ args: [String]) -> Never {
    var destDir = homeInputMethods, ask = true, tis = true, select = true
    var i = 0
    while i < args.count {
      switch args[i] {
      case "--to" where i + 1 < args.count: destDir = URL(fileURLWithPath: args[i + 1], isDirectory: true); i += 1
      case "--yes": ask = false
      case "--no-tis": tis = false
      case "--no-select": select = false
      default: print("不認得的參數：\(args[i])"); exit(2)
      }
      i += 1
    }
    switch run(destDir: destDir, ask: ask, tis: tis, select: select) {
    case .ready: exit(0)
    case .needsRelogin: exit(exitNeedsRelogin)
    case .failed: exit(1)
    }
  }

  static func version(of app: URL) -> String? {
    guard let info = NSDictionary(contentsOf: app.appending(components: "Contents", "Info.plist")) else { return nil }
    return (info["CFBundleShortVersionString"] ?? info["CFBundleVersion"]) as? String
  }

  enum Outcome { case ready, needsRelogin, failed }

  private static func run(destDir: URL, ask: Bool, tis: Bool, select: Bool) -> Outcome {
    let source = Bundle.main.bundleURL
    let dest = destDir.appending(component: appName, directoryHint: .isDirectory)
    let newVersion = version(of: source) ?? "?"
    let oldVersion = FileManager.default.fileExists(atPath: dest.path) ? version(of: dest) ?? "?" : nil

    if ask {
      let app = NSApplication.shared
      app.setActivationPolicy(.regular)
      app.activate(ignoringOtherApps: true)
      let alert = NSAlert()
      alert.messageText = oldVersion == nil ? "安裝貂毫 \(newVersion)" : "更新貂毫"
      alert.informativeText = oldVersion.map {
        "這台 Mac 已經裝了貂毫 \($0)，要換成 \(newVersion) 嗎？\n\n學習紀錄和設定在「~/Library/Rime」，不會動。"
      } ?? "貂毫會裝到你的輸入法資料夾（~/Library/Input Methods），裝好就切換過去，可以直接打字。\n\n不用管理員密碼，只裝給目前登入的使用者。"
      alert.addButton(withTitle: oldVersion == nil ? "安裝" : "更新")
      alert.addButton(withTitle: "取消")
      guard alert.runModal() == .alertFirstButtonReturn else { print("取消安裝"); return .ready }
    }

    var outcome = Outcome.ready
    do {
      if tis { quitRunning() }
      try copy(from: source, to: dest)
      print("已複製：\(dest.path)（\(oldVersion.map { "\($0) → " } ?? "")\(newVersion)）")
      if tis { outcome = try activate(dest, select: select) }
    } catch {
      print("安裝失敗：\(error.localizedDescription)")
      if ask { report(title: "貂毫沒有裝好", text: error.localizedDescription) }
      return .failed
    }
    // 從 LaunchServices 取消登記打開的這一份（DMG 退出後就不在了；同一個 bundle id 登記好幾份時系統可能解析到錯的那份）
    if tis, source.standardizedFileURL != dest.standardizedFileURL {
      _ = runTool("/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister", ["-u", source.path])
    }
    if ask {
      switch outcome {
      case .needsRelogin:
        report(title: "貂毫裝好了，還差兩步",
               text: "這台 Mac 第一次裝貂毫，macOS 不讓安裝程式自己把它加進輸入法清單，要登出再登入一次，再自己加入。\n\n"
                 + "1. 按螢幕左上角的蘋果選單 ›「登出」，再登入。\n"
                 + "2. 打開「系統設定 › 鍵盤 › 輸入方式」，按「編輯⋯」再按左下角的「＋」，在「繁體中文」裡選「貂毫」加入。\n\n"
                 + "之後在這台 Mac 更新就不用再做。說明書：https://penglai.im/wiki/install/")
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

  /// 註冊、啟用上一層和每個模式、選取。啟用不了（第一次裝、macOS 不認）就回 .needsRelogin，不當成失敗
  private static func activate(_ app: URL, select: Bool) throws -> Outcome {
    let error = TISRegisterInputSource(app as CFURL)
    guard error == noErr else { throw InstallError(errorDescription: "註冊輸入法失敗（\(error)）") }
    print("已註冊：\(app.path)")
    // 剛註冊完清單不一定馬上看得到，每 0.5 秒重查。這台以前加過貂毫的話一下就好；沒加過的話等再久也不會好
    var ready = waitEnabled(tries: 6)
    if !ready {
      print("TISEnableInputSource 沒有生效（這台沒加過 \(bundleID)）")
      switch addToEnabledThirdPartyList() {
      case .written: print("已寫入 com.apple.inputsources AppleEnabledThirdPartyInputSources"); ready = waitEnabled(tries: 4)
      case .present: print("AppleEnabledThirdPartyInputSources 已經有 \(bundleID)")
      case .refused: print("com.apple.inputsources 寫不進去（macOS 27 起不給寫）")
      }
    }
    guard ready else {
      print("要登出再登入，再到「系統設定 › 鍵盤 › 輸入方式」按「＋」加入（登入後用程式啟用也不生效）")
      return .needsRelogin
    }
    print("已啟用 \(([bundleID] + modeIDs).joined(separator: "、"))")
    if select, let mode = modeIDs.first, let m = currentSources()[mode] {
      let r = TISSelectInputSource(m)
      print(r == noErr ? "已切換到貂毫" : "切換到貂毫失敗（\(r)），請從選單列的輸入法選單選")
    }
    return .ready
  }

  /// 上一層和每個模式都啟用了沒；還沒的就叫一次 TISEnableInputSource。最多查 tries 次，每次隔 0.5 秒
  private static func waitEnabled(tries: Int) -> Bool {
    for i in 0..<tries {
      if i > 0 { Thread.sleep(forTimeInterval: 0.5) }
      let sources = currentSources()
      for id in [bundleID] + modeIDs {
        if let s = sources[id], !bool(s, kTISPropertyInputSourceIsEnabled) { TISEnableInputSource(s) }
      }
      let after = currentSources()
      // 模式在沒被加過時也讀得到 enabled=1（Info.plist 的 tsInputModeDefaultStateKey），所以一定要看上一層
      if ([bundleID] + modeIDs).allSatisfy({ after[$0].map { bool($0, kTISPropertyInputSourceIsEnabled) } ?? false }) { return true }
    }
    return false
  }

  enum ListWrite { case written, present, refused }

  /// 系統設定加入輸入法時寫的那張表：一筆 Input Mode、一筆 Keyboard Input Method。TISEnableInputSource 不寫它
  private static func addToEnabledThirdPartyList() -> ListWrite {
    let domain = "com.apple.inputsources" as CFString, key = "AppleEnabledThirdPartyInputSources" as CFString
    let list = CFPreferencesCopyAppValue(key, domain) as? [[String: Any]] ?? []
    if list.contains(where: { $0["Bundle ID"] as? String == bundleID }) { return .present }
    let added: [[String: Any]] = modeIDs.map { ["Bundle ID": bundleID, "Input Mode": $0, "InputSourceKind": "Input Mode"] }
      + [["Bundle ID": bundleID, "InputSourceKind": "Keyboard Input Method"]]
    CFPreferencesSetAppValue(key, (list + added) as CFArray, domain)
    guard CFPreferencesAppSynchronize(domain) else { return .refused }
    let check = CFPreferencesCopyAppValue(key, domain) as? [[String: Any]] ?? []
    return check.contains(where: { $0["Bundle ID"] as? String == bundleID }) ? .written : .refused
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

  private static func report(title: String, text: String) {
    let alert = NSAlert()
    alert.messageText = title
    alert.informativeText = text
    alert.addButton(withTitle: "好")
    NSApp.activate(ignoringOtherApps: true)
    alert.runModal()
  }
}
