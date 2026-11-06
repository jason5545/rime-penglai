//
//  PenglaiDictionary.swift
//  Squirrel
//
//  蓬萊設定視窗的「詞庫」頁：三份使用者資料夾裡的文字檔，在這裡加、改、刪。
//    自訂詞（custom_phrase.txt）：文字＋碼，整段輸入剛好是那個碼時出現（英文縮寫、符號、常用句）。
//    詞典（擴充詞典 *.dict.yaml）：加進詞典的詞，可以跟別的字詞組成整句。方案用的詞典本身沒有匯入別的詞典時，
//      第一次加詞先建一份 penglai_custom.dict.yaml（匯入原本的詞典，檔頭的詞典設定照抄），再把 translator/dictionary 指過去。
//    隱藏的詞（translator/dictionary_exclude_file）：右 Command 隱藏的詞典詞，這裡可以取消隱藏或手動加。
//  只動改的那一行，其他行（註解、分區）照舊；改動記進變更紀錄，可以復原（PenglaiSettingsStore 的 textKey）。
//  改了自訂詞或詞典，使用者資料夾裡有可執行的 penglai_dict_hook 時，部署之前先跑它（引數是改了的檔名）。
//  隱藏清單引擎自己會重讀，不用部署。
//

import AppKit
import SwiftUI

enum PenglaiDictKind: String, CaseIterable, Identifiable {
  case phrase, dict, hidden
  var id: String { rawValue }

  var title: String {
    switch self {
    case .phrase: return "自訂詞"
    case .dict: return "詞典"
    case .hidden: return "隱藏的詞"
    }
  }

  var desc: String {
    switch self {
    case .phrase: return "整段輸入剛好是這個碼時出現，適合英文縮寫、符號、常用句。碼是鍵盤上按的鍵。"
    case .dict: return "加進詞典的詞，可以跟前後的字詞組成整句，適合人名、專有名詞。讀音不填時照每個字的讀音配。"
    case .hidden: return "選字窗開著時按右 Command 隱藏的詞，不會再出現在候選裡。取消隱藏就會回來。"
    }
  }
}

/// 檔案裡的一個詞（一行）。line、raw 是改、刪之前核對用的：檔案在別處被改過，就不動它
struct PenglaiDictEntry: Identifiable, Equatable {
  var line: Int
  var raw: String
  var text: String
  var code: String      // 自訂詞：按鍵；詞典：注音（音節以空白隔開）；隱藏的詞：隱藏的時間
  var weight: String
  var section: String   // 上面最近的一行註解（分區名稱）
  var id: Int { line }
}

/// 一份詞庫檔案讀進來的樣子。text 是整份內容（行照原樣），entries 是裡面的詞
struct PenglaiDictDocument {
  enum EditError: Error, Equatable {
    case invalid(String)
    case changed        // 那一行已經不是讀進來時的樣子

    var message: String {
      switch self {
      case .invalid(let text): return text
      case .changed: return "檔案在別的地方改過，請重新整理再試一次"
      }
    }
  }

  /// 這個視窗加的詞放在這個分區（沒有就加在檔案最後）
  static let addedSection = "設定視窗加的詞"
  /// 新加的詞典詞沒填權重時用這個：權重空著是 0，排不上來（人名、專有名詞這樣就排得到同碼常用詞前面）
  static let defaultWeight = "50000"

  let kind: PenglaiDictKind
  private(set) var lines: [String]
  private(set) var entries: [PenglaiDictEntry] = []
  /// 詞典檔頭的 columns（沒寫時 Rime 照 text、code、weight）；自訂詞固定 text、code、weight
  private(set) var columns = ["text", "code", "weight"]
  private(set) var imports: [String] = []
  /// 詞典檔頭的純量設定（sort、use_preset_vocabulary……）
  private(set) var header: [(key: String, value: String)] = []
  private(set) var hasHeader = false

  init(kind: PenglaiDictKind, text: String) {
    self.kind = kind
    lines = text.isEmpty ? [] : text.components(separatedBy: "\n")
    parse()
  }

  var text: String { lines.joined(separator: "\n") }
  var hasCode: Bool { kind == .phrase || (kind == .dict && columns.contains("code")) }
  var hasWeight: Bool { kind != .hidden && columns.contains("weight") }

  // MARK: 讀

