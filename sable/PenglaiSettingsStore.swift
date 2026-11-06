//
//  PenglaiSettingsStore.swift
//  Squirrel
//
//  蓬萊設定視窗的檔案層：直接改使用者的 *.custom.yaml，讓設定視窗和手寫的檔案永遠是同一份。
//  只認 `patch:` 底下一層的扁平 key 路徑（`style/font_point: 16`、`"menu/page_size": 9`、`speller/algebra:` 加一段清單），
//  改值只換那一行的值，改清單只換那一段，其他行（註解、空行、順序、引號）一個字元都不動。認不得的寫法回報 unsupported，不硬改。
//  每次寫檔前把原檔存進 settings_history.bak/，並記下改了哪一段，用來復原。
//  這個檔只用 Foundation，不碰 librime，tools/settings_test.sh 會單獨編譯它來測。
//

import Foundation

/// 寫進 yaml 的值。
enum PenglaiValue: Equatable {
  case int(Int)
  case double(Double)
  case bool(Bool)
  case string(String)

  var yaml: String {
    switch self {
    case .int(let value): return String(value)
    case .double(let value):
      return value == value.rounded() && abs(value) < 1e9 ? String(Int(value)) : String(value)
    case .bool(let value): return value ? "true" : "false"
    case .string(let value):
      return PenglaiCustomYAML.isPlainSafe(value) ? value : PenglaiCustomYAML.doubleQuoted(value)
    }
  }
}

/// 一份 *.custom.yaml 的文字，只動 `patch:` 底下某一項。
struct PenglaiCustomYAML {
  enum Location: Equatable {
    case line(Int)           // 單一值那一行
    case absent              // 檔案裡沒有這一項
    case unsupported(String) // 寫法認不得，原因
  }

  enum Region: Equatable {
    case range(ClosedRange<Int>) // 這一項佔的行：單一值就一行，清單或表格連同底下的內容
    case absent
    case unsupported(String)
  }

  enum EditError: Error, Equatable {
    case unsupported(String)
  }

  /// 清單裡的一項。
  struct ListItem: Equatable {
    var index: Int
    var value: String?   // 單一值的項目（去掉引號）；{…} 或多行的項目是 nil
    var raw: String      // `- ` 後面原本的文字
  }

  private(set) var lines: [String]
  private var trailingNewline: Bool
  private var fileProblem: String?

  init(text: String) {
    if text.unicodeScalars.contains("\r") {
      fileProblem = "檔案用了 Windows 換行（CRLF）"
    }
    var parts = text.components(separatedBy: "\n")
    trailingNewline = text.hasSuffix("\n")
    if trailingNewline || text.isEmpty { parts.removeLast() }
    lines = parts
  }

  var text: String {
    if lines.isEmpty { return "" }
    return lines.joined(separator: "\n") + (trailingNewline ? "\n" : "")
  }

  // MARK: 找

  /// patch 底下第一層的每一項（key, 起始行）。給「沒人讀的設定」用。
  func patchEntries() -> [(key: String, line: Int, isBlock: Bool)] {
    guard fileProblem == nil, let block = patchBlock() else { return [] }
    return block.children.compactMap { index in
      guard let entry = Self.parseEntry(lines[index], indent: block.indent) else { return nil }
      return (entry.key, index, entry.scalar == nil)
    }
  }

  func region(_ key: String) -> Region {
    if let problem = fileProblem { return .unsupported(problem) }
    guard let block = patchBlock() else {
      if let flow = flowPatchLine() {
        let rest = Self.rootValue(lines[flow], key: "patch") ?? ""
        if rest.hasPrefix("{}") { return .absent }
        return .unsupported("第 \(flow + 1) 行的 patch 寫成一行（{…}）")
      }
      return .absent
    }
    var found: Int?
    for index in block.children {
      guard let entry = Self.parseEntry(lines[index], indent: block.indent) else { continue }
      let bare = Self.stripOperator(entry.key)
      if bare == key {
        if entry.key != key { return .unsupported("第 \(index + 1) 行用了 \(entry.key) 的合併寫法") }
        if entry.flow { return .unsupported("第 \(index + 1) 行的值寫成一行的 {…} 或 […]") }
        if found != nil { return .unsupported("檔案裡有兩行 \(key)") }
        found = index
      } else if key.hasPrefix(bare + "/") {
        // 清單往後接（"switches/+": 底下幾個 - 項目）不動原本那幾項：寫明第幾項的鍵（switches/@3/reset）照樣能改
        if entry.key.hasSuffix("/+"), Self.isIndexPath(key.dropFirst(bare.count + 1)), appendsList(at: index, indent: block.indent) { continue }
        return .unsupported("第 \(index + 1) 行用 \(entry.key) 整段設定")
      }
    }
    guard let start = found else { return .absent }
    let entry = Self.parseEntry(lines[start], indent: block.indent)!
    if entry.scalar != nil { return .range(start...start) }
    // 底下一段：縮排比這一項深的行，或同縮排的 `- ` 清單項目；尾端的空行、註解不算
    var end = start
    var index = start + 1
    while index < lines.count {
      let line = lines[index]
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      if trimmed.isEmpty || trimmed.hasPrefix("#") {
        index += 1
        continue
      }
      let indent = Self.indentation(line)
      if indent > block.indent || (indent == block.indent && trimmed.hasPrefix("- ")) {
        end = index
        index += 1
        continue
      }
      break
    }
    return .range(start...end)
  }

