//
//  PenglaiInstall.swift
//  Squirrel
//
//  自己安裝：從 DMG（或任何不是輸入法資料夾的地方）打開貂毫時，問要不要裝到 ~/Library/Input Methods，
//  裝好之後註冊、啟用、切換過去。輸入法程序本身是系統從輸入法資料夾叫起來的，不會走到這裡。
//  步驟：關掉正在跑的貂毫 → 複製成 Sable.app.new 再換掉舊的（學習紀錄、設定在 ~/Library/Rime，不動）→ 拿掉下載標記
//  → TISRegisterInputSource → 上一層（bundle id）和 .Hant 都啟用（只啟用 .Hant 會選不到，回 -50）→ 選取。
//  `Sable --self-install [--to <資料夾>] [--yes] [--no-tis]`：測試用。--to 換安裝資料夾（不碰正式的），
//  --yes 不問直接裝，--no-tis 不關貂毫、不註冊、不啟用（只測複製）。結果印在標準輸出，失敗時結束碼 1。
//

import AppKit
import InputMethodKit

enum PenglaiInstall {
  static let bundleID = "im.penglai.inputmethod.Sable"
  static let modeID = "im.penglai.inputmethod.Sable.Hant"

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
    exit(run(destDir: homeInputMethods, ask: true, tis: true) ? 0 : 1)
  }

  /// `--self-install` 的參數
  static func runCommand(_ args: [String]) -> Never {
    var destDir = homeInputMethods, ask = true, tis = true
    var i = 0
    while i < args.count {
      switch args[i] {
      case "--to" where i + 1 < args.count: destDir = URL(fileURLWithPath: args[i + 1], isDirectory: true); i += 1
      case "--yes": ask = false
      case "--no-tis": tis = false
      default: print("不認得的參數：\(args[i])"); exit(2)
      }
      i += 1
    }
    exit(run(destDir: destDir, ask: ask, tis: tis) ? 0 : 1)
  }

  static func version(of app: URL) -> String? {
    guard let info = NSDictionary(contentsOf: app.appending(components: "Contents", "Info.plist")) else { return nil }
    return (info["CFBundleShortVersionString"] ?? info["CFBundleVersion"]) as? String
  }

  private static func run(destDir: URL, ask: Bool, tis: Bool) -> Bool {
    let source = Bundle.main.bundleURL
    let dest = destDir.appending(component: "Sable.app", directoryHint: .isDirectory)
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
      guard alert.runModal() == .alertFirstButtonReturn else { print("取消安裝"); return true }
    }

    do {
      if tis { quitRunning() }
      try copy(from: source, to: dest)
      print("已複製：\(dest.path)（\(oldVersion.map { "\($0) → " } ?? "")\(newVersion)）")
      if tis { try activate(dest) }
    } catch {
      print("安裝失敗：\(error.localizedDescription)")
      if ask { report(title: "貂毫沒有裝好", text: error.localizedDescription) }
      return false
    }
    // 從 LaunchServices 取消登記打開的這一份（DMG 退出後就不在了；同一個 bundle id 登記好幾份時系統可能解析到錯的那份）
    if tis, source.standardizedFileURL != dest.standardizedFileURL {
      _ = runTool("/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister", ["-u", source.path])
    }
    if ask {
      report(title: oldVersion == nil ? "貂毫裝好了" : "貂毫更新好了",
             text: oldVersion == nil
               ? "選單列的輸入法選單已經切換到「貂毫」。第一次用會先準備詞典，等幾秒；之後跳出一個小視窗，選好讀音就能開始打字。\n\n用法和設定見說明書：https://penglai.im/wiki/"
               : "已經換成 \(newVersion)。如果正在打字的視窗沒有反應，切換一次輸入法就好。")
    }
    return true
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
    let staging = dest.deletingLastPathComponent().appending(component: "Sable.app.new", directoryHint: .isDirectory)
    if fm.fileExists(atPath: staging.path) { try fm.removeItem(at: staging) }
    try fm.copyItem(at: source, to: staging)
    _ = runTool("/usr/bin/xattr", ["-dr", "com.apple.quarantine", staging.path])
    if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
    try fm.moveItem(at: staging, to: dest)
  }

  private struct InstallError: LocalizedError {
    let errorDescription: String?
  }

  /// 註冊、啟用上一層和 .Hant、選取。剛註冊完清單不一定馬上看得到，每 0.5 秒重查，最多 10 秒
  private static func activate(_ app: URL) throws {
    let error = TISRegisterInputSource(app as CFURL)
    guard error == noErr else { throw InstallError(errorDescription: "註冊輸入法失敗（\(error)）") }
    var ready = false
    for _ in 0..<20 {
      let sources = currentSources()
      for id in [bundleID, modeID] {
        if let s = sources[id], !bool(s, kTISPropertyInputSourceIsEnabled) { TISEnableInputSource(s) }
      }
      let after = currentSources()
      if let b = after[bundleID], let m = after[modeID], bool(b, kTISPropertyInputSourceIsEnabled), bool(m, kTISPropertyInputSourceIsEnabled) {
        ready = true
        break
      }
      Thread.sleep(forTimeInterval: 0.5)
    }
    guard ready else {
      throw InstallError(errorDescription: "已經複製到 \(app.path)，但輸入法沒有啟用。請到「系統設定 › 鍵盤 › 輸入方式」按「＋」，在「繁體中文」裡加入「貂毫」。")
    }
    print("已註冊、啟用 \(bundleID)、\(modeID)")
    if let m = currentSources()[modeID] {
      let r = TISSelectInputSource(m)
      print(r == noErr ? "已切換到貂毫" : "切換到貂毫失敗（\(r)），請從選單列的輸入法選單選")
    }
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
