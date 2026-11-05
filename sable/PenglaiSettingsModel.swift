//
//  PenglaiSettingsModel.swift
//  Squirrel
//
//  蓬萊設定視窗的資料：從 librime 讀「部署後實際生效」的值，對照每個 *.custom.yaml 標出這個值寫在哪裡，
//  依設定目錄（penglai-settings.json，tools/gen_settings_catalog.py 從原始碼掃出來）列出程式會讀的全部設定，
//  改了就交給 PenglaiSettingsStore 寫回原檔，再部署。
//

import AppKit
import SwiftUI

// MARK: - 設定目錄

enum PenglaiJSONScalar: Decodable, Hashable {
  case int(Int), double(Double), bool(Bool), string(String)

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if let value = try? container.decode(Int.self) { self = .int(value) } else if let value = try? container.decode(Double.self) {
      self = .double(value)
    } else if let value = try? container.decode(Bool.self) { self = .bool(value) } else { self = .string(try container.decode(String.self)) }
  }

  var text: String {
    switch self {
    case .int(let value): return String(value)
    case .double(let value): return String(value)
    case .bool(let value): return value ? "true" : "false"
    case .string(let value): return value
    }
  }
}

struct PenglaiCatalog: Decodable {
  struct Key: Decodable {
    var id: String
    var config: String
    var key: String
    var component: String?
    var relative: Bool?
    var type: String
    var `default`: String?
    var sources: [String]?
    var title: String?
    var desc: String?
    var options: [PenglaiJSONScalar]?
    var labels: [String: String]?
    var min: Double?
    var max: Double?
    var step: Double?
    var penglai: Bool?
    var defaultSection: Bool?
    var lua: String?            // 外掛模組（Lua）的鍵：哪個 Lua 檔讀的（`lua_processor@*penglai_tap@…` 的 penglai_tap）；key 接在元件命名空間後面
    var luaNs: String?          // Lua 寫死的命名空間（penglai_forget 一律讀 penglai_forget/…，不看 @ 後面寫什麼）
    var noReset: Bool?          // 不顯示「改回預設」：方案原檔的值跟這個鍵的意思相反（筆畫反查）

    enum CodingKeys: String, CodingKey {
      case id, config, key, component, relative, type, `default`, sources, title, desc, options, labels, min, max, step, penglai, lua
      case defaultSection = "default_section"
      case luaNs = "lua_ns"
      case noReset = "no_reset"
    }
  }

  struct Family: Decodable {
    var types: [String]
    var defaultNs: String?
    var label: String

    enum CodingKeys: String, CodingKey {
      case types, label
      case defaultNs = "default_ns"
    }
  }

  var versions: [String: String]
  var families: [String: Family]
  var dataSections: [String]
  var recipes: [PenglaiRecipe]
  var keys: [Key]

  enum CodingKeys: String, CodingKey {
    case versions, families, recipes, keys
    case dataSections = "data_sections"
  }

  static func load(from url: URL?) -> PenglaiCatalog? {
    guard let url, let data = try? Data(contentsOf: url) else { return nil }
    return try? JSONDecoder().decode(PenglaiCatalog.self, from: data)
  }

  /// 本機說明：使用者資料夾的 penglai-settings.local.json（keys 跟目錄同格式），同一個 id 蓋過目錄裡的。
  /// 只有這台機器才有的外掛模組（例如讀自己資料的 Lua）把說明放這裡，不放進 App 帶的目錄。
  static let localFile = "penglai-settings.local.json"

  mutating func merge(localAt url: URL) {
    struct Local: Decodable { var keys: [Key] }
    guard let data = try? Data(contentsOf: url), let local = try? JSONDecoder().decode(Local.self, from: data) else { return }
    let ids = Set(local.keys.map(\.id))
    keys = keys.filter { !ids.contains($0.id) } + local.keys
  }
}

/// 快速鍵（10/30）：哪件事用哪個鍵。修飾鍵點一下的三件事（penglai_tap.lua）和數字選字的觸發鍵（penglai_numsel.lua）
/// 從同一組鍵裡選，不能兩件事用同一個；排列順序就是 Lua 的處理順序（同一個鍵時先列的有作用）。
/// 一鍵忘掉是打一串鍵（translator/forget_last_code），只能選幾個不會是注音的碼，跟上面那組不會撞在一起。
/// 都用分段按鈕選，不用打字：設定視窗開在貂毫自己的程序裡，打字的可能就是貂毫自己，7 是輕聲鍵
enum PenglaiShortcuts {
  static let tapKeys = ["penglai_tap/copy", "penglai_tap/forget", "penglai_tap/second", "penglai_numsel/trigger"]
  static let codeKey = "translator/forget_last_code"
  static let keys = tapKeys + [codeKey]
}

// MARK: - 讀部署後的設定

enum PenglaiConfigID: Hashable {
  case squirrel, defaultConfig, schema(String)

  var rimeID: String {
    switch self {
    case .squirrel: return "sable"   // 前端設定檔 sable.yaml（型別名照舊叫 squirrel，跟上游同步時少衝突）
    case .defaultConfig: return "default"
    case .schema(let id): return id
    }
  }

  var customFile: String { rimeID + ".custom.yaml" }
}

/// 打開一份部署後的設定（build/*.yaml），讀完就關。
final class PenglaiRimeConfig {
  private let rimeAPI: RimeApi_stdbool = rime_get_api_stdbool().pointee
  private var config = RimeConfig()
  private(set) var isOpen = false

  init(_ id: PenglaiConfigID) {
    switch id {
    case .schema(let schemaID): isOpen = rimeAPI.schema_open(schemaID, &config)
    default: isOpen = rimeAPI.config_open(id.rimeID, &config)
    }
  }

  /// 使用者資料夾裡的原檔（沒部署、沒套 custom），例如 "penglai_zhuyin.schema"。
  init(userConfig name: String) {
    isOpen = rimeAPI.user_config_open(name, &config)
  }

  deinit {
    if isOpen { _ = rimeAPI.config_close(&config) }
  }

  func string(_ key: String) -> String? {
    guard isOpen, let value = rimeAPI.config_get_cstring(&config, key) else { return nil }
    return String(cString: value)
  }

  func listSize(_ key: String) -> Int {
    isOpen ? Int(rimeAPI.config_list_size(&config, key)) : 0
  }

  func listStrings(_ key: String) -> [String] {
    (0..<listSize(key)).compactMap { string("\(key)/@\($0)") }
  }

  func mapKeys(_ key: String) -> [String]? {
    guard isOpen else { return nil }
    var iterator = RimeConfigIterator()
    guard rimeAPI.config_begin_map(&iterator, &config, key) else { return nil }
    var keys: [String] = []
    while rimeAPI.config_next(&iterator) {
      if let name = iterator.key { keys.append(String(cString: name)) }
    }
    rimeAPI.config_end(&iterator)
    return keys
  }

  /// 這個路徑有沒有東西（單一值、清單或表格）。
  func exists(_ key: String) -> Bool {
    string(key) != nil || listSize(key) > 0 || mapKeys(key) != nil
  }
}

// MARK: - 一列設定

struct PenglaiSettingRow: Identifiable {
  enum Source: Equatable {
    case userFile(String, Int)  // 寫在使用者的檔案第幾行（1 起算）
    case shipped                // 方案檔或官方設定
    case builtin                // 檔案都沒寫，用程式內建的值
  }

  var id: String { "\(group)|\(key)" }
  var group: String           // 分組名稱（選字窗、全域、方案名）
  var config: PenglaiConfigID
  var key: String             // 完整路徑
  var info: PenglaiCatalog.Key?
  var type: String
  var effective: String?      // 部署後的值（單一值）；清單、表格是 nil
  var structureSummary: String?
  var source: Source
  var file: String?           // 改的話寫進哪個檔
  var fileValue: String?      // 檔案裡寫的值
  var blocked: String?        // 改不了的原因
  var unknownLine: Int?       // 「沒人讀」：檔案裡第幾行
  var luaComponent: String?