  private mutating func parse() {
    var start = 0
    if kind == .dict {
      // 檔頭：--- 到 ...（前面可以有註解）
      if let open = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" }),
         let close = lines[(open + 1)...].firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "..." }) {
        hasHeader = true
        parseHeader(Array(lines[(open + 1)..<close]))
        start = close + 1
      } else {
        start = lines.count   // 沒有檔頭的不是詞典，不列
      }
    }
    var section = ""
    var comments = true
    var result: [PenglaiDictEntry] = []
    for index in start..<lines.count {
      var line = lines[index]
      if line.hasSuffix("\r") { line.removeLast() }
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      if trimmed.isEmpty { continue }
      if comments, line.hasPrefix("#") {
        if line == "# no comment" { comments = false }
        let name = line.drop(while: { $0 == "#" }).trimmingCharacters(in: CharacterSet(charactersIn: " \t=－-—"))
        if !name.isEmpty { section = name }
        continue
      }
      if kind == .hidden && line.hasPrefix("\t") { continue }
      let fields = line.components(separatedBy: "\t")
      func field(_ name: String) -> String {
        guard let column = columns.firstIndex(of: name), column < fields.count else { return "" }
        return fields[column]
      }
      let text: String, code: String, weight: String
      switch kind {
      case .hidden:
        text = fields[0]
        code = fields.count > 1 ? fields[1] : ""
        weight = ""
      case .phrase, .dict:
        text = field("text")
        code = field("code")
        weight = field("weight")
      }
      guard !text.isEmpty else { continue }
      result.append(PenglaiDictEntry(line: index, raw: lines[index], text: text, code: code, weight: weight, section: section))
    }
    entries = result
  }

  private mutating func parseHeader(_ body: [String]) {
    var list: String?
    var cols: [String] = [], imps: [String] = []
    for raw in body {
      let line = raw.components(separatedBy: " #").first ?? raw
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
      if trimmed.hasPrefix("- "), let name = list {
        let value = Self.unquote(String(trimmed.dropFirst(2)))
        if name == "columns" { cols.append(value) } else if name == "import_tables" { imps.append(value) }
        continue
      }
      guard !line.hasPrefix(" "), let colon = trimmed.firstIndex(of: ":") else { continue }
      let key = String(trimmed[..<colon]).trimmingCharacters(in: .whitespaces)
      let value = String(trimmed[trimmed.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
      list = nil
      if value.isEmpty {
        list = key
      } else if value.hasPrefix("[") && value.hasSuffix("]") {
        let items = value.dropFirst().dropLast().split(separator: ",").map { Self.unquote($0.trimmingCharacters(in: .whitespaces)) }
        if key == "columns" { cols = items } else if key == "import_tables" { imps = items }
      } else {
        header.append((key, value))
      }
    }
    if !cols.isEmpty { columns = cols }
    imports = imps
  }

  private static func unquote(_ value: String) -> String {
    value.count >= 2 && (value.hasPrefix("\"") && value.hasSuffix("\"") || value.hasPrefix("'") && value.hasSuffix("'"))
      ? String(value.dropFirst().dropLast()) : value
  }

  func headerValue(_ key: String) -> String? { header.first { $0.key == key }?.value }

  // MARK: 改

  /// 加一個詞或改一個詞（original 是改之前那一個）。新加的詞跟已經有的同一個（文字一樣、碼也一樣）就改那一行。
  /// 回傳改好的那一行在第幾行
  @discardableResult
  mutating func upsert(original: PenglaiDictEntry?, text: String, code: String, weight: String, note: String = "") throws -> Int {
    var target = original
    if let original {
      guard original.line < lines.count, lines[original.line] == original.raw else { throw EditError.changed }
    } else {
      target = entries.first { $0.text == text && (kind == .hidden || !hasCode || $0.code == code) }
    }
    if let target {
      lines[target.line] = row(text: text, code: code, weight: weight, note: kind == .hidden ? target.code : note, keeping: target.raw)
      parse()
      return target.line
    }
    let line = row(text: text, code: code, weight: weight, note: note, keeping: nil)
    let index: Int
    if kind == .hidden {
      index = append([line])
    } else if let header = lines.firstIndex(where: { $0.hasPrefix("#") && $0.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces) == Self.addedSection }) {
      // 分區最後一個詞後面（下一行註解之前）
      var last = header
      var cursor = header + 1
      while cursor < lines.count, !lines[cursor].hasPrefix("#") {
        if !lines[cursor].trimmingCharacters(in: .whitespaces).isEmpty { last = cursor }
        cursor += 1
      }
      lines.insert(line, at: last + 1)
      index = last + 1
    } else {
      let hasContent = lines.contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
      index = append((hasContent ? [""] : []) + ["# " + Self.addedSection, line]) + (hasContent ? 2 : 1)
    }
    parse()
    return index
  }

  mutating func remove(_ entry: PenglaiDictEntry) throws {
    guard entry.line < lines.count, lines[entry.line] == entry.raw else { throw EditError.changed }
    lines.remove(at: entry.line)
    parse()
  }

  /// 接在檔案最後（最後一行是空的就是檔案以換行結尾，接在它前面）；回傳第一行在第幾行
  private mutating func append(_ newLines: [String]) -> Int {
    if lines.last == "" {
      let at = lines.count - 1
      lines.insert(contentsOf: newLines, at: at)
      return at
    }
    let at = lines.count
    lines.append(contentsOf: newLines + [""])
    return at
  }

  /// 一行的內容：照欄位順序放，原本那一行多出來的欄位（例如讀音的變體權重）照留，後面空的欄位拿掉
  private func row(text: String, code: String, weight: String, note: String, keeping raw: String?) -> String {
    if kind == .hidden { return note.isEmpty ? text : text + "\t" + note }
    var fields = raw?.components(separatedBy: "\t") ?? []
    let order = kind == .phrase ? ["text", "code", "weight"] : columns
    while fields.count < order.count { fields.append("") }
    for (name, value) in [("text", text), ("code", code), ("weight", weight)] {
      if let column = order.firstIndex(of: name) { fields[column] = value }
    }
    while fields.count > 1, fields.last?.isEmpty == true { fields.removeLast() }
    return fields.joined(separator: "\t")
  }

  // MARK: 新建擴充詞典

  /// 匯入 base 的擴充詞典：檔頭的詞典設定照抄 base（use_preset_vocabulary、max_phrase_length 這些換掉了，essay 的詞會不一樣）
  static func newExtension(name: String, base: PenglaiDictDocument, baseName: String) -> String {
    var lines = [
      "# Rime dictionary",
      "# encoding: utf-8",
      "# 蓬萊設定視窗「詞庫」加的詞。匯入 \(baseName)：原本的詞照舊，這裡的詞加在上面。",
      "# 一行一個詞：詞<Tab>讀音（注音，音節以空白隔開，可以不填）<Tab>權重",
      "---",
      "name: \(name)",
      "version: \"1\"",
    ]
    for key in ["sort", "use_preset_vocabulary", "vocabulary", "max_phrase_length", "min_phrase_weight"] {
      if let value = base.headerValue(key) { lines.append("\(key): \(value)") }
    }
    if base.headerValue("sort") == nil { lines.append("sort: by_weight") }
    lines += ["columns:", "  - text", "  - code", "  - weight", "import_tables:", "  - \(baseName)", "..."]
    return lines.joined(separator: "\n") + "\n"
  }
}