  func locate(_ key: String) -> Location {
    switch region(key) {
    case .unsupported(let reason): return .unsupported(reason)
    case .absent: return .absent
    case .range(let range):
      let block = patchBlock()!
      guard range.count == 1, Self.parseEntry(lines[range.lowerBound], indent: block.indent)?.scalar != nil else {
        return .unsupported("第 \(range.lowerBound + 1) 行的值不是單一個值")
      }
      return .line(range.lowerBound)
    }
  }

  /// 檔案裡寫的值（去掉引號）；沒有或認不得時是 nil。
  func value(_ key: String) -> String? {
    guard case .line(let index) = locate(key), let block = patchBlock(),
          let entry = Self.parseEntry(lines[index], indent: block.indent) else { return nil }
    return entry.scalar?.text
  }

  func regionText(_ key: String) -> String? {
    guard case .range(let range) = region(key) else { return nil }
    return lines[range].joined(separator: "\n")
  }

  /// 清單的每一項（只認 `- 值` 一行一項；註解行略過）。
  func listItems(_ key: String) -> [ListItem]? {
    guard case .range(let range) = region(key), range.count > 1 else { return nil }
    var items: [ListItem] = []
    for index in range.dropFirst() {
      let line = lines[index]
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      guard trimmed.hasPrefix("- ") else { continue }
      let raw = String(trimmed.dropFirst(2))
      let scalar = Self.parseScalar(Array(raw), at: 0)
      items.append(ListItem(index: index, value: scalar?.text, raw: raw))
    }
    return items
  }

  // MARK: 改

  /// 設定一項：有那一行就換值，沒有就加在 patch 最後；沒有 patch 就在檔尾加。回傳改了哪一行（索引）。
  @discardableResult
  mutating func set(_ key: String, _ value: PenglaiValue) throws -> Int {
    switch locate(key) {
    case .unsupported(let reason):
      throw EditError.unsupported(reason)
    case .line(let index):
      let block = patchBlock()!
      let scalar = Self.parseEntry(lines[index], indent: block.indent)!.scalar!
      var newValue = value.yaml
      if case .string(let str) = value, scalar.quote == "'" {
        newValue = "'" + str.replacingOccurrences(of: "'", with: "''") + "'"
      } else if case .string(let str) = value, scalar.quote == "\"" {
        newValue = Self.doubleQuoted(str)
      }
      let line = Array(lines[index])
      lines[index] = String(line[..<scalar.start]) + newValue + String(line[scalar.end...])
      return index
    case .absent:
      return appendEntry([Self.keyToken(key) + ": " + value.yaml])
    }
  }

  /// 換掉一整段（清單、表格）。body 是不含縮排的內容行；沒有這一項時加在 patch 最後。
  @discardableResult
  mutating func setBlock(_ key: String, body: [String]) throws -> ClosedRange<Int> {
    switch region(key) {
    case .unsupported(let reason):
      throw EditError.unsupported(reason)
    case .range(let range):
      let block = patchBlock()!
      if range.count == 1, Self.parseEntry(lines[range.lowerBound], indent: block.indent)?.scalar != nil {
        throw EditError.unsupported("第 \(range.lowerBound + 1) 行的值是單一個值，不是清單")
      }
      let itemIndent = range.dropFirst().first { !lines[$0].trimmingCharacters(in: .whitespaces).isEmpty }
        .map { Self.indentation(lines[$0]) } ?? block.indent + 2
      let pad = String(repeating: " ", count: itemIndent)
      let newBody = body.map { pad + $0 }
      lines.replaceSubrange((range.lowerBound + 1)...range.upperBound, with: newBody)
      return range.lowerBound...(range.lowerBound + newBody.count)
    case .absent:
      let start = appendEntry([Self.keyToken(key) + ":"] + body.map { "  " + $0 })
      return (start - body.count)...start
    }
  }

  /// 在清單裡插入幾行（不含縮排），插在第一個值符合 beforePattern 的項目前面；找不到就插在清單最後。
  mutating func insertListLines(_ key: String, lines newLines: [String], beforePattern: String?) throws {
    guard case .range(let range) = region(key), let items = listItems(key), let first = items.first else {
      throw EditError.unsupported("\(key) 不是寫在這個檔裡的清單")
    }
    let pad = String(repeating: " ", count: Self.indentation(lines[first.index]))
    var at = range.upperBound + 1
    if let pattern = beforePattern,
       let anchor = items.first(where: { ($0.value ?? $0.raw).range(of: pattern, options: .regularExpression) != nil }) {
      at = anchor.index
    }
    lines.insert(contentsOf: newLines.map { pad + $0 }, at: at)
  }

  mutating func removeLines(_ indices: [Int]) {
    for index in indices.sorted(by: >) { lines.remove(at: index) }
  }