  var title: String { info?.title ?? key }
  var described: Bool { info?.title != nil }
  /// 進階頁列得出來的：有中文名稱、是單一個值、程式會讀、這裡改得了（設定鍵不上畫面，沒名稱的就不列），
  /// 主頁已經有的不重複；目錄標了〔危險〕〔元件沒掛〕〔寫錯地方〕的不列（改了會打不出字或沒作用）；
  /// 沒有選項的文字設定只列字型、格式這類看得懂的，詞典、標籤、檔名這類不列
  var presentable: Bool {
    guard unknownLine == nil, described, isScalar, structureSummary == nil, blocked == nil else { return false }
    guard !PenglaiSettingsModel.featuredKeys.contains(key),
          !PenglaiSettingsModel.technicalKeys.contains(where: key.hasSuffix) else { return false }
    let desc = info?.desc ?? ""
    if ["〔危險〕", "〔元件沒掛〕", "〔寫錯地方〕"].contains(where: desc.hasPrefix) { return false }
    if type == "string", (info?.options ?? []).isEmpty {
      return PenglaiSettingsModel.freeTextKeys.contains { key.hasSuffix($0) }
    }
    return true
  }
  var isScalar: Bool { ["bool", "int", "double", "string"].contains(type) }
  var isUserSet: Bool { if case .userFile = source { return true } else { return false } }
  var builtinDefault: String? { info?.default }
  var shownValue: String? { effective ?? builtinDefault }
  /// 檔案改了但還沒部署（或被更高層蓋過）
  var pendingValue: String? {
    guard let fileValue, let effective, !PenglaiSettingsModel.same(fileValue, effective) else { return nil }
    return fileValue
  }
}

/// 配色選項
struct PenglaiColorScheme: Identifiable {
  var id: String
  var name: String
  var back: NSColor?
  var text: NSColor?
  var hilitedBack: NSColor?
  var hilitedText: NSColor?
  var overrides: [String]  // 這個配色自帶、會蓋過選字窗設定的項目
}

struct PenglaiSchemaInfo: Identifiable {
  var id: String
  var name: String
}

/// 方案 switches 裡讀音那一組：第幾組、選項（方案檔的順序）、部署後的 reset
struct PenglaiReadingSwitch: Equatable {
  var index: Int
  var options: [String]
  var deployed: Int?
}

/// 方案 switches 裡一組只有開、關的選項（例如聯想 prediction）：第幾組、部署後的 reset
struct PenglaiOptionSwitch: Equatable {
  var index: Int
  var deployed: Int?
}

/// 開關列用：存著的是開還是關、能不能點、要不要提醒
struct PenglaiOptionState: Equatable {
  var on: Bool?
  var enabled: Bool
  var note: String?
}

/// 讀音頁、引導畫面用：列哪幾個、存著的是哪一個、能不能點、要不要提醒
struct PenglaiReadingState: Equatable {
  var options: [String]
  var choice: String?
  var enabled: Bool
  var note: String?
}

// MARK: - 模型

final class PenglaiSettingsModel: ObservableObject {
  enum Page: String, CaseIterable, Identifiable {
    case panel, colors, typing, reading, schemas, all, history
    var id: String { rawValue }
    var title: String {
      switch self {
      case .panel: return "選字窗"
      case .colors: return "配色"
      case .typing: return "輸入"
      case .reading: return "讀音"
      case .schemas: return "輸入方案"
      case .all: return "進階"
      case .history: return "變更紀錄"
      }
    }
    /// 側欄色塊裡改放字（讀音放ㄅ，SF Symbols 沒有注音）
    var glyph: String? { self == .reading ? "ㄅ" : nil }
    var symbol: String {
      switch self {
      case .panel: return "rectangle.grid.1x2.fill"
      case .colors: return "paintpalette.fill"
      case .typing: return "keyboard.fill"
      case .reading: return "textformat"   // 側欄畫 glyph（ㄅ），這個只是備用
      case .schemas: return "list.bullet"
      case .all: return "slider.horizontal.3"
      case .history: return "clock.arrow.circlepath"
      }
    }
  }

  /// 側欄列哪幾頁：輸入方案只有一個可選時不列（那一頁只有一個關不掉的開關）
  var sidebarPages: [Page] { Page.allCases.filter { $0 != .schemas || schemas.count > 1 || page == .schemas } }

  /// 進階頁的篩選：全部（照分類）、只看自訂過的
  enum Filter: String, CaseIterable, Identifiable {
    case all, changed
    var id: String { rawValue }
  }

  enum Status: Equatable {
    case idle
    case applying
    case applied(Date)
    case failed(String)
  }

  /// 部署：onlySquirrel 為真時只重讀前端設定 sable.yaml；完成後回呼（成功與否）。
  typealias Deployer = (_ onlySquirrel: Bool, _ completion: @escaping (Bool) -> Void) -> Void

  let userDir: URL
  let sharedDir: URL?
  let catalog: PenglaiCatalog?
  let store: PenglaiSettingsStore
  private let deployer: Deployer

  @Published var page: Page = .panel
  @Published var filter: Filter = .all
  /// 進階頁看的是哪一類（PenglaiAdvanced.Section 的 id）；nil 是分類總覽
  @Published var advancedSection: String?
  /// 那一類裡看的是哪一組（分段按鈕；只有一組時就是那一組）
  @Published var advancedSegment = ""
  @Published var pageIndex = 0
  /// 側欄搜尋欄的字；不是空的時候右邊顯示搜尋結果
  @Published var searchText = "" { didSet { if searchText != oldValue { searchPage = 0 } } }
  @Published var searchPage = 0
  /// 從搜尋跳過來時閃一下的那一列（標題）
  @Published var highlight: String?
  /// 配色頁現在看的是深色模式那組
  @Published var colorsDark = false
  @Published private(set) var status: Status = .idle
  @Published private(set) var message: String?
  @Published private(set) var schemaID = ""
  @Published private(set) var schemaName = ""
  @Published private(set) var rows: [PenglaiSettingRow] = []
  @Published private(set) var colorSchemes: [PenglaiColorScheme] = []
  @Published private(set) var schemas: [PenglaiSchemaInfo] = []
  @Published private(set) var activeSchemas: [String] = []
  /// 方案原本（沒套 custom）的反查規則；nil 是方案沒掛反查，或讀不到原檔。打字頁「筆畫反查」打開時寫回這個值
  @Published private(set) var reverseLookupPattern: String?
  /// 方案原本（沒套 custom）的英文單字表；nil 是方案沒有中英混輸，或讀不到原檔。打字頁「中英混輸」打開時寫回這個值
  @Published private(set) var englishLexicon: String?
  /// 方案 switches 裡讀音那一組（部署後的方案）；nil 是方案沒有讀音選項
  @Published private(set) var readingSwitch: PenglaiReadingSwitch?
  /// 方案 switches 裡聯想那一組（name: prediction）；nil 是方案沒有聯想開關
  @Published private(set) var predictionSwitch: PenglaiOptionSwitch?
  /// 聯想資料檔（部署後方案的 predictor/db）在使用者資料夾或共用資料夾裡找得到
  @Published private(set) var predictionData = false
  @Published private(set) var history: [PenglaiSettingsStore.Entry] = []
  @Published private(set) var revision = 0

  /// 改正在用的 session 的選項（讀音即時生效）：輸入法程序裡通知每個輸入框的 session，沙盒視窗改自己開的 session；沒有就不改
  var liveOptions: (([String: Bool]) -> Void)?

