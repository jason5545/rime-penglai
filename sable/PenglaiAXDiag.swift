//
//  PenglaiAXDiag.swift
//  貂毫：用輔助使用（AX）補讀游標前的字的實驗診斷（docs/findings.md〈AX 補讀前後文實測〉，11/4）
//
//  預設關著：使用者資料夾裡有 penglai-axdiag 這個檔才開（每個鍵最多每 2 秒查一次檔案在不在）。關著時除了查檔，什麼都不做。
//  開著時，貂毫送出字之後、組字區空著按空白時，同時用 IMK 和 AX 讀游標前的字，在記憶體裡比對，
//  記錄只寫長度、位置、對不對、耗時，不寫任何字。
//  AX 一律在背景佇列讀（AXUIElementSetMessagingTimeout 0.25 秒），不卡打字；IMK 的延遲重讀在主執行緒，
//  使用者按了下一個鍵（視窗伺服器的按鍵計數變了）就不讀。
//  記錄：/usr/bin/log show --predicate 'subsystem == "im.penglai.inputmethod.Sable" AND category == "axdiag"'
//  檔案內容（第一行）選要打開無障礙樹的屬性：auto（預設：Electron 用 AXManualAccessibility，Chrome 系用
//  AXEnhancedUserInterface，其他不設）、manual、enhanced、none。旗標拿掉時把設過的設回去。
//  Electron 44、Chrome 收到這兩個屬性都要等 2 秒才建完整的無障礙樹（electron_application.mm、
//  chrome_browser_application_mac.mm 的 enableScreenReaderCompleteModeAfterDelay）；AXEnhancedUserInterface 另外交給
//  AppKit，設定時一律回 -25208，其實有效，Electron 的 AXManualAccessibility 讀回來一律是 0（11/4 對 T3 實測）。
//

import AppKit
import ApplicationServices
import InputMethodKit
import os

/// 一次 AX 讀取：字只留在記憶體裡比對。
struct PenglaiAXRead {
  var role = ""          // 焦點元件的 AXRole
  var method = "-"       // v：AXSelectedTextRange＋AXStringForRange；V：同上但字用 AXValue；m：text marker；-：讀不到
  var caret = -1         // 游標在元件裡的 UTF-16 位置
  var selection = -1     // 選取長度
  var total = -1         // 整欄長度
  var before = ""        // 游標前最多 PenglaiAX.beforeLimit 個 UTF-16
  var calls = 0
  var micros = 0
  var error: Int32 = 0   // 第一個失敗的 AXError
  var ok: Bool { method != "-" }
}

enum PenglaiAX {
  static let beforeLimit = 200
  static let timeout: Float = 0.25

  private static func copy(_ element: AXUIElement, _ attribute: String, _ read: inout PenglaiAXRead) -> CFTypeRef? {
    var value: CFTypeRef?
    read.calls += 1
    let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
    if error != .success {
      if read.error == 0 { read.error = error.rawValue }
      return nil
    }
    return value
  }

  private static func copy(_ element: AXUIElement, _ attribute: String, _ parameter: CFTypeRef, _ read: inout PenglaiAXRead) -> CFTypeRef? {
    var value: CFTypeRef?
    read.calls += 1
    let error = AXUIElementCopyParameterizedAttributeValue(element, attribute as CFString, parameter, &value)
    if error != .success {
      if read.error == 0 { read.error = error.rawValue }
      return nil
    }
    return value
  }

  private static func element(_ value: CFTypeRef?) -> AXUIElement? {
    guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
    return (value as! AXUIElement)
  }

  private static func markerRange(_ value: CFTypeRef?) -> AXTextMarkerRange? {
    guard let value, CFGetTypeID(value) == AXTextMarkerRangeGetTypeID() else { return nil }
    return (value as! AXTextMarkerRange)
  }

  /// 讀 pid 這個 App 焦點元件游標前的字：一般 App 用 AXSelectedTextRange、AXStringForRange；網頁讀不到時往上找
  /// AXEditableAncestor，用 AXSelectedTextMarkerRange、AXTextMarkerRangeForUIElement、AXStringForTextMarkerRange。
  static func read(pid: pid_t) -> PenglaiAXRead {
    let start = DispatchTime.now().uptimeNanoseconds
    var read = PenglaiAXRead()
    let app = AXUIElementCreateApplication(pid)
    AXUIElementSetMessagingTimeout(app, timeout)
    if let focused = element(copy(app, kAXFocusedUIElementAttribute, &read)) {
      readElement(focused, &read)
    }
    read.micros = Int((DispatchTime.now().uptimeNanoseconds - start) / 1000)
    return read
  }

  /// 讀指定元件游標前的字（read(pid:) 的後半段）。
  static func readElement(_ focused: AXUIElement, _ read: inout PenglaiAXRead) {
    AXUIElementSetMessagingTimeout(focused, timeout)
    read.role = roleCode(copy(focused, kAXRoleAttribute, &read) as? String)
    readByRange(focused, &read)
    if !read.ok {
      readByMarkers(focused, &read)
    }
  }