// MARK: - 注音和按鍵

/// 碼的按鍵和注音互換（方案 translator/preedit_format 的第一條 xlit；讀不到用大千）
struct PenglaiKeymap {
  static let dachenKeys = "1qaz2wsxedcrfv5tgbyhnujm8ik,9ol.0p;/- 6347"
  static let dachenZhuyin = "ㄅㄆㄇㄈㄉㄊㄋㄌㄍㄎㄏㄐㄑㄒㄓㄔㄕㄖㄗㄘㄙㄧㄨㄩㄚㄛㄜㄝㄞㄟㄠㄡㄢㄣㄤㄥㄦˉˊˇˋ˙"
  static let initials = Set("ㄅㄆㄇㄈㄉㄊㄋㄌㄍㄎㄏㄐㄑㄒㄓㄔㄕㄖㄗㄘㄙ")
  static let medials = Set("ㄧㄨㄩ")
  static let finals = Set("ㄚㄛㄜㄝㄞㄟㄠㄡㄢㄣㄤㄥㄦ")
  static let tones = Set("ˊˇˋ˙")

  private(set) var toZhuyinMap: [Character: Character] = [:]
  private(set) var toKeyMap: [Character: Character] = [:]

  init(preeditFormat: [String] = []) {
    var keys = Array(Self.dachenKeys), zhuyin = Array(Self.dachenZhuyin)
    for rule in preeditFormat where rule.hasPrefix("xlit") && rule.count > 5 {
      let separator = rule[rule.index(rule.startIndex, offsetBy: 4)]
      let parts = rule.split(separator: separator, omittingEmptySubsequences: false)
      if parts.count >= 3, parts[1].count == parts[2].count, !parts[1].isEmpty {
        keys = Array(parts[1])
        zhuyin = Array(parts[2])
        break
      }
    }
    for (key, symbol) in zip(keys, zhuyin) {
      if toZhuyinMap[key] == nil { toZhuyinMap[key] = symbol }
      if toKeyMap[symbol] == nil { toKeyMap[symbol] = key }
    }
    toKeyMap["ˉ"] = toKeyMap["ˉ"] ?? " "
  }

  func zhuyin(ofKeys keys: String) -> String { String(keys.map { toZhuyinMap[$0] ?? $0 }) }
  func keys(ofZhuyin text: String) -> String { String(text.map { toKeyMap[$0] ?? $0 }) }

  static func isZhuyin(_ ch: Character) -> Bool { initials.contains(ch) || medials.contains(ch) || finals.contains(ch) || tones.contains(ch) || ch == "ˉ" }

  /// 詞典的讀音：打注音或照鍵盤打按鍵都行。聲調（空白是一聲）把音節分開，一聲不寫符號（跟詞典一樣），
  /// 回傳以空白隔開的音節；看不懂的回傳 nil
  func syllables(_ input: String) -> [String]? {
    var text = input.trimmingCharacters(in: .whitespaces)
    if text.contains(where: { $0.isASCII && !$0.isWhitespace }) { text = zhuyin(ofKeys: text) }
    var result: [String] = []
    var current = ""
    func close() -> Bool {
      guard !current.isEmpty else { return true }
      guard Self.validSyllable(current) else { return false }
      result.append(current)
      current = ""
      return true
    }
    for ch in text {
      if ch == "ˉ" || ch.isWhitespace || ch == "'" {
        guard close() else { return nil }
      } else if Self.tones.contains(ch) {
        guard !current.isEmpty else { return nil }
        current.append(ch)
        guard close() else { return nil }
      } else if Self.isZhuyin(ch) {
        current.append(ch)
      } else {
        return nil
      }
    }
    guard close() else { return nil }
    return result
  }

