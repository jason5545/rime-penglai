//
//  PenglaiSettingsStandalone.swift
//  Squirrel
//
//  `Sable --settings --user-dir <資料夾>`：不啟動輸入法，單獨把蓬萊設定視窗開起來，用自己的 librime 讀寫那個資料夾。
//  給測試和截圖用：資料夾不能是正式的 ~/Library/Rime（正在跑的輸入法也開著它，兩邊同時部署會打架）。
//    --snapshot <資料夾>  每一頁存一張 PNG 後結束
//    --script <步驟>      照順序呼叫按鈕背後同一組函式（分號隔開，例如 "font=20;inline=hanzi;undo"），每步印出結果
//    --search <字>        跟 --snapshot 一起用：多截搜尋結果、點第一項之後各一張
//    --page <頁>          一開始停在哪一頁（panel、colors、typing、reading、schemas、all、history）
//    --offscreen          跟 --snapshot 一起用：視窗放在螢幕外、不搶前景（正在打字時截圖用），自己畫視窗內容
//  --script 的 type=<按鍵>：用視窗自己開的一個 session 打字（不送出，留在組字中），印第一頁候選和讀音選項，模擬正在打字的輸入框；
//  reading=<讀音> 選了之後、部署之前先印那個 session 組字中的候選（即時換了沒有）。部署跟輸入法一樣會關掉所有 session，
//  之後的 type= 是新開的 session（照部署後的方案設定選項）；fresh=<按鍵> 不管有沒有都先關掉再開。
//  prediction=on|off：輸入頁「聯想」開關（同讀音：視窗自己的 session 馬上換、寫進方案 custom 檔的 reset 再部署）。
//  keys=<按鍵>：同一個 session 不清組字接著打（rime 的按鍵序列寫法；分號是分步驟的，分號鍵寫 {semicolon}）；
//  select=<字>：選這一頁文字是它的候選（跟滑鼠點一樣），印選完的組字區；panel=<路徑.png>：照組字中的狀態和部署後的外觀設定
//  畫一張選字窗（跟正式打字時一樣帶軟游標；視窗透明、放在螢幕外，畫面上看不到）。給組字區的樣子截圖用。
//

import AppKit
import SwiftUI

enum PenglaiSettingsStandalone {
  /// `--名字 值`；後面沒有值（或接著另一個 --）的旗標記成 "1"（--show）
  static func parse(_ args: [String]) -> [String: String] {
    var options: [String: String] = [:]
    var index = 0
    while index < args.count {
      let name = args[index]
      guard name.hasPrefix("--") else {
        index += 1
        continue
      }
      if index + 1 < args.count, !args[index + 1].hasPrefix("--") {
        options[String(name.dropFirst(2))] = args[index + 1]
        index += 2
      } else {
        options[String(name.dropFirst(2))] = "1"
        index += 1
      }
    }
    return options
  }

  /// --user-dir 的沙盒資料夾；沒給、或是正式的 ~/Library/Rime 就印用法結束
  static func sandbox(_ options: [String: String], usage: String) -> URL {
    guard let dirPath = options["user-dir"] else {
      print(usage)
      exit(2)
    }
    let userDir = URL(fileURLWithPath: dirPath, isDirectory: true).resolvingSymlinksInPath()
    if userDir.standardizedFileURL.path == SquirrelApp.userDir.resolvingSymlinksInPath().standardizedFileURL.path {
      print("不能用正式的 \(SquirrelApp.userDir.path)：正在跑的輸入法也開著它。請複製一份到別的資料夾。")
      exit(2)
    }
    return userDir
  }

