//
//  PenglaiOnboarding.swift
//  Squirrel
//
//  第一次使用的引導：輸入框第一次用貂毫時開一個小視窗，一頁一個選擇（目前只有讀音）。
//  選了之後寫進設定的路跟蓬萊設定視窗同一條（PenglaiSettingsModel：寫 custom 檔、記變更紀錄、部署），
//  所以設定視窗看得到、復原得了。看過哪幾頁記在使用者資料夾的 penglai-onboarding.json（PenglaiOnboardingRecord）：
//  按「開始使用」或直接關掉視窗都算看過，選了的也照樣寫進設定，只出現一次。
//  `Sable --onboarding --user-dir <沙盒>`：不啟動輸入法，在沙盒上開引導（測試、截圖用）
//    --snapshot <資料夾>  開著視窗跑 --script，shot=<名字> 存一張 PNG
//    --script <步驟>      分號隔開：choose=zhongzhou、next、back、shot=first、done（按開始使用）、close（直接關掉）
//    --show               跑完 --script 不結束，留著視窗
//

import AppKit
import SwiftUI

/// 引導的頁。之後加頁：加一個 case，補上 available（這台用不用得到）、PenglaiOnboardingView 的畫面、
/// PenglaiOnboardingState.commit（按「開始使用」時寫進設定）。看過的頁記名稱，已經看過舊頁的人只會看到新加的頁
enum PenglaiOnboardingPage: String, CaseIterable, Identifiable {
  case reading

  var id: String { rawValue }

  func available(_ model: PenglaiSettingsModel) -> Bool {
    switch self {
    case .reading: return model.readingState.enabled
    }
  }
}

/// 引導進行中：第幾頁、每一頁選了什麼。選的時候只記在這裡，按「開始使用」才寫進設定
final class PenglaiOnboardingState: ObservableObject {
  let model: PenglaiSettingsModel
  let pages: [PenglaiOnboardingPage]
  @Published var index = 0
  /// 讀音頁的選擇。引導只放蓬萊音、中州音（兼收並蓄只在設定視窗）；一開始是存著的那個，不是這兩個就是蓬萊音
  @Published var reading: String
  static let readingChoices = ["reading_penglai", "reading_zhongzhou"]

  init(model: PenglaiSettingsModel, pages: [PenglaiOnboardingPage]) {
    self.model = model
    self.pages = pages
    let saved = model.readingState.choice ?? PenglaiReading.defaultOption
    reading = Self.readingChoices.contains(saved) ? saved : PenglaiReading.defaultOption
  }

  var page: PenglaiOnboardingPage { pages[min(index, pages.count - 1)] }
  var isLast: Bool { index >= pages.count - 1 }

  /// 每一頁選的寫進設定。跟存著的一樣就不寫（不記變更紀錄、不部署）；回傳寫了哪些
  @discardableResult
  func commit() -> [String] {
    var written: [String] = []
    for page in pages {
      switch page {
      case .reading:
        guard reading != model.readingState.choice else { continue }
        model.setReading(reading)
        written.append("讀音：\(PenglaiCopy.readingOption(reading).title)")
      }
    }
    return written
  }
}

// MARK: - 畫面

struct PenglaiOnboardingView: View {
  @ObservedObject var state: PenglaiOnboardingState
  var finish: () -> Void

  static let size = CGSize(width: 600, height: 420)

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 10) {
        Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 28, height: 28)
        Text("歡迎使用貂毫").font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
      }
      .padding(.bottom, 18)
      switch state.page {
      case .reading: readingPage
      }
      Spacer(minLength: 0)
      bottomBar
    }
    .padding(.horizontal, 32).padding(.top, 22).padding(.bottom, 20)
    .frame(width: Self.size.width, height: Self.size.height)
  }

  private var readingPage: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(PenglaiCopy.readingPage.title).font(.system(size: 26, weight: .bold))
      Text(PenglaiCopy.readingPage.desc ?? "").font(.system(size: 13.5)).foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true).padding(.top, 8)
      HStack(spacing: 14) {
        ForEach(PenglaiOnboardingState.readingChoices, id: \.self) { option in
          PenglaiReadingCard(option: option, selected: state.reading == option, large: true) { state.reading = option }
        }
      }
      .fixedSize(horizontal: false, vertical: true)
      .padding(.top, 22)
      Text(PenglaiCopy.readingLater).font(.system(size: 12.5)).foregroundStyle(.secondary).padding(.top, 14)
    }
  }

  /// 頁數點點（不只一頁時）、上一步、下一步或開始使用
  private var bottomBar: some View {
    HStack(spacing: 10) {
      if state.pages.count > 1 {
        HStack(spacing: 6) {
          ForEach(state.pages.indices, id: \.self) { number in
            Circle().fill(number == state.index ? Color.accentColor : Color.secondary.opacity(0.3)).frame(width: 7, height: 7)
          }
        }
      }
      Spacer()
      if state.index > 0 {
        Button("上一步") { state.index -= 1 }
      }
      Button {
        if state.isLast { finish() } else { state.index += 1 }
      } label: {
        Text(state.isLast ? "開始使用" : "下一步").frame(minWidth: 80)
      }
      .buttonStyle(.borderedProminent)
      .keyboardShortcut(.defaultAction)
    }
    .controlSize(.large)
  }
}