  private var pendingSquirrelOnly = true
  private var deployWork: DispatchWorkItem?
  /// 進階頁一頁最多幾列：分類時每一組都排在這個數以內，超過（別的方案、新加的設定）才翻頁
  static let rowsPerPage = 8
  /// 全部設定裡外掛模組（Lua）那一組的名稱
  static let pluginGroup = "外掛模組"

  init(userDir: URL, sharedDir: URL?, catalogURL: URL?, deployer: @escaping Deployer) {
    self.userDir = userDir
    self.sharedDir = sharedDir
    var catalog = PenglaiCatalog.load(from: catalogURL)
    catalog?.merge(localAt: userDir.appendingPathComponent(PenglaiCatalog.localFile))
    self.catalog = catalog
    self.store = PenglaiSettingsStore(userDir: userDir)
    self.deployer = deployer
    reload()
  }

  // MARK: 讀

  /// 重新讀部署後的值和檔案。視窗打開、回到前景、部署完都會叫。
  func reload() {
    history = store.history
    readSchema()
    rows = buildRows()
    colorSchemes = readColorSchemes()
    let defaults = PenglaiRimeConfig(.defaultConfig)
    activeSchemas = (0..<defaults.listSize("schema_list")).compactMap { defaults.string("schema_list/@\($0)/schema") }
    schemas = readSchemas()
    // 進階頁停在的那一類、那一組重讀之後沒有了（換方案、檔案被手改）就回總覽、第一組
    if let section = advancedSection {
      let segments = advancedSegments(section)
      if segments.isEmpty { advancedSection = nil } else if !segments.contains(where: { $0.id == advancedSegment }) { advancedSegment = segments[0].id }
    }
    reverseLookupPattern = readReverseLookupPattern()
    englishLexicon = readEnglishLexicon()
    readingSwitch = readReadingSwitch()
    predictionSwitch = readPredictionSwitch()
    predictionData = findPredictionData()
    revision += 1
  }

  private func readSchema() {
    let user = (try? String(contentsOf: userDir.appendingPathComponent("user.yaml"), encoding: .utf8)) ?? ""
    var id = user.range(of: "previously_selected_schema: *([A-Za-z0-9_.-]+)", options: .regularExpression)
      .map { String(user[$0]).components(separatedBy: ":").last!.trimmingCharacters(in: .whitespaces) } ?? ""
    let defaults = PenglaiRimeConfig(.defaultConfig)
    let listed = (0..<defaults.listSize("schema_list")).compactMap { defaults.string("schema_list/@\($0)/schema") }
    if id.isEmpty || (!listed.isEmpty && !listed.contains(id)) { id = listed.first ?? "" }
    schemaID = id
    schemaName = id.isEmpty ? "" : (PenglaiRimeConfig(.schema(id)).string("schema/name") ?? id)
  }

  /// 方案掛的外掛模組（Lua）：Lua 檔名 → 命名空間（`lua_filter@*penglai_hide*filter@penglai_hide` → penglai_hide、penglai_hide）。
  private func luaModules(_ schema: PenglaiRimeConfig) -> [(module: String, ns: String)] {
    var result: [(module: String, ns: String)] = []
    for spec in ["processors", "segmentors", "translators", "filters"].flatMap({ schema.listStrings("engine/\($0)") }) {
      let parts = spec.components(separatedBy: "@")
      guard parts[0].hasPrefix("lua_"), parts.count >= 2 else { continue }
      let script = parts[1].trimmingCharacters(in: CharacterSet(charactersIn: "*"))
      let module = script.components(separatedBy: "*").first ?? script
      let ns = parts.count >= 3 ? parts.last! : script
      if !module.isEmpty, !result.contains(where: { $0.module == module && $0.ns == ns }) { result.append((module, ns)) }
    }
    return result
  }

  /// 方案的 engine 清單：元件型別 → 命名空間（`script_translator@custom_phrase` → custom_phrase）。
  private func components(_ schema: PenglaiRimeConfig) -> [(type: String, ns: String?)] {
    ["processors", "segmentors", "translators", "filters"].flatMap { schema.listStrings("engine/\($0)") }.map { spec in
      let parts = spec.components(separatedBy: "@")
      if parts[0].hasPrefix("lua_") {
        return (parts[0], parts.count >= 3 ? parts.last : parts.count == 2 ? parts[1].trimmingCharacters(in: CharacterSet(charactersIn: "*")) : nil)
      }
      return (parts[0], parts.count >= 2 ? parts[1] : nil)
    }
  }