  /// 聲母、介音、韻母各最多一個，照這個順序，後面可以接一個聲調
  static func validSyllable(_ syllable: String) -> Bool {
    var chars = Array(syllable)
    if let last = chars.last, tones.contains(last) { chars.removeLast() }
    guard !chars.isEmpty, chars.count <= 3 else { return false }
    var stage = 0
    for ch in chars {
      let level = initials.contains(ch) ? 1 : medials.contains(ch) ? 2 : finals.contains(ch) ? 3 : 0
      guard level > stage else { return false }
      stage = level
    }
    return true
  }
}

// MARK: - 用到哪幾個檔案

/// 部署後的方案用到的三份詞庫檔（重讀設定時算一次）。nil 是方案沒有那一種
struct PenglaiDictionaryFiles: Equatable {
  /// 自訂詞：碼表翻譯器（dictionary 空著、db_class stabledb）的 user_dict.txt
  var phrase: String?
  /// 方案現在用的詞典（translator/dictionary）
  var dictionary: String?
  /// 詞庫頁「詞典」要改的檔案：方案的詞典本身是擴充詞典（有 import_tables、在使用者資料夾）就是它；
  /// 不是的話是要新建的 penglai_custom.dict.yaml（dictCreates 為真）
  var dict: String?
  var dictCreates = false
  /// 不能加詞典詞的原因
  var dictNote: String?
  var hidden: String?

  static let customName = "penglai_custom"

  static func read(schemaID: String, userDir: URL, sharedDir: URL?) -> PenglaiDictionaryFiles {
    var files = PenglaiDictionaryFiles()
    guard !schemaID.isEmpty else { return files }
    let schema = PenglaiRimeConfig(.schema(schemaID))
    guard schema.isOpen else { return files }
    for spec in schema.listStrings("engine/translators") {
      let parts = spec.components(separatedBy: "@")
      guard parts.count == 2, parts[0] == "table_translator" else { continue }
      let ns = parts[1]
      guard (schema.string("\(ns)/dictionary") ?? "").isEmpty, schema.string("\(ns)/db_class") == "stabledb" else { continue }
      files.phrase = (schema.string("\(ns)/user_dict") ?? ns) + ".txt"
      break
    }
    if let hidden = schema.string("translator/dictionary_exclude_file"), !hidden.isEmpty { files.hidden = hidden }
    guard let name = schema.string("translator/dictionary"), !name.isEmpty else { return files }
    files.dictionary = name
    let fm = FileManager.default
    let userFile = userDir.appendingPathComponent(name + ".dict.yaml")
    let sharedFile = sharedDir?.appendingPathComponent(name + ".dict.yaml")
    let source = fm.fileExists(atPath: userFile.path) ? userFile : sharedFile.flatMap { fm.fileExists(atPath: $0.path) ? $0 : nil }
    guard let source, let text = try? String(contentsOf: source, encoding: .utf8) else {
      files.dictNote = "找不到詞典檔 \(name).dict.yaml"
      return files
    }
    let doc = PenglaiDictDocument(kind: .dict, text: text)
    if !doc.imports.isEmpty {
      if source == userFile {
        files.dict = name + ".dict.yaml"
      } else {
        files.dictNote = "方案用的詞典 \(name) 不在使用者資料夾，這裡改不了"
      }
    } else {
      files.dict = customName + ".dict.yaml"
      files.dictCreates = true
    }
    return files
  }
}

// MARK: - 改完之後的指令

/// 使用者資料夾裡可執行的 penglai_dict_hook：自訂詞、詞典改了以後、部署之前跑一次（例如從自訂詞再產生一份詞典）。
/// 引數是改了的檔名，工作目錄是使用者資料夾；兩分鐘沒跑完就停掉。沒有這個檔案就什麼都不做
enum PenglaiDictionaryHook {
  static let file = "penglai_dict_hook"
  static let timeout: TimeInterval = 120

  static func exists(_ userDir: URL) -> Bool {
    FileManager.default.isExecutableFile(atPath: userDir.appendingPathComponent(file).path)
  }