  /// 用 App 自己的 librime 開沙盒、部署一次；回傳部署函式（設定視窗改了檔案之後用）
  static func startRime(_ userDir: URL) -> (RimeApi_stdbool, PenglaiSettingsModel.Deployer) {
    let rimeAPI: RimeApi_stdbool = rime_get_api_stdbool().pointee
    let logDir = userDir.appendingPathComponent("log", isDirectory: true)
    try? FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
    var traits = RimeTraits.rimeStructInit()
    traits.setCString(Bundle.main.sharedSupportPath!, to: \.shared_data_dir)
    traits.setCString(userDir.path, to: \.user_data_dir)
    traits.setCString(logDir.path, to: \.log_dir)
    traits.setCString("Sable", to: \.distribution_code_name)
    traits.setCString("貂毫", to: \.distribution_name)
    traits.setCString(Bundle.main.object(forInfoDictionaryKey: kCFBundleVersionKey as String) as? String ?? "0", to: \.distribution_version)
    traits.setCString("rime.sable.settings", to: \.app_name)
    rimeAPI.setup(&traits)
    rimeAPI.initialize(nil)
    let started = Date()
    _ = rimeAPI.start_maintenance(true)
    rimeAPI.join_maintenance_thread()
    _ = rimeAPI.deploy_config_file("sable.yaml", "config_version")
    print("沙盒部署完成（\(String(format: "%.1f", Date().timeIntervalSince(started))) 秒）：\(userDir.path)")

    let deployer: PenglaiSettingsModel.Deployer = { onlySquirrel, completion in
      if !onlySquirrel {
        // 輸入法程序部署時整個重開（finalize），session 全部關掉；這裡也先關，不然開著的 session 部署後查不到詞
        rimeAPI.cleanup_all_sessions()
        _ = rimeAPI.start_maintenance(true)
        rimeAPI.join_maintenance_thread()
      }
      completion(rimeAPI.deploy_config_file("sable.yaml", "config_version"))
    }
    return (rimeAPI, deployer)
  }