  /// 刪掉一項（改回預設）。回傳刪掉的那一段；本來就沒有時回傳 nil。
  @discardableResult
  mutating func remove(_ key: String) throws -> String? {
    switch region(key) {
    case .unsupported(let reason):
      throw EditError.unsupported(reason)
    case .absent:
      return nil
    case .range(let range):
      let removed = lines[range].joined(separator: "\n")
      lines.removeSubrange(range)
      // patch 底下一項都不剩時寫成 `patch: {}`，不留下沒有值的 patch:
      if let block = patchBlock(), block.children.isEmpty {
        let header = lines[block.header]
        if let colon = header.firstIndex(of: ":") {
          lines[block.header] = String(header[...colon]) + " {}" + Self.trailingComment(of: String(header[header.index(after: colon)...]))
        }
      }
      return removed
    }
  }

  /// 把某一項換回原本的文字（復原用，text 可以是多行）。這一項找不到時插在 hint 的位置。
  mutating func restore(_ key: String, text: String?, hintIndex: Int?) throws {
    let newLines = text.map { $0.components(separatedBy: "\n") }
    switch region(key) {
    case .unsupported(let reason):
      throw EditError.unsupported(reason)
    case .range(let range):
      if let newLines {
        lines.replaceSubrange(range, with: newLines)
      } else {
        try remove(key)
      }
    case .absent:
      guard let newLines else { return }
      reopenEmptyPatch()
      if let block = patchBlock() {
        let lower = block.header + 1
        let upper = (block.lastContent ?? block.header) + 1
        let at = min(max(hintIndex ?? upper, lower), upper)
        lines.insert(contentsOf: newLines, at: at)
      } else {
        trailingNewline = true
        lines.append("patch:")
        lines.append(contentsOf: newLines)
      }
    }
  }

  // MARK: 內部

  private struct Block {
    var header: Int        // `patch:` 那一行
    var indent: Int        // 子項的縮排
    var children: [Int]    // 縮排等於 indent 的非註解、非清單項目行
    var lastContent: Int?  // patch 底下最後一個有縮排、非空白的行
  }

  private struct Scalar {
    var text: String
    var start: Int   // 值在那一行的起訖（字元位置）
    var end: Int
    var quote: Character?
  }

  private struct Entry {
    var key: String
    var scalar: Scalar?
    var flow = false   // 值是 {…}、[…] 這類一行寫完的結構
  }

  /// 在 patch 最後加幾行（第一行是 key，已經不含縮排的部分由呼叫端排好）。回傳最後一行的索引。
  private mutating func appendEntry(_ entryLines: [String]) -> Int {
    reopenEmptyPatch()
    if let block = patchBlock() {
      let pad = String(repeating: " ", count: block.indent)
      let at = (block.lastContent ?? block.header) + 1
      lines.insert(contentsOf: entryLines.map { pad + $0 }, at: at)
      return at + entryLines.count - 1
    }
    trailingNewline = true
    lines.append("patch:")
    lines.append(contentsOf: entryLines.map { "  " + $0 })
    return lines.count - 1
  }

  private func patchHeader() -> Int? {
    lines.firstIndex { line in
      guard let rest = Self.rootValue(line, key: "patch") else { return false }
      return rest.isEmpty
    }
  }

  private func flowPatchLine() -> Int? {
    lines.firstIndex { line in
      guard let rest = Self.rootValue(line, key: "patch") else { return false }
      return !rest.isEmpty
    }
  }

  private func patchBlock() -> Block? {
    guard let header = patchHeader() else { return nil }
    var end = lines.count
    for index in (header + 1)..<lines.count {
      let line = lines[index]
      if let first = line.first, first != " ", first != "#" {
        end = index
        break
      }
    }
    let body = Array((header + 1)..<end)
    let content = body.filter { index in
      let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
      return !trimmed.isEmpty && !trimmed.hasPrefix("#") && lines[index].first == " "
    }
    let indent = content.first.map { Self.indentation(lines[$0]) } ?? 2
    let children = content.filter {
      Self.indentation(lines[$0]) == indent && !lines[$0].trimmingCharacters(in: .whitespaces).hasPrefix("- ")
    }
    let lastContent = body.last { index in
      let line = lines[index]
      return line.first == " " && !line.trimmingCharacters(in: .whitespaces).isEmpty
    }
    return Block(header: header, indent: indent, children: children, lastContent: lastContent)
  }