  /// 成功或沒有 hook 時回傳 nil，失敗回傳給人看的一句話（細節寫進系統記錄）
  static func run(_ userDir: URL, files: [String]) -> String? {
    guard exists(userDir) else { return nil }
    let process = Process()
    process.executableURL = userDir.appendingPathComponent(file)
    process.arguments = files
    process.currentDirectoryURL = userDir
    var environment = ProcessInfo.processInfo.environment
    environment["PENGLAI_USER_DIR"] = userDir.path
    process.environment = environment
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    let lock = NSLock()
    var output = Data()
    pipe.fileHandleForReading.readabilityHandler = { handle in
      let data = handle.availableData
      lock.lock(); output.append(data); lock.unlock()
    }
    do {
      try process.run()
    } catch {
      pipe.fileHandleForReading.readabilityHandler = nil
      NSLog("Penglai settings: %@ 跑不起來：%@", file, error.localizedDescription)
      return "\(file) 跑不起來"
    }
    let deadline = Date().addingTimeInterval(timeout)
    while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
    if process.isRunning {
      process.terminate()
      pipe.fileHandleForReading.readabilityHandler = nil
      return "\(file) 超過 \(Int(timeout)) 秒，停掉了"
    }
    pipe.fileHandleForReading.readabilityHandler = nil
    lock.lock()
    output.append(pipe.fileHandleForReading.readDataToEndOfFile())
    let text = String(decoding: output, as: UTF8.self)
    lock.unlock()
    NSLog("Penglai settings: %@ %@ → %d：%@", file, files.joined(separator: " "), process.terminationStatus, text)
    guard process.terminationStatus != 0 else { return nil }
    let last = text.split(separator: "\n").last.map(String.init) ?? ""
    return "\(file) 失敗（\(process.terminationStatus)）" + (last.isEmpty ? "" : "：\(last)")
  }
}

// MARK: - 模型：讀、改

/// 上次用 Control 複製的輸入（使用者資料夾的 penglai_dump.json）
struct PenglaiLastCopy: Equatable {
  var input: String
  var zhuyin: String
  var first: String

  static func load(_ userDir: URL) -> PenglaiLastCopy? {
    guard let data = try? Data(contentsOf: userDir.appendingPathComponent("penglai_dump.json")),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let input = object["input"] as? String, !input.isEmpty else { return nil }
    let candidates = object["candidates"] as? [[String: Any]] ?? []
    return PenglaiLastCopy(input: input, zhuyin: object["zhuyin"] as? String ?? "", first: candidates.first?["text"] as? String ?? "")
  }
}

extension PenglaiSettingsModel {
  func dictionaryFile(_ kind: PenglaiDictKind) -> String? {
    switch kind {
    case .phrase: return dictionaryFiles.phrase
    case .dict: return dictionaryFiles.dict
    case .hidden: return dictionaryFiles.hidden
    }
  }

  /// 那一份還不能用的原因；nil 是可以用
  func dictionaryUnavailable(_ kind: PenglaiDictKind) -> String? {
    guard !schemaID.isEmpty else { return "還沒選方案" }
    switch kind {
    case .phrase: return dictionaryFiles.phrase == nil ? "這個方案沒有自訂詞" : nil
    case .dict: return dictionaryFiles.dict == nil ? (dictionaryFiles.dictNote ?? "這個方案沒有詞典") : nil
    case .hidden: return dictionaryFiles.hidden == nil ? "這個方案沒有隱藏詞的清單" : nil
    }
  }

  func dictionaryDocument(_ kind: PenglaiDictKind) -> PenglaiDictDocument? {
    guard let file = dictionaryFile(kind) else { return nil }
    let text = (try? String(contentsOf: userDir.appendingPathComponent(file), encoding: .utf8)) ?? ""
    return PenglaiDictDocument(kind: kind, text: text)
  }

  var keymap: PenglaiKeymap {
    guard !schemaID.isEmpty else { return PenglaiKeymap() }
    return PenglaiKeymap(preeditFormat: PenglaiRimeConfig(.schema(schemaID)).listStrings("translator/preedit_format"))
  }

  var lastCopy: PenglaiLastCopy? { PenglaiLastCopy.load(userDir) }