  static func run(_ args: [String]) {
    let options = parse(args)
    let userDir = sandbox(options, usage: "用法：Sable --settings --user-dir <沙盒資料夾> [--snapshot <資料夾>] [--script <步驟>] [--page <頁>]")
    let (rimeAPI, deployer) = startRime(userDir)
    let catalogURL = options["catalog"].map { URL(fileURLWithPath: $0) }
      ?? Bundle.main.url(forResource: "penglai-settings", withExtension: "json")
    let model = PenglaiSettingsModel(userDir: userDir, sharedDir: Bundle.main.sharedSupportURL, catalogURL: catalogURL, deployer: deployer)
    if let page = options["page"].flatMap(PenglaiSettingsModel.Page.init(rawValue:)) { model.page = page }
    let probe = PenglaiProbeSession()
    model.liveOptions = { probe.set($0) }

    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    let controller = PenglaiSettingsWindowController(model: model)

    if let script = options["script"] {
      for step in script.components(separatedBy: ";").map({ $0.trimmingCharacters(in: .whitespaces) }) where !step.isEmpty {
        let result = perform(step, on: model, probe: probe)
        waitForDeploy(model)
        print("步驟 \(step)：\(result)；狀態 \(describe(model.status))；歷史 \(model.history.count) 筆" + (model.message.map { "；訊息 \($0)" } ?? ""))
      }
      model.reload()
      for key in ["style/candidate_list_layout", "style/font_point", "style/inline_preedit", "style/inline_candidate", "status_icon/show", "style/color_scheme"] {
        if let row = model.row(key, config: .squirrel) { print("生效值 sable \(key) = \(row.effective ?? "（沒寫）")；\(describe(row.source))") }
      }
      for key in ["menu/page_size", "translator/revert_learning_seconds", "translator/max_user_phrase_syllables", "translator/max_sentences",
                  PenglaiSettingsModel.reverseLookupKey, PenglaiSettingsModel.englishKey] {
        if let row = model.schemaRow(key) { print("生效值 \(model.schemaID) \(key) = \(row.effective ?? "（沒寫）")；\(describe(row.source))") }
      }
      for recipe in model.catalog?.recipes ?? [] { print("功能開關 \(recipe.id) = \(model.recipeState(recipe))") }
      let reading = model.readingState
      print("讀音：存的是 \(reading.choice.map { PenglaiCopy.readingOption($0).title } ?? "（沒有）")" + (model.readingSwitch.map { sw in
        let key = PenglaiReading.resetKey(sw.index)
        return "；方案 custom 檔 \(key) = \(model.store.read(PenglaiConfigID.schema(model.schemaID).customFile).value(key) ?? "（沒寫）")"
          + "；部署後 reset = \(sw.deployed.map(String.init) ?? "（沒有）")"
      } ?? "；方案沒有讀音選項") + (reading.note.map { "；提醒 \($0)" } ?? ""))
      let prediction = model.predictionState
      print("聯想：\(prediction.on.map { $0 ? "開" : "關" } ?? "（沒有）")" + (model.predictionSwitch.map { sw in
        let key = PenglaiReading.resetKey(sw.index)
        return "；方案 custom 檔 \(key) = \(model.store.read(PenglaiConfigID.schema(model.schemaID).customFile).value(key) ?? "（沒寫）")"
          + "；部署後 reset = \(sw.deployed.map(String.init) ?? "（沒有）")；聯想資料 \(model.predictionData ? "有" : "沒有")"
      } ?? "；方案沒有聯想開關") + (prediction.note.map { "；提醒 \($0)" } ?? ""))
      print(shortcuts(model))
      print("方案清單 = \(model.activeSchemas.joined(separator: ","))；方案頁列出 = \(model.schemas.map(\.id).joined(separator: ","))")
      print("沒人讀的設定：" + model.rows.filter { $0.unknownLine != nil }.map { "\($0.file ?? "") 第 \($0.unknownLine!) 行 \($0.key)" }.joined(separator: "、"))
      print("外掛模組：" + model.rows.filter { $0.group == PenglaiSettingsModel.pluginGroup }
        .map { "\($0.key) = \($0.shownValue ?? "（沒值）")（\($0.described ? $0.title : "沒說明")；\(describe($0.source))）" }.joined(separator: "、"))
      // 進階頁每一類每一組幾列（超過一頁的標出來）、沒分到類的、不列的、同一組裡標題重複的
      let advanced = model.advancedRows
      print("進階頁：" + model.advancedSections.map { section in
        let segments = model.advancedSegments(section.id).map { segment -> String in
          let count = advanced.filter { $0.place.section == section.id && $0.place.segment == segment.id }.count
          return "\(segment.title) \(count)" + (count > PenglaiSettingsModel.rowsPerPage ? "（超過一頁）" : "")
        }
        return "\(section.title) \(advanced.filter { $0.place.section == section.id }.count) 列" + (segments.count > 1 ? "（" + segments.joined(separator: "、") + "）" : "")
      }.joined(separator: "、"))
      let unplaced = advanced.filter { $0.place.section == PenglaiAdvanced.otherSection && $0.place.order % 10_000 == 99 }
      print("進階頁沒分到類的（列在其他）：" + unplaced.map(\.row.key).joined(separator: "、"))
      print("進階頁不列的：" + model.rows.filter { $0.presentable && PenglaiAdvanced.place($0, model: model) == nil }.map(\.key).joined(separator: "、"))
      print("進階頁標題重複：" + Dictionary(grouping: advanced, by: { "\($0.place.section)|\($0.place.segment)|\(model.displayTitle($0.row))" })
        .filter { $0.value.count > 1 }.map { "\(model.displayTitle($0.value[0].row))（" + $0.value.map(\.row.key).joined(separator: "、") + "）" }.sorted().joined(separator: "、"))
      print("進階頁的列：" + advanced.map { "\(model.advancedLocation($0.row) ?? "")｜\(model.displayTitle($0.row))" + (PenglaiAdvanced.hint($0.row, model: model).map { "（\($0)）" } ?? "") }
        .joined(separator: "、"))
      print("全部設定：\(model.rows.filter { $0.unknownLine == nil }.count) 列，其中檔案都沒寫的 \(model.hiddenCount) 列；改過的 \(model.rows.filter { $0.isUserSet && $0.unknownLine == nil }.count) 列")
    }

    if let snapshotDir = options["snapshot"] {
      let dir = URL(fileURLWithPath: snapshotDir, isDirectory: true)
      try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
      offscreen = options["offscreen"] != nil
      if offscreen {
        // 放在螢幕外、不搶前景：截圖時正在別的程式打字也不受影響
        app.setActivationPolicy(.accessory)
        controller.window?.setFrameOrigin(NSPoint(x: -20_000, y: -20_000))
        controller.window?.orderFrontRegardless()
      } else {
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        app.activate(ignoringOtherApps: true)
      }
      let pages: [(PenglaiSettingsModel.Page, PenglaiSettingsModel.Filter?)] = model.sidebarPages.map { ($0, nil) }
        + [(.all, .changed)]
      for (page, filter) in pages {
        model.page = page
        if let filter { model.filter = filter; model.pageIndex = 0 } else { model.filter = .all }
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        let name = page.rawValue + (filter.map { "-" + $0.rawValue } ?? "")
        save(controller.window, to: dir.appendingPathComponent("\(name).png"))
      }
      // 進階頁每一類每一組都截（all-<類>-<組>.png；超過一頁的再加 -<第幾頁>）
      for section in model.advancedSections {
        for segment in model.advancedSegments(section.id) {
          model.openAdvanced(section.id, segment: segment.id)
          for index in 0..<model.pageCount {
            model.pageIndex = index
            RunLoop.current.run(until: Date().addingTimeInterval(0.6))
            let suffix = model.pageCount > 1 ? "-\(index + 1)" : ""
            save(controller.window, to: dir.appendingPathComponent("all-\(section.id)-\(segment.id)\(suffix).png"))
          }
        }
      }
      model.advancedSection = nil
      // --search <字>：搜尋結果一張，點第一項跳過去（那一列閃著）再一張
      if let query = options["search"] {
        model.searchText = query
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        save(controller.window, to: dir.appendingPathComponent("search.png"))
        if let first = PenglaiSearch.results(query, model: model).first {
          model.go(to: first)
          RunLoop.current.run(until: Date().addingTimeInterval(0.8))
          save(controller.window, to: dir.appendingPathComponent("search-go.png"))
        }
      }
      print("截圖存在 \(dir.path)，視窗編號 \(controller.window?.windowNumber ?? 0)")
      rimeAPI.finalize()
      exit(0)
    }
    if options["script"] != nil && options["show"] == nil {
      rimeAPI.finalize()
      exit(0)
    }
    controller.showWindow(nil)
    controller.window?.makeKeyAndOrderFront(nil)
    app.activate(ignoringOtherApps: true)
    NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: controller.window, queue: .main) { _ in
      rimeAPI.finalize()
      exit(0)
    }
    app.run()
  }

  /// 視窗存成 PNG：先用系統的 screencapture 擷取真正的畫面；沒有螢幕錄影權限時退回自己畫整個視窗框（含背景）。
  /// --offscreen：視窗在螢幕外，系統截圖抓不到，直接自己畫
  static var offscreen = false

  static func save(_ window: NSWindow?, to url: URL) {
    guard let window else { return }
    if offscreen {
      draw(window, to: url)
      return
    }
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    task.arguments = ["-x", "-o", "-l\(window.windowNumber)", url.path]
    try? task.run()
    task.waitUntilExit()
    if let size = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int, size > 10_000 { return }
    draw(window, to: url)
  }

  static func draw(_ window: NSWindow, to url: URL) {
    guard let view = window.contentView?.superview ?? window.contentView else { return }
    view.layoutSubtreeIfNeeded()
    guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
    view.cacheDisplay(in: view.bounds, to: rep)
    try? rep.representation(using: .png, properties: [:])?.write(to: url)
  }

  static func waitForDeploy(_ model: PenglaiSettingsModel) {
    let deadline = Date().addingTimeInterval(30)
    RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    while model.status == .applying && Date() < deadline {
      RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    }
  }

  private static func describe(_ status: PenglaiSettingsModel.Status) -> String {
    switch status {
    case .idle: return "沒動"
    case .applying: return "套用中"
    case .applied: return "已套用"
    case .failed(let text): return "失敗（\(text)）"
    }
  }

  private static func describe(_ source: PenglaiSettingRow.Source) -> String {
    switch source {
    case .userFile(let file, let line): return "寫在 \(file) 第 \(line) 行"
    case .shipped: return "方案檔或官方預設"
    case .builtin: return "程式內建"
    }
  }

  /// 快速鍵：每件事用哪個鍵（畫面上的標籤）、寫在哪裡、有沒有撞到
  static func shortcuts(_ model: PenglaiSettingsModel) -> String {
    "快速鍵 " + PenglaiShortcuts.keys.compactMap { key -> String? in
      guard let row = model.schemaRow(key) else { return nil }
      let value = model.shortcutValue(row)
      return "\(model.displayTitle(row))＝\(row.info?.labels?[value] ?? PenglaiSettingsModel.display(value))"
        + (row.isUserSet ? "（自訂）" : "") + (model.shortcutConflict(row).map { "〔\($0)〕" } ?? "")
    }.joined(separator: "、") + (model.schemaCustomDeployed() ? "" : "；方案 custom 檔這一版還沒部署")
  }

  /// 每一步呼叫的都是畫面按鈕背後的同一個函式。
  private static func perform(_ step: String, on model: PenglaiSettingsModel, probe: PenglaiProbeSession) -> String {
    let parts = step.components(separatedBy: "=")
    let name = parts[0]
    let value = parts.count > 1 ? parts.dropFirst().joined(separator: "=") : ""
    func squirrelRow(_ key: String) -> PenglaiSettingRow? { model.row(key, config: .squirrel) }
    switch name {
    case "layout":
      guard let row = squirrelRow("style/candidate_list_layout") else { return "找不到" }
      model.set(row, .string(value))
    case "font":
      guard let row = squirrelRow("style/font_point") else { return "找不到" }
      model.set(row, .int(Int(value) ?? 16))
    case "inline":
      guard let preedit = squirrelRow("style/inline_preedit"), let candidate = squirrelRow("style/inline_candidate") else { return "找不到" }
      let hanzi = value == "hanzi"
      model.setPair([(preedit, .bool(!hanzi)), (candidate, .bool(hanzi))], summary: "文件裡顯示：\(hanzi ? "漢字" : "注音")")
    case "icon":
      guard let row = squirrelRow("status_icon/show") else { return "找不到" }
      model.set(row, .bool(value == "true"))
    case "color", "color_dark":
      guard let row = squirrelRow(name == "color" ? "style/color_scheme" : "style/color_scheme_dark") else { return "找不到" }
      model.set(row, .string(value))
    case "page_size", "revert", "phrase", "sentences":
      let key = ["page_size": "menu/page_size", "revert": "translator/revert_learning_seconds",
                 "phrase": "translator/max_user_phrase_syllables", "sentences": "translator/max_sentences"][name]!
      guard let row = model.schemaRow(key) else { return "找不到 \(key)" }
      model.set(row, .int(Int(value) ?? 0))
    case "recipe":
      guard let recipe = model.catalog?.recipes.first else { return "沒有功能開關" }
      model.setRecipe(recipe, enable: value == "on")
    case "reverse_lookup":
      guard model.reverseLookupPattern != nil else { return "方案沒有掛反查，或讀不到原本的規則" }
      model.setReverseLookup(value == "on")
    case "english":
      guard model.englishLexicon != nil else { return "方案沒有中英混輸（english_lexicon），或讀不到方案原檔" }
      model.setEnglish(value == "on")
    case "prediction":
      // prediction=on|off：輸入頁「聯想」開關
      guard model.predictionSwitch != nil else { return "方案沒有聯想開關（switches 裡 name: prediction）" }
      guard model.predictionState.enabled else { return "改不了聯想：\(model.predictionState.note ?? "")" }
      model.setPrediction(value == "on")
      return probe.composing().map { "ok；部署前 \($0)" } ?? "ok"
    case "reading":
      // reading=penglai|zhongzhou|jianshou：讀音頁點那張卡片
      let option = value.hasPrefix("reading_") ? value : "reading_" + value
      guard model.readingState.enabled else { return "改不了讀音：\(model.readingState.note ?? "")" }
      guard model.readingState.options.contains(option) else { return "方案沒有 \(option)" }
      model.setReading(option)
      return probe.composing().map { "ok；部署前 \($0)" } ?? "ok"
    case "type", "fresh":
      return probe.type(value, fresh: name == "fresh")
    case "keys":
      return probe.keys(value)
    case "select":
      return probe.select(value)
    case "panel":
      return probe.panel(to: URL(fileURLWithPath: value))
    case "schema+", "schema-":
      var list = model.activeSchemas
      if name == "schema+" { list.append(value) } else { list.removeAll { $0 == value } }
      model.setSchemaList(list)
    case "reset":
      guard let row = model.rows.first(where: { $0.key == value && $0.isUserSet }) else { return "找不到 \(value)" }
      model.resetToDefault(row)
    case "set":
      // set=<sable|default|schema>:<key>:<值>
      let fields = value.components(separatedBy: ":")
      guard fields.count >= 3 else { return "格式：set=<設定>:<鍵>:<值>" }
      let config: PenglaiConfigID = fields[0] == "sable" ? .squirrel : fields[0] == "default" ? .defaultConfig : .schema(model.schemaID)
      guard let row = model.row(fields[1], config: config) else { return "找不到 \(fields[1])" }
      let text = fields.dropFirst(2).joined(separator: ":")
      switch row.type {
      case "bool": model.set(row, .bool(text == "true"))
      case "int": model.set(row, .int(Int(text) ?? 0))
      case "double": model.set(row, .double(Double(text) ?? 0))
      default: model.set(row, .string(text))
      }
    case "key":
      // key=<設定鍵>:<值>：快速鍵那一列的分段按鈕（選了別人的鍵就對調），值空白＝關；印出每件事現在用哪個鍵
      let fields = value.components(separatedBy: ":")
      guard fields.count == 2 else { return "格式：key=<鍵>:<值>" }
      guard PenglaiShortcuts.keys.contains(fields[0]), let row = model.schemaRow(fields[0]) else { return "不是快速鍵或方案沒有：\(fields[0])" }
      guard row.info?.options?.contains(where: { $0.text == fields[1] }) == true else { return "沒有這個選項：\(fields[1])" }
      model.setShortcut(row, fields[1])
      waitForDeploy(model)
      model.reload()
      return "ok；" + shortcuts(model)
    case "key_reset":
      guard PenglaiShortcuts.keys.contains(value), let row = model.schemaRow(value), row.isUserSet else { return "沒自訂過：\(value)" }
      model.resetToDefault(row)
      waitForDeploy(model)
      model.reload()
      return "ok；" + shortcuts(model)
    case "search":
      // 搜尋欄打這些字，印出結果（標題→頁）
      model.searchText = value
      let results = PenglaiSearch.results(value, model: model)
      return results.isEmpty ? "沒有結果" : "\(results.count) 項：" + results.map { "\($0.title)→\($0.location ?? $0.page.title)" }.joined(separator: "、")
    case "go":
      // 點目前搜尋結果的第幾項（1 起算），印出跳到哪裡
      let results = PenglaiSearch.results(model.searchText, model: model)
      guard let number = Int(value), (1...results.count).contains(number) else { return "沒有第 \(value) 項" }
      model.go(to: results[number - 1])
      return "跳到 \(model.page.title)" + (model.page == .all ? "／\(model.advancedSection.flatMap(PenglaiAdvanced.section)?.title ?? "總覽")"
        + (model.advancedSegments(model.advancedSection ?? "").count > 1 ? "／\(model.advancedSegments(model.advancedSection ?? "").first { $0.id == model.advancedSegment }?.title ?? "")" : "")
        + " 第 \(model.pageIndex + 1) 頁" : "")
        + (model.page == .colors ? (model.colorsDark ? "／深色" : "／淺色") : "") + "，閃 \(model.highlight ?? "（沒有）")"
        + (model.page == .all ? (model.visibleRows.contains { model.displayTitle($0) == model.highlight } ? "，那一頁看得到" : "，那一頁看不到") : "")
    case "undo":
      model.undoLast()
    case "undo_all":
      guard let first = model.history.first else { return "沒有歷史" }
      model.undo(through: first.id)
    default:
      return "不認得這一步"
    }
    return "ok"
  }
}