// MARK: - 視窗

final class PenglaiOnboardingWindowController: NSWindowController, NSWindowDelegate {
  static var shared: PenglaiOnboardingWindowController?
  let state: PenglaiOnboardingState
  private var finished = false
  var onClose: (() -> Void)?

  init(state: PenglaiOnboardingState) {
    self.state = state
    let window = NSWindow(contentRect: NSRect(origin: .zero, size: PenglaiOnboardingView.size), styleMask: [.titled, .closable],
                          backing: .buffered, defer: false)
    window.title = "歡迎使用貂毫"   // 標題列不顯示（畫面裡已經有），留給視窗選單、任務控制
    window.titleVisibility = .hidden
    window.titlebarAppearsTransparent = true
    window.isReleasedWhenClosed = false
    super.init(window: window)
    window.contentView = NSHostingView(rootView: PenglaiOnboardingView(state: state) { [weak self] in self?.finish() })
    window.center()
    window.delegate = self
  }

  required init?(coder: NSCoder) { nil }

  /// 按「開始使用」：寫進設定、記成看過、關掉視窗。回傳寫了哪些
  @discardableResult
  func finish() -> [String] {
    guard !finished else { return [] }
    finished = true
    let written = state.commit()
    markSeen()
    window?.close()
    return written
  }

  /// 直接關掉視窗也算看過，選了的照樣寫進設定（點了卡片卻按紅點關掉，不該當成沒選）
  func windowWillClose(_ notification: Notification) {
    if !finished {
      finished = true
      _ = state.commit()
      markSeen()
    }
    onClose?()
  }

  private func markSeen() {
    var record = PenglaiOnboardingRecord.load(state.model.userDir)
    record.mark(state.pages.map(\.rawValue), at: Date())
    do {
      try record.save(state.model.userDir)
    } catch {
      NSLog("Penglai onboarding: 記不下看過的頁：%@", error.localizedDescription)
    }
  }
}

enum PenglaiOnboarding {
  /// 還沒看過、這台用得到的頁
  static func pendingPages(_ model: PenglaiSettingsModel) -> [PenglaiOnboardingPage] {
    let record = PenglaiOnboardingRecord.load(model.userDir)
    return PenglaiOnboardingPage.allCases.filter { !record.seen($0.rawValue) && $0.available(model) }
  }

  private static var waiting = false
  private static var done = false