  /// 檢查、整理使用者填的值：回傳要寫進檔案的碼、權重，或給人看的錯誤
  func normalizeDictionaryInput(_ kind: PenglaiDictKind, text rawText: String, code rawCode: String, weight rawWeight: String,
                                document: PenglaiDictDocument) -> Result<(text: String, code: String, weight: String), PenglaiDictDocument.EditError> {
    let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return .failure(.invalid("請填要加的詞")) }
    guard !text.contains("\t"), !text.contains("\n") else { return .failure(.invalid("詞裡面不能有 Tab 或換行")) }
    let weight = rawWeight.trimmingCharacters(in: .whitespaces)
    if !weight.isEmpty, weight.range(of: #"^-?[0-9]+(\.[0-9]+)?%?$"#, options: .regularExpression) == nil {
      return .failure(.invalid("權重要填數字（可以空著）"))
    }
    switch kind {
    case .hidden:
      return .success((text, "", ""))
    case .phrase:
      var code = String(rawCode.drop(while: { $0 == " " }))
      if code.contains(where: PenglaiKeymap.isZhuyin) { code = keymap.keys(ofZhuyin: code) }
      guard !code.isEmpty else { return .failure(.invalid("請填碼（鍵盤上按的鍵），或按「帶入上次複製的輸入」")) }
      guard !code.contains("\t"), !code.contains("\n") else { return .failure(.invalid("碼裡面不能有 Tab 或換行")) }
      return .success((text, code, weight))
    case .dict:
      let trimmed = rawCode.trimmingCharacters(in: .whitespaces)
      guard !trimmed.isEmpty else { return .success((text, "", weight)) }
      guard document.hasCode else { return .failure(.invalid("這份詞典不寫讀音，讀音照每個字的讀音配，請把讀音空著")) }
      guard let syllables = keymap.syllables(trimmed) else {
        return .failure(.invalid("讀音看不懂：打注音（ㄐㄧㄢˇ ㄉㄢ）或照鍵盤按鍵打（ru04 2u0），音節之間用聲調或空白分開"))
      }
      let hanzi = text.unicodeScalars.filter { $0.properties.isIdeographic }.count
      if hanzi == text.unicodeScalars.count, hanzi != syllables.count {
        return .failure(.invalid("讀音有 \(syllables.count) 個音節，詞有 \(hanzi) 個字"))
      }
      return .success((text, syllables.joined(separator: " "), weight))
    }
  }

  /// 加或改一個詞；成功回傳 nil，不然回傳給人看的錯誤
  @discardableResult
  func saveDictionaryEntry(_ kind: PenglaiDictKind, original: PenglaiDictEntry?, text: String, code: String, weight: String) -> String? {
    if let reason = dictionaryUnavailable(kind) { return reason }
    guard var doc = dictionaryDocument(kind), let file = dictionaryFile(kind) else { return "讀不到詞庫檔" }
    var values: (text: String, code: String, weight: String)
    switch normalizeDictionaryInput(kind, text: text, code: code, weight: weight, document: doc) {
    case .success(let value): values = value
    case .failure(let error): return error.message
    }
    let before = original ?? doc.entries.first { $0.text == values.text && (kind == .hidden || !doc.hasCode || $0.code == values.code) }
    if kind == .dict, before == nil, values.weight.isEmpty, doc.hasWeight || dictionaryFiles.dictCreates { values.weight = PenglaiDictDocument.defaultWeight }
    var texts: [String: String] = [:]
    var changes: [PenglaiSettingsStore.Change] = []
    if kind == .dict, dictionaryFiles.dictCreates, let base = dictionaryFiles.dictionary {
      // 第一次加詞典詞：新建擴充詞典（檔案已經有了就接著用），方案 custom 檔指過去
      if !FileManager.default.fileExists(atPath: userDir.appendingPathComponent(file).path) {
        let baseURL = [userDir, sharedDir].compactMap { $0?.appendingPathComponent(base + ".dict.yaml") }
          .first { FileManager.default.fileExists(atPath: $0.path) }
        let baseDoc = PenglaiDictDocument(kind: .dict, text: baseURL.flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? "")
        doc = PenglaiDictDocument(kind: .dict, text: PenglaiDictDocument.newExtension(name: PenglaiDictionaryFiles.customName, base: baseDoc, baseName: base))
      }
      changes.append(.init(file: PenglaiConfigID.schema(schemaID).customFile, key: "translator/dictionary",
                           action: .set(.string(PenglaiDictionaryFiles.customName))))
    }
    let note = kind == .hidden ? Self.hiddenStamp() : ""
    do {
      try doc.upsert(original: original, text: values.text, code: values.code, weight: values.weight, note: note)
    } catch let error as PenglaiDictDocument.EditError {
      return error.message
    } catch {
      return error.localizedDescription
    }
    texts[file] = doc.text
    let shown = values.code.isEmpty || kind == .hidden ? values.text : "\(values.text)（\(values.code)）"
    let verb: String
    switch kind {
    case .hidden: verb = before == nil ? "隱藏" : "改"
    default: verb = before == nil ? "加入" : "改"
    }
    return apply(changes, texts: texts, summary: "\(kind.title)：\(verb) \(shown)")
  }

  @discardableResult
  func removeDictionaryEntry(_ kind: PenglaiDictKind, _ entry: PenglaiDictEntry) -> String? {
    guard var doc = dictionaryDocument(kind), let file = dictionaryFile(kind) else { return "讀不到詞庫檔" }
    do {
      try doc.remove(entry)
    } catch let error as PenglaiDictDocument.EditError {
      return error.message
    } catch {
      return error.localizedDescription
    }
    let verb = kind == .hidden ? "取消隱藏" : "刪掉"
    return apply([], texts: [file: doc.text], summary: "\(kind.title)：\(verb) \(entry.text)")
  }

  static func hiddenStamp(_ date: Date = Date()) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    return formatter.string(from: date)
  }
}

// MARK: - 畫面

struct PenglaiDictionaryPage: View {
  @EnvironmentObject var model: PenglaiSettingsModel
  @State private var doc: PenglaiDictDocument?
  @State private var text = ""
  @State private var code = ""
  @State private var weight = ""
  @State private var editing: PenglaiDictEntry?
  @State private var error: String?
  @State private var query = ""
  @State private var keymap = PenglaiKeymap()