/// 沙盒視窗自己開的一個 session，模擬正在打字的輸入框：讀音改了它馬上跟著換（model.liveOptions），
/// 新開的照部署後的方案設定選項（--script 的 type=、fresh=）
final class PenglaiProbeSession {
  private let rimeAPI: RimeApi_stdbool = rime_get_api_stdbool().pointee
  private var session: RimeSessionId = 0

  func set(_ options: [String: Bool]) {
    guard session != 0, rimeAPI.find_session(session) else { return }
    for (name, value) in options { rimeAPI.set_option(session, name, value) }
  }

  /// 清掉組字、打一串鍵，回傳第一頁候選（帶序號）和讀音選項。不送出（不學習），留在組字中
  func type(_ keys: String, fresh: Bool) -> String {
    if fresh, session != 0 {
      _ = rimeAPI.destroy_session(session)
      session = 0
    }
    var created = false
    if session == 0 || !rimeAPI.find_session(session) {
      session = rimeAPI.create_session()
      created = true
    }
    guard session != 0 else { return "開不了 session" }
    rimeAPI.clear_composition(session)
    _ = rimeAPI.simulate_key_sequence(session, keys)
    return "\(created ? "新開的" : "開著的") session 打 \(keys.debugDescription)：\(describe())"
  }

  /// 不清組字，接著打一串鍵，回傳第一頁候選
  func keys(_ keys: String) -> String {
    guard session != 0, rimeAPI.find_session(session) else { return "沒有開著的 session（先 type= 或 fresh=）" }
    _ = rimeAPI.simulate_key_sequence(session, keys)
    return "接著打 \(keys.debugDescription)：組字區「\(preedit())」；\(describe())"
  }