  private static func readByRange(_ focused: AXUIElement, _ read: inout PenglaiAXRead) {
    guard let value = copy(focused, kAXSelectedTextRangeAttribute, &read), CFGetTypeID(value) == AXValueGetTypeID() else { return }
    var range = CFRange()
    guard AXValueGetValue(value as! AXValue, .cfRange, &range), range.location >= 0 else { return }
    read.caret = range.location
    read.selection = range.length
    if let count = copy(focused, kAXNumberOfCharactersAttribute, &read) as? Int {
      read.total = count
    }
    let from = max(0, range.location - beforeLimit)
    var want = CFRange(location: from, length: range.location - from)
    if want.length == 0 {
      read.method = "v"
      return
    }
    if let parameter = AXValueCreate(.cfRange, &want),
       let text = copy(focused, kAXStringForRangeParameterizedAttribute, parameter, &read) as? String {
      read.before = text
      read.method = "v"
    } else if (0...200_000).contains(read.total), let text = copy(focused, kAXValueAttribute, &read) as? String {
      let units = Array(text.utf16)
      guard range.location <= units.count else { return }
      read.before = String(decoding: units[from..<range.location], as: UTF16.self)
      read.method = "V"
    }
  }

  private static func readByMarkers(_ focused: AXUIElement, _ read: inout PenglaiAXRead) {
    let host = element(copy(focused, "AXEditableAncestor", &read)) ?? focused
    AXUIElementSetMessagingTimeout(host, timeout)
    guard let selection = markerRange(copy(host, "AXSelectedTextMarkerRange", &read)),
          let whole = markerRange(copy(host, "AXTextMarkerRangeForUIElement", host, &read)) else { return }
    let first = AXTextMarkerRangeCopyStartMarker(whole)
    let caret = AXTextMarkerRangeCopyStartMarker(selection)
    let before = AXTextMarkerRangeCreate(nil, first, caret)
    guard let text = copy(host, "AXStringForTextMarkerRange", before, &read) as? String else { return }
    read.caret = text.utf16.count
    read.before = PenglaiAXDiag.suffix(text, beforeLimit)
    read.selection = copy(host, "AXLengthForTextMarkerRange", selection, &read) as? Int ?? -1
    read.total = copy(host, "AXLengthForTextMarkerRange", whole, &read) as? Int ?? -1
    read.method = "m"
  }

  /// 記錄只放標準的 AXRole：role 是目標 App 給的字串，不合規的 App 可能把任何東西放進來（11/4 Terra 第 1 輪第 1 條），其他一律記 other。
  static let knownRoles: Set<String> = [
    "AXTextArea", "AXTextField", "AXComboBox", "AXWebArea", "AXGroup", "AXStaticText", "AXOutline", "AXList", "AXTable",
    "AXScrollArea", "AXWindow", "AXButton", "AXCell", "AXRow", "AXApplication", "AXUnknown",
  ]

  static func roleCode(_ role: String?) -> String {
    guard let role, !role.isEmpty else { return "" }
    return knownRoles.contains(role) ? role : "other"
  }

  /// App 層的布林屬性（AXManualAccessibility、AXEnhancedUserInterface）：nil 是讀不到。
  static func flag(pid: pid_t, _ attribute: String) -> Bool? {
    let app = AXUIElementCreateApplication(pid)
    AXUIElementSetMessagingTimeout(app, timeout)
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(app, attribute as CFString, &value) == .success else { return nil }
    return (value as? NSNumber)?.boolValue
  }

  static func setFlag(pid: pid_t, _ attribute: String, _ on: Bool) -> Int32 {
    let app = AXUIElementCreateApplication(pid)
    AXUIElementSetMessagingTimeout(app, timeout)
    return AXUIElementSetAttributeValue(app, attribute as CFString, (on ? kCFBooleanTrue : kCFBooleanFalse)!).rawValue
  }

  /// Electron 的 App 包裡有 Electron Framework；Chrome 系有「… Framework.framework」裡帶 Chrom、Edge、Brave、Vivaldi、Arc。
  static func engine(_ app: NSRunningApplication) -> String {
    guard let url = app.bundleURL else { return "" }
    let frameworks = url.appendingPathComponent("Contents/Frameworks")
    let names = (try? FileManager.default.contentsOfDirectory(atPath: frameworks.path)) ?? []
    if names.contains("Electron Framework.framework") { return "electron" }
    if names.contains(where: { $0.hasSuffix(" Framework.framework") &&
      ["Chrom", "Edge", "Brave", "Vivaldi", "Arc", "Opera"].contains(where: $0.contains) }) { return "chrome" }
    return ""
  }
}

/// IMK 那一份：跟 0023、0027 一樣讀 selectedRange 和游標前的字。
struct PenglaiIMKRead {
  var caret = -1
  var selection = -1
  var before: String?
  var micros = 0
  var ok: Bool { before != nil }

  static let beforeLimit = 100

  init() {}

  init(_ client: IMKTextInput) {
    let start = DispatchTime.now().uptimeNanoseconds
    let range = client.selectedRange()
    if range.location != NSNotFound {
      caret = range.location
      selection = range.length
      let from = max(0, range.location - Self.beforeLimit)
      if range.location == from {
        before = ""
      } else {
        before = client.attributedSubstring(from: NSRange(location: from, length: range.location - from))?.string
      }
    }
    micros = Int((DispatchTime.now().uptimeNanoseconds - start) / 1000)
  }
}

