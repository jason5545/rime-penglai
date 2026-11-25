//
//  PenglaiSecureInput.swift
//  貂毫
//
//  防側錄模式（Secure Input）卡住時提醒。
//
//  任何程式都能開 macOS 的防側錄模式（密碼欄位、終端機的「安全鍵盤輸入」、鎖定畫面）；開著的時候系統停用所有不是 Apple
//  的輸入法，選單裡的貂毫變灰、點不動。程式忘了關、或關到一半就結束，貂毫就一直無法使用，使用者只看到「輸入法壞了」，
//  重裝也沒用。貂毫解不開這個鎖（解得開的輸入法就是側錄程式），能做的是說出系統記的是誰、照情況給解法。
//
//  - 每 5 秒問一次 IsSecureEventInputEnabled()（整個登入階段的狀態，別的程式開的也看得到；11/25 實測）。
//    連續開著 60 秒、螢幕沒鎖，才跳提示；鎖定、螢幕睡著、切到別的使用者時不算，解鎖之後重新計時。
//  - 持有者讀 IORegistry 根節點 IOConsoleUsers 裡這個使用者的 kCGSSessionSecureInputPID（跟 `ioreg -k IOConsoleUsers` 同一個值，
//    不開子程序、不會跳權限視窗）。這個 PID 常常不對：11/25 在終端機跑一支開防側錄模式的小程式，系統記成 Helium。
//    所以提示一律講「系統記的是」，記成 loginwindow 時先叫人查密碼管理程式。
//  - 提示是自己的小視窗，不用系統通知：貂毫沒有通知權限，要權限會跳系統視窗；provisional 的通知只進通知中心，看不到。
//    視窗不搶前景（nonactivating），防側錄模式一關就自己收掉；按「知道了」之後，這一次不再跳。
//  - 跳出時在記錄檔資料夾（選單「記錄檔…」）的 secure_input.log 記一行（時間、情況、PID、名字、開著的密碼管理程式），回報問題用：
//    這個狀態登出就沒了，活動監視器也看不到。
//  - 設定：sable.yaml 的 secure_input_hint（預設開；蓬萊設定「一般」頁）。
//  - 命令列：`Sable --secure-input` 印出現在的狀態；`--png <檔> --kind held|login|ended|unknown` 把提示畫成圖（不開視窗）。
//

import AppKit
import Carbon
import IOKit
import SwiftUI

// MARK: - 狀態

struct PenglaiSecureInputStatus: Equatable {
  enum Kind: String {
    case off       // 沒開
    case held      // 系統記的程式還在
    case login     // 記在 loginwindow 頭上（多半不對）
    case ended     // 記的程式已經結束，旗標卻沒放
    case unknown   // 開著，但讀不到是誰
  }

  var kind: Kind
  var pid: pid_t?
  var name: String?
  var bundleID: String?
  /// 開著的密碼管理程式（名字）
  var passwordManagers: [String] = []

  static let off = PenglaiSecureInputStatus(kind: .off)

  /// 終端機類的程式有常駐的「安全鍵盤輸入」開關
  var isTerminal: Bool { ["com.apple.Terminal", "com.googlecode.iterm2"].contains(bundleID ?? "") }

  var logLine: String {
    var parts = ["kind=\(kind.rawValue)"]
    if let pid { parts.append("pid=\(pid)") }
    if let name { parts.append("name=\(name)") }
    if let bundleID { parts.append("bundle=\(bundleID)") }
    if !passwordManagers.isEmpty { parts.append("password_managers=\(passwordManagers.joined(separator: ","))") }
    return parts.joined(separator: " ")
  }
}

enum PenglaiSecureInputProbe {
  /// 認得的密碼管理程式（比對 App 名字，不寫死 bundle id：各版本、各通路的 id 不一樣）
  static let passwordManagerNames = ["1Password", "Bitwarden", "LastPass", "Proton Pass", "Enpass", "Dashlane", "KeePassXC", "Keeper"]

  static func read() -> PenglaiSecureInputStatus {
    guard IsSecureEventInputEnabled() else { return .off }
    var status = PenglaiSecureInputStatus(kind: .unknown)
    status.passwordManagers = runningPasswordManagers()
    guard let pid = holderPID() else { return status }
    status.pid = pid
    if kill(pid, 0) != 0 && errno == ESRCH {
      status.kind = .ended
      return status
    }
    let app = NSRunningApplication(processIdentifier: pid)
    status.bundleID = app?.bundleIdentifier
    status.name = app?.localizedName ?? processName(pid)
    let isLogin = status.bundleID == "com.apple.loginwindow" || status.name == "loginwindow"
    status.kind = isLogin ? .login : .held
    return status
  }