  private func buildRows() -> [PenglaiSettingRow] {
    guard let catalog else { return [] }
    var result: [PenglaiSettingRow] = []
    var seen = Set<String>()
    let squirrel = PenglaiRimeConfig(.squirrel)
    let defaults = PenglaiRimeConfig(.defaultConfig)
    let schema = schemaID.isEmpty ? nil : PenglaiRimeConfig(.schema(schemaID))
    let schemaGroup = schemaName.isEmpty ? "方案" : "方案：\(schemaName)"
    let docs = [PenglaiConfigID.squirrel, .defaultConfig] + (schemaID.isEmpty ? [] : [.schema(schemaID)])
    let files = Dictionary(uniqueKeysWithValues: docs.map { ($0.customFile, store.read($0.customFile)) })

    func add(_ info: PenglaiCatalog.Key?, config: PenglaiConfigID, key: String, type: String, group: String, defaultSection: Bool) {
      let rowID = "\(config.rimeID)|\(key)"
      guard !seen.contains(rowID) else { return }
      seen.insert(rowID)
      let reader: PenglaiRimeConfig? = {
        switch config {
        case .squirrel: return squirrel
        case .defaultConfig: return defaults
        case .schema: return schema
        }
      }()
      var effective = reader?.string(key)
      if effective == nil, defaultSection, case .schema = config { effective = defaults.string(key) }
      var structure: String?
      if effective == nil, let reader {
        let size = reader.listSize(key)
        if size > 0 { structure = "清單 \(size) 項" } else if let keys = reader.mapKeys(key) { structure = "表格 \(keys.count) 項" }
      }
      // 寫在哪個檔：方案檔優先，default 段落的鍵也看 default.custom.yaml；都沒有就寫進最該寫的那個
      var candidates = [config.customFile]
      if defaultSection, case .schema = config { candidates.append(PenglaiConfigID.defaultConfig.customFile) }
      var source: PenglaiSettingRow.Source = (effective != nil || structure != nil) ? .shipped : .builtin
      var file = defaultSection ? PenglaiConfigID.defaultConfig.customFile : config.customFile
      var fileValue: String?
      var blocked: String?
      for candidate in candidates {
        guard let doc = files[candidate] else { continue }
        switch doc.region(key) {
        case .range(let range):
          source = .userFile(candidate, range.lowerBound + 1)
          file = candidate
          fileValue = doc.value(key)
        case .unsupported(let reason):
          blocked = "\(candidate)：\(reason)"
          file = candidate
        case .absent:
          continue
        }
        break
      }
      let scalarTypes = ["bool", "int", "double", "string"]
      if blocked == nil, !scalarTypes.contains(type) || structure != nil {
        blocked = "這是清單或表格，請打開檔案改"
      }
      result.append(PenglaiSettingRow(group: group, config: config, key: key, info: info, type: type, effective: effective,
                                      structureSummary: structure, source: source, file: file, fileValue: fileValue, blocked: blocked))
    }

    // 寫死路徑的鍵
    for info in catalog.keys where info.relative != true {
      switch info.config {
      case "sable":
        add(info, config: .squirrel, key: info.key, type: info.type, group: info.key.hasPrefix("style/") ? "選字窗外觀" : "貂毫", defaultSection: false)
      case "default":
        add(info, config: .defaultConfig, key: info.key, type: info.type, group: "全域", defaultSection: false)
      default:
        guard !schemaID.isEmpty else { continue }
        add(info, config: .schema(schemaID), key: info.key, type: info.type, group: schemaGroup, defaultSection: info.defaultSection == true)
      }
    }
    // 元件的鍵：照方案實際掛的元件換成完整路徑
    if let schema {
      let parts = components(schema)
      for info in catalog.keys where info.relative == true {
        guard let family = info.component.flatMap({ catalog.families[$0] }) else { continue }
        for part in parts where family.types.contains(part.type) {
          let ns = part.ns ?? family.defaultNs ?? ""
          guard !ns.isEmpty else { continue }
          add(info, config: .schema(schemaID), key: "\(ns)/\(info.key)", type: info.type, group: schemaGroup, defaultSection: false)
        }
      }
      // 外掛模組（Lua）的設定：目錄寫了說明的鍵照目錄列（檔案沒寫也列，值是 Lua 裡的預設）；
      // 方案裡那一段還有目錄沒寫的單一值，也列出來
      for part in luaModules(schema) {
        var keys: [(key: String, info: PenglaiCatalog.Key?)] = catalog.keys.filter { $0.lua == part.module }
          .map { ("\($0.luaNs ?? part.ns)/\($0.key)", $0) }
        for sub in schema.mapKeys(part.ns) ?? [] where !keys.contains(where: { $0.key == "\(part.ns)/\(sub)" }) {
          keys.append(("\(part.ns)/\(sub)", nil))
        }
        for (key, info) in keys {
          let value = schema.string(key)
          guard info != nil || value != nil else { continue }
          let type = info?.type ?? value.map { Int($0) != nil ? "int" : Double($0) != nil ? "double" : ["true", "false"].contains($0) ? "bool" : "string" } ?? "string"
          var row = PenglaiSettingRow(group: Self.pluginGroup, config: .schema(schemaID), key: key, info: info, type: type, effective: value,
                                      structureSummary: nil, source: value != nil ? .shipped : .builtin,
                                      file: PenglaiConfigID.schema(schemaID).customFile,
                                      fileValue: nil, blocked: nil, luaComponent: part.module)
          if let file = row.file, let doc = files[file] {
            switch doc.region(key) {
            case .range(let range):
              row.source = .userFile(file, range.lowerBound + 1)
              row.fileValue = doc.value(key)
            case .unsupported(let reason):
              row.blocked = reason
              if let entry = doc.patchEntries().first(where: { $0.key == key.components(separatedBy: "/").first }) { row.source = .userFile(file, entry.line + 1) }
            case .absent: break
            }
          }
          if !seen.contains("\(row.config.rimeID)|\(key)") {
            seen.insert("\(row.config.rimeID)|\(key)")
            result.append(row)
          }
        }
      }
    }
    // 沒人讀的設定：手寫檔裡有、目錄和元件都對不上的
    let known = result.map(\.key)
    let schemaParts = schema.map(components) ?? []
    let namespaces = Set(schemaParts.compactMap(\.ns))
    for config in docs {
      guard let doc = files[config.customFile] else { continue }
      for entry in doc.patchEntries() {
        var key = entry.key
        for suffix in ["/+", "/="] where key.hasSuffix(suffix) { key = String(key.dropLast(2)) }
        if key.hasPrefix("__") { continue }
        let readable = known.contains { $0 == key || $0.hasPrefix(key + "/") || key.hasPrefix($0 + "/") }
          || catalog.dataSections.contains { key == $0 || key.hasPrefix($0 + "/") || $0.hasPrefix(key + "/") }
          || namespaces.contains { key == $0 || key.hasPrefix($0 + "/") }
        if readable { continue }
        let group: String = {
          switch config {
          case .squirrel: return key.hasPrefix("style/") ? "選字窗外觀" : "貂毫"
          case .defaultConfig: return "全域"
          case .schema: return schemaGroup
          }
        }()
        result.append(PenglaiSettingRow(group: group, config: config, key: key, info: nil, type: entry.isBlock ? "map" : "string",
                                        effective: nil, structureSummary: nil, source: .userFile(config.customFile, entry.line + 1),
                                        file: config.customFile, fileValue: doc.value(key), blocked: nil, unknownLine: entry.line + 1))
      }
    }
    return result
  }

  private func readColorSchemes() -> [PenglaiColorScheme] {
    let base = SquirrelConfig()
    guard base.openBaseConfig() else { return [] }
    defer { base.close() }
    let raw = PenglaiRimeConfig(.squirrel)
    var result = [PenglaiColorScheme(id: "native", name: "系統", back: nil, text: nil, hilitedBack: nil, hilitedText: nil, overrides: [])]
    for id in raw.mapKeys("preset_color_schemes") ?? [] where id != "native" {
      let prefix = "preset_color_schemes/\(id)"
      let space = SquirrelTheme.RimeColorSpace.from(name: base.getString("\(prefix)/color_space") ?? "")
      let text = base.getColor("\(prefix)/text_color", inSpace: space)
      let candidateText = base.getColor("\(prefix)/candidate_text_color", inSpace: space) ?? text
      let hilitedBack = base.getColor("\(prefix)/hilited_candidate_back_color", inSpace: space) ?? base.getColor("\(prefix)/hilited_back_color", inSpace: space)
      let hilitedText = base.getColor("\(prefix)/hilited_candidate_text_color", inSpace: space) ?? base.getColor("\(prefix)/hilited_text_color", inSpace: space) ?? candidateText
      var overrides: [String] = []
      if let layout = raw.string("\(prefix)/candidate_list_layout") { overrides.append(layout == "linear" ? "橫" : "直") }
      if let size = raw.string("\(prefix)/font_point") { overrides.append(size) }
      if raw.string("\(prefix)/inline_preedit") != nil { overrides.append("注音") }
      result.append(PenglaiColorScheme(id: id, name: raw.string("\(prefix)/name") ?? id,
                                       back: base.getColor("\(prefix)/back_color", inSpace: space), text: candidateText,
                                       hilitedBack: hilitedBack, hilitedText: hilitedText, overrides: overrides))
    }
    return result
  }

  /// 裝了哪些方案：使用者資料夾和共用資料夾的 *.schema.yaml，扣掉附屬資料（見 auxiliarySchemas）。
  private func readSchemas() -> [PenglaiSchemaInfo] {
    var found: [String: String] = [:]
    for dir in [sharedDir, userDir].compactMap({ $0 }) {
      let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
      for name in names where name.hasSuffix(".schema.yaml") {
        let text = (try? String(contentsOf: dir.appendingPathComponent(name), encoding: .utf8)) ?? ""
        let id = String(name.dropLast(".schema.yaml".count))
        var title = id
        if let range = text.range(of: "\n  name: *[^\n]+", options: .regularExpression) {
          title = String(text[range]).components(separatedBy: "name:").last!.trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        }
        found[id] = title
      }
    }
    let auxiliary = auxiliarySchemas(Array(found.keys))
    return found.filter { !auxiliary.contains($0.key) }.map { PenglaiSchemaInfo(id: $0.key, name: $0.value) }.sorted { $0.id < $1.id }
  }

  /// 附屬資料：被別的方案拿來當 dependencies 或反查詞典、自己又不在 schema_list 裡的方案（例如蓬萊注音的筆畫反查 stroke）。
  /// 不能單獨用，方案頁不列；使用者自己加進 schema_list 的照樣列，才取消得掉。規則從部署後的方案讀，不寫死名字。
  private func auxiliarySchemas(_ ids: [String]) -> Set<String> {
    var used = Set<String>()
    for id in ids {
      let schema = PenglaiRimeConfig(.schema(id))
      guard schema.isOpen else { continue }
      used.formUnion(schema.listStrings("schema/dependencies"))
      for part in components(schema) where ["reverse_lookup_translator", "reverse_lookup_filter"].contains(part.type) {
        if let dict = schema.string("\(part.ns ?? "reverse_lookup")/dictionary"), !dict.isEmpty { used.insert(dict) }
      }
    }
    return used.subtracting(activeSchemas)
  }