  /// `patch: {}` 要加東西時先改回 `patch:`。
  private mutating func reopenEmptyPatch() {
    guard patchHeader() == nil, let flow = flowPatchLine() else { return }
    let header = lines[flow]
    guard let colon = header.firstIndex(of: ":") else { return }
    let rest = String(header[header.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
    if rest.hasPrefix("{}") {
      lines[flow] = String(header[...colon]) + Self.trailingComment(of: " " + String(rest.dropFirst(2)))
    }
  }

  /// 根層 `key:` 那一行冒號後面的內容（去掉註解、空白）；不是這個 key 時 nil。
  private static func rootValue(_ line: String, key: String) -> String? {
    for token in [key, "\"\(key)\"", "'\(key)'"] where line.hasPrefix(token + ":") {
      let rest = line.dropFirst(token.count + 1)
      if let first = rest.first, first != " ", first != "\t", first != "#" { return nil }
      return stripComment(String(rest)).trimmingCharacters(in: .whitespaces)
    }
    return nil
  }

  private static func stripComment(_ text: String) -> String {
    if text.hasPrefix("#") { return "" }
    if let range = text.range(of: " #") { return String(text[..<range.lowerBound]) }
    return text
  }

  private static func trailingComment(of rest: String) -> String {
    if let range = rest.range(of: " #") { return String(rest[range.lowerBound...]) }
    return ""
  }

  private static func indentation(_ line: String) -> Int {
    line.prefix { $0 == " " }.count
  }

  /// 從 pos 開始讀一個單一值（引號或不加引號），後面只能接空白或註解。不是單一值時 nil。
  private static func parseScalar(_ chars: [Character], at start: Int) -> Scalar? {
    var pos = start
    while pos < chars.count, chars[pos] == " " { pos += 1 }
    guard pos < chars.count, chars[pos] != "#" else { return nil }
    let first = chars[pos]
    if "{[|>&*!".contains(first) { return nil }
    if first == "\"" || first == "'" {
      var end = pos + 1
      var text = ""
      while end < chars.count {
        if chars[end] == first {
          if first == "'", end + 1 < chars.count, chars[end + 1] == "'" {
            text.append("'")
            end += 2
            continue
          }
          break
        }
        if first == "\"", chars[end] == "\\", end + 1 < chars.count {
          end += 1
        }
        text.append(chars[end])
        end += 1
      }
      guard end < chars.count else { return nil }
      let rest = String(chars[(end + 1)...]).trimmingCharacters(in: .whitespaces)
      guard rest.isEmpty || rest.hasPrefix("#") else { return nil }
      return Scalar(text: text, start: pos, end: end + 1, quote: first)
    }
    var end = pos
    while end < chars.count {
      if chars[end] == "#", chars[end - 1] == " " { break }
      end += 1
    }
    while end > pos, chars[end - 1] == " " { end -= 1 }
    return Scalar(text: String(chars[pos..<end]), start: pos, end: end, quote: nil)
  }

  /// 解析 `  key: value  # 註解` 這種一行。縮排不對、是註解、清單項目或空行時 nil。
  private static func parseEntry(_ line: String, indent: Int) -> Entry? {
    guard indentation(line) == indent else { return nil }
    let chars = Array(line)
    var pos = indent
    guard pos < chars.count, chars[pos] != "#", chars[pos] != "-" else { return nil }
    var key = ""
    if chars[pos] == "\"" || chars[pos] == "'" {
      let quote = chars[pos]
      pos += 1
      while pos < chars.count, chars[pos] != quote {
        if quote == "\"", chars[pos] == "\\", pos + 1 < chars.count { pos += 1 }
        key.append(chars[pos])
        pos += 1
      }
      guard pos < chars.count else { return nil }
      pos += 1
      guard pos < chars.count, chars[pos] == ":" else { return nil }
    } else {
      while pos < chars.count {
        if chars[pos] == ":" && (pos + 1 == chars.count || chars[pos + 1] == " ") { break }
        key.append(chars[pos])
        pos += 1
      }
      guard pos < chars.count else { return nil }
    }
    pos += 1  // 冒號
    var probe = pos
    while probe < chars.count, chars[probe] == " " { probe += 1 }
    if probe == chars.count || chars[probe] == "#" { return Entry(key: key, scalar: nil) }
    guard let scalar = parseScalar(chars, at: pos) else { return Entry(key: key, scalar: nil, flow: true) }
    return Entry(key: key, scalar: scalar)
  }

  /// `@3`、`@3/reset`：清單的第幾項（寫明數字；@last、@next 這類會跟著往後接的項目變，不算）
  private static func isIndexPath(_ rest: Substring) -> Bool {
    rest.range(of: "^@[0-9]+(/|$)", options: .regularExpression) != nil
  }

  /// 第 index 行那一項的值是清單：同一行的 […]，或底下一段 `- ` 項目
  private func appendsList(at index: Int, indent: Int) -> Bool {
    if lines[index].range(of: #"^\s*("[^"]*"|'[^']*'|[^:"']+):\s*\["#, options: .regularExpression) != nil { return true }
    for line in lines[(index + 1)...] {
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
      return Self.indentation(line) >= indent && trimmed.hasPrefix("- ")
    }
    return false
  }

  private static func stripOperator(_ key: String) -> String {
    for suffix in ["/+", "/="] where key.hasSuffix(suffix) {
      return String(key.dropLast(2))
    }
    return key
  }

  static func keyToken(_ key: String) -> String {
    key.range(of: "^[A-Za-z_][A-Za-z0-9_/]*$", options: .regularExpression) != nil ? key : doubleQuoted(key)
  }

  static func isPlainSafe(_ value: String) -> Bool {
    guard value.range(of: "^[A-Za-z_][A-Za-z0-9_.-]*$", options: .regularExpression) != nil else { return false }
    let reserved = ["true", "false", "yes", "no", "on", "off", "null", "y", "n"]
    return !reserved.contains(value.lowercased())
  }

  static func doubleQuoted(_ value: String) -> String {
    "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
  }
}

/// 設定視窗寫檔、記歷史、復原。檔案都在使用者資料夾（~/Library/Rime）。
final class PenglaiSettingsStore {
  /// 一次改動裡的一項：那一項改之前、改之後佔的文字（可能是多行）。
  struct Edit: Codable, Equatable {
    var file: String       // 檔名，例如 sable.custom.yaml
    var key: String
    var before: String?    // nil：原本沒有
    var after: String?     // nil：刪掉了
    var index: Int?        // 改之前那一項的起始行，復原時插回去用
  }

  struct Entry: Codable, Equatable {
    var id: String         // 時間戳記，也是備份資料夾名
    var time: Date
    var summary: String
    var edits: [Edit]
  }

  /// 一次要寫的一項。
  struct Change {
    enum Action {
      case set(PenglaiValue)
      case remove                                  // 刪掉那一項（改回預設）
      case block([String])                         // 換掉整段清單（內容行，不含縮排）
      case recipe(PenglaiRecipe, enable: Bool, base: [String]? = nil)   // 在清單裡加上或拿掉某個功能的幾行；base 見 PenglaiRecipe.state
    }
    var file: String
    var key: String
    var action: Action
  }

  enum StoreError: Error, Equatable {
    case unsupported(file: String, key: String, reason: String)
    case conflict([String])   // 復原時那一項已經被別人改過
    case io(String)

    var message: String {
      switch self {
      case .unsupported(let file, let key, let reason): return "\(file) 的 \(key) 改不了：\(reason)"
      case .conflict(let items): return "這些地方後來又被改過，沒有復原：" + items.joined(separator: "；")
      case .io(let text): return text
      }
    }
  }

  static let historyDirName = "settings_history.bak"   // 名字帶 .bak：tools/snapshot.sh 不會帶走，rime-backup 也不在白名單
  static let historyLimit = 50

  let userDir: URL
  private(set) var history: [Entry] = []
  private let fileManager = FileManager.default
  var now: () -> Date = Date.init

  init(userDir: URL) {
    self.userDir = userDir
    loadHistory()
  }

  var historyDir: URL { userDir.appendingPathComponent(Self.historyDirName, isDirectory: true) }
  private var logURL: URL { historyDir.appendingPathComponent("log.json") }

  func url(of file: String) -> URL { userDir.appendingPathComponent(file) }

  func read(_ file: String) -> PenglaiCustomYAML {
    let text = (try? String(contentsOf: url(of: file), encoding: .utf8)) ?? ""
    return PenglaiCustomYAML(text: text)
  }

  /// 文字檔（詞庫：custom_phrase.txt、*.dict.yaml、隱藏清單）的改動記成一項：key 固定是這個，
  /// before、after 是改動的那幾行（每行後面帶 \n，沒有行是空字串），index 是第一行；原本沒有這個檔案時 index 是 nil、復原就刪掉檔案
  static let textKey = "（整行）"

  /// 寫一組改動（同一次點擊可能改兩項，例如文件裡顯示注音／漢字）。沒有實際變化時回傳 nil、不記歷史。
  /// texts：整份換掉的文字檔（檔名 → 新內容），跟 changes 記成同一筆（詞庫第一次加詞：新建詞典檔＋方案 custom 檔指過去）
  @discardableResult
  func apply(_ changes: [Change], texts: [String: String] = [:], summary: String) throws -> Entry? {
    var docs: [String: PenglaiCustomYAML] = [:]
    var originals: [String: String] = [:]
    var edits: [Edit] = []
    for (file, text) in texts.sorted(by: { $0.key < $1.key }) {
      let path = url(of: file)
      let existed = fileManager.fileExists(atPath: path.path)
      let original = existed ? ((try? String(contentsOf: path, encoding: .utf8)) ?? "") : ""
      guard !existed || original != text else { continue }
      if existed {
        let diff = Self.lineDiff(original, text)
        edits.append(Edit(file: file, key: Self.textKey, before: diff.before, after: diff.after, index: diff.index))
      } else {
        edits.append(Edit(file: file, key: Self.textKey, before: nil, after: text, index: nil))
      }
    }
    for change in changes {
      if docs[change.file] == nil {
        let path = url(of: change.file)
        let original = (try? String(contentsOf: path, encoding: .utf8)) ?? ""
        originals[change.file] = original
        docs[change.file] = PenglaiCustomYAML(text: original)
      }
      var doc = docs[change.file]!
      let region = doc.region(change.key)
      if case .unsupported(let reason) = region {
        throw StoreError.unsupported(file: change.file, key: change.key, reason: reason)
      }
      let before = doc.regionText(change.key)
      var index: Int?
      if case .range(let range) = region { index = range.lowerBound }
      do {
        switch change.action {
        case .set(let value):
          try doc.set(change.key, value)
        case .remove:
          try doc.remove(change.key)
        case .block(let body):
          try doc.setBlock(change.key, body: body)
        case .recipe(let recipe, let enable, let base):
          try recipe.apply(to: &doc, key: change.key, enable: enable, base: base)
        }
      } catch PenglaiCustomYAML.EditError.unsupported(let reason) {
        throw StoreError.unsupported(file: change.file, key: change.key, reason: reason)
      }
      let after = doc.regionText(change.key)
      if index == nil, case .range(let range) = doc.region(change.key) { index = range.lowerBound }
      docs[change.file] = doc
      if before != after {
        edits.append(Edit(file: change.file, key: change.key, before: before, after: after, index: index))
      }
    }
    guard !edits.isEmpty else { return nil }
    let date = now()
    let entry = Entry(id: Self.stamp(date), time: date, summary: summary, edits: edits)
    let textFiles = Set(edits.filter { $0.key == Self.textKey }.map(\.file))
    try snapshot(files: Array(docs.keys) + Array(textFiles), into: entry.id)
    for file in textFiles.sorted() {
      try write(texts[file]!, to: file)
    }
    for (file, doc) in docs where doc.text != originals[file] {
      try write(doc.text, to: file)
    }
    history.append(entry)
    pruneHistory()
    try saveHistory()
    return entry
  }

  /// 復原最後一筆。
  @discardableResult
  func undoLast() throws -> Entry? {
    guard let last = history.last else { return nil }
    try revert(last)
    history.removeLast()
    try saveHistory()
    return last
  }

  /// 回到某一筆之前（那一筆和之後的都復原）。
  func undo(through id: String) throws {
    guard let position = history.firstIndex(where: { $0.id == id }) else { return }
    while history.count > position {
      try undoLast()
    }
  }

  private func revert(_ entry: Entry) throws {
    var docs: [String: PenglaiCustomYAML] = [:]
    var texts: [String: String?] = [:]   // 文字檔復原後的內容；nil 是刪掉檔案
    var conflicts: [String] = []
    for edit in entry.edits.reversed() {
      if edit.key == Self.textKey {
        let current: String?
        if let pending = texts[edit.file] { current = pending } else { current = try? String(contentsOf: url(of: edit.file), encoding: .utf8) }
        guard let current, let restored = Self.revertLines(current, edit) else {
          conflicts.append("\(edit.file) 的那幾行")
          continue
        }
        texts.updateValue(restored, forKey: edit.file)   // restored 是 nil 時也要留著這個鍵（刪掉檔案）
        continue
      }
      var doc = docs[edit.file] ?? read(edit.file)
      if case .unsupported(let reason) = doc.region(edit.key) {
        conflicts.append("\(edit.file) \(edit.key)：\(reason)")
        continue
      }
      guard doc.regionText(edit.key) == edit.after else {
        conflicts.append("\(edit.file) 的 \(edit.key)")
        continue
      }
      do {
        try doc.restore(edit.key, text: edit.before, hintIndex: edit.index)
      } catch {
        conflicts.append("\(edit.file) 的 \(edit.key)")
        continue
      }
      docs[edit.file] = doc
    }
    if !conflicts.isEmpty { throw StoreError.conflict(conflicts) }
    try snapshot(files: Array(docs.keys) + Array(texts.keys), into: Self.stamp(now()) + "-undo")
    for (file, text) in texts.sorted(by: { $0.key < $1.key }) {
      if let text {
        try write(text, to: file)
      } else {
        do { try fileManager.removeItem(at: url(of: file)) } catch { throw StoreError.io("刪不掉 \(file)：\(error.localizedDescription)") }
      }
    }
    for (file, doc) in docs {
      try write(doc.text, to: file)
    }
  }

  // MARK: 文字檔的整行改動

  /// 一段行：每行後面帶 \n（最後一行沒有換行的檔案，讀回來照樣對得上）
  static func chunk(_ lines: ArraySlice<String>) -> String { lines.map { $0 + "\n" }.joined() }

  static func chunkLines(_ chunk: String) -> [String] {
    guard !chunk.isEmpty else { return [] }
    var lines = chunk.components(separatedBy: "\n")
    if lines.last == "" { lines.removeLast() }
    return lines
  }

  /// 前後相同的行拿掉，剩中間改過的那段
  static func lineDiff(_ old: String, _ new: String) -> (before: String, after: String, index: Int) {
    let a = old.components(separatedBy: "\n"), b = new.components(separatedBy: "\n")
    var prefix = 0
    while prefix < a.count, prefix < b.count, a[prefix] == b[prefix] { prefix += 1 }
    var suffix = 0
    while suffix < a.count - prefix, suffix < b.count - prefix, a[a.count - 1 - suffix] == b[b.count - 1 - suffix] { suffix += 1 }
    return (chunk(a[prefix..<(a.count - suffix)]), chunk(b[prefix..<(b.count - suffix)]), prefix)
  }

  /// 把 after 那幾行換回 before。原來的位置對不上時（之後在上面加過行）找檔案裡唯一一處相同的；找不到、不只一處就是衝突（nil）。
  /// 回傳 .some(nil) 是要刪掉檔案（這一筆新建了它，內容也沒再改過）
  static func revertLines(_ current: String, _ edit: Edit) -> String?? {
    guard let after = edit.after else { return nil }
    guard let index = edit.index else { return current == after ? .some(nil) : nil }
    var lines = current.components(separatedBy: "\n")
    let target = chunkLines(after), restore = chunkLines(edit.before ?? "")
    func matches(_ at: Int) -> Bool { at >= 0 && at + target.count <= lines.count && Array(lines[at..<(at + target.count)]) == target }
    var at: Int? = matches(index) ? index : nil
    if at == nil, !target.isEmpty {
      let found = (0...max(0, lines.count - target.count)).filter(matches)
      if found.count == 1 { at = found[0] }
    }
    guard let at else { return nil }
    lines.replaceSubrange(at..<(at + target.count), with: restore)
    return .some(lines.joined(separator: "\n"))
  }

  // MARK: 檔案

  /// 這個視窗最近一次部署開始的時間（PenglaiSettingsModel.scheduleDeploy 寫）
  var deployStarted: Date?

  private func write(_ text: String, to file: String) throws {
    waitPastDeployedSecond(file)
    do {
      try Data(text.utf8).write(to: url(of: file), options: .atomic)
    } catch {
      throw StoreError.io("寫不進 \(file)：\(error.localizedDescription)")
    }
  }

  /// librime 記設定檔的修改時間只到秒（build/*.yaml 的 __build_info/timestamps），下次部署看時間一不一樣決定要不要重編。
  /// 這一秒有部署開始過（這個視窗的部署是非同步的，可能已經讀了上一版、還沒寫進 build），或 build 記的就是這一秒
  /// （別的入口剛部署過；檔案被刪掉再建也算）時，現在寫的會跟記下的同一秒、被當成沒變（連點兩下、--script 連續幾步、改完馬上復原）：
  /// 等到下一秒再寫。其他時候不等：整批復原逐筆寫同一個檔，中間沒有部署，不會撞。修改時間不改到未來（會跟手改檔案的編輯器撞同一秒）
  private func waitPastDeployedSecond(_ file: String) {
    let second = Date().timeIntervalSince1970.rounded(.down)
    let deploying = deployStarted.map { $0.timeIntervalSince1970.rounded(.down) == second } ?? false
    guard deploying || recordedSeconds(file).contains(second) else { return }
    let wait = second + 1 - Date().timeIntervalSince1970
    if wait > 0 { Thread.sleep(forTimeInterval: wait + 0.01) }
  }

  /// build/*.yaml 開頭記的這個檔的修改時間，例如 penglai_zhuyin.custom.yaml 記成「penglai_zhuyin.custom: 1793327327」
  private func recordedSeconds(_ file: String) -> Set<Double> {
    let stem = (file as NSString).deletingPathExtension
    let build = userDir.appendingPathComponent("build", isDirectory: true)
    guard let names = try? fileManager.contentsOfDirectory(atPath: build.path) else { return [] }
    var result: Set<Double> = []
    for name in names where name.hasSuffix(".yaml") {
      guard let handle = FileHandle(forReadingAtPath: build.appendingPathComponent(name).path) else { continue }
      let head = String(decoding: handle.readData(ofLength: 4096), as: UTF8.self)
      try? handle.close()
      for line in head.split(separator: "\n") {
        let parts = line.trimmingCharacters(in: .whitespaces).components(separatedBy: ": ")
        if parts.count == 2, parts[0] == stem, let value = Double(parts[1]) { result.insert(value) }
      }
    }
    return result
  }

  /// 寫檔前把原檔複製一份到 settings_history.bak/<id>/（原本沒有的檔案就不複製）。
  private func snapshot(files: [String], into id: String) throws {
    let dir = historyDir.appendingPathComponent(id, isDirectory: true)
    do {
      try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
      for file in files where fileManager.fileExists(atPath: url(of: file).path) {
        let dest = dir.appendingPathComponent(file)
        if fileManager.fileExists(atPath: dest.path) { try fileManager.removeItem(at: dest) }
        try fileManager.copyItem(at: url(of: file), to: dest)
      }
    } catch {
      throw StoreError.io("備份不了：\(error.localizedDescription)")
    }
  }

  private func loadHistory() {
    guard let data = try? Data(contentsOf: logURL) else { return }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    history = (try? decoder.decode([Entry].self, from: data)) ?? []
  }

  private func saveHistory() throws {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    do {
      try fileManager.createDirectory(at: historyDir, withIntermediateDirectories: true)
      try encoder.encode(history).write(to: logURL, options: .atomic)
    } catch {
      throw StoreError.io("歷史紀錄寫不進去：\(error.localizedDescription)")
    }
  }

  private func pruneHistory() {
    guard history.count > Self.historyLimit else { return }
    history.removeFirst(history.count - Self.historyLimit)
    let keep = history.map(\.id)
    if let items = try? fileManager.contentsOfDirectory(atPath: historyDir.path) {
      for item in items where item != "log.json" && !keep.contains(where: { item.hasPrefix($0) }) && item < (keep.first ?? "") {
        try? fileManager.removeItem(at: historyDir.appendingPathComponent(item))
      }
    }
  }

  static func stamp(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
    return formatter.string(from: date)
  }
}

/// 清單類設定的功能開關：某個功能對應清單裡的哪幾行（settings/notes.json 的 recipes）。
struct PenglaiRecipe: Codable, Equatable {
  var id: String
  var title: String
  var desc: String
  var config: String
  var list: String
  var insertBefore: String?
  var comments: [String]
  var items: [String]

  enum CodingKeys: String, CodingKey {
    case id, title, desc, config, list, comments, items
    case insertBefore = "insert_before"
  }

  enum State: Equatable {
    case on, off
    case partial
    case unavailable(String)
  }

  /// base：部署後方案的這個清單。這個檔沒寫這個清單時（方案檔本身就帶著這個功能，例如公開預設的 penglai_zhuyin），
  /// 照 base 判斷；nil 或空的＝方案也沒有這個清單
  func state(in doc: PenglaiCustomYAML, base: [String]? = nil) -> State {
    switch doc.region(list) {
    case .unsupported(let reason): return .unavailable(reason)
    case .absent:
      guard let base, !base.isEmpty else { return .unavailable("\(list) 沒有寫在這個檔裡") }
      return state(of: Set(base))
    case .range: break
    }
    guard let listItems = doc.listItems(list) else { return .unavailable("\(list) 不是清單") }
    return state(of: Set(listItems.compactMap(\.value)))
  }

  private func state(of values: Set<String>) -> State {
    let present = items.filter { values.contains($0) }.count
    if present == items.count { return .on }
    if present == 0 { return .off }
    return .partial
  }

  func apply(to doc: inout PenglaiCustomYAML, key: String, enable: Bool, base: [String]? = nil) throws {
    switch state(in: doc, base: base) {
    case .unavailable(let reason): throw PenglaiCustomYAML.EditError.unsupported(reason)
    case .partial: throw PenglaiCustomYAML.EditError.unsupported("清單裡只有這個功能的一部分，請打開檔案確認")
    case .on where enable, .off where !enable: return
    default: break
    }
    if case .absent = doc.region(list), let base {
      // 方案檔的清單整段抄進這個檔，再加上或拿掉這幾行：Rime 的 patch 拿不掉清單裡的單獨一項。
      // 之後方案檔再改這個清單會被這一段蓋住（跟手寫 custom 檔整段改清單一樣）；復原上一步會拿掉整段
      var body = base.filter { enable || !items.contains($0) }.map { "- " + PenglaiCustomYAML.doubleQuoted($0) }
      if enable {
        let at = insertBefore.flatMap { pattern in base.firstIndex { $0.range(of: pattern, options: .regularExpression) != nil } } ?? base.count
        body.insert(contentsOf: comments + items.map { "- " + PenglaiCustomYAML.doubleQuoted($0) }, at: at)
      }
      try doc.setBlock(list, body: body)
      return
    }
    if enable {
      let body = comments + items.map { "- " + PenglaiCustomYAML.doubleQuoted($0) }
      try doc.insertListLines(list, lines: body, beforePattern: insertBefore)
      return
    }
    guard let listItems = doc.listItems(list) else { return }
    var remove = listItems.filter { item in item.value.map(items.contains) ?? false }.map(\.index)
    // 緊接在第一項前面、跟這個功能的註解一字不差的那幾行一起拿掉
    if let first = remove.min() {
      var index = first - 1
      for comment in comments.reversed() {
        guard index >= 0, doc.lines[index].trimmingCharacters(in: .whitespaces) == comment else { break }
        remove.append(index)
        index -= 1
      }
    }
    doc.removeLines(remove)
  }
}

/// 讀音（librime patch 0010）：方案 switches 裡的一組三選一，打開哪一個，查詞就用詞典那一欄的比重（同一個字哪個讀音先出）。
/// 畫面上的名稱和說明在 PenglaiCopy；這裡只管選項名稱和寫進方案 custom 檔的位置。
enum PenglaiReading {
  /// 選項名稱（方案檔那一組的順序：reset 的 0、1、2）。蓬萊音、中州音、兼收並蓄
  static let options = ["reading_penglai", "reading_zhongzhou", "reading_jianshou"]
  static let defaultOption = options[0]

  /// 方案 switches 的第幾組是讀音：那一組的 options 有 reading_penglai。參數是每一組的 options（沒有的是空清單）
  static func switchIndex(_ switches: [[String]]) -> Int? {
    switches.firstIndex { $0.contains(defaultOption) }
  }

  /// 存在方案 custom 檔的鍵：那一組的 reset（選項在那一組裡的位置）。每次開 session 都會照它設定，也蓋過 F4 選單記的
  static func resetKey(_ switchIndex: Int) -> String {
    "switches/@\(switchIndex)/reset"
  }
}

/// 第一次使用的引導看過哪幾頁：使用者資料夾的 penglai-onboarding.json，{"pages": {"reading": "2026-10-29T21:05:00+08:00"}}。
/// 一頁一筆（頁的名稱 → 看過的時間），之後加頁時，看過舊頁的人只會看到新加的那頁。
/// 放在使用者資料夾：沙盒有自己的一份、不會動到正式的；資料夾重建（換電腦）時會再出現一次。
struct PenglaiOnboardingRecord: Codable, Equatable {
  static let file = "penglai-onboarding.json"
  var pages: [String: String] = [:]

  static func load(_ userDir: URL) -> PenglaiOnboardingRecord {
    guard let data = try? Data(contentsOf: userDir.appendingPathComponent(file)),
          let record = try? JSONDecoder().decode(PenglaiOnboardingRecord.self, from: data) else { return PenglaiOnboardingRecord() }
    return record
  }

  func seen(_ page: String) -> Bool { pages[page] != nil }

  mutating func mark(_ ids: [String], at date: Date) {
    let formatter = ISO8601DateFormatter()
    formatter.timeZone = .current
    for id in ids where pages[id] == nil { pages[id] = formatter.string(from: date) }
  }

  func save(_ userDir: URL) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(self).write(to: userDir.appendingPathComponent(Self.file), options: .atomic)
  }
}