  /// IOConsoleUsers 裡這個使用者的 kCGSSessionSecureInputPID；沒有這個鍵就是沒人持有（或讀不到）
  static func holderPID() -> pid_t? {
    let root = IORegistryGetRootEntry(kIOMainPortDefault)
    guard root != 0 else { return nil }
    defer { IOObjectRelease(root) }
    guard let users = IORegistryEntryCreateCFProperty(root, "IOConsoleUsers" as CFString, kCFAllocatorDefault, 0)?
      .takeRetainedValue() as? [[String: Any]] else { return nil }
    let uid = Int(getuid())
    let mine = users.first { ($0["kCGSSessionUserIDKey"] as? Int) == uid } ?? users.first
    return (mine?["kCGSSessionSecureInputPID"] as? Int).map { pid_t($0) }
  }

  /// 沒有 App 的程序（命令列工具、背景服務）：用執行檔的名字
  static func processName(_ pid: pid_t) -> String? {
    var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
    guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
    return URL(fileURLWithPath: String(cString: buffer)).lastPathComponent
  }

  static func runningPasswordManagers() -> [String] {
    var names: [String] = []
    for app in NSWorkspace.shared.runningApplications {
      guard let name = app.localizedName,
            let known = passwordManagerNames.first(where: { name.localizedCaseInsensitiveContains($0) }),
            !names.contains(known) else { continue }
      names.append(known)
    }
    return names
  }

  /// 螢幕鎖著、或這個使用者不在前台（切到別的使用者）：這時候 loginwindow 開著防側錄模式是正常的
  static func sessionInactive() -> Bool {
    guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
    if (session["CGSSessionScreenIsLocked"] as? Bool) == true { return true }
    if let onConsole = session["kCGSSessionOnConsoleKey"] as? Bool, !onConsole { return true }
    return false
  }
}

// MARK: - 提示的文字

struct PenglaiSecureInputCopy {
  var title: String
  var intro: String
  var steps: [String]
  var footer: String

  static let manualURL = URL(string: "https://penglai.im/wiki/secure-input/")!
  static let lockKeys = "⌃⌘Q"

  init(_ status: PenglaiSecureInputStatus) {
    title = "防側錄模式沒關，貂毫暫時無法使用"
    let base = "有程式開了 macOS 的防側錄模式（Secure Input），超過一分鐘還沒關。開著的時候，系統停用所有不是 Apple 的輸入法，選單裡的貂毫會變灰。"
    let managers = status.passwordManagers
    let managerStep: String = {
      let who = managers.isEmpty ? "密碼管理程式（1Password 這類）" : managers.map { "「\($0)」" }.joined(separator: "、")
      return "\(who)：打開它解鎖一次；還是不行，從選單列的圖示選「結束」，只關視窗沒用。"
    }()
    let lockStep = "鎖定螢幕（\(Self.lockKeys)），等幾秒，用密碼解鎖。"
    let name = status.name.map { "「\($0)」" } ?? "那個程式"

    switch status.kind {
    case .held:
      intro = base + "系統記的是\(name)，但這個名字有時候不對。"
      var list = ["\(name)如果停在密碼欄位、解鎖畫面，把密碼打完或關掉那個視窗。"]
      if status.isTerminal {
        list.append("\(name)的選單裡「安全鍵盤輸入」如果勾著，取消勾選。")
      }
      list.append("還是不行就結束\(name)。")
      if !managers.isEmpty { list.append(managerStep) }
      list.append(lockStep)
      steps = list
    case .login:
      intro = base + "系統記在登入視窗（loginwindow）頭上，這個名字多半不對，真正開著的常常是密碼管理程式。"
      steps = [
        managerStep,
        "找找有沒有在背景等你打密碼的視窗：瀏覽器的登入頁、鑰匙圈、Apple 帳號的密碼要求。",
        lockStep,
      ]
    case .ended:
      let pid = status.pid.map { "（PID \($0)）" } ?? ""
      intro = base + "開它的程式\(pid)已經結束，系統卻沒把它關掉。這時候結束別的程式都沒用。"
      steps = ["登出再登入。"]
    case .unknown, .off:
      intro = base + "系統沒說是哪個程式。"
      steps = [
        "找找有沒有在等你打密碼的視窗：瀏覽器的登入頁、鑰匙圈、終端機的密碼提示。",
        managerStep,
        lockStep,
      ]
    }
    footer = status.kind == .ended
      ? "這個提醒可以在蓬萊設定的「一般」頁關掉。"
      : "都不行的話，登出再登入一定有用。這個提醒可以在蓬萊設定的「一般」頁關掉。"
  }
}