  // MARK: 筆畫反查

  static let reverseLookupKey = "recognizer/patterns/reverse_lookup"

  /// 方案掛著反查翻譯器（有詞典），而且原檔寫了反查規則，才回傳那條規則。
  private func readReverseLookupPattern() -> String? {
    guard !schemaID.isEmpty else { return nil }
    let schema = PenglaiRimeConfig(.schema(schemaID))
    let hasLookup = components(schema).contains { part in
      part.type == "reverse_lookup_translator" && !(schema.string("\(part.ns ?? "reverse_lookup")/dictionary") ?? "").isEmpty
    }
    guard hasLookup else { return nil }
    let raw = PenglaiRimeConfig(userConfig: "\(schemaID).schema")
    return raw.string(Self.reverseLookupKey).flatMap { $0.isEmpty ? nil : $0 }
  }

  /// 開關的狀態：部署後的反查規則不是空的就是開。
  var reverseLookupOn: Bool { !(schemaRow(Self.reverseLookupKey)?.effective ?? "").isEmpty }

  /// 打開：那一行寫回方案原本的規則；關掉：寫空字串。只改那一行（沒有那一行才加在 patch 最後）。
  func setReverseLookup(_ on: Bool) {
    guard let row = schemaRow(Self.reverseLookupKey), let pattern = reverseLookupPattern else { return }
    set(row, .string(on ? pattern : ""), summary: "筆畫反查：\(on ? "開" : "關")")
  }

  // MARK: 中英混輸（librime patch 0003、0004）

  static let englishKey = "translator/english_lexicon"
  /// 送出之後按空白補標點（外掛模組 penglai_space 讀，沒寫時開）
  static let spacePunctKey = "penglai_space/punct"

  /// 方案原檔寫了英文單字表（english_lexicon），才回傳那個名字。方案原檔預設打開，關掉是在 custom 寫空字串。
  private func readEnglishLexicon() -> String? {
    guard !schemaID.isEmpty else { return nil }
    let raw = PenglaiRimeConfig(userConfig: "\(schemaID).schema")
    return raw.string(Self.englishKey).flatMap { $0.isEmpty ? nil : $0 }
  }

  /// 開關的狀態：部署後的單字表名稱不是空的就是開。
  var englishOn: Bool { !(schemaRow(Self.englishKey)?.effective ?? "").isEmpty }

  /// 打開：那一行寫回方案原本的單字表；關掉：寫空字串。只改那一行（沒有那一行才加在 patch 最後）。
  func setEnglish(_ on: Bool) {
    guard let row = schemaRow(Self.englishKey), let lexicon = englishLexicon else { return }
    set(row, .string(on ? lexicon : ""), summary: "中英混輸：\(on ? "開" : "關")")
  }

  // MARK: 讀音（librime patch 0010）

  private func readReadingSwitch() -> PenglaiReadingSwitch? {
    guard !schemaID.isEmpty else { return nil }
    let schema = PenglaiRimeConfig(.schema(schemaID))
    let lists = (0..<schema.listSize("switches")).map { schema.listStrings("switches/@\($0)/options") }
    guard let index = PenglaiReading.switchIndex(lists) else { return nil }
    return PenglaiReadingSwitch(index: index, options: lists[index], deployed: schema.string("switches/@\(index)/reset").flatMap { Int($0) })
  }

  /// 讀音頁、引導用的狀態：存著的是哪一個（方案 custom 檔寫的，沒寫就是部署後方案檔的 reset，都沒有是蓬萊音）、能不能改
  var readingState: PenglaiReadingState {
    guard let readingSwitch, !schemaID.isEmpty else {
      return PenglaiReadingState(options: PenglaiReading.options, choice: nil, enabled: false, note: Self.unsupportedText)
    }
    let options = readingSwitch.options.filter(PenglaiReading.options.contains)
    let doc = store.read(PenglaiConfigID.schema(schemaID).customFile)
    let key = PenglaiReading.resetKey(readingSwitch.index)
    if case .unsupported(let reason) = doc.region(key) {
      NSLog("Penglai settings: %@ 的 %@ 改不了：%@", PenglaiConfigID.schema(schemaID).customFile, key, reason)
      return PenglaiReadingState(options: options, choice: nil, enabled: false, note: Self.blockedText)
    }
    let written = doc.value(key).flatMap { Int($0) }
    let saved = written ?? readingSwitch.deployed ?? 0
    let choice = readingSwitch.options.indices.contains(saved) ? readingSwitch.options[saved] : nil
    // 檔案寫了、部署後的方案卻不是那個值：還沒部署完，或被別的設定蓋過
    let pending = written != nil && readingSwitch.deployed != written && status != .applying
    return PenglaiReadingState(options: options, choice: choice, enabled: true, note: pending ? "這項變更還沒生效，可能被其他設定蓋過" : nil)
  }

  /// 選讀音：正在用的 session 馬上換（跟 F4 選單一樣，選中的打開、另外兩個關掉，組字中的候選跟著換），
  /// 同時寫進方案 custom 檔的 reset 再部署（只重寫 prism，表不重編），之後開的 session 都照這個
  func setReading(_ option: String) {
    guard let readingSwitch, !schemaID.isEmpty, let index = readingSwitch.options.firstIndex(of: option) else { return }
    liveOptions?(Dictionary(uniqueKeysWithValues: readingSwitch.options.map { ($0, $0 == option) }))
    apply([.init(file: PenglaiConfigID.schema(schemaID).customFile, key: PenglaiReading.resetKey(readingSwitch.index), action: .set(.int(index)))],
          summary: "讀音：\(PenglaiCopy.readingOption(option).title)")
  }

  /// 復原動到讀音時，正在用的 session 也換回存著的那個
  private func touchesReading(_ entries: ArraySlice<PenglaiSettingsStore.Entry>) -> Bool {
    guard let readingSwitch else { return false }
    let key = PenglaiReading.resetKey(readingSwitch.index)
    return entries.contains { $0.edits.contains { $0.key == key } }
  }

  private func syncLiveReading() {
    guard let readingSwitch, let choice = readingState.choice else { return }
    liveOptions?(Dictionary(uniqueKeysWithValues: readingSwitch.options.map { ($0, $0 == choice) }))
  }

  // MARK: 聯想（librime-predict，patches/librime-predict/0001）

  static let predictionOption = "prediction"

  private func readPredictionSwitch() -> PenglaiOptionSwitch? {
    guard !schemaID.isEmpty else { return nil }
    let schema = PenglaiRimeConfig(.schema(schemaID))
    guard let index = (0..<schema.listSize("switches")).first(where: { schema.string("switches/@\($0)/name") == Self.predictionOption })
    else { return nil }
    return PenglaiOptionSwitch(index: index, deployed: schema.string("switches/@\(index)/reset").flatMap { Int($0) })
  }

  /// 聯想資料（predictor/db，沒寫是 predict.db）：使用者資料夾先找，再找 App 帶的共用資料夾（貂毫附官方 data-1.0）
  private func findPredictionData() -> Bool {
    guard !schemaID.isEmpty else { return false }
    let name = PenglaiRimeConfig(.schema(schemaID)).string("predictor/db") ?? "predict.db"
    guard !name.isEmpty else { return false }
    return [userDir, sharedDir].compactMap { $0 }.contains { FileManager.default.fileExists(atPath: $0.appendingPathComponent(name).path) }
  }