  /// 選這一頁文字是 text 的候選，回傳選完的組字區和第一頁候選
  func select(_ text: String) -> String {
    guard session != 0, rimeAPI.find_session(session) else { return "沒有開著的 session（先 type= 或 fresh=）" }
    var found: Int?
    var ctx = RimeContext_stdbool.rimeStructInit()
    if rimeAPI.get_context(session, &ctx) {
      for index in 0..<Int(ctx.menu.num_candidates) where ctx.menu.candidates[index].text.map({ String(cString: $0) }) == text {
        found = index
        break
      }
      _ = rimeAPI.free_context(&ctx)
    }
    guard let found else { return "這一頁沒有「\(text)」：\(describe())" }
    _ = rimeAPI.select_candidate_on_current_page(session, found)
    return "選了「\(text)」：組字區「\(preedit())」；\(describe())"
  }

  /// 照組字中的狀態畫一張選字窗（照部署後的外觀設定）。跟正式打字時一樣帶軟游標，組字區照 inline_preedit 關掉時的樣子
  func panel(to url: URL) -> String {
    guard session != 0, rimeAPI.find_session(session) else { return "沒有開著的 session（先 type= 或 fresh=）" }
    rimeAPI.set_option(session, "soft_cursor", true)
    var ctx = RimeContext_stdbool.rimeStructInit()
    guard rimeAPI.get_context(session, &ctx) else { return "讀不到組字" }
    defer { _ = rimeAPI.free_context(&ctx) }
    let preedit = ctx.composition.preedit.map { String(cString: $0) } ?? ""
    let utf8 = preedit.utf8
    let index = { (offset: Int32) in String.Index(utf8.index(utf8.startIndex, offsetBy: Int(offset)), within: preedit) ?? preedit.startIndex }
    let start = index(ctx.composition.sel_start), end = index(ctx.composition.sel_end), caret = index(ctx.composition.cursor_pos)
    var candidates = [String](), comments = [String](), labels = [String]()
    for i in 0..<Int(ctx.menu.num_candidates) {
      candidates.append(ctx.menu.candidates[i].text.map { String(cString: $0) } ?? "")
      comments.append(ctx.menu.candidates[i].comment.map { String(cString: $0) } ?? "")
    }
    if let keys = ctx.menu.select_keys {
      labels = String(cString: keys).map { String($0) }
    } else if let selectLabels = ctx.select_labels {
      for i in 0..<Int(ctx.menu.page_size) { labels.append(selectLabels[i].map { String(cString: $0) } ?? "") }
    }
    let config = SquirrelConfig()
    guard config.openBaseConfig() else { return "讀不到 sable 設定" }
    let panel = SquirrelPanel(position: .zero)
    panel.load(config: config, forDarkMode: false)
    panel.load(config: config, forDarkMode: true)
    config.close()
    panel.update(preedit: preedit, selRange: NSRange(location: start.utf16Offset(in: preedit), length: preedit.utf16.distance(from: start, to: end)),
                 caretPos: caret.utf16Offset(in: preedit), candidates: candidates, comments: comments, labels: labels,
                 highlighted: Int(ctx.menu.highlighted_candidate_index), page: Int(ctx.menu.page_no), lastPage: ctx.menu.is_last_page, update: true)
    // update 會照游標位置擺出來；回到 run loop 之前就變透明、移到螢幕外，畫面上不會閃
    panel.alphaValue = 0
    panel.setFrameOrigin(NSPoint(x: -20_000, y: -20_000))
    RunLoop.current.run(until: Date().addingTimeInterval(0.3))
    PenglaiSettingsStandalone.draw(panel, to: url)
    panel.orderOut(nil)
    return "存成 \(url.path)：組字區「\(preedit)」"
  }