struct PenglaiSecureInputView: View {
  static let width: CGFloat = 380
  var copy: PenglaiSecureInputCopy
  var onManual: () -> Void
  var onDismiss: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Image(systemName: "lock.fill").foregroundStyle(.orange)
        Text(copy.title).font(.system(size: 14, weight: .semibold))
      }
      Text(copy.intro).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
      VStack(alignment: .leading, spacing: 5) {
        ForEach(Array(copy.steps.enumerated()), id: \.offset) { index, step in
          HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(copy.steps.count > 1 ? "\(index + 1)." : "・").font(.system(size: 12).monospacedDigit()).foregroundStyle(.secondary)
            Text(step).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
          }
        }
      }
      Text(copy.footer).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
      HStack {
        Spacer()
        Button("看說明", action: onManual)
        Button("知道了", action: onDismiss).keyboardShortcut(.defaultAction)
      }
    }
    .padding(16)
    .frame(width: Self.width, alignment: .leading)
  }
}

// MARK: - 監看

final class PenglaiSecureInput: NSObject, NSWindowDelegate {
  static let shared = PenglaiSecureInput()
  static let settingKey = "secure_input_hint"
  /// 開著多久才提醒：輸入密碼本來就會開，打完就關
  var delay: TimeInterval = 60
  var interval: TimeInterval = 5
  /// 設定的開關；命令列 --watch 沒有貂毫的設定，一律開
  var enabled: () -> Bool = { NSApp.squirrelAppDelegate.config?.getBool("secure_input_hint") ?? true }

  private var timer: Timer?
  /// 這一次從什麼時候開始算（鎖定、睡著時清掉）
  private var since: Date?
  /// 這一次已經按過「知道了」
  private var dismissed = false
  private var shownAt: Date?
  private var panel: NSPanel?
  private var shownStatus: PenglaiSecureInputStatus?
  /// --watch：記錄也印到標準輸出
  var echo = false