  /// 輸入法程序：輸入框開始用貂毫時（activateServer）叫。還有沒看過的頁才開，一個程序最多開一次。
  /// 剛裝好第一次啟動時還在部署，等部署完再讀（讀音選項要從部署後的方案讀）
  static func showIfNeeded() {
    guard !done, !waiting else { return }
    let record = PenglaiOnboardingRecord.load(SquirrelApp.userDir)
    guard PenglaiOnboardingPage.allCases.contains(where: { !record.seen($0.rawValue) }) else {
      done = true
      return
    }
    waiting = true
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
      waiting = false
      if NSApp.squirrelAppDelegate.rimeAPI.is_maintenance_mode() {
        showIfNeeded()
        return
      }
      done = true
      let model = PenglaiSettingsWindowController.inputMethodModel
      model.reload()
      let pages = pendingPages(model)
      guard !pages.isEmpty else { return }
      let controller = PenglaiOnboardingWindowController(state: PenglaiOnboardingState(model: model, pages: pages))
      controller.onClose = { PenglaiOnboardingWindowController.shared = nil }
      PenglaiOnboardingWindowController.shared = controller
      controller.showWindow(nil)
      controller.window?.makeKeyAndOrderFront(nil)
      controller.window?.orderFrontRegardless()
      NSApp.activate(ignoringOtherApps: true)
    }
  }

  // MARK: 沙盒

  /// `Sable --onboarding --user-dir <沙盒>`：照輸入法同一套判斷要不要出現；出現就開視窗（或照 --script 點）
  static func runStandalone(_ args: [String]) {
    let options = PenglaiSettingsStandalone.parse(args)
    let userDir = PenglaiSettingsStandalone.sandbox(options, usage: "用法：Sable --onboarding --user-dir <沙盒資料夾> [--snapshot <資料夾>] [--script <步驟>] [--show]")
    let (rimeAPI, deployer) = PenglaiSettingsStandalone.startRime(userDir)
    let model = PenglaiSettingsModel(userDir: userDir, sharedDir: Bundle.main.sharedSupportURL,
                                     catalogURL: Bundle.main.url(forResource: "penglai-settings", withExtension: "json"), deployer: deployer)
    let before = PenglaiOnboardingRecord.load(userDir)
    print("看過的頁：" + (before.pages.isEmpty ? "（沒有）" : before.pages.sorted { $0.key < $1.key }.map { "\($0.key)（\($0.value)）" }.joined(separator: "、")))
    let pages = pendingPages(model)
    guard !pages.isEmpty else {
      print("引導不出現：每一頁都看過了，或這個方案用不到")
      rimeAPI.finalize()
      exit(0)
    }
    let state = PenglaiOnboardingState(model: model, pages: pages)
    print("引導出現：\(pages.map(\.rawValue).joined(separator: "、"))；讀音一開始選 \(PenglaiCopy.readingOption(state.reading).title)")

    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    let controller = PenglaiOnboardingWindowController(state: state)
    controller.showWindow(nil)
    controller.window?.makeKeyAndOrderFront(nil)
    app.activate(ignoringOtherApps: true)
    let snapshotDir = options["snapshot"].map { URL(fileURLWithPath: $0, isDirectory: true) }
    if let snapshotDir { try? FileManager.default.createDirectory(at: snapshotDir, withIntermediateDirectories: true) }

    let customFile = PenglaiConfigID.schema(model.schemaID).customFile
    for step in (options["script"] ?? "").components(separatedBy: ";").map({ $0.trimmingCharacters(in: .whitespaces) }) where !step.isEmpty {
      let parts = step.components(separatedBy: "=")
      let value = parts.dropFirst().joined(separator: "=")
      var result = "ok"
      switch parts[0] {
      case "choose":
        let option = value.hasPrefix("reading_") ? value : "reading_" + value
        if PenglaiOnboardingState.readingChoices.contains(option) { state.reading = option } else { result = "引導沒有 \(option)" }
      case "next": state.index = min(state.index + 1, pages.count - 1)
      case "back": state.index = max(state.index - 1, 0)
      case "shot":
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        guard let snapshotDir else { result = "沒給 --snapshot"; break }
        let url = snapshotDir.appendingPathComponent("onboarding-\(value).png")
        PenglaiSettingsStandalone.save(controller.window, to: url)
        result = url.path
      case "done":
        let written = controller.finish()
        PenglaiSettingsStandalone.waitForDeploy(model)
        result = written.isEmpty ? "跟存著的一樣，沒寫設定" : "寫了 " + written.joined(separator: "、")
      case "close":
        controller.close()
        PenglaiSettingsStandalone.waitForDeploy(model)
      default:
        result = "不認得這一步"
      }
      print("步驟 \(step)：\(result)")
    }
    if options["script"] != nil {
      model.reload()
      let doc = model.store.read(customFile)
      let key = model.readingSwitch.map { PenglaiReading.resetKey($0.index) }
      print("方案 custom 檔 \(customFile) 的 \(key ?? "讀音")：\(key.flatMap { doc.value($0) } ?? "（沒寫）")；讀音存的是 "
        + (model.readingState.choice.map { PenglaiCopy.readingOption($0).title } ?? "（沒有）"))
      let after = (try? String(contentsOf: userDir.appendingPathComponent(PenglaiOnboardingRecord.file), encoding: .utf8)) ?? "（沒有檔案）"
      print("\(PenglaiOnboardingRecord.file)：\(after.replacingOccurrences(of: "\n", with: " "))")
      if options["show"] == nil {
        rimeAPI.finalize()
        exit(0)
      }
    }
    NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: controller.window, queue: .main) { _ in
      PenglaiSettingsStandalone.waitForDeploy(model)
      rimeAPI.finalize()
      exit(0)
    }
    app.run()
  }
}