  private func preedit() -> String {
    var ctx = RimeContext_stdbool.rimeStructInit()
    guard rimeAPI.get_context(session, &ctx) else { return "" }
    defer { _ = rimeAPI.free_context(&ctx) }
    return ctx.composition.preedit.map { String(cString: $0) } ?? ""
  }

  /// 組字中的候選（不重打）；沒有在組字就 nil
  func composing() -> String? {
    guard session != 0, rimeAPI.find_session(session), let input = rimeAPI.get_input(session), input.pointee != 0 else { return nil }
    return "組字中的候選：\(describe())"
  }

  private func describe() -> String {
    var candidates: [String] = []
    var ctx = RimeContext_stdbool.rimeStructInit()
    if rimeAPI.get_context(session, &ctx) {
      for index in 0..<Int(ctx.menu.num_candidates) {
        candidates.append("\(index + 1).\(ctx.menu.candidates[index].text.map { String(cString: $0) } ?? "")")
      }
      _ = rimeAPI.free_context(&ctx)
    }
    let states = (PenglaiReading.options + [PenglaiSettingsModel.predictionOption])
      .map { "\($0)=\(rimeAPI.get_option(session, $0) ? "開" : "關")" }.joined(separator: " ")
    return "\(candidates.joined(separator: " "))；\(states)"
  }
}