  /// 開關的狀態：方案 custom 檔寫的 reset，沒寫就是部署後方案檔的，都沒有是關
  var predictionState: PenglaiOptionState {
    guard let predictionSwitch, !schemaID.isEmpty else {
      return PenglaiOptionState(on: nil, enabled: false, note: Self.unsupportedText)
    }
    let doc = store.read(PenglaiConfigID.schema(schemaID).customFile)
    let key = PenglaiReading.resetKey(predictionSwitch.index)
    if case .unsupported(let reason) = doc.region(key) {
      NSLog("Penglai settings: %@ 的 %@ 改不了：%@", PenglaiConfigID.schema(schemaID).customFile, key, reason)
      return PenglaiOptionState(on: nil, enabled: false, note: Self.blockedText)
    }
    let written = doc.value(key).flatMap { Int($0) }
    let on = (written ?? predictionSwitch.deployed ?? 0) != 0
    if written != nil && predictionSwitch.deployed != written && status != .applying {
      return PenglaiOptionState(on: on, enabled: true, note: "這項變更還沒生效，可能被其他設定蓋過")
    }
    return PenglaiOptionState(on: on, enabled: true, note: on && !predictionData ? Self.noPredictionDataText : nil)
  }

  static let noPredictionDataText = "還沒有聯想資料，打開了也不會出現"

  /// 開、關聯想：正在用的 session 馬上換（跟 F4 選單一樣），同時寫進方案 custom 檔的 reset 再部署（只重寫設定，表不重編），
  /// 之後開的 session 都照這個
  func setPrediction(_ on: Bool) {
    guard let predictionSwitch, !schemaID.isEmpty else { return }
    liveOptions?([Self.predictionOption: on])
    apply([.init(file: PenglaiConfigID.schema(schemaID).customFile, key: PenglaiReading.resetKey(predictionSwitch.index),
                 action: .set(.int(on ? 1 : 0)))],
          summary: "聯想：\(on ? "開" : "關")")
  }

  private func touchesPrediction(_ entries: ArraySlice<PenglaiSettingsStore.Entry>) -> Bool {
    guard let predictionSwitch else { return false }
    let key = PenglaiReading.resetKey(predictionSwitch.index)
    return entries.contains { $0.edits.contains { $0.key == key } }
  }

  private func syncLivePrediction() {
    guard let on = predictionState.on else { return }
    liveOptions?([Self.predictionOption: on])
  }

  // MARK: 給畫面用

  func row(_ key: String, config: PenglaiConfigID? = nil) -> PenglaiSettingRow? {
    rows.first { $0.key == key && (config == nil || $0.config == config!) && $0.unknownLine == nil }
  }

  func schemaRow(_ key: String) -> PenglaiSettingRow? {
    schemaID.isEmpty ? nil : row(key, config: .schema(schemaID))
  }

  // MARK: 進階頁的分類

  /// 進階頁列得出來的每一列和它分到哪一類、哪一組，照分類、組、列出的順序排（分類表在 PenglaiAdvanced）
  var advancedRows: [(row: PenglaiSettingRow, place: PenglaiAdvanced.Place)] {
    rows.filter(\.presentable).compactMap { row in PenglaiAdvanced.place(row, model: self).map { (row, $0) } }
      .sorted { lhs, rhs in lhs.place.order != rhs.place.order ? lhs.place.order < rhs.place.order : lhs.row.key < rhs.row.key }
  }

  /// 有東西可列的分類（照分類表的順序）
  var advancedSections: [PenglaiAdvanced.Section] {
    let used = Set(advancedRows.map(\.place.section))
    return PenglaiAdvanced.sections.filter { used.contains($0.id) }
  }

  /// 那一類裡有東西可列的組
  func advancedSegments(_ section: String) -> [PenglaiAdvanced.Segment] {
    let used = Set(advancedRows.filter { $0.place.section == section }.map(\.place.segment))
    return PenglaiAdvanced.section(section)?.segments.filter { used.contains($0.id) } ?? []
  }

  func advancedRows(section: String, segment: String? = nil) -> [PenglaiSettingRow] {
    advancedRows.filter { $0.place.section == section && (segment == nil || $0.place.segment == segment) }.map(\.row)
  }

  /// 打開進階頁的某一類（主頁的「更多」、總覽的卡片都走這裡）
  func openAdvanced(_ section: String, segment: String? = nil) {
    searchText = ""
    page = .all
    filter = .all
    advancedSection = section
    advancedSegment = segment ?? advancedSegments(section).first?.id ?? ""
    pageIndex = 0
  }

  /// 這一列在進階頁的哪裡（「中英混輸 › 字母串」），只有一組的分類不寫組名
  func advancedLocation(_ row: PenglaiSettingRow) -> String? {
    guard let place = PenglaiAdvanced.place(row, model: self), let section = PenglaiAdvanced.section(place.section) else { return nil }
    let segments = advancedSegments(place.section)
    guard segments.count > 1, let segment = segments.first(where: { $0.id == place.segment }) else { return section.title }
    return "\(section.title) › \(segment.title)"
  }

  var filteredRows: [PenglaiSettingRow] {
    switch filter {
    case .changed: return advancedRows.map(\.row).filter(\.isUserSet)
    case .all: return advancedSection.map { advancedRows(section: $0, segment: advancedSegment) } ?? []
    }
  }

  var changedCount: Int { advancedRows.filter(\.row.isUserSet).count }

  /// 「沒人讀」的設定：手寫檔裡有、程式不會讀的那幾行
  var unusedCount: Int { rows.filter { $0.unknownLine != nil }.count }

  /// 能不能「還原預設」：自訂過、這裡改得了
  func canReset(_ row: PenglaiSettingRow) -> Bool {
    row.isUserSet && row.unknownLine == nil && row.blocked == nil && row.info?.noReset != true
  }

  var pageCount: Int { max(1, (filteredRows.count + Self.rowsPerPage - 1) / Self.rowsPerPage) }

  var visibleRows: [PenglaiSettingRow] {
    let all = filteredRows
    let start = min(pageIndex, pageCount - 1) * Self.rowsPerPage
    return Array(all[min(start, all.count)..<min(start + Self.rowsPerPage, all.count)])
  }

  var hiddenCount: Int { rows.filter { $0.unknownLine == nil && $0.source == .builtin }.count }

  func recipeState(_ recipe: PenglaiRecipe) -> PenglaiRecipe.State {
    guard !schemaID.isEmpty else { return .unavailable("還沒選方案") }
    let doc = store.read(PenglaiConfigID.schema(schemaID).customFile)
    return recipe.state(in: doc, base: recipeBase(recipe, doc))
  }

  /// custom 檔沒寫這個清單時，部署後方案的那個清單就是方案檔本身寫的（公開預設的漏打聲母規則寫在方案檔，custom 檔是空的）
  private func recipeBase(_ recipe: PenglaiRecipe, _ doc: PenglaiCustomYAML) -> [String]? {
    guard doc.region(recipe.list) == .absent else { return nil }
    return PenglaiRimeConfig(.schema(schemaID)).listStrings(recipe.list)
  }

  /// 目前的配色有沒有蓋過某個選字窗設定
  func colorOverride(_ key: String) -> String? {
    let config = PenglaiRimeConfig(.squirrel)
    for (option, label) in [("style/color_scheme", "淺色"), ("style/color_scheme_dark", "深色")] {
      guard let id = config.string(option), id != "native", config.string("preset_color_schemes/\(id)/\(key.replacingOccurrences(of: "style/", with: ""))") != nil else { continue }
      let name = config.string("preset_color_schemes/\(id)/name") ?? id
      return "\(label)配色「\(name)」自帶這一項，會蓋過這裡的設定"
    }
    return nil
  }

  // MARK: 改

  func set(_ row: PenglaiSettingRow, _ value: PenglaiValue, summary: String? = nil) {
    guard let file = row.file else { return }
    let text = summary ?? "\(row.title)：\(row.shownValue.map { valueText(row, $0) } ?? "—") → \(valueText(row, value.yaml))"
    apply([.init(file: file, key: row.key, action: .set(value))], summary: text)
  }