/// 實驗本身：記事件、排延遲重讀、寫記錄。除了 AX 讀取，全部在主執行緒。
///
/// 事件有三種，每種結束時寫一行記錄：
/// - c：貂毫送出字（commit(string:)）。游標前應該是「上一次送出以來的字＋這次的字」（中間有鍵交給 App、點滑鼠、按 Command、
///   切換 App 就只看這次的字）。送出後照 schedule 的時間點，IMK、AX 各讀到對為止；下一個鍵一按就停。
/// - r：換掉剛補的標點（replace(_:with:)，第二下空白）。跟 c 一樣。
/// - s：組字區空著、中文模式按純空白。交給 librime 之前 IMK 讀一次（同步）、AX 讀一次（背景），處理完之後在 100、300、600、
///   1000 毫秒兩邊各讀一次；最後一輪兩邊讀到一樣的字當成真實內容，回頭看按下去那一刻兩邊各自對不對。
final class PenglaiAXDiag {
  static let shared = PenglaiAXDiag()
  static let flagFile = "penglai-axdiag"
  /// 送出之後重讀的時間點（毫秒）：0 是送出後主執行緒下一輪。
  static let schedule: [Int] = [0, 15, 30, 60, 100, 200, 300, 600, 1000]
  static let spaceSchedule: [Int] = [100, 300, 600, 1000]
  /// 比對時看的字數（UTF-16）
  static let window = 40

  private let log = Logger(subsystem: "im.penglai.inputmethod.Sable", category: "axdiag")
  private let queue = DispatchQueue(label: "im.penglai.inputmethod.Sable.axdiag", qos: .userInitiated)

  var userDir: URL?
  private(set) var on = false
  private var mode = "auto"
  private var checkedAt: UInt64 = 0
  private var flagTimer: Timer?
  private var seq = 0
  private var keySeq = 0
  // keySeq 的副本給背景佇列讀：視窗伺服器的計數不算自動重複的鍵，也可能比貂毫處理到的鍵超前，
  // 背景讀完時兩個都要比（11/4 Terra 第 3 輪第 3、4 條）
  private let processedKeys = NSLock()
  private var processedKeySeq = 0
  private var lastKeyAt: UInt64 = 0
  private var gap = -1
  private var mouseAtLastKey: UInt32 = 0
  // 上一次送出之後 App 只收到貂毫送的字時，游標前應該是這幾個字
  private var tail = ""
  private var tailKnown = false
  // 這個空白鍵裡發生的事
  private var space: SpaceEvent?
  // 0027 的 sendSpaceContext() 剛送給引擎的前後文（長度、讀後文走哪條路、游標前一個字的類別），給接著的空白事件
  private var sentContext: String?
  private var axBusy = false   // 主執行緒看的：背景還有一次 AX 讀取沒回來
  private var promptedForTrust = false
  // 背景佇列那邊的狀態（只在 queue 上碰）
  private var apps: [pid_t: AppAX] = [:]
  private var loggedUntrusted = false

  private struct AppAX {
    var bundle = ""
    var engine = ""
    var setAttribute = ""   // 這次實驗設過的屬性（關掉旗標時設回去）
    var setAt: UInt64 = 0
    var readyLogged = false
    var failures = 0
  }

  private final class Event {
    let id: Int
    let kind: String
    let app: String
    let pid: pid_t
    weak var client: IMKTextInput?
    let keySeq: Int
    let keys: UInt32          // 視窗伺服器的按鍵＋滑鼠計數
    let born: UInt64
    let gap: Int
    var expected = ""         // c、r：游標前應該結尾的字
    var adjacent = false      // expected 帶了之前送出的字
    var preedit = false       // c：送出前有組字
    var imk: [(ms: Int, read: PenglaiIMKRead)] = []
    var ax: [(ms: Int, read: PenglaiAXRead)] = []   // ms 是背景讀完的時間
    var supersededAt = -1
    var axSkipped = 0
    var axLate = 0            // 讀完時已經被下一個鍵、滑鼠取代，不算的 AX 結果
    var imkDone = false
    var axDone = false
    var pendingSlots = 0
    var axInFlight = false
    var finished = false
    // s
    var foreignWanted = false
    var pendingPunct: (caret: Int, text: String, length: Int)?
    var imkPre = PenglaiIMKRead()
    var axPre: PenglaiAXRead?
    var axPreDone = -1        // 背景讀完的時間（毫秒）
    var handledAt = -1        // 這個鍵處理完、回給 App 的時間
    var drop = 0
    var insert = ""
    var outcome = "?"
    var sent = "-"
    init(id: Int, kind: String, app: String, pid: pid_t, client: IMKTextInput, keySeq: Int, gap: Int) {
      self.id = id; self.kind = kind; self.app = app; self.pid = pid; self.client = client
      self.keySeq = keySeq; self.keys = PenglaiAXDiag.inputCount(); self.born = DispatchTime.now().uptimeNanoseconds; self.gap = gap
    }
    func ms(_ time: UInt64 = DispatchTime.now().uptimeNanoseconds) -> Int { Int((time &- born) / 1_000_000) }
  }

  private final class SpaceEvent {
    let event: Event
    var commits: [String] = []
    var replacedWith: (drop: Int, insert: String)?
    init(_ event: Event) { self.event = event }
  }

  // MARK: 旗標