  func start() {
    guard timer == nil else { return }
    let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in self?.tick() }
    timer.tolerance = 1
    RunLoop.main.add(timer, forMode: .common)
    self.timer = timer
    // 鎖定、螢幕睡著時 loginwindow 開著是正常的；解鎖、醒來重新計時
    let reset: (Notification) -> Void = { [weak self] _ in self?.since = nil }
    NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main, using: reset)
    NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main, using: reset)
    NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil, queue: .main, using: reset)
    DistributedNotificationCenter.default().addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main, using: reset)
  }

  private func tick() {
    guard IsSecureEventInputEnabled() else {
      endEpisode()
      return
    }
    if PenglaiSecureInputProbe.sessionInactive() {
      since = nil
      hidePanel()
      return
    }
    let now = Date()
    let start = since ?? now
    since = start
    let on = enabled()
    guard on, !dismissed, now.timeIntervalSince(start) >= delay else {
      if !on { hidePanel() }
      return
    }
    let status = PenglaiSecureInputProbe.read()
    guard status.kind != .off else { return }
    if panel == nil {
      shownAt = now
      log("shown after \(Int(now.timeIntervalSince(start)))s \(status.logLine)")
    }
    if status != shownStatus {
      if panel != nil { log("changed \(status.logLine)") }
      show(status)
    }
  }

  private func endEpisode() {
    if let shownAt {
      log("released \(Int(Date().timeIntervalSince(shownAt)))s after shown")
    }
    since = nil
    dismissed = false
    shownAt = nil
    hidePanel()
  }

  private func show(_ status: PenglaiSecureInputStatus) {
    shownStatus = status
    let view = PenglaiSecureInputView(copy: PenglaiSecureInputCopy(status), onManual: { [weak self] in
      NSWorkspace.shared.open(PenglaiSecureInputCopy.manualURL)
      self?.dismiss()
    }, onDismiss: { [weak self] in
      self?.dismiss()
    })
    let hosting = NSHostingView(rootView: view)
    let size = hosting.fittingSize
    let panel = self.panel ?? {
      let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable, .nonactivatingPanel],
                          backing: .buffered, defer: false)
      panel.title = "貂毫"
      panel.titleVisibility = .hidden
      panel.titlebarAppearsTransparent = true
      panel.isFloatingPanel = true
      panel.level = .floating
      panel.hidesOnDeactivate = false
      panel.isReleasedWhenClosed = false
      panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
      panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
      panel.standardWindowButton(.zoomButton)?.isHidden = true
      panel.delegate = self
      self.panel = panel
      return panel
    }()
    panel.contentView = hosting
    panel.setContentSize(size)
    // 放在滑鼠所在螢幕的右上角，跟系統通知同一個位置
    let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
    if let visible = screen?.visibleFrame {
      let frame = panel.frame
      panel.setFrameOrigin(NSPoint(x: visible.maxX - frame.width - 16, y: visible.maxY - frame.height - 16))
    }
    panel.orderFrontRegardless()
  }

  /// 按紅點關掉也算「知道了」（自己收掉時 panel 已經先清成 nil）
  func windowWillClose(_ notification: Notification) {
    guard let window = notification.object as? NSPanel, window === panel else { return }
    panel = nil
    shownStatus = nil
    dismissed = true
    log("dismissed")
  }

  private func dismiss() {
    dismissed = true
    log("dismissed")
    hidePanel()
  }

  func hidePanel() {
    guard let panel else { return }
    self.panel = nil
    shownStatus = nil
    panel.close()
  }

  private func log(_ message: String) {
    let url = SquirrelApp.logDir.appendingPathComponent("secure_input.log")
    let formatter = ISO8601DateFormatter()
    formatter.timeZone = .current
    let line = "\(formatter.string(from: Date())) \(message)\n"
    if echo { print(line, terminator: ""); fflush(stdout) }
    guard let data = line.data(using: .utf8) else { return }
    if let handle = try? FileHandle(forWritingTo: url) {
      defer { try? handle.close() }
      // 只留最近的：超過 256 KB 就從頭寫
      if (try? handle.seekToEnd()) ?? 0 > 256 * 1024 {
        try? handle.truncate(atOffset: 0)
      }
      try? handle.write(contentsOf: data)
    } else {
      try? data.write(to: url)
    }
  }

  // MARK: 命令列

  /// `Sable --secure-input`：印出現在的狀態。`--png <檔> --kind held|login|ended|unknown [--name X] [--managers A,B]`：把提示畫成圖
  static func runCommand(_ args: [String]) {
    var options: [String: String] = [:]
    var index = 0
    while index < args.count {
      let key = args[index].replacingOccurrences(of: "--", with: "")
      if index + 1 < args.count, !args[index + 1].hasPrefix("--") {
        options[key] = args[index + 1]
        index += 2
      } else {
        options[key] = ""
        index += 1
      }
    }
    if let seconds = options["watch"].flatMap(Double.init) {
      // 測試用：在這個程序裡跑監看 seconds 秒，--delay、--interval 換掉 60、5 秒；狀態變化印到標準輸出
      let app = NSApplication.shared
      app.setActivationPolicy(.accessory)
      let monitor = PenglaiSecureInput()
      monitor.delay = options["delay"].flatMap(Double.init) ?? 3
      monitor.interval = options["interval"].flatMap(Double.init) ?? 1
      monitor.enabled = { true }
      monitor.echo = true
      monitor.start()
      DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
        monitor.hidePanel()
        app.terminate(nil)
      }
      app.run()
      return
    }
    guard let png = options["png"] else {
      let status = PenglaiSecureInputProbe.read()
      print(status.kind == .off ? "off" : status.logLine)
      return
    }
    var status = PenglaiSecureInputStatus(kind: PenglaiSecureInputStatus.Kind(rawValue: options["kind"] ?? "held") ?? .held)
    status.pid = 1234
    status.name = options["name"] ?? (status.kind == .login ? "loginwindow" : "終端機")
    status.bundleID = status.kind == .login ? "com.apple.loginwindow" : (status.name == "終端機" ? "com.apple.Terminal" : nil)
    status.passwordManagers = options["managers"].map { $0.split(separator: ",").map(String.init) } ?? []
    _ = NSApplication.shared
    let view = PenglaiSecureInputView(copy: PenglaiSecureInputCopy(status), onManual: {}, onDismiss: {})
      .background(Color(nsColor: .windowBackgroundColor))
    let hosting = NSHostingView(rootView: view)
    hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)
    hosting.layoutSubtreeIfNeeded()
    guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return }
    hosting.cacheDisplay(in: hosting.bounds, to: rep)
    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: png))
    print("\(png) \(Int(hosting.bounds.width))×\(Int(hosting.bounds.height))")
  }
}