  /// 紀錄裡的值：配色用名稱、有選項標籤的用標籤，不寫內部代號
  private func valueText(_ row: PenglaiSettingRow, _ raw: String) -> String {
    if row.key.hasPrefix("style/color_scheme"), let scheme = colorSchemes.first(where: { $0.id == raw }) { return scheme.name }
    return row.info?.labels?[raw] ?? Self.display(raw)
  }

  func resetToDefault(_ row: PenglaiSettingRow) {
    guard case .userFile(let file, _) = row.source else { return }
    // 快速鍵：預設的鍵正被別的事用著時，那件事換成這件事現在的鍵（跟選鍵時一樣對調）
    let swaps = shortcutSwaps(row, to: row.builtinDefault ?? "")
    apply([.init(file: file, key: row.key, action: .remove)] + swaps.changes, summary: "\(row.title)：還原預設" + swaps.summary)
    if !swaps.notes.isEmpty { message = "已對調：" + swaps.notes.joined(separator: "、") }
  }

  /// 快速鍵：選一個鍵。這個鍵別的事正在用時對調（那件事換成這件事原本的鍵；它不能用那個鍵時改成關），兩邊記成一筆、一起復原
  func setShortcut(_ row: PenglaiSettingRow, _ value: String) {
    guard let file = row.file else { return }
    let old = shortcutValue(row)
    guard old != value else { return }
    let swaps = shortcutSwaps(row, to: value)
    apply([.init(file: file, key: row.key, action: .set(.string(value)))] + swaps.changes,
          summary: "\(row.title)：\(valueText(row, old)) → \(valueText(row, value))" + swaps.summary)
    if !swaps.notes.isEmpty { message = "已對調：" + swaps.notes.joined(separator: "、") }
  }

  private func shortcutSwaps(_ row: PenglaiSettingRow, to value: String)
    -> (changes: [PenglaiSettingsStore.Change], notes: [String], summary: String) {
    guard PenglaiShortcuts.tapKeys.contains(row.key), !value.isEmpty else { return ([], [], "") }
    let old = shortcutValue(row)
    var changes: [PenglaiSettingsStore.Change] = []
    var notes: [String] = []
    let rows = PenglaiShortcuts.tapKeys.compactMap { schemaRow($0) }
    for other in rows where other.key != row.key && shortcutValue(other) == value {
      guard let file = other.file else { continue }
      // 換成這件事原本的鍵；那個鍵它不能用、或已經有第三件事在用（設定檔手改出來的衝突）時改成關，不把衝突搬到別處
      let usable = other.info?.options?.contains { $0.text == old } == true
      let taken = rows.contains { $0.key != row.key && $0.key != other.key && shortcutValue($0) == old }
      let swapped = usable && !taken ? old : ""
      changes.append(.init(file: file, key: other.key, action: .set(.string(swapped))))
      notes.append("「\(displayTitle(other))」改用\(valueText(other, swapped))")
    }
    return (changes, notes, notes.isEmpty ? "" : "（" + notes.joined(separator: "、") + "）")
  }

  /// 快速鍵現在用的鍵：custom 檔寫了就照檔案（剛點完、還沒部署完時生效值還是舊的，連點兩下會拿舊值對調）。
  /// 沒寫時，custom 檔這一版已經部署過才看生效值；還沒部署（剛還原預設、復原，部署失敗，手改了檔案）時生效值可能還是拿掉的那一行，
  /// 改看部署後會拿到的：方案原檔寫的（一鍵忘掉的 77），沒寫就是內建預設（修飾鍵那四件，預設在 Lua）
  func shortcutValue(_ row: PenglaiSettingRow) -> String {
    if let value = row.fileValue { return value }
    if schemaCustomDeployed() { return row.shownValue ?? "" }
    return PenglaiRimeConfig(userConfig: "\(schemaID).schema").string(row.key) ?? row.builtinDefault ?? ""
  }

  /// 方案 custom 檔現在這一版部署了沒：部署後的方案記下的修改時間（__build_info/timestamps，到秒）跟檔案的一樣
  func schemaCustomDeployed() -> Bool {
    let id = PenglaiConfigID.schema(schemaID)
    guard let recorded = PenglaiRimeConfig(id).string("__build_info/timestamps/\(id.rimeID).custom").flatMap(Double.init) else { return true }
    let attributes = try? FileManager.default.attributesOfItem(atPath: userDir.appendingPathComponent(id.customFile).path)
    guard let modified = attributes?[.modificationDate] as? Date else { return recorded == 0 }
    return modified.timeIntervalSince1970.rounded(.down) == recorded
  }

  /// 快速鍵：別的事也用同一個鍵（設定檔手改出來的；視窗裡選的會對調，不會這樣）。照 Lua 的處理順序，先列的那件有作用
  func shortcutConflict(_ row: PenglaiSettingRow) -> String? {
    guard let index = PenglaiShortcuts.tapKeys.firstIndex(of: row.key) else { return nil }
    let value = shortcutValue(row)
    guard !value.isEmpty else { return nil }
    let others = PenglaiShortcuts.tapKeys.enumerated().filter { $0.element != row.key }
      .compactMap { item in schemaRow(item.element).map { (item.offset, $0) } }.filter { shortcutValue($0.1) == value }
    guard let (otherIndex, other) = others.first else { return nil }
    let name = displayTitle(other)
    return otherIndex < index ? "跟「\(name)」用同一個鍵，這一項現在沒有作用" : "跟「\(name)」用同一個鍵，「\(name)」現在沒有作用"
  }

  func setPair(_ changes: [(PenglaiSettingRow, PenglaiValue)], summary: String) {
    apply(changes.compactMap { row, value in row.file.map { .init(file: $0, key: row.key, action: .set(value)) } }, summary: summary)
  }

  func setRecipe(_ recipe: PenglaiRecipe, enable: Bool) {
    guard !schemaID.isEmpty else { return }
    let file = PenglaiConfigID.schema(schemaID).customFile
    apply([.init(file: file, key: recipe.list, action: .recipe(recipe, enable: enable, base: recipeBase(recipe, store.read(file))))],
          summary: "\(recipe.title)：\(enable ? "開" : "關")")
  }

  func setSchemaList(_ ids: [String]) {
    guard !ids.isEmpty else {
      message = "至少要留一個方案"
      return
    }
    let names = ids.map { id in schemas.first { $0.id == id }?.name ?? id }
    apply([.init(file: PenglaiConfigID.defaultConfig.customFile, key: "schema_list", action: .block(ids.map { "- {schema: \($0)}" }))],
          summary: "輸入方案：" + names.joined(separator: "、"))
  }

  /// 一次清掉所有「沒人讀」的行，記成一筆
  func removeUnusedSettings() {
    let changes = rows.filter { $0.unknownLine != nil }.compactMap { row in
      row.file.map { PenglaiSettingsStore.Change(file: $0, key: row.key, action: .remove) }
    }
    guard !changes.isEmpty else { return }
    apply(changes, summary: "清除 \(changes.count) 項沒有作用的設定")
  }

  func apply(_ changes: [PenglaiSettingsStore.Change], summary: String) {
    do {
      guard let entry = try store.apply(changes, summary: summary) else { return }
      message = nil
      scheduleDeploy(onlySquirrel: entry.edits.allSatisfy { $0.file == PenglaiConfigID.squirrel.customFile })
    } catch let error as PenglaiSettingsStore.StoreError {
      message = Self.friendly(error)
      status = .failed(Self.friendly(error))
    } catch {
      message = error.localizedDescription
    }
    history = store.history
    rows = buildRows()
    revision += 1
  }

  func undoLast() {
    guard let last = store.history.last else { return }
    runUndo(onlySquirrel: last.edits.allSatisfy { $0.file == PenglaiConfigID.squirrel.customFile },
            reading: touchesReading(store.history.suffix(1)), prediction: touchesPrediction(store.history.suffix(1))) { try self.store.undoLast() }
  }