  private var kind: PenglaiDictKind { model.dictionaryKind }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        PenglaiSegmented(options: PenglaiDictKind.allCases.map { ($0, $0.title) }, selection: kind) { value in
          model.dictionaryKind = value
        }
        Spacer()
        if let file = model.dictionaryFile(kind), model.dictionaryUnavailable(kind) == nil {
          Button {
            let url = model.userDir.appendingPathComponent(file)
            if FileManager.default.fileExists(atPath: url.path) {
              NSWorkspace.shared.activateFileViewerSelecting([url])
            } else {
              NSWorkspace.shared.open(model.userDir)
            }
          } label: {
            Label(file, systemImage: "doc.text").font(.system(size: 11.5))
          }
          .buttonStyle(.link)
          .help("在 Finder 裡顯示這個檔案")
        }
      }
      Text(kind.desc).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
      if let reason = model.dictionaryUnavailable(kind) {
        Label(reason, systemImage: "exclamationmark.triangle.fill").font(.system(size: 12)).foregroundStyle(.orange)
        Spacer()
      } else {
        editor
        list
      }
    }
    .padding(.horizontal, 30).padding(.top, 14).padding(.bottom, 14)
    .onAppear { load() }
    .onChange(of: model.revision) { _ in load() }
    .onChange(of: model.dictionaryKind) { _ in
      clearForm()
      query = ""
      load()
    }
  }

  // MARK: 編輯區

  private var editor: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .firstTextBaseline, spacing: 10) {
        field(kind == .hidden ? "要隱藏的詞" : "詞", text: $text, width: kind == .hidden ? 300 : 190)
        if showsCode {
          field(kind == .phrase ? "碼（按鍵）" : "讀音（可以不填）", text: $code, width: 170, mono: kind == .phrase)
        }
        if showsWeight {
          field(kind == .dict && editing == nil ? "權重（不填是 \(PenglaiDictDocument.defaultWeight)）" : "權重", text: $weight, width: kind == .dict ? 150 : 80, mono: true)
        }
        Spacer(minLength: 0)
      }
      HStack(spacing: 8) {
        if let hint = codeHint {
          Text(hint).font(.system(size: 11.5)).foregroundStyle(.secondary).lineLimit(1)
        }
        Spacer(minLength: 0)
        if kind == .phrase {
          Button("帶入上次複製的輸入") { importLastCopy() }
            .help("選字窗開著時按 Control 複製的輸入（碼）帶進來")
        }
        if editing != nil || !text.isEmpty || !code.isEmpty || !weight.isEmpty {
          Button(editing == nil ? "清除" : "取消") { clearForm() }
        }
        Button(editing == nil ? (kind == .hidden ? "隱藏" : "加入") : "儲存") { save() }
          .keyboardShortcut(.defaultAction)
          .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
      }
      .controlSize(.large)
      if let error {
        Label(error, systemImage: "xmark.octagon.fill").font(.system(size: 11.5)).foregroundStyle(.red)
      } else if let warning {
        Label(warning, systemImage: "exclamationmark.triangle.fill").font(.system(size: 11.5)).foregroundStyle(.orange)
      }
    }
    .padding(12)
    .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(nsColor: .separatorColor)))
  }

  private func field(_ title: String, text: Binding<String>, width: CGFloat, mono: Bool = false) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(title).font(.system(size: 11)).foregroundStyle(.secondary)
      TextField("", text: text)
        .textFieldStyle(.roundedBorder)
        .font(mono ? .system(size: 13, design: .monospaced) : .system(size: 13))
        .frame(width: width)
        .onSubmit { save() }
    }
  }

  private var showsCode: Bool { kind == .phrase || (kind == .dict && (doc?.hasCode ?? true)) }
  private var showsWeight: Bool { kind != .hidden && (doc?.hasWeight ?? true) }

  /// 碼底下的說明：自訂詞照注音鍵盤顯示按的鍵，詞典顯示整理後的讀音
  private var codeHint: String? {
    switch kind {
    case .phrase:
      guard !code.isEmpty else { return "碼可以照鍵盤按鍵打，也可以打注音。" }
      let keys = code.contains(where: PenglaiKeymap.isZhuyin) ? keymap.keys(ofZhuyin: code) : code
      return "按鍵 \(Self.visibleKeys(keys))" + (Self.lettersOnly(keys) ? "" : "　注音鍵盤上是 \(keymap.zhuyin(ofKeys: keys))")
    case .dict:
      guard showsCode else { return "讀音照每個字的讀音配。" }
      guard !code.trimmingCharacters(in: .whitespaces).isEmpty else { return "多音字、人名念法特別的再填讀音。" }
      return keymap.syllables(code).map { "讀音 " + $0.joined(separator: " ") } ?? "讀音看不懂"
    case .hidden:
      return nil
    }
  }

  /// 碼全是英文字母：多半是英文縮寫（ts、vpn），照注音鍵盤翻出來（ㄔㄋ）沒有意思，不顯示
  static func lettersOnly(_ keys: String) -> Bool { !keys.isEmpty && keys.allSatisfy { $0.isASCII && $0.isLetter } }

  /// 空白（一聲）看不到，換成 ␣
  static func visibleKeys(_ keys: String) -> String { keys.replacingOccurrences(of: " ", with: "␣") }

  private var warning: String? {
    guard kind == .phrase else { return nil }
    let keys = code.contains(where: PenglaiKeymap.isZhuyin) ? keymap.keys(ofZhuyin: code) : code
    guard !keys.isEmpty, keys.count <= 2 else { return nil }
    return "兩個鍵以內的碼，單獨打時會排在同碼的常用詞前面"
  }

  // MARK: 清單

  private var list: some View {
    let entries = filtered
    return VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 8) {
        HStack(spacing: 6) {
          Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
          TextField("搜尋\(kind.title)", text: $query).textFieldStyle(.plain)
          if !query.isEmpty {
            Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
              .buttonStyle(.plain).help("清除搜尋")
          }
        }
        .font(.system(size: 12.5))
        .padding(.horizontal, 8).frame(width: 260, height: 26)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor).opacity(0.6)))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor)))
        Spacer()
        Text(query.isEmpty ? "共 \(doc?.entries.count ?? 0) 個" : "找到 \(entries.count) 個（共 \(doc?.entries.count ?? 0) 個）")
          .font(.system(size: 11.5).monospacedDigit()).foregroundStyle(.secondary)
      }
      if entries.isEmpty {
        Text(query.isEmpty ? (kind == .hidden ? "沒有隱藏的詞。" : "還沒有詞，可以從上面加。") : "沒有符合的詞。")
          .font(.system(size: 12)).foregroundStyle(.secondary).padding(.top, 6)
        Spacer()
      } else {
        List {
          ForEach(entries) { entry in
            row(entry)
          }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor)))
      }
    }
  }

  private func row(_ entry: PenglaiDictEntry) -> some View {
    HStack(spacing: 12) {
      Text(entry.text).font(.system(size: 13)).lineLimit(1).frame(width: 190, alignment: .leading)
      switch kind {
      case .phrase:
        VStack(alignment: .leading, spacing: 1) {
          Text(Self.visibleKeys(entry.code)).font(.system(size: 12, design: .monospaced)).lineLimit(1)
          if !Self.lettersOnly(entry.code) {
            Text(keymap.zhuyin(ofKeys: entry.code)).font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(1)
          }
        }
        .frame(width: 150, alignment: .leading)
      case .dict:
        if doc?.hasCode ?? false {
          Text(entry.code.isEmpty ? "（照字配）" : entry.code).font(.system(size: 12)).foregroundStyle(entry.code.isEmpty ? .secondary : .primary)
            .lineLimit(1).frame(width: 150, alignment: .leading)
        }
      case .hidden:
        Text(entry.code).font(.system(size: 11.5).monospacedDigit()).foregroundStyle(.secondary).frame(width: 150, alignment: .leading)
      }
      if kind != .hidden, doc?.hasWeight ?? false {
        Text(entry.weight).font(.system(size: 12).monospacedDigit()).foregroundStyle(.secondary).frame(width: 70, alignment: .trailing)
      }
      Text(entry.section).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
      if kind != .hidden {
        Button { startEditing(entry) } label: { Image(systemName: "pencil") }
          .buttonStyle(.borderless).help("改這個詞")
      }
      Button { remove(entry) } label: { Image(systemName: kind == .hidden ? "eye" : "trash") }
        .buttonStyle(.borderless).help(kind == .hidden ? "取消隱藏" : "刪掉這個詞")
    }
    .padding(.vertical, 1)
    .background(editing?.line == entry.line ? Color.accentColor.opacity(0.15) : Color.clear)
  }

  private var filtered: [PenglaiDictEntry] {
    let entries = Array((doc?.entries ?? []).reversed())   // 最近加的（檔案後面的）排前面
    let words = query.split(whereSeparator: \.isWhitespace).map(String.init)
    guard !words.isEmpty else { return entries }
    return entries.filter { entry in
      let zhuyin = kind == .phrase ? keymap.zhuyin(ofKeys: entry.code) : ""
      return words.allSatisfy { word in
        [entry.text, entry.code, zhuyin, entry.section].contains { $0.localizedStandardContains(word) }
      }
    }
  }

  // MARK: 動作

  private func load() {
    keymap = model.keymap
    doc = model.dictionaryDocument(kind)
    if let current = editing, doc?.entries.contains(where: { $0 == current }) != true { editing = nil }
  }

  private func clearForm() {
    text = ""; code = ""; weight = ""; editing = nil; error = nil
  }

  private func startEditing(_ entry: PenglaiDictEntry) {
    editing = entry
    text = entry.text
    code = entry.code
    weight = entry.weight
    error = nil
  }

  private func importLastCopy() {
    guard let copy = model.lastCopy else {
      error = "還沒有複製過：選字窗開著時按一下 Control，就會把輸入和候選複製起來"
      return
    }
    code = copy.input
    error = nil
  }

  private func save() {
    guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
    if let failure = model.saveDictionaryEntry(kind, original: editing, text: text, code: code, weight: weight) {
      error = failure
      return
    }
    clearForm()
    load()
  }

  private func remove(_ entry: PenglaiDictEntry) {
    if let failure = model.removeDictionaryEntry(kind, entry) {
      error = failure
      return
    }
    if editing?.line == entry.line { clearForm() }
    load()
  }
}