  /// 每個 keyDown 最先叫（Command 組合鍵也算）。關著時只比時間，每 2 秒才查一次檔案在不在。
  func noteKeyDown(command: Bool) {
    let now = DispatchTime.now().uptimeNanoseconds
    if checkedAt == 0 || now &- checkedAt > 2_000_000_000 {
      checkedAt = now
      refresh()
    }
    guard on else { return }
    keySeq += 1
    processedKeys.lock()
    processedKeySeq = keySeq
    processedKeys.unlock()
    gap = lastKeyAt == 0 ? -1 : Int((now - lastKeyAt) / 1_000_000)
    lastKeyAt = now
    let mouse = Self.mouseCount()
    if command || mouse != mouseAtLastKey {
      breakTail()
    }
    mouseAtLastKey = mouse
  }

  private func refresh() {
    guard let userDir else { return }
    let url = userDir.appendingPathComponent(Self.flagFile)
    let exists = FileManager.default.fileExists(atPath: url.path)
    guard exists != on else { return }
    on = exists
    if on {
      let first = (try? String(contentsOf: url, encoding: .utf8))?.split(whereSeparator: \.isNewline).first
      let word = first.map { $0.trimmingCharacters(in: .whitespaces).lowercased() } ?? ""
      mode = ["manual", "enhanced", "none"].contains(word) ? word : "auto"
      let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
      let trusted = AXIsProcessTrusted()
      // 沒有「輔助使用」權限時，這次開機問一次：系統跳出對話框、把貂毫加進清單，使用者只要打開開關
      var prompted = false
      if !trusted && !promptedForTrust {
        promptedForTrust = true
        prompted = true
        _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary)
      }
      // 開著時另外每 3 秒查一次：拿掉旗標之後就算不再用貂毫打字（切到別的輸入法），屬性也會設回去（11/4 Terra 第 1 輪第 3 條）。
      // 關著時沒有這個計時器
      let timer = Timer(timeInterval: 3, repeats: true) { [weak self] _ in
        guard let self else { return }
        self.checkedAt = DispatchTime.now().uptimeNanoseconds
        self.refresh()
      }
      RunLoop.main.add(timer, forMode: .common)
      flagTimer = timer
      log.notice("axdiag on trusted=\(trusted ? 1 : 0, privacy: .public) prompted=\(prompted ? 1 : 0, privacy: .public) mode=\(self.mode, privacy: .public) pid=\(getpid(), privacy: .public) version=\(version, privacy: .public) path=\(Bundle.main.bundlePath, privacy: .public)")
      mouseAtLastKey = Self.mouseCount()
    } else {
      log.notice("axdiag off")
      flagTimer?.invalidate()
      flagTimer = nil
      space = nil
      queue.async { self.resetAttributes() }
    }
    breakTail()
  }

  // MARK: 掛在輸入法流程上的點（關著時都是馬上 return）

  /// App 拿到貂毫以外的輸入（鍵交給 App、切換 App）：之後游標前是什麼就不知道了。
  func breakTail() {
    tail = ""
    tailKnown = false
  }

  /// 這個鍵交給 App（空白另外算）。
  func keyPassedOn() {
    guard on else { return }
    breakTail()
  }

  /// 0027 的 sendSpaceContext() 寫完 penglai_space_before／after 之後：read 是前文讀回來的長度（-1 是 nil），
  /// how 是讀後文的路（textAfterCaret(_:_:)：d 直接讀到；z、l、L 照 length()；s 後面沒字；a stringFromRange 給的範圍；
  /// b 找讀得到的最長那段；-：前文沒讀到、沒讀後文）。micros 是 sendSpaceContext() 整段（含讀前後文的 IMK 呼叫）花的時間。
  func noteSpaceContext(read: Int, before: String, after: String, how: String, micros: Int) {
    guard on else { return }
    let first = after.unicodeScalars.first.map { String($0) }
    sentContext = "\(read),\(before.utf16.count),\(after.utf16.count),\(how),\(Self.charClass(before)),\(Self.charClass(first)),\(micros)"
  }

  /// 組字區空著、中文模式按下純空白，交給 librime 之前。
  func spaceWillProcess(app: String, client: IMKTextInput?, foreignWanted: Bool,
                        pendingPunct: (caret: Int, text: String, length: Int)?) {
    guard on, let client, let pid = Self.pid(app) else { return }
    seq += 1
    let event = Event(id: seq, kind: "s", app: app, pid: pid, client: client, keySeq: keySeq, gap: gap)
    event.foreignWanted = foreignWanted
    event.pendingPunct = pendingPunct
    event.expected = tailKnown ? tail : ""
    event.adjacent = tailKnown && !tail.isEmpty
    event.imkPre = PenglaiIMKRead(client)
    event.sent = sentContext ?? "-"
    sentContext = nil
    space = SpaceEvent(event)
    startAX(event, pre: true)
  }

  /// 這個空白鍵處理完：handled 是貂毫收掉了（送出標點、換掉標點、全形空白），不然 App 照常收到空白。
  func spaceDidProcess(handled: Bool) {
    guard on, let current = space else { return }
    space = nil
    let event = current.event
    event.handledAt = event.ms()
    if let replaced = current.replacedWith {
      event.drop = replaced.drop
      event.insert = replaced.insert
      event.outcome = "r"
    } else if !current.commits.isEmpty {
      event.insert = current.commits.joined()
      event.outcome = "c"
    } else if !handled {
      event.insert = " "
      event.outcome = "a"
      appendTail(" ")
    } else {
      event.outcome = "n"
    }
    schedule(event, slots: Self.spaceSchedule)
  }

  /// commit(string:) 送進 App 之後。
  func committed(_ string: String, app: String, client: IMKTextInput?, hadPreedit: Bool) {
    guard on, !string.isEmpty else { return }
    let expected = (tailKnown ? tail : "") + string
    let adjacent = tailKnown && !tail.isEmpty
    appendTail(string)
    space?.commits.append(string)
    guard let client, let pid = Self.pid(app) else { return }
    seq += 1
    let event = Event(id: seq, kind: "c", app: app, pid: pid, client: client, keySeq: keySeq, gap: gap)
    event.expected = Self.suffix(expected, Self.window)
    event.adjacent = adjacent
    event.preedit = hadPreedit
    schedule(event, slots: Self.schedule)
  }

  /// replace(_:with:) 換掉剛補的標點之後。Return 換句號不記：Return 接著交給 App，游標前會變。
  func replaced(length: Int, with string: String, app: String, client: IMKTextInput?) {
    guard on else { return }
    let known = tailKnown && tail.utf16.count >= length
    let kept = known ? String(decoding: Array(tail.utf16.dropLast(length)), as: UTF16.self) : ""
    tail = Self.suffix(kept + string, 16)
    tailKnown = true
    space?.replacedWith = (drop: length, insert: string)
    guard string != "。", string != ".", let client, let pid = Self.pid(app) else { return }
    seq += 1
    let event = Event(id: seq, kind: "r", app: app, pid: pid, client: client, keySeq: keySeq, gap: gap)
    event.expected = kept + string
    event.adjacent = known && !kept.isEmpty
    schedule(event, slots: Self.schedule)
  }

  private func appendTail(_ string: String) {
    tail = Self.suffix((tailKnown ? tail : "") + string, 16)
    tailKnown = true
  }

  // MARK: 讀取排程

  private static func pid(_ bundle: String) -> pid_t? {
    if let front = NSWorkspace.shared.frontmostApplication, front.bundleIdentifier == bundle {
      return front.processIdentifier
    }
    return NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first?.processIdentifier
  }

  /// 下一個鍵按了（就算還沒送到貂毫：視窗伺服器的計數先變）、點了滑鼠、輸入框換了：之後讀到的不算這個事件。
  private func superseded(_ event: Event) -> Bool {
    if event.supersededAt >= 0 { return true }
    if keySeq != event.keySeq || Self.inputCount() != event.keys || event.client == nil {
      event.supersededAt = event.ms()
      return true
    }
    return false
  }

  private func schedule(_ event: Event, slots: [Int]) {
    event.pendingSlots = slots.count
    for ms in slots {
      DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(ms)) { [weak self] in
        self?.sample(event)
      }
    }
  }

  private func sample(_ event: Event) {
    event.pendingSlots -= 1
    defer { finishIfDone(event) }
    guard on, !event.finished, !superseded(event), let client = event.client else { return }
    if event.kind == "s" {
      event.imk.append((event.ms(), PenglaiIMKRead(client)))
      startAX(event, pre: false)
      return
    }
    if !event.imkDone {
      let read = PenglaiIMKRead(client)
      event.imk.append((event.ms(), read))
      event.imkDone = Self.ends(read.before, event.expected)
    }
    if !event.axDone {
      startAX(event, pre: false)
    }
  }

  private func startAX(_ event: Event, pre: Bool) {
    if axBusy {
      event.axSkipped += 1
      return
    }
    axBusy = true
    event.axInFlight = true
    let pid = event.pid, bundle = event.app, mode = self.mode
    queue.async { [weak self] in
      guard let self else { return }
      self.prepare(pid: pid, bundle: bundle, mode: mode)
      let read = PenglaiAX.read(pid: pid)
      let done = event.ms()
      // 讀完的當下有沒有新的輸入：用這個判斷讀到的是不是之後的字，不看主執行緒什麼時候執行回呼（11/4 Terra 第 2 輪第 3 條）。
      // 兩個都比（Terra 第 3 輪第 3、4 條）：視窗伺服器的按鍵、滑鼠計數（還沒送到貂毫的鍵、點滑鼠），和貂毫自己處理過的鍵
      // （含自動重複的鍵；鍵要經過貂毫，App 裡的字才會因它改變，所以還沒處理到的鍵改不了這次讀到的字）
      let doneKeys = Self.inputCount()
      self.processedKeys.lock()
      let doneSeq = self.processedKeySeq
      self.processedKeys.unlock()
      self.noteReadable(pid: pid, read)
      DispatchQueue.main.async {
        self.axBusy = false
        event.axInFlight = false
        // 讀完時已經按了下一個鍵（或點了滑鼠）：讀到的可能是之後的字，不算（11/4 Terra 第 1 輪第 6 條）
        if doneKeys != event.keys || doneSeq != event.keySeq {
          event.axLate += 1
        } else if pre {
          event.axPre = read
          event.axPreDone = done
        } else {
          event.ax.append((done, read))
          if event.kind != "s", read.ok, Self.ends(read.before, event.expected) {
            event.axDone = true
          }
        }
        self.finishIfDone(event)
      }
    }
  }

  private func finishIfDone(_ event: Event) {
    guard !event.finished, event.pendingSlots == 0, !event.axInFlight else { return }
    event.finished = true
    write(event)
  }

  // MARK: 背景：打開無障礙樹

  private func prepare(pid: pid_t, bundle: String, mode: String) {
    guard apps[pid] == nil else { return }
    // 還沒有「輔助使用」權限時設不了屬性：先不記這個 App，等使用者打開權限之後的下一個事件再設
    guard AXIsProcessTrusted() else {
      if !loggedUntrusted {
        loggedUntrusted = true
        log.notice("axdiag untrusted app=\(bundle, privacy: .public)：還沒有輔助使用權限，打開之後下一個事件再設屬性")
      }
      return
    }
    var state = AppAX()
    state.bundle = bundle
    if let app = NSRunningApplication(processIdentifier: pid) {
      state.engine = PenglaiAX.engine(app)
    }
    let manual = PenglaiAX.flag(pid: pid, "AXManualAccessibility")
    let enhanced = PenglaiAX.flag(pid: pid, "AXEnhancedUserInterface")
    var attribute = ""
    switch mode {
    case "manual": attribute = "AXManualAccessibility"
    case "enhanced": attribute = "AXEnhancedUserInterface"
    case "none": attribute = ""
    default: attribute = state.engine == "electron" ? "AXManualAccessibility" : state.engine == "chrome" ? "AXEnhancedUserInterface" : ""
    }
    // 原本已經開著（讀得到、是 1：別的輔助工具開的）就不碰，拿掉旗標時也不關；讀不到原本的值也不設：不知道原狀，就保證不了
    // 設得回去（11/4 Terra 第 1 輪第 2 條、第 2 輪第 2 條）。已知限制：Electron 的 AXManualAccessibility 讀回來一律是 0
    // （getter 比的是 == kAXModeComplete，實際模式多了 kScreenReader），別的輔助工具在 Electron 上開著時分不出來，拿掉旗標會把它關掉；
    // 11/4 實測一個 Electron App 兩個原本都是 0（AXEnhancedUserInterface 讀得到真值）。
    let original = attribute == "AXManualAccessibility" ? manual : attribute == "AXEnhancedUserInterface" ? enhanced : nil
    let already = original == true
    let unknown = !attribute.isEmpty && original == nil
    var result: Int32 = 0
    var after = "-"
    if !attribute.isEmpty && !already && !unknown {
      result = PenglaiAX.setFlag(pid: pid, attribute, true)
      // 原值確定是 0、送出了設定：不管回傳值、讀回什麼，一律記著拿掉旗標時設回 0（AXEnhancedUserInterface 設定時一律回 -25208、
      // 其實有效；逾時也可能已經生效）。對原本就是 0 的設回 0 沒有副作用（11/4 Terra 第 2 輪第 1 條）
      state.setAttribute = attribute
      state.setAt = DispatchTime.now().uptimeNanoseconds
      if attribute == "AXEnhancedUserInterface" {
        after = Self.flagText(PenglaiAX.flag(pid: pid, attribute))
      }
    }
    apps[pid] = state
    log.notice("axdiag app=\(bundle, privacy: .public) trusted=\(AXIsProcessTrusted() ? 1 : 0, privacy: .public) pid=\(pid, privacy: .public) engine=\(state.engine.isEmpty ? "-" : state.engine, privacy: .public) manual0=\(Self.flagText(manual), privacy: .public) enhanced0=\(Self.flagText(enhanced), privacy: .public) set=\(attribute.isEmpty ? "-" : attribute, privacy: .public) already=\(already ? 1 : 0, privacy: .public) unknown=\(unknown ? 1 : 0, privacy: .public) err=\(result, privacy: .public) enhanced1=\(after, privacy: .public) recorded=\(state.setAttribute.isEmpty ? 0 : 1, privacy: .public)")
  }

  private func noteReadable(pid: pid_t, _ read: PenglaiAXRead) {
    guard var state = apps[pid], !state.readyLogged else { return }
    if read.ok {
      state.readyLogged = true
      let ms = state.setAt == 0 ? -1 : Int((DispatchTime.now().uptimeNanoseconds - state.setAt) / 1_000_000)
      log.notice("axdiag ready app=\(state.bundle, privacy: .public) set=\(state.setAttribute.isEmpty ? "-" : state.setAttribute, privacy: .public) after_set_ms=\(ms, privacy: .public) failures_before=\(state.failures, privacy: .public) method=\(read.method, privacy: .public) role=\(read.role, privacy: .public)")
    } else {
      state.failures += 1
    }
    apps[pid] = state
  }

  /// 拿掉旗標時把設過的屬性設回 0，確認關掉了才算：AXEnhancedUserInterface 讀回 0、AXManualAccessibility 回傳成功（Electron 讀回來
  /// 一律是 0，只能看回傳值），程序已經結束也算。失敗、逾時（App 忙超過 0.25 秒）隔 0.5 秒再試，最多 3 次；還不成記 reset_failed，
  /// 要人手動處理（重開那個 App 也會清掉）（11/4 Terra 第 3 輪第 2 條）。
  private func resetAttributes() {
    for (pid, state) in apps where !state.setAttribute.isEmpty {
      var done = false
      for attempt in 1...3 {
        if NSRunningApplication(processIdentifier: pid) == nil {
          log.notice("axdiag reset app=\(state.bundle, privacy: .public) attr=\(state.setAttribute, privacy: .public) gone=1")
          done = true
          break
        }
        let result = PenglaiAX.setFlag(pid: pid, state.setAttribute, false)
        let now = state.setAttribute == "AXEnhancedUserInterface" ? PenglaiAX.flag(pid: pid, state.setAttribute) : nil
        done = state.setAttribute == "AXEnhancedUserInterface" ? now == false : result == 0
        log.notice("axdiag reset app=\(state.bundle, privacy: .public) attr=\(state.setAttribute, privacy: .public) attempt=\(attempt, privacy: .public) err=\(result, privacy: .public) now=\(Self.flagText(now), privacy: .public) ok=\(done ? 1 : 0, privacy: .public)")
        if done { break }
        Thread.sleep(forTimeInterval: 0.5)
      }
      if !done {
        log.notice("axdiag reset_failed app=\(state.bundle, privacy: .public) pid=\(pid, privacy: .public) attr=\(state.setAttribute, privacy: .public)")
      }
    }
    apps = [:]
  }

  // MARK: 記錄（只有長度、位置、對不對、耗時）

  private func write(_ event: Event) {
    let base = "ev=\(event.id) k=\(event.kind) app=\(event.app) gap=\(event.gap) adj=\(event.adjacent ? 1 : 0) sup=\(event.supersededAt) axskip=\(event.axSkipped) axlate=\(event.axLate)"
    let ax = event.ax.last?.read ?? event.axPre ?? PenglaiAXRead()
    let axInfo = "axm=\(ax.method) role=\(ax.role.isEmpty ? "-" : ax.role) axerr=\(ax.error) axtotal=\(ax.total)"
    let body = event.kind == "s" ? spaceLine(event) : commitLine(event)
    log.notice("axdiag \(base, privacy: .public) \(body, privacy: .public) \(axInfo, privacy: .public)")
  }

  private func commitLine(_ event: Event) -> String {
    let imkOK = event.imk.first { Self.ends($0.read.before, event.expected) }
    let axOK = event.ax.first { $0.read.ok && Self.ends($0.read.before, event.expected) }
    let imk0 = event.imk.first.map { Self.ends($0.read.before, event.expected) ? "1" : "0" } ?? "-"
    let ax0 = event.ax.first.map { $0.read.ok ? (Self.ends($0.read.before, event.expected) ? "1" : "0") : "x" } ?? "-"
    // 第一輪兩邊都讀到時，讀到的游標前一不一致
    var agree = "-"
    if let i = event.imk.first?.read.before, let a = event.ax.first?.read, a.ok {
      agree = Self.same(i, a.before) ? "1" : "0"
    }
    return "pre=\(event.preedit ? 1 : 0) x=\(event.expected.utf16.count) imk0=\(imk0) ax0=\(ax0) imkok=\(imkOK?.ms ?? -1) axok=\(axOK?.ms ?? -1) agree0=\(agree)"
      + " imk=[\(Self.list(event.imk.map { ($0.ms, $0.read.micros, $0.read.caret, Self.ends($0.read.before, event.expected)) }))]"
      + " ax=[\(Self.list(event.ax.map { ($0.ms, $0.read.micros, $0.read.caret, $0.read.ok && Self.ends($0.read.before, event.expected)) }))]"
  }

  private func spaceLine(_ event: Event) -> String {
    // 處理完之後，游標前應該是「按空白時的游標前，去掉 drop 個字、接上 insert」：前面不到 window 個字時是整段，不然比最後 window 個
    func matchesAfter(_ before: String, _ truth: String) -> Bool {
      let units = Array(before.utf16)
      guard units.count >= event.drop else { return false }
      let kept = String(decoding: units.dropLast(event.drop), as: UTF16.self)
      if kept.utf16.count < Self.window {
        return truth.utf16.elementsEqual((kept + event.insert).utf16)
      }
      return Self.ends(truth, Self.suffix(kept, Self.window) + event.insert)
    }
    // 真實內容：越晚的那輪越好，IMK、AX 在 60 毫秒內讀到一樣的字（兩邊都追上了）
    var truth: String?
    var truthAt = -1
    search: for imk in event.imk.reversed() {
      guard let i = imk.read.before else { continue }
      for ax in event.ax.reversed() where ax.read.ok && abs(ax.ms - imk.ms) <= 60 && Self.same(i, ax.read.before) {
        truth = ax.read.before.utf16.count >= i.utf16.count ? ax.read.before : i
        truthAt = max(imk.ms, ax.ms)
        break search
      }
    }
    let imkPre = event.imkPre.before
    let axPre = event.axPre.flatMap { $0.ok ? $0.before : nil }
    // 1：按下去那一刻讀到的是對的；L：AX 讀到的已經是處理完的樣子（也是真的，只是晚了）；0：錯；x：讀不到；?：沒有真實內容可比
    func right(_ pre: String?, late: Bool) -> String {
      guard let truth else { return "?" }
      guard let pre else { return "x" }
      if matchesAfter(pre, truth) { return "1" }
      if late, !event.insert.isEmpty || event.drop > 0, Self.same(pre, truth) { return "L" }
      return "0"
    }
    var imkCheck = "-", axCheck = "-"
    if let punct = event.pendingPunct {
      imkCheck = event.imkPre.caret == punct.caret && event.imkPre.selection == 0 && Self.ends(imkPre, punct.text) ? "1" : "0"
      axCheck = axPre == nil ? "x" : Self.ends(axPre, punct.text) ? "1" : "0"
    }
    let imkAdj = event.adjacent ? (Self.ends(imkPre, event.expected) ? "1" : "0") : "-"
    let axAdj = event.adjacent ? (axPre == nil ? "x" : Self.ends(axPre, event.expected) ? "1" : "0") : "-"
    var agree = "-"
    if let imkPre, let axPre { agree = Self.same(imkPre, axPre) ? "1" : "0" }
    let axRead = event.axPre ?? PenglaiAXRead()
    return "sent=\(event.sent) cls=\(Self.charClass(imkPre))/\(Self.charClass(axPre)) fw=\(event.foreignWanted ? 1 : 0) pend=\(event.pendingPunct == nil ? 0 : 1) out=\(event.outcome) ins=\(event.insert.utf16.count) drop=\(event.drop) handled_ms=\(event.handledAt)"
      + " imkpre=\(imkPre?.utf16.count ?? -1),\(event.imkPre.caret),\(event.imkPre.micros)"
      + " axpre=\(axPre?.utf16.count ?? -1),\(axRead.caret),\(axRead.micros),\(event.axPreDone),\(axRead.method)"
      + " agree=\(agree) imkchk=\(imkCheck) axchk=\(axCheck) imkadj=\(imkAdj) axadj=\(axAdj)"
      + " truth=\(truth == nil ? -1 : truthAt) imkright=\(right(imkPre, late: false)) axright=\(right(axPre, late: true))"
      + " imk=[\(Self.list(event.imk.map { ($0.ms, $0.read.micros, $0.read.caret, truth != nil && $0.read.before.map { Self.same($0, truth!) } == true) }))]"
      + " ax=[\(Self.list(event.ax.map { ($0.ms, $0.read.micros, $0.read.caret, $0.read.ok && truth != nil && Self.same($0.read.before, truth!)) }))]"
  }

  // MARK: 小工具

  /// 「時間:微秒:游標:對不對」一筆一個，逗號分開。
  private static func list(_ items: [(Int, Int, Int, Bool)]) -> String {
    items.map { "\($0.0):\($0.1):\($0.2):\($0.3 ? 1 : 0)" }.joined(separator: ",")
  }

  /// 游標前一個字的類別（不記字）：H 漢字、L 英文字母、D 數字、F 全形字母數字、S 空白、N 換行、P 標點符號、O 其他、- 沒有。
  static func charClass(_ text: String?) -> String {
    guard let scalar = text?.unicodeScalars.last else { return "-" }
    let v = scalar.value
    switch v {
    case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF, 0x20000...0x3134F: return "H"
    case 0x41...0x5A, 0x61...0x7A: return "L"
    case 0x30...0x39: return "D"
    case 0xFF10...0xFF19, 0xFF21...0xFF3A, 0xFF41...0xFF5A: return "F"
    case 0x0A, 0x0D, 0x2028, 0x2029: return "N"
    default:
      if CharacterSet.whitespaces.contains(scalar) { return "S" }
      if CharacterSet.punctuationCharacters.contains(scalar) || CharacterSet.symbols.contains(scalar) { return "P" }
      return "O"
    }
  }

  static func flagText(_ value: Bool?) -> String { value.map { $0 ? "1" : "0" } ?? "-" }

  static func suffix(_ text: String, _ count: Int) -> String {
    let units = text.utf16
    guard units.count > count else { return text }
    return String(decoding: Array(units.suffix(count)), as: UTF16.self)
  }

  /// before 以 expected 結尾（expected 空的不算對：沒東西可比）。
  static func ends(_ before: String?, _ expected: String) -> Bool {
    guard let before, !expected.isEmpty else { return false }
    return before.utf16.count >= expected.utf16.count && before.utf16.suffix(expected.utf16.count).elementsEqual(expected.utf16)
  }

  /// 兩份游標前的字一致：最後 window 個相同；有一份不到 window 個（游標前本來就沒那麼多字，兩邊都讀得到全部）就要整段相同。
  /// 只比較短那份的長度太鬆：IMK 讀到「a」、AX 讀到「ba」會算一致（11/4 Terra 第 1 輪第 5 條）。
  static func same(_ a: String, _ b: String) -> Bool {
    let ua = a.utf16, ub = b.utf16
    if ua.count < window || ub.count < window {
      return ua.count == ub.count && ua.elementsEqual(ub)
    }
    return ua.suffix(window).elementsEqual(ub.suffix(window))
  }

  static func inputCount() -> UInt32 {
    [CGEventType.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown].reduce(0) {
      $0 &+ CGEventSource.counterForEventType(.combinedSessionState, eventType: $1)
    }
  }

  static func mouseCount() -> UInt32 {
    [CGEventType.leftMouseDown, .rightMouseDown, .otherMouseDown].reduce(0) {
      $0 &+ CGEventSource.counterForEventType(.combinedSessionState, eventType: $1)
    }
  }
}