  func undo(through id: String) {
    guard let position = store.history.firstIndex(where: { $0.id == id }) else { return }
    let squirrelOnly = store.history[position...].allSatisfy { $0.edits.allSatisfy { $0.file == PenglaiConfigID.squirrel.customFile } }
    runUndo(onlySquirrel: squirrelOnly, reading: touchesReading(store.history[position...]),
            prediction: touchesPrediction(store.history[position...])) { try self.store.undo(through: id) }
  }

  private func runUndo(onlySquirrel: Bool, reading: Bool = false, prediction: Bool = false, _ body: () throws -> Void) {
    do {
      try body()
      message = nil
      if reading { syncLiveReading() }
      if prediction { syncLivePrediction() }
      scheduleDeploy(onlySquirrel: onlySquirrel)
    } catch let error as PenglaiSettingsStore.StoreError {
      message = Self.friendly(error)
    } catch {
      message = error.localizedDescription
    }
    history = store.history
    rows = buildRows()
    revision += 1
  }

  func redeploy() {
    scheduleDeploy(onlySquirrel: false, delay: 0)
  }

  /// 連續點的時候等最後一下過 0.6 秒才部署。
  private func scheduleDeploy(onlySquirrel: Bool, delay: Double = 0.6) {
    pendingSquirrelOnly = pendingSquirrelOnly && onlySquirrel
    deployWork?.cancel()
    status = .applying
    let work = DispatchWorkItem { [weak self] in
      guard let self else { return }
      let squirrelOnly = self.pendingSquirrelOnly
      self.pendingSquirrelOnly = true
      self.store.deployStarted = Date()
      self.deployer(squirrelOnly) { ok in
        DispatchQueue.main.async {
          self.status = ok ? .applied(Date()) : .failed("套用失敗，可以按「復原上一步」")
          self.reload()
        }
      }
    }
    deployWork = work
    DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
  }

  func openFile(_ file: String?) {
    let url = file.map { userDir.appendingPathComponent($0) } ?? userDir
    if let file, !FileManager.default.fileExists(atPath: url.path) {
      FileManager.default.createFile(atPath: url.path, contents: Data("patch:\n".utf8))
      _ = file
    }
    NSWorkspace.shared.open(url)
  }

  // MARK: 工具

  static func same(_ lhs: String, _ rhs: String) -> Bool {
    if lhs == rhs { return true }
    if let left = Double(lhs), let right = Double(rhs) { return left == right }
    return false
  }

  // MARK: 給使用者看的字（畫面上不出現檔名、行號、設定鍵）

  /// 選字窗、配色、輸入頁已經有的設定，進階頁不重複列
  static let featuredKeys: Set<String> = [
    "style/candidate_list_layout", "style/font_point", "style/inline_preedit", "style/inline_candidate", "status_icon/show",
    "style/color_scheme", "style/color_scheme_dark", "menu/page_size", "translator/max_sentences",
    "translator/max_user_phrase_syllables", "translator/revert_learning_seconds", reverseLookupKey, englishKey, spacePunctKey,
  ]

  /// 進階頁不列的技術項目：值是檔名或資料格式，使用者不會需要換
  static let technicalKeys = ["english_judge", "db_class", "pasteboard"]

  /// 進階頁要列的文字設定（看得懂、打錯也不會打不出字）
  static let freeTextKeys = [
    "font_face", "style/candidate_format", "switcher/caption", "switcher/option_list_prefix", "switcher/option_list_separator",
    "switcher/option_list_suffix", "menu/alternative_select_keys", "forget_last_code",
  ]

  static let blockedText = "這一項目前沒辦法在這裡調整"
  static let unsupportedText = "目前的輸入方案不支援這個功能"

  /// 寫檔失敗的原因：細節（檔名、哪一行）記進系統紀錄，畫面只說發生了什麼
  static func friendly(_ error: PenglaiSettingsStore.StoreError) -> String {
    NSLog("Penglai settings: %@", error.message)
    switch error {
    case .unsupported: return blockedText
    case .conflict: return "有些項目之後又被改過，這一步沒有復原"
    case .io: return "沒辦法儲存設定，請再試一次"
    }
  }

  /// 進階頁那一組裡顯示的標題：分類表改過名的照改，分類名稱已經講了的開頭拿掉（「中英混輸：」「聯想：」）；
  /// 同一組裡還是重複時（同一種元件掛了兩個），後面補上是哪一個
  func displayTitle(_ row: PenglaiSettingRow) -> String {
    guard let place = PenglaiAdvanced.place(row, model: self) else { return searchTitle(row) }
    let title = PenglaiAdvanced.title(row, in: place.section)
    let twins = advancedRows.filter { $0.place.section == place.section && $0.place.segment == place.segment
      && PenglaiAdvanced.title($0.row, in: place.section) == title }
    guard twins.count > 1, let ns = row.key.components(separatedBy: "/").first else { return title }
    return "\(title)（\(Self.namespaceTitles[ns] ?? ns)）"
  }

  /// 搜尋結果、已自訂列表用的標題（離開了分類，開頭不拿掉）：進階頁裡標題重複時補上是哪一個
  func searchTitle(_ row: PenglaiSettingRow) -> String {
    let title = PenglaiAdvanced.titles[row.key] ?? row.title
    let twins = advancedRows.filter { (PenglaiAdvanced.titles[$0.row.key] ?? $0.row.title) == title }
    guard twins.count > 1, let ns = row.key.components(separatedBy: "/").first else { return title }
    return "\(title)（\(Self.namespaceTitles[ns] ?? ns)）"
  }

  static let namespaceTitles = [
    "translator": "主翻譯器", "custom_phrase": "自訂詞", "reverse_lookup": "反查",
    "zh_hans": "簡化字", "zh_hant_tw": "臺灣字形", "zh_hant": "傳統字形",
  ]

  /// 進階頁的說明只取第一句、拿掉括號裡的補充（目錄的說明是寫給維護者的，後面常帶例子和實測）
  static func brief(_ desc: String) -> String? {
    // 開頭的〔要先打開…〕這類標記拿掉；第一句是「例：」或提到設定檔就不顯示說明
    var text = desc.replacingOccurrences(of: "^(〔[^〕]*〕)+", with: "", options: .regularExpression)
    // 句號緊接「」」的是引號裡的字（換成「。」），不是句尾
    var from = text.startIndex
    while let end = text[from...].firstIndex(of: "。") {
      let next = text.index(after: end)
      if next < text.endIndex, text[next] == "」" {
        from = next
        continue
      }
      text = String(text[...end])
      break
    }
    if text.hasPrefix("例") { return nil }
    // 提到檔名（penglai_dump.json）、路徑或設定鍵（recognizer/patterns）、程式裡的名字（digit_penalty）就不顯示
    if text.range(of: "[A-Za-z0-9]\\.[a-z]{2,5}\\b|/|\\b[a-z]+_[a-z_]+\\b", options: .regularExpression) != nil { return nil }
    text = text.replacingOccurrences(of: "（[^（）]*）", with: "", options: .regularExpression)
    text = text.replacingOccurrences(of: "\\([^()]*\\)", with: "", options: .regularExpression)
    text = text.trimmingCharacters(in: .whitespaces)
    return text.isEmpty || text == "。" ? nil : text
  }

  /// 舊的紀錄寫過檔名（「改回預設（刪掉 x.custom.yaml 那一行）」），顯示時拿掉
  static func cleanSummary(_ summary: String) -> String {
    summary.replacingOccurrences(of: " 改回預設（刪掉[^）]*）", with: "：還原預設", options: .regularExpression)
  }

  static func display(_ value: String) -> String {
    switch value {
    case "true": return "開"
    case "false": return "關"
    case "": return "關"   // 文字設定的選項裡，空字串是不用這個功能
    default: return value
    }
  }
}
