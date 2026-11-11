//
//  PenglaiSettingsView.swift
//  Squirrel
//
//  蓬萊設定視窗的畫面。版面照 macOS 系統設定：左邊側欄換頁，右邊分組表單，每列左邊是名稱和一句說明、右邊是控制項。
//  畫面上不出現設定檔：檔名、行號、設定鍵都不顯示，也沒有「打開檔案」；寫不了的項目只說這裡改不了。
//  一根手指能操作：每個設定點一下就完成（開關、分段按鈕、−／＋、色塊），不用下拉選單、滑桿、拖拉、組合鍵；
//  每頁放得下不捲動，「進階」用上一頁、下一頁翻。
//  側欄照一般輸入法設定的排法分四組（11/11）：打字（一般、讀音、打錯修正、標點符號、按鍵）、外觀（選字窗、配色）、
//  詞庫和輸入方案、進階和變更紀錄。每一頁最上面是常用的幾項；同一件事的細項用頁首底下的分頁列換（選字窗的字型、
//  按鍵的快速鍵），不用再到「進階」找。細項照舊登記在 PenglaiAdvanced 的分類表，表裡寫它掛在哪一頁。
//

import AppKit
import SwiftUI

// MARK: - 文案

/// 主頁每一項的名稱、說明和搜尋用的別名。頁面和搜尋都從這裡拿，兩邊寫的字才會一樣。
struct PenglaiCopyItem {
  var title: String
  var desc: String?
  var keywords: [String] = []
}

enum PenglaiCopy {
  static let layout = PenglaiCopyItem(title: "候選排列", desc: "直式一行一個候選，橫式排成一列。", keywords: ["直式", "橫式", "直排", "橫排", "方向"])
  static let fontSize = PenglaiCopyItem(title: "字級", desc: "候選字的大小（點）。", keywords: ["字體", "字型大小", "字的大小", "放大", "縮小"])
  static let pageSize = PenglaiCopyItem(title: "每頁候選數", desc: "一頁列出幾個候選字，其餘的翻頁再看。", keywords: ["候選數", "一頁幾個", "翻頁"])
  static let inlineMode = PenglaiCopyItem(title: "打字時游標處顯示", desc: "選「候選字」時，游標處直接顯示會送出的字，注音改在選字窗上方顯示。",
                                          keywords: ["組字", "內嵌", "預覽", "注音顯示", "游標"])
  static let statusIcon = PenglaiCopyItem(title: "顯示中／英狀態圖示", desc: "在選單列顯示目前是中文還是英文模式。", keywords: ["選單列", "圖示", "中西", "狀態"])
  static let english = PenglaiCopyItem(title: "中英混輸", desc: "中文組不成句時，自動改用英文單字，或照原樣輸出按下的字母、數字。",
                                       keywords: ["英文", "混打", "字母", "數字"])
  static let prediction = PenglaiCopyItem(title: "聯想", desc: "送出之後，在選字窗列出接下來可能要打的詞，用 ⇧數字、數字選字（預設 ↓ 再按數字）或點一下選。直接打字、按 Return 或空白鍵就照常。",
                                          keywords: ["預測", "聯想詞", "下一個詞", "接下來", "接著打", "自動完成"])
  static let spacePunct = PenglaiCopyItem(title: "送出之後按空白補標點", desc: "中文送出之後按空白，補上「，」，像問句時補「？」。緊接著再按一次空白換成空白。",
                                          keywords: ["標點", "逗號", "問號", "句號", "空白鍵", "自動標點", "猜標點"])
  static let longPress = PenglaiCopyItem(title: "長按出符號", desc: "數字鍵和 , . / ; - 按著不放，打出按 Shift 的那個符號：. 是「。」、/ 是「？」、1 是「！」。按多久算長按，照系統設定的「重複前延遲」。",
                                         keywords: ["長按", "按住", "符號", "標點", "句號", "問號", "冒號", "驚嘆號", "Shift", "不用 Shift"])
  static let keyModel = PenglaiCopyItem(title: "打錯也對得到", desc: "打完整注音時按到旁邊的鍵、漏打聲母或介音、同一鍵連按兩下，也找得到原本要打的詞（ㄧㄝˋ ㄒㄧㄝ˙ → 謝謝）。只打第一個注音時不改。",
                                        keywords: ["容錯", "糾錯", "聲母", "漏打", "打錯", "按錯", "模糊音", "連按"])
  static let fuzzy = PenglaiCopyItem(title: "模糊音", desc: "分不清的注音勾起來：勾了 ㄣㄥ，打 ㄖㄥˊ ㄕㄥ 也找得到「人生」，沒打聲調也行。只勾自己真的會混的那幾對，勾越多，照打本來就對的詞越容易被換掉。",
                                     keywords: ["模糊音", "ㄣㄥ", "前後鼻音", "捲舌", "ㄓㄗ", "ㄕㄙ", "台灣國語", "分不清"])
  static let strokeLookup = PenglaiCopyItem(title: "筆畫查字", desc: "先按 ` 鍵，再用 h s p n z（橫、豎、撇、點、折）打筆畫，查出不知道讀音的字。",
                                            keywords: ["反查", "筆畫", "不會念", "讀音"])
  static let sentences = PenglaiCopyItem(title: "整句候選數", desc: "一次列出幾種不同的整句組合。", keywords: ["整句", "組句"])
  static let phraseLength = PenglaiCopyItem(title: "記住整句的長度", desc: "這個字數以內的句子，打過一次之後就能整句叫回來。", keywords: ["學習", "記憶", "長句"])
  static let revertSeconds = PenglaiCopyItem(title: "取消學習的時限（秒）", desc: "送出後在這段時間內按 ⌫，這次選的字就不會被記住。",
                                             keywords: ["取消學習", "撤銷", "學習", "選錯", "刪除", "BackSpace"])
  static let lightScheme = PenglaiCopyItem(title: "淺色模式配色", desc: "系統是淺色外觀時，選字窗用的顏色。", keywords: ["顏色", "主題", "外觀", "配色"])
  static let darkScheme = PenglaiCopyItem(title: "深色模式配色", desc: "系統是深色外觀時，選字窗用的顏色。", keywords: ["顏色", "主題", "外觀", "配色", "夜間"])
  static let schemes = PenglaiCopyItem(title: "方案選單", desc: "方案選單裡要列出哪些輸入方案。", keywords: ["輸入方案", "方案"])
  static let redeploy = PenglaiCopyItem(title: "重新部署", desc: "重新整理詞典和設定。平常不需要手動執行。", keywords: ["部署", "重新整理", "重新載入", "沒反應"])
  static let cleanup = PenglaiCopyItem(title: "清除沒有作用的設定", desc: "目前的版本已經不會讀這些設定，清掉不影響打字。", keywords: ["清除", "清理", "失效"])
  static let dictionary = PenglaiCopyItem(title: "詞庫", desc: "自己加的詞：英文縮寫、人名、專有名詞，還有隱藏起來的詞。",
                                          keywords: ["自訂詞", "加詞", "新增詞", "造詞", "詞典", "字典", "人名", "專有名詞", "縮寫", "隱藏", "取消隱藏", "刪詞"])
  static let history = PenglaiCopyItem(title: "最近的變更", desc: "從這個視窗做的每一次變更都可以復原。", keywords: ["復原", "還原", "紀錄", "上一步"])

  // 讀音（librime patch 0010）：讀音頁和第一次使用的引導共用
  static let readingPage = PenglaiCopyItem(title: "讀音", desc: "同一個字，各地讀法有時不同。兩邊的讀音都已收錄，這裡只決定先出哪一種。",
                                           keywords: ["發音", "念法", "唸法", "讀法", "多音字", "破音字", "蓬萊音", "中州音", "兼收並蓄"])
  static let readingPenglai = PenglaiCopyItem(title: "蓬萊音", desc: "「期」先出ㄑㄧˊ（預設）", keywords: ["讀音", "預設"])
  static let readingZhongzhou = PenglaiCopyItem(title: "中州音", desc: "「期」先出ㄑㄧ", keywords: ["讀音"])
  static let readingJianshou = PenglaiCopyItem(title: "兼收並蓄", desc: "兩種讀音並列，不分先後", keywords: ["讀音", "並列"])
  static let readingFootnote = "換讀音不影響已經學過的字詞。"
  static let readingLater = "之後可以在蓬萊設定裡更改。"

  /// 方案選項名稱 → 畫面上的名稱和說明
  static func readingOption(_ option: String) -> PenglaiCopyItem {
    switch option {
    case "reading_zhongzhou": return readingZhongzhou
    case "reading_jianshou": return readingJianshou
    default: return readingPenglai
    }
  }

  /// 卡片上例字「期」底下的注音
  static func readingExample(_ option: String) -> String {
    switch option {
    case "reading_zhongzhou": return "ㄑㄧ"
    case "reading_jianshou": return "ㄑㄧˊ　ㄑㄧ"
    default: return "ㄑㄧˊ"
    }
  }
}

// MARK: - 共用元件

/// 分段按鈕：一下選一個。selection 是 nil 時都不亮（例如設定是兩個選項以外的組合）。
struct PenglaiSegmented<Value: Hashable>: View {
  var options: [(Value, String)]
  var selection: Value?
  var enabled = true
  var action: (Value) -> Void

  var body: some View {
    Picker("", selection: Binding<Value?>(get: { selection }, set: { value in
      if let value, value != selection { action(value) }
    })) {
      ForEach(Array(options.enumerated()), id: \.offset) { _, option in
        Text(option.1).tag(Optional(option.0))
      }
    }
    .pickerStyle(.segmented)
    .labelsHidden()
    .controlSize(.large)
    .fixedSize()
    .disabled(!enabled)
  }
}

/// 開關：一下切換。
struct PenglaiSwitch: View {
  var isOn: Bool?
  var enabled = true
  var action: (Bool) -> Void

  var body: some View {
    Toggle("", isOn: Binding(get: { isOn ?? false }, set: { value in
      if value != isOn { action(value) }
    }))
    .toggleStyle(.switch)
    .labelsHidden()
    .disabled(!enabled)
  }
}

/// −／＋：一下加減一格。
struct PenglaiStepper: View {
  var value: Double?
  var step: Double
  var range: ClosedRange<Double>
  var enabled = true
  var unit = ""
  var action: (Double) -> Void

  var body: some View {
    HStack(spacing: 4) {
      Button { change(-step) } label: { Image(systemName: "minus").frame(width: 22, height: 18) }
        .disabled(!enabled || start <= range.lowerBound)
      Text(value.map { Self.format($0) + unit } ?? "—")
        .font(.system(size: 13, weight: .medium).monospacedDigit())
        .frame(minWidth: 44)
      Button { change(step) } label: { Image(systemName: "plus").frame(width: 22, height: 18) }
        .disabled(!enabled || start >= range.upperBound)
    }
    .controlSize(.large)
    .fixedSize()
  }

  /// 沒有值（程式內建、看不出預設）時從 0 起算
  private var start: Double { value ?? min(max(0, range.lowerBound), range.upperBound) }

  private func change(_ delta: Double) {
    let next = min(max(start + delta, range.lowerBound), range.upperBound)
    action((next * 1000).rounded() / 1000)
  }

  static func format(_ value: Double) -> String {
    value == value.rounded() ? String(Int(value)) : String(format: "%.2f", value).replacingOccurrences(of: "0+$", with: "", options: .regularExpression)
  }
}

/// 從搜尋跳過來的那一列閃一下底色（model.highlight 是那一列的標題）。
struct PenglaiHighlight: ViewModifier {
  @EnvironmentObject var model: PenglaiSettingsModel
  var title: String

  func body(content: Content) -> some View {
    content
      .background(RoundedRectangle(cornerRadius: 6).fill(Color.accentColor.opacity(model.highlight == title ? 0.25 : 0)).padding(-6))
      .animation(.easeOut(duration: 0.4), value: model.highlight)
  }
}

extension View {
  func penglaiHighlight(_ title: String) -> some View { modifier(PenglaiHighlight(title: title)) }
}

/// 表單裡的一列：左邊名稱、說明和提醒，右邊「還原預設」和控制項。改不了的項目在名稱旁邊放一個鎖。
struct PenglaiFormRow<Control: View>: View {
  @EnvironmentObject var model: PenglaiSettingsModel
  var title: String
  var desc: String?
  var row: PenglaiSettingRow?
  var note: String?
  var resettable = true
  /// 要先開（或關）別的項目才有作用時，說要先做什麼（灰色，不是警告）
  var hint: String? = nil
  @ViewBuilder var control: () -> Control

  var body: some View {
    LabeledContent {
      HStack(spacing: 10) {
        if resettable, let row, model.canReset(row) {
          Button("還原預設") { model.resetToDefault(row) }.buttonStyle(.link).font(.system(size: 11.5))
        }
        control()
      }
    } label: {
      VStack(alignment: .leading, spacing: 3) {
        HStack(spacing: 5) {
          Text(title)
          if row?.blocked != nil {
            Image(systemName: "lock.fill").font(.system(size: 10)).foregroundStyle(.secondary).help(PenglaiSettingsModel.blockedText)
          }
        }
        if let desc {
          Text(desc).font(.system(size: 11.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        if let warning {
          Label(warning, systemImage: "exclamationmark.triangle.fill").font(.system(size: 11)).foregroundStyle(.orange)
        }
        if let hint {
          Label(hint, systemImage: "arrow.turn.down.right").font(.system(size: 11)).foregroundStyle(.secondary)
        }
      }
    }
    .padding(.vertical, 2)
    .penglaiHighlight(title)
  }

  private var warning: String? {
    if let note { return note }
    guard let row, row.blocked == nil else { return nil }
    if row.pendingValue != nil { return "這項變更還沒生效，可能被其他設定蓋過" }
    return nil
  }
}

extension PenglaiFormRow {
  init(_ item: PenglaiCopyItem, row: PenglaiSettingRow?, note: String? = nil, resettable: Bool = true, @ViewBuilder control: @escaping () -> Control) {
    self.init(title: item.title, desc: item.desc, row: row, note: note, resettable: resettable, control: control)
  }
}

// MARK: - 主畫面

struct PenglaiSettingsView: View {
  @ObservedObject var model: PenglaiSettingsModel

  static let size = CGSize(width: 880, height: 700)

  var body: some View {
    HStack(spacing: 0) {
      sidebar
      Divider()
      VStack(spacing: 0) {
        content.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        Divider()
        statusBar
      }
    }
    .frame(width: Self.size.width, height: Self.size.height)
    .environmentObject(model)
  }

  private var sidebar: some View {
    VStack(alignment: .leading, spacing: 2) {
      HStack(spacing: 10) {
        Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 36, height: 36)
        VStack(alignment: .leading, spacing: 1) {
          Text("蓬萊設定").font(.system(size: 15, weight: .semibold))
          Text(Self.versionText).font(.system(size: 11)).foregroundStyle(.secondary)
        }
      }
      .padding(.horizontal, 8).padding(.bottom, 12)
      searchField.padding(.horizontal, 4).padding(.bottom, 10)
      let listed = model.sidebarPages
      ForEach(Array(PenglaiSettingsModel.sidebarGroups.enumerated()), id: \.offset) { index, group in
        let pages = group.filter(listed.contains)
        if !pages.isEmpty {
          // 組和組之間留空，不加標題（跟系統設定一樣）
          if index > 0 { Color.clear.frame(height: 8) }
          ForEach(pages) { page in sidebarButton(page) }
        }
      }
      Spacer()
      if !model.schemaName.isEmpty {
        Text("目前方案：\(model.schemaName)").font(.system(size: 11)).foregroundStyle(.secondary).padding(.horizontal, 8)
      }
    }
    .padding(.horizontal, 10).padding(.top, 18).padding(.bottom, 12)
    .frame(width: 200)
    .background(Color(nsColor: .underPageBackgroundColor).opacity(0.5))
  }

  private func sidebarButton(_ page: PenglaiSettingsModel.Page) -> some View {
    let selected = model.page == page && model.searchText.isEmpty
    return Button {
      model.searchText = ""
      // 點側欄一律回到那一頁的最上層（進階頁回總覽，有分頁列的回第一個分頁）
      if model.page == page { model.showHome() } else { model.page = page }
    } label: {
      HStack(spacing: 9) {
        Group {
          if let glyph = page.glyph { Text(glyph).font(.system(size: 13, weight: .bold)) } else { Image(systemName: page.symbol) }
        }
          .font(.system(size: 12, weight: .semibold)).foregroundColor(.white)
          .frame(width: 22, height: 22)
          .background(RoundedRectangle(cornerRadius: 5).fill(page.tint.gradient))
        Text(page.title).font(.system(size: 13)).foregroundColor(selected ? .white : .primary)
        Spacer(minLength: 0)
      }
      .padding(.horizontal, 8)
      .frame(height: 32)
      .background(RoundedRectangle(cornerRadius: 7).fill(selected ? Color.accentColor : Color.clear))
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }

  /// 搜尋欄：點進去打字就搜；右邊的 ⓧ 一下清掉（不用組合鍵）
  private var searchField: some View {
    HStack(spacing: 6) {
      Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
      TextField("搜尋設定", text: $model.searchText).textFieldStyle(.plain)
      if !model.searchText.isEmpty {
        Button { model.searchText = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
          .buttonStyle(.plain).help("清除搜尋")
      }
    }
    .font(.system(size: 13))
    .padding(.horizontal, 8).frame(height: 30)
    .background(RoundedRectangle(cornerRadius: 7).fill(Color(nsColor: .textBackgroundColor).opacity(0.6)))
    .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color(nsColor: .separatorColor)))
  }

  @ViewBuilder private var content: some View {
    if !model.searchText.trimmingCharacters(in: .whitespaces).isEmpty {
      PenglaiSearchPage()
    } else {
      pageContent
    }
  }

  @ViewBuilder private var pageContent: some View {
    VStack(alignment: .leading, spacing: 0) {
      VStack(alignment: .leading, spacing: 4) {
        if let back = header.back {
          Button {
            model.showHome()
          } label: {
            HStack(spacing: 3) {
              Image(systemName: "chevron.left").font(.system(size: 11, weight: .semibold))
              Text(back)
            }
          }
          .buttonStyle(.link)
          .font(.system(size: 12.5))
          .padding(.bottom, 2)
        }
        Text(header.title).font(.system(size: 20, weight: .bold))
        Text(header.subtitle).font(.system(size: 12)).foregroundStyle(.secondary)
      }
      .padding(.horizontal, 30).padding(.top, header.back == nil ? 18 : 12)
      switch model.page {
      case .typing: PenglaiGeneralPage()
      case .reading: PenglaiReadingPage()
      case .correction: PenglaiTabbedPage { PenglaiCorrectionPage() }
      case .punct: PenglaiTabbedPage { PenglaiPunctPage() }
      case .keys: PenglaiTabbedPage { EmptyView() }
      case .panel: PenglaiTabbedPage { PenglaiPanelPage() }
      case .colors: PenglaiColorsPage()
      case .dictionary: PenglaiDictionaryPage()
      case .schemas: PenglaiSchemasPage()
      case .all: PenglaiAdvancedPage()
      case .history: PenglaiHistoryPage()
      }
    }
  }

  /// 頁首的標題、說明；進階頁的分類和已自訂列表多一個回總覽的連結
  private var header: (title: String, subtitle: String, back: String?) {
    if model.page == .all {
      if model.filter == .changed {
        return ("已自訂的項目", "改過預設值的細項，每一頁的都列在這裡。點「還原預設」就回到原本的值。", model.page.title)
      }
      if let id = model.advancedSection, let section = PenglaiAdvanced.section(id), section.page == .all {
        return (section.title, section.desc + "。", model.page.title)
      }
    }
    return (model.page.title, model.page.subtitle, nil)
  }

  private var statusBar: some View {
    HStack(spacing: 10) {
      switch model.status {
      case .idle: Text("變更會立即套用").foregroundStyle(.secondary)
      case .applying:
        ProgressView().controlSize(.small)
        Text("套用中…").foregroundStyle(.secondary)
      case .applied(let date):
        Label("已套用（\(Self.time(date))）", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
      case .failed(let text): Label(text, systemImage: "xmark.octagon.fill").foregroundStyle(.red).lineLimit(1)
      }
      if let message = model.message, model.status != .failed(message) {
        Text(message).foregroundStyle(.orange).lineLimit(1)
      }
      Spacer()
      Button("復原上一步") { model.undoLast() }.disabled(model.history.isEmpty).controlSize(.large)
    }
    .font(.system(size: 12))
    .padding(.horizontal, 20)
    .frame(height: 48)
  }

  static var versionText: String {
    let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    return version.isEmpty ? "貂毫" : "貂毫 \(version)"
  }

  static func time(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = Calendar.current.isDateInToday(date) ? "HH:mm:ss" : "M/d HH:mm"
    return formatter.string(from: date)
  }
}

extension PenglaiSettingsModel.Page {
  var subtitle: String {
    switch self {
    case .typing: return "打字時的輔助功能，還有整句怎麼組、打過的怎麼記住。"
    case .reading: return PenglaiCopy.readingPage.desc ?? ""
    case .correction: return "按到旁邊的鍵、漏打、分不清的音，也找得到原本要打的詞。"
    case .punct: return "不按 Shift 也打得出標點：送出之後按空白、按著不放、連打。"
    case .keys: return "空白鍵、選字鍵、Caps Lock 怎麼用，還有快速鍵。"
    case .panel: return "候選字視窗的版面、字型和顯示方式。"
    case .colors: return "選字窗的顏色，淺色和深色模式各選一個。"
    case .dictionary: return PenglaiCopy.dictionary.desc ?? ""
    case .schemas: return "方案選單裡要列出哪些輸入方案。"
    case .all: return "比較少用到的項目，依用途分類。一般使用不需要更動。"
    case .history: return "從這個視窗做的每一次變更都可以復原。"
    }
  }

  var tint: Color {
    switch self {
    case .typing: return .gray
    case .reading: return .teal
    case .correction: return .purple
    case .punct: return .green
    case .keys: return .orange
    case .panel: return .blue
    case .colors: return .pink
    case .dictionary: return .brown
    case .schemas: return .cyan
    case .all: return Color(red: 0.36, green: 0.38, blue: 0.45)
    case .history: return .indigo
    }
  }
}

/// 表單共用的外觀：分組、跟頁首對齊、不要多餘的捲動。
private extension View {
  func penglaiForm() -> some View {
    formStyle(.grouped).scrollDisabled(true).padding(.horizontal, 10)
  }
}

// MARK: - 選字窗

struct PenglaiPanelPage: View {
  @EnvironmentObject var model: PenglaiSettingsModel

  var body: some View {
    if model.catalog == nil {
      Text("設定資料遺失，請重新安裝貂毫。").foregroundStyle(.red).padding(30)
    }
    Form {
      Section("版面") {
        if let row = model.row("style/candidate_list_layout", config: .squirrel) {
          PenglaiFormRow(PenglaiCopy.layout, row: row, note: model.colorOverride("style/candidate_list_layout")) {
            PenglaiSegmented(options: [("stacked", "直式"), ("linear", "橫式")], selection: row.shownValue, enabled: row.blocked == nil) {
              model.set(row, .string($0))
            }
          }
        }
        if let row = model.row("style/font_point", config: .squirrel) {
          PenglaiFormRow(PenglaiCopy.fontSize, row: row, note: model.colorOverride("style/font_point")) {
            HStack(spacing: 12) {
              PenglaiSegmented(options: [(14.0, "小"), (16.0, "標準"), (20.0, "大"), (24.0, "特大")],
                               selection: row.shownValue.flatMap(Double.init), enabled: row.blocked == nil) {
                model.set(row, .int(Int($0)))
              }
              PenglaiStepper(value: row.shownValue.flatMap(Double.init), step: 1, range: 8...72, enabled: row.blocked == nil) {
                model.set(row, .double($0))
              }
            }
          }
        }
        if let row = model.schemaRow("menu/page_size") {
          PenglaiFormRow(PenglaiCopy.pageSize, row: row) {
            PenglaiSegmented(options: (5...9).map { ($0, String($0)) }, selection: row.shownValue.flatMap(Int.init), enabled: row.blocked == nil) {
              model.set(row, .int($0))
            }
          }
        }
      }
      Section("組字") {
        if let preedit = model.row("style/inline_preedit", config: .squirrel), let candidate = model.row("style/inline_candidate", config: .squirrel) {
          let mode: String? = {
            switch (preedit.shownValue, candidate.shownValue ?? "false") {
            case ("true", "false"): return "zhuyin"
            case ("false", "true"): return "hanzi"
            default: return nil
            }
          }()
          PenglaiFormRow(PenglaiCopy.inlineMode,
                         row: preedit.isUserSet ? preedit : candidate,
                         note: mode == nil ? "目前是自訂的組合，點一下就會改成其中一種" : nil) {
            PenglaiSegmented(options: [("zhuyin", "注音"), ("hanzi", "候選字")], selection: mode,
                             enabled: preedit.blocked == nil && candidate.blocked == nil) { choice in
              let hanzi = choice == "hanzi"
              model.setPair([(preedit, .bool(!hanzi)), (candidate, .bool(hanzi))], summary: "打字時游標處顯示：\(hanzi ? "候選字" : "注音")")
            }
          }
        }
      }
      Section("選單列") {
        if let row = model.row("status_icon/show", config: .squirrel) {
          PenglaiFormRow(PenglaiCopy.statusIcon, row: row) {
            PenglaiSwitch(isOn: (row.shownValue ?? "true") == "true", enabled: row.blocked == nil) {
              model.set(row, .bool($0), summary: "選單列狀態圖示：\($0 ? "顯示" : "隱藏")")
            }
          }
        }
      }
    }
    .penglaiForm()
  }
}

// MARK: - 配色

struct PenglaiColorsPage: View {
  @EnvironmentObject var model: PenglaiSettingsModel
  private var dark: Bool { model.colorsDark }

  private var key: String { dark ? "style/color_scheme_dark" : "style/color_scheme" }
  private var modeName: String { dark ? "深色模式" : "淺色模式" }

  var body: some View {
    let row = model.row(key, config: .squirrel)
    let current = row?.shownValue ?? "native"
    Form {
      Section {
        LabeledContent {
          PenglaiSegmented(options: [(false, "淺色模式"), (true, "深色模式")], selection: dark) { model.colorsDark = $0 }
        } label: {
          VStack(alignment: .leading, spacing: 3) {
            Text("\(modeName)：\(model.colorSchemes.first { $0.id == current }?.name ?? current)")
            if let row, model.canReset(row) {
              Button("還原預設") { model.resetToDefault(row) }.buttonStyle(.link).font(.system(size: 11))
            }
            if row?.blocked != nil {
              Label(PenglaiSettingsModel.blockedText, systemImage: "exclamationmark.triangle.fill").font(.system(size: 11)).foregroundStyle(.orange)
            }
          }
        }
        .penglaiHighlight(dark ? PenglaiCopy.darkScheme.title : PenglaiCopy.lightScheme.title)
      }
      Section {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 8) {
          ForEach(model.colorSchemes) { scheme in
            Button {
              if let row { model.set(row, .string(scheme.id), summary: "\(modeName)配色：\(scheme.name)") }
            } label: {
              swatch(scheme, selected: scheme.id == current)
                .background(RoundedRectangle(cornerRadius: 8).fill(model.highlight == scheme.name ? Color.accentColor.opacity(0.3) : .clear).padding(-4))
            }
            .buttonStyle(.plain)
            .disabled(row?.blocked != nil)
          }
        }
        .padding(.vertical, 4)
      } footer: {
        Text("標示「附版面」的配色會一併改變候選排列或字級。").font(.system(size: 11)).foregroundStyle(.secondary)
      }
    }
    .penglaiForm()
  }

  private func swatch(_ scheme: PenglaiColorScheme, selected: Bool) -> some View {
    let back = scheme.back.map { Color(nsColor: $0) } ?? Color(nsColor: .windowBackgroundColor)
    let text = scheme.text.map { Color(nsColor: $0) } ?? Color(nsColor: .labelColor)
    let hiBack = scheme.hilitedBack.map { Color(nsColor: $0) } ?? Color.accentColor
    let hiText = scheme.hilitedText.map { Color(nsColor: $0) } ?? Color.white
    return VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 4) {
        Text("1 蓬萊").font(.system(size: 11)).foregroundColor(hiText)
          .padding(.horizontal, 4).padding(.vertical, 1).background(RoundedRectangle(cornerRadius: 3).fill(hiBack))
        Text("2 注音").font(.system(size: 11)).foregroundColor(text)
      }
      .padding(8)
      .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
      .background(RoundedRectangle(cornerRadius: 6).fill(back))
      .overlay(alignment: .topTrailing) {
        if !scheme.overrides.isEmpty {
          Text("附版面").font(.system(size: 8.5, weight: .medium)).foregroundColor(.white)
            .padding(.horizontal, 3).padding(.vertical, 1)
            .background(RoundedRectangle(cornerRadius: 3).fill(Color.black.opacity(0.6))).padding(3)
        }
      }
      .overlay(RoundedRectangle(cornerRadius: 6).stroke(selected ? Color.accentColor : Color(nsColor: .separatorColor), lineWidth: selected ? 3 : 1))
      Text(scheme.name).font(.system(size: 11, weight: selected ? .semibold : .regular)).lineLimit(1)
        .frame(maxWidth: .infinity)
    }
    .contentShape(Rectangle())
  }
}

// MARK: - 分頁列

/// 有分頁列的頁：頁首底下一排分段按鈕，第一個是這一頁自己的主畫面（home），後面是掛在這一頁的進階分組
/// （PenglaiAdvanced 的分類表寫 page）。只有一個時不畫分頁列。沒有主畫面的頁（按鍵）只有後面那些
struct PenglaiTabbedPage<Home: View>: View {
  @EnvironmentObject var model: PenglaiSettingsModel
  @ViewBuilder var home: () -> Home

  var body: some View {
    let tabs = model.tabs(for: model.page)
    let homeTitle = model.page.homeTab
    let current = model.advancedSection.map { "\($0)/\(model.advancedSegment)" } ?? ""
    VStack(alignment: .leading, spacing: 0) {
      if tabs.count + (homeTitle == nil ? 0 : 1) > 1 {
        PenglaiSegmented(options: (homeTitle.map { [("", $0)] } ?? []) + tabs.map { ($0.id, $0.title) }, selection: current) { choice in
          if let tab = tabs.first(where: { $0.id == choice }) {
            model.advancedSection = tab.section
            model.advancedSegment = tab.segment
            model.pageIndex = 0
          } else {
            model.showHome()
          }
        }
        .padding(.horizontal, 30).padding(.top, 14)
      }
      if model.advancedSection == nil, homeTitle != nil {
        home()
      } else {
        PenglaiAdvancedRows(listed: false, footer: footer)
      }
    }
  }

  /// 那一組的頁尾說明（快速鍵的鍵名對照）
  private var footer: String? {
    guard let section = model.advancedSection else { return nil }
    return PenglaiAdvanced.section(section)?.segments.first { $0.id == model.advancedSegment }?.footer
  }
}

/// 直接列在主畫面的進階分組（分類表的 inline）：照分類表的順序一列一列排，控制項照型別給
struct PenglaiInlineRows: View {
  @EnvironmentObject var model: PenglaiSettingsModel
  var section: String
  var segment: String

  var body: some View {
    ForEach(model.advancedRows(section: section, segment: segment)) { row in
      PenglaiGenericRow(row: row)
    }
  }
}

// MARK: - 一般

/// 打字時的輔助功能和組句、學習（11/11：原本的「輸入」「組句與學習」兩頁併成一頁；打錯修正、標點各自成頁）
struct PenglaiGeneralPage: View {
  @EnvironmentObject var model: PenglaiSettingsModel

  var body: some View {
    Form {
      Section("輸入輔助") {
        if let row = model.schemaRow(PenglaiSettingsModel.englishKey) {
          let available = model.englishLexicon != nil && row.blocked == nil
          PenglaiFormRow(PenglaiCopy.english, row: row,
                         note: available ? nil : PenglaiSettingsModel.unsupportedText, resettable: false) {
            PenglaiDetailLink(section: "english")
            PenglaiSwitch(isOn: model.englishOn, enabled: available) { model.setEnglish($0) }
          }
        }
        if model.predictionSwitch != nil {
          let state = model.predictionState
          PenglaiFormRow(PenglaiCopy.prediction, row: nil, note: state.note) {
            PenglaiDetailLink(section: "prediction")
            PenglaiSwitch(isOn: state.on, enabled: state.enabled) { model.setPrediction($0) }
          }
        }
        ForEach(model.catalog?.recipes ?? [], id: \.id) { recipe in
          let state = model.recipeState(recipe)
          let copy = PenglaiCopyItem(title: recipe.title)
          PenglaiFormRow(copy, row: nil, note: recipeNote(state)) {
            PenglaiSwitch(isOn: state == .on ? true : state == .off ? false : nil, enabled: state == .on || state == .off) {
              model.setRecipe(recipe, enable: $0)
            }
          }
        }
        if let row = model.schemaRow(PenglaiSettingsModel.reverseLookupKey) {
          let available = model.reverseLookupPattern != nil && row.blocked == nil
          PenglaiFormRow(PenglaiCopy.strokeLookup, row: row,
                         note: available ? nil : PenglaiSettingsModel.unsupportedText, resettable: false) {
            PenglaiSwitch(isOn: model.reverseLookupOn, enabled: available) { model.setReverseLookup($0) }
          }
        }
      }
      Section {
        if let row = model.schemaRow("translator/max_sentences") {
          PenglaiFormRow(PenglaiCopy.sentences, row: row) {
            PenglaiSegmented(options: [1, 3, 5].map { ($0, String($0)) }, selection: row.shownValue.flatMap(Int.init), enabled: row.blocked == nil) {
              model.set(row, .int($0))
            }
          }
        }
        if let row = model.schemaRow("translator/max_user_phrase_syllables") {
          PenglaiFormRow(PenglaiCopy.phraseLength, row: row) {
            PenglaiSegmented(options: [(5, "5 字"), (10, "10 字")], selection: row.shownValue.flatMap(Int.init), enabled: row.blocked == nil) {
              model.set(row, .int($0))
            }
          }
        }
        if let row = model.schemaRow("translator/revert_learning_seconds") {
          PenglaiFormRow(PenglaiCopy.revertSeconds, row: row) {
            PenglaiSegmented(options: [3, 5, 10, 15, 30].map { ($0, String($0)) }, selection: row.shownValue.flatMap(Int.init),
                             enabled: row.blocked == nil) { model.set(row, .int($0)) }
          }
        }
      } header: {
        HStack {
          Text("組句與學習")
          Spacer()
          PenglaiDetailLink(section: "composing")
        }
      }
    }
    .penglaiForm()
  }

  private func recipeNote(_ state: PenglaiRecipe.State) -> String? {
    switch state {
    case .unavailable: return PenglaiSettingsModel.unsupportedText
    case .partial: return "這個功能的設定不完整，這裡沒辦法切換"
    default: return nil
    }
  }
}

// MARK: - 打錯修正

/// 打錯也對得到的總開關、它底下的幾個開關（分類表 correction 的 options 那一組）、模糊音；各種錯的機率在分頁「細部調整」
struct PenglaiCorrectionPage: View {
  @EnvironmentObject var model: PenglaiSettingsModel

  var body: some View {
    Form {
      if let row = model.schemaRow(PenglaiSettingsModel.keyModelKey) {
        Section("按錯鍵") {
          PenglaiFormRow(PenglaiCopy.keyModel, row: row) {
            PenglaiSwitch(isOn: row.shownValue.map { $0 == "true" }, enabled: row.blocked == nil) { model.set(row, .bool($0)) }
          }
          PenglaiInlineRows(section: "correction", segment: "options")
        }
        Section("分不清的音") {
          let fuzzy = model.fuzzyState
          PenglaiFormRow(PenglaiCopy.fuzzy, row: nil, note: fuzzy.note) {
            PenglaiFuzzyPairs()
          }
        }
      } else {
        Section {
          Text(PenglaiSettingsModel.unsupportedText).foregroundStyle(.secondary)
        }
      }
    }
    .penglaiForm()
  }
}

// MARK: - 標點符號

/// 送出之後按空白補標點（總開關和它的細項：分類表 punct 的 space_punct 那一組）、長按出符號、連打三個點
struct PenglaiPunctPage: View {
  @EnvironmentObject var model: PenglaiSettingsModel

  var body: some View {
    Form {
      if let row = model.schemaRow(PenglaiSettingsModel.spacePunctKey) {
        Section("送出之後補標點") {
          PenglaiFormRow(PenglaiCopy.spacePunct, row: row) {
            PenglaiSwitch(isOn: row.shownValue.map { $0 != "false" }, enabled: row.blocked == nil) { model.set(row, .bool($0)) }
          }
          PenglaiInlineRows(section: "punct", segment: "space_punct")
        }
      }
      Section("符號") {
        if let row = model.row(PenglaiSettingsModel.longPressKey, config: .squirrel) {
          PenglaiFormRow(PenglaiCopy.longPress, row: row) {
            PenglaiSwitch(isOn: (row.shownValue ?? "true") != "false", enabled: row.blocked == nil) {
              model.set(row, .bool($0), summary: "長按出符號：\($0 ? "開" : "關")")
            }
          }
        }
        PenglaiInlineRows(section: "punct", segment: "symbols")
      }
    }
    .penglaiForm()
  }
}

// MARK: - 讀音

/// 讀音的一個選項：例字「期」和注音、名稱、說明；選中的外框亮起來、右上角打勾。讀音頁和第一次使用的引導共用
struct PenglaiReadingCard: View {
  var option: String
  var selected: Bool
  var enabled = true
  var large = false
  var action: () -> Void

  var body: some View {
    let item = PenglaiCopy.readingOption(option)
    Button(action: action) {
      VStack(spacing: 0) {
        HStack {
          Spacer()
          Image(systemName: selected ? "checkmark.circle.fill" : "circle")
            .font(.system(size: large ? 18 : 16))
            .foregroundStyle(selected ? Color.accentColor : Color.secondary.opacity(0.6))
        }
        Text("期").font(.system(size: large ? 46 : 38, weight: .medium))
        Text(PenglaiCopy.readingExample(option)).font(.system(size: large ? 18 : 16)).foregroundStyle(.secondary).padding(.top, 2)
        Text(item.title).font(.system(size: large ? 15 : 13.5, weight: .semibold)).padding(.top, large ? 22 : 16)
        Text(item.desc ?? "").font(.system(size: large ? 12.5 : 11.5)).foregroundStyle(.secondary)
          .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true).padding(.top, 3)
      }
      .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, large ? 18 : 14)
      .frame(maxWidth: .infinity)
      .background(RoundedRectangle(cornerRadius: 10).fill(selected ? Color.accentColor.opacity(0.08) : Color(nsColor: .controlBackgroundColor)))
      .overlay(RoundedRectangle(cornerRadius: 10).stroke(selected ? Color.accentColor : Color(nsColor: .separatorColor), lineWidth: selected ? 2.5 : 1))
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .disabled(!enabled)
    .opacity(enabled ? 1 : 0.5)
  }
}

/// 讀音頁：三個選項一下選一個。選了正在打字的地方馬上換，同時存起來（方案 custom 檔的 reset），之後開的也照這個
struct PenglaiReadingPage: View {
  @EnvironmentObject var model: PenglaiSettingsModel

  var body: some View {
    let state = model.readingState
    Form {
      Section {
        HStack(spacing: 12) {
          ForEach(state.options, id: \.self) { option in
            PenglaiReadingCard(option: option, selected: option == state.choice, enabled: state.enabled) {
              if option != state.choice { model.setReading(option) }
            }
            .penglaiHighlight(PenglaiCopy.readingOption(option).title)
          }
        }
        .padding(.vertical, 6)
        .penglaiHighlight(PenglaiCopy.readingPage.title)
      } footer: {
        VStack(alignment: .leading, spacing: 4) {
          if let note = state.note {
            Label(note, systemImage: "exclamationmark.triangle.fill").font(.system(size: 11)).foregroundStyle(.orange)
          }
          Text(PenglaiCopy.readingFootnote).font(.system(size: 11)).foregroundStyle(.secondary)
        }
      }
    }
    .penglaiForm()
  }
}

// MARK: - 輸入方案

struct PenglaiSchemasPage: View {
  @EnvironmentObject var model: PenglaiSettingsModel

  var body: some View {
    Form {
      Section {
        ForEach(model.schemas) { schema in
          let on = model.activeSchemas.contains(schema.id)
          LabeledContent {
            PenglaiSwitch(isOn: on, enabled: !(on && model.activeSchemas.count == 1)) { enable in
              var list = model.activeSchemas
              if enable { list.append(schema.id) } else { list.removeAll { $0 == schema.id } }
              model.setSchemaList(list)
            }
          } label: {
            HStack(spacing: 8) {
              Text(schema.name)
              if schema.id == model.schemaID {
                Text("使用中").font(.system(size: 10.5, weight: .medium)).foregroundStyle(.secondary)
                  .padding(.horizontal, 6).padding(.vertical, 1).background(Capsule().fill(Color.secondary.opacity(0.15)))
              }
            }
          }
          .padding(.vertical, 3)
          .penglaiHighlight(schema.name)
        }
      } footer: {
        Text("至少要保留一個方案。").font(.system(size: 11)).foregroundStyle(.secondary)
      }
    }
    .penglaiForm()
  }
}

// MARK: - 進階

/// 細項照「要做什麼」分類，不照設定檔分：Rime 的設定照元件、檔案散在選字窗外觀、全域、方案好幾處，
/// 原樣照檔案列出來，方案那一組就有六十幾列、十一頁，而且是照設定鍵的字母排。
/// 每一類可以再分幾組（分段按鈕），一組一頁放得下（rowsPerPage）。keys 是完整路徑（元件的鍵照方案掛的命名空間），照列出的順序排。
/// hidden 是這個輸入法改了也沒作用、或只給測試用的，不列；沒分到的列在「其他」，目錄新加的設定不會不見。
/// 每一類掛在哪一頁寫在 page（11/11）：預設是「進階」（總覽一張卡片）；寫了別頁的，它的每一組是那一頁分頁列上的一個分頁
/// （選字窗的字型、按鍵的快速鍵），inline 的那一組直接列在那一頁的主畫面（補標點的細項接在總開關底下）。
/// 手機版（penglai-android 的 PenglaiAdvanced.kt）照這份表搬：類、組、keys、hidden、requirements 改了要一起改；page、inline、tab 是 Mac 的排法
enum PenglaiAdvanced {
  struct Segment: Identifiable {
    var id: String
    var title: String
    var keys: [String]
    /// 頁尾的說明（引擎參數那幾類另有固定的一句）
    var footer: String? = nil
    /// 直接列在那一頁的主畫面，不另成分頁
    var inline = false
    /// 分頁列上的名字（跟別類的組放在同一排、title 分不出來時）
    var tab: String? = nil
  }

  struct Section: Identifiable {
    var id: String
    var title: String
    var desc: String
    var symbol: String
    var tint: Color
    /// 掛在哪一頁：.all 是進階頁的總覽
    var page: PenglaiSettingsModel.Page = .all
    /// 引擎參數：改了直接影響候選排序，總覽裡另成一區、頁尾提醒
    var tuning = false
    /// 這一類裡標題開頭重複的字（分類名稱已經講了），長的先比
    var prefixes: [String] = []
    var segments: [Segment]
  }

  struct Place {
    var section: String
    var segment: String
    var order: Int
  }

  static let otherSection = "other"

  static let sections: [Section] = [
    // 打錯修正頁：開關類的接在總開關底下（options），各種錯的機率是分頁「細部調整」
    Section(id: "correction", title: "打錯修正", desc: "按到旁邊的鍵、漏打、連按兩下的機率", symbol: "wand.and.stars", tint: .purple, page: .correction,
            prefixes: ["打錯也對得到："], segments: [
      Segment(id: "options", title: "修正", keys: [
        "translator/key_model/lone_finals", "translator/key_model/valid_first", "translator/key_model/show_reading",
        "translator/key_model/fuzzy_pairs",
      ], inline: true),
      Segment(id: "rates", title: "細部調整", keys: [
        "translator/key_model/substitution", "translator/key_model/omit_initial", "translator/key_model/omit_medial",
        "translator/key_model/double_press", "translator/key_model/extra",
      ]),
    ]),
    // 標點符號頁：兩組都直接列在主畫面（補標點的細項接在總開關底下，連打三個點跟長按出符號放一起）
    Section(id: "punct", title: "標點符號", desc: "送出之後補標點的細節、連打三個點", symbol: "quote.opening", tint: .green, page: .punct, segments: [
      Segment(id: "space_punct", title: "送出之後補標點", keys: [
        "penglai_space/replace", "penglai_space/period", "penglai_space/foreign", "penglai_space/english",
      ], inline: true),
      Segment(id: "symbols", title: "符號", keys: ["penglai_space/ellipsis"], inline: true),
    ]),
    // 按鍵頁：沒有主畫面，三組就是三個分頁
    Section(id: "keys", title: "按鍵", desc: "空白鍵、Caps Lock、選字鍵、翻頁", symbol: "keyboard", tint: .orange, page: .keys, segments: [
      Segment(id: "keys", title: "按鍵", keys: [
        "speller/use_space", "punctuator/use_space", "ascii_composer/good_old_caps_lock", "menu/alternative_select_keys",
        "menu/page_down_cycle", "translator/raw_lead_keys",
      ], tab: "常用按鍵"),
    ]),
    Section(id: "shortcuts", title: "快速鍵", desc: "複製、刪學習紀錄、選第二個、數字選字、一鍵忘掉用哪個鍵", symbol: "command", tint: .purple, page: .keys, segments: [
      // 選鍵的列控制項比較寬、說明另起一行，一頁放五列；選完之後的細節另成一組
      Segment(id: "shortcuts", title: "按鍵", keys: PenglaiShortcuts.keys,
              footer: "⌃ Control（左右都算）、⌥ Option、⌘ Command。選了別的功能正在用的鍵，兩個功能對調。", tab: "快速鍵"),
      Segment(id: "details", title: "細部調整", keys: ["penglai_numsel/commit_whole", "translator/forget_last_history", "penglai_tap/limit"],
              tab: "快速鍵選項"),
    ]),
    // 選字窗頁：主畫面是版面那幾項，這四組是後面的分頁
    Section(id: "appearance", title: "選字窗外觀", desc: "字型、圓角、間距、讀音提示", symbol: "macwindow", tint: .blue, page: .panel, segments: [
      Segment(id: "fonts", title: "字型與字級", keys: [
        "style/font_face", "style/label_font_face", "style/label_font_point", "style/comment_font_face", "style/comment_font_point",
        "style/preedit_font_face", "style/preedit_font_point",
      ]),
      Segment(id: "shape", title: "形狀與效果", keys: [
        "style/corner_radius", "style/hilited_corner_radius", "style/shadow_size", "style/surrounding_extra_expansion",
        "style/alpha", "style/translucency", "style/mutual_exclusive",
      ]),
      Segment(id: "spacing", title: "間距", keys: ["style/border_height", "style/border_width", "style/line_spacing", "style/spacing", "style/base_offset"]),
      Segment(id: "content", title: "顯示內容", keys: [
        "translator/spelling_hints", "translator/always_show_comments", "style/candidate_format", "style/show_paging",
        "style/status_message_type", "style/text_orientation", "style/memorize_size",
      ]),
    ]),
    Section(id: "composing", title: "組句與學習", desc: "補完、參考前文、候選排序、記住選過的字詞", symbol: "text.badge.checkmark", tint: .green, segments: [
      Segment(id: "composing", title: "組句與補完", keys: [
        "translator/contextual_suggestions", "translator/last_commit_as_context", "translator/enable_completion",
        "translator/enable_word_completion", "translator/enable_correction", "translator/strict_spelling", "reverse_lookup/enable_completion",
      ]),
      Segment(id: "split", title: "選字吃幾個鍵", keys: ["translator/extend_selection", "translator/split_penalty"]),
      Segment(id: "typing_style", title: "打法", keys: ["translator/typing_style"]),
      Segment(id: "order", title: "候選排序", keys: [
        "translator/long_phrase_quota", "translator/recent_phrase_max", "translator/recent_phrase_window",
      ]),
      Segment(id: "short_sentence", title: "短輸入也組整句", keys: [
        "translator/short_sentence_max", "translator/short_sentence_min", "translator/short_sentence_penalty",
        "translator/short_sentence_position", "translator/short_sentence_full_spelling",
      ]),
      Segment(id: "learning", title: "學習", keys: [
        "translator/enable_user_dict", "translator/max_word_length", "translator/core_word_length", "translator/dictionary_exclude_min_length",
      ]),
    ]),
    Section(id: "prediction", title: "聯想", desc: "送出之後列出接下來的詞", symbol: "text.append", tint: .teal, prefixes: ["聯想："], segments: [
      Segment(id: "prediction", title: "聯想", keys: ["predictor/max_candidates", "predictor/max_context_chars", "predictor/max_iterations"]),
    ]),
    Section(id: "conversion", title: "字形轉換", desc: "臺灣字形、簡化字轉換的細節", symbol: "character", tint: .pink, prefixes: ["繁簡轉換："], segments: [
      Segment(id: "zh_hant_tw", title: "臺灣字形", keys: ["zh_hant_tw/show_in_comment", "zh_hant_tw/inherit_comment", "zh_hant_tw/random"]),
      Segment(id: "zh_hans", title: "簡化字", keys: ["zh_hans/show_in_comment", "zh_hans/inherit_comment", "zh_hans/random"]),
    ]),
    Section(id: "switcher", title: "方案選單", desc: "按 F4 叫出的選單怎麼顯示", symbol: "list.bullet.rectangle", tint: .indigo, segments: [
      Segment(id: "switcher", title: "方案選單", keys: [
        "switcher/caption", "switcher/fold_options", "switcher/abbreviate_options", "switcher/option_list_prefix",
        "switcher/option_list_separator", "switcher/option_list_suffix", "switcher/fix_schema_list_order",
      ]),
    ]),
    Section(id: otherSection, title: "其他", desc: "通知和其他設定", symbol: "gearshape", tint: .gray, segments: [
      Segment(id: otherSection, title: "其他", keys: ["show_notifications_when"]),
    ]),
    Section(id: "english", title: "中英混輸", desc: "英文、字母串、數字什麼時候出來、排第幾", symbol: "globe", tint: .orange, tuning: true,
            prefixes: ["中英混輸：按鍵層的", "中英混輸：按鍵層", "中英混輸：", "英文單字進整句：", "整段數字鍵："], segments: [
      Segment(id: "judge", title: "判斷", keys: [
        "translator/english_judge_tau", "translator/english_judge_readings", "translator/english_judge_learned", "translator/english_position",
      ]),
      Segment(id: "words", title: "英文單字", keys: [
        "translator/english_min_length", "translator/english_min_zipf", "translator/english_max_sentences", "translator/english_weight",
        "translator/english_space", "translator/english_space_min_length",
      ]),
      Segment(id: "letters", title: "字母串", keys: [
        "translator/english_letter_runs", "translator/english_letter_trim", "translator/english_letter_penalty", "translator/english_letter_position",
      ]),
      Segment(id: "keylid", title: "按鍵層辨識", keys: [
        "translator/english_keylid", "translator/english_keylid_position", "translator/english_keylid_max", "translator/english_keylid_min_length",
        "translator/english_keylid_candidates", "translator/english_keylid_margin", "translator/english_keylid_switch", "translator/english_keylid_beam",
      ]),
      Segment(id: "digits", title: "數字", keys: [
        "translator/digit_runs", "translator/digit_min_length", "translator/digit_penalty", "speller/digit_tones", "speller/digit_lead_tones",
      ]),
    ]),
    Section(id: "ranking", title: "排序參數", desc: "組整句的同音詞數、截斷門檻、語言模型", symbol: "slider.horizontal.3", tint: .gray, tuning: true,
            prefixes: ["語言模型："], segments: [
      Segment(id: "sentence", title: "整句", keys: ["translator/max_homophones", "translator/sentence_cutoff_threshold", "translator/initial_quality"]),
      Segment(id: "grammar", title: "語言模型", keys: [
        "grammar/collocation_max_length", "grammar/collocation_min_length", "grammar/collocation_penalty",
        "grammar/non_collocation_penalty", "grammar/weak_collocation_penalty", "grammar/rear_penalty",
      ]),
    ]),
    Section(id: "custom_phrase", title: "自訂詞", desc: "自訂詞的候選怎麼排、要不要學習", symbol: "text.book.closed", tint: .brown, tuning: true, segments: [
      Segment(id: "custom_phrase", title: "自訂詞", keys: [
        "custom_phrase/initial_quality", "custom_phrase/enable_user_dict", "custom_phrase/enable_completion", "custom_phrase/strict_spelling",
        "custom_phrase/contextual_suggestions", "custom_phrase/last_commit_as_context", "custom_phrase/dictionary_exclude_min_length",
      ]),
    ]),
  ]

  /// 不列的：蓬萊注音用不到的元件功能（並擊、碼表造詞、唯一候選自動送出、含空白的特殊輸入規則、沒有先驗檔的學習計分），
  /// 一下就讓打字失常的（最長碼長：+ 一下就每打一鍵送出），只給沙盒測試用的（Control 複製不放剪貼簿），產生器寫的清單（罕用黏合音節）
  static let hidden: Set<String> = [
    "chord_duration", "speller/auto_select", "speller/max_code_length", "recognizer/use_space",
    "translator/user_scoring/prior_weight", "translator/user_scoring/recency", "translator/user_scoring/unit",
    "penglai_tap/clipboard", "penglai_tap/pasteboard",
    // 罕用黏合音節的清單是詞典產生器照字頻寫的（tools/gen_terra_tw.py），不是給人調的
    "translator/glue_syllables",
    // 按鍵模型的內部參數：11/6 量出來的界線，調了會讓一般打字變差（只打首注音的長句改錯幾百題），不給人調
    "translator/key_model/abbreviations", "translator/key_model/require_tone", "translator/key_model/fuzzy_untoned",
    "translator/key_model/valid",
    "translator/key_model/valid_suggest", "translator/key_model/closed_type", "translator/key_model/sigma",
    "translator/key_model/fuzzy", "translator/key_model/max_corrections", "translator/key_model/max_edits",
    // 觸控（手機前端傳按下去的位置時才有作用）：一樣是按鍵模型的內部參數，Mac 沒有觸控
    "translator/key_model/touch_sigma", "translator/key_model/touch_prior", "translator/key_model/touch_valid",
    "translator/key_model/touch_near", "translator/key_model/touch_close", "translator/key_model/touch_abbreviations",
    "translator/key_model/touch_max_edits",
    "custom_phrase/enable_charset_filter", "custom_phrase/enable_encoder", "custom_phrase/enable_sentence",
    "custom_phrase/encode_commit_history", "custom_phrase/max_homographs", "custom_phrase/max_phrase_length",
    "custom_phrase/sentence_over_completion", "custom_phrase/max_sentences", "custom_phrase/sentence_cutoff_threshold",
  ]

  /// 目錄的名稱是寫給維護者的（翻譯器、反查），這幾個換成使用者看得懂、跟主頁一致的
  static let titles: [String: String] = [
    "translator/initial_quality": "詞典候選的權重",
    "custom_phrase/initial_quality": "自訂詞的權重",
    "reverse_lookup/enable_completion": "\(PenglaiCopy.strokeLookup.title)：筆畫沒打完就先列出",
  ]

  /// 目錄說明的第一句不能上畫面（提到檔名、按鍵碼）的，另外寫一句
  static let descs: [String: String] = [
    "translator/raw_lead_keys": "整段輸入用這個鍵開頭時，只給按下的字（例如 /loop），不組中文。",
    "translator/english_keylid": "單字表裡沒有的英文（縮寫、專有名詞），從按鍵判斷像不像英文，另外列成候選。",
  ]

  /// 進階頁那一列的說明
  static func desc(_ row: PenglaiSettingRow) -> String? {
    descs[row.key] ?? row.info?.desc.flatMap(PenglaiSettingsModel.brief)
  }

  /// 要先開（或關）同一類裡的另一項才有作用的：parent 不是 met 的值時，控制項變灰、說要先做什麼
  struct Requirement {
    var parent: String
    var verb: String
    var met: (String?) -> Bool
  }

  static let requirements: [String: Requirement] = {
    var result: [String: Requirement] = [
      "punctuator/use_space": Requirement(parent: "speller/use_space", verb: "關掉") { $0 == "false" },
      "translator/always_show_comments": Requirement(parent: "translator/spelling_hints", verb: "打開") { (Int($0 ?? "") ?? 0) > 0 },
    ]
    for key in ["english_letter_trim", "english_letter_penalty", "english_letter_position"] {
      result["translator/\(key)"] = Requirement(parent: "translator/english_letter_runs", verb: "打開") { $0 == "true" }
    }
    for key in ["position", "max", "min_length", "candidates", "margin", "switch", "beam"] {
      result["translator/english_keylid_\(key)"] = Requirement(parent: "translator/english_keylid", verb: "打開") { !($0 ?? "").isEmpty }
    }
    result["translator/english_space_min_length"] = Requirement(parent: "translator/english_space", verb: "打開") { $0 == "true" }
    for key in ["valid_first", "fuzzy_pairs", "substitution", "omit_initial", "omit_medial", "double_press", "extra", "max_edits", "lone_finals"] {
      result["translator/key_model/\(key)"] = Requirement(parent: PenglaiSettingsModel.keyModelKey, verb: "打開") { $0 == "true" }
    }
    result["penglai_space/replace"] = Requirement(parent: "penglai_space/punct", verb: "打開") { $0 != "false" }
    result["penglai_space/period"] = Requirement(parent: "penglai_space/punct", verb: "打開") { $0 != "false" }
    result["penglai_space/foreign"] = Requirement(parent: "penglai_space/punct", verb: "打開") { $0 != "false" }
    result["penglai_space/english"] = Requirement(parent: "penglai_space/punct", verb: "打開") { $0 != "false" }
    result["translator/split_penalty"] = Requirement(parent: "translator/extend_selection", verb: "打開") { $0 == "true" }
    result["translator/recent_phrase_window"] = Requirement(parent: "translator/recent_phrase_max", verb: "打開") { (Int($0 ?? "") ?? 0) > 0 }
    for key in ["short_sentence_min", "short_sentence_penalty", "short_sentence_position", "short_sentence_full_spelling"] {
      result["translator/\(key)"] = Requirement(parent: "translator/short_sentence_max", verb: "打開") { (Int($0 ?? "") ?? 0) > 0 }
    }
    for key in ["digit_min_length", "digit_penalty"] {
      result["translator/\(key)"] = Requirement(parent: "translator/digit_runs", verb: "打開") { $0 == "true" }
    }
    return result
  }()

  private static let index: [String: Place] = {
    var result: [String: Place] = [:]
    for (s, section) in sections.enumerated() {
      for (g, segment) in section.segments.enumerated() {
        for (k, key) in segment.keys.enumerated() where result[key] == nil {
          result[key] = Place(section: section.id, segment: segment.id, order: s * 10_000 + g * 100 + k)
        }
      }
    }
    return result
  }()

  static func section(_ id: String) -> Section? { sections.first { $0.id == id } }

  /// 這一列分到哪一類、哪一組；nil 是不列
  static func place(_ row: PenglaiSettingRow, model: PenglaiSettingsModel) -> Place? {
    guard !hidden.contains(row.key) else { return nil }
    // 方案選單只有一個方案時，「順序固定」看不出差別
    if row.key == "switcher/fix_schema_list_order", model.activeSchemas.count < 2 { return nil }
    if let place = index[row.key] { return place }
    let other = sections.firstIndex { $0.id == otherSection } ?? sections.count
    return Place(section: otherSection, segment: otherSection, order: other * 10_000 + 99)
  }

  /// 在這一類裡顯示的標題：改過名的照改，開頭跟分類名稱重複的拿掉
  static func title(_ row: PenglaiSettingRow, in section: String) -> String {
    let title = titles[row.key] ?? row.title
    for prefix in self.section(section)?.prefixes ?? [] where title.hasPrefix(prefix) && title.count > prefix.count {
      return String(title.dropFirst(prefix.count))
    }
    return title
  }

  /// 這一列要先開（或關）別的項目才有作用時的提示；有作用、或沒有前提的是 nil
  static func hint(_ row: PenglaiSettingRow, model: PenglaiSettingsModel) -> String? {
    if row.key == "reverse_lookup/enable_completion" {
      return model.reverseLookupOn ? nil : "要先在「\(PenglaiSettingsModel.Page.typing.title)」打開「\(PenglaiCopy.strokeLookup.title)」"
    }
    // 補標點的總開關是主頁的項目（標點符號頁最上面），分類表不列
    if requirements[row.key]?.parent == PenglaiSettingsModel.spacePunctKey,
       let parent = model.row(PenglaiSettingsModel.spacePunctKey, config: row.config), parent.shownValue == "false" {
      return "要先打開「\(PenglaiCopy.spacePunct.title)」"
    }
    guard let requirement = requirements[row.key], let parent = model.row(requirement.parent, config: row.config),
          !requirement.met(parent.shownValue) else { return nil }
    let title = PenglaiAdvanced.place(parent, model: model) != nil ? model.displayTitle(parent) : parent.title
    return "要先\(requirement.verb)「\(title)」"
  }

  /// 整類要先在「一般」打開某個功能才有作用：沒打開時頁首提醒，附一個過去打開的按鈕
  static func banner(_ section: String, model: PenglaiSettingsModel) -> (text: String, item: PenglaiCopyItem)? {
    switch section {
    case "english" where model.englishLexicon != nil && !model.englishOn:
      return ("「中英混輸」目前關著，這裡的設定要打開之後才有作用。", PenglaiCopy.english)
    case "prediction" where model.predictionSwitch != nil && model.predictionState.on != true:
      return ("「聯想」目前關著，這裡的設定要打開之後才有作用。", PenglaiCopy.prediction)
    default:
      return nil
    }
  }
}

/// 進階頁：沒選分類時是總覽（卡片），選了是那一類（分段按鈕＋那一組的設定），另有已自訂的項目列表
struct PenglaiAdvancedPage: View {
  @EnvironmentObject var model: PenglaiSettingsModel

  var body: some View {
    if model.filter == .changed {
      PenglaiAdvancedRows(listed: true)
    } else if let id = model.advancedSection, let section = PenglaiAdvanced.section(id) {
      PenglaiAdvancedSectionPage(section: section)
    } else {
      PenglaiAdvancedHub()
    }
  }
}

/// 進階頁總覽：一般的設定、引擎參數兩區，每一類一張卡片，點一下進去
struct PenglaiAdvancedHub: View {
  @EnvironmentObject var model: PenglaiSettingsModel
  private let columns = Array(repeating: GridItem(.flexible(), spacing: 10, alignment: .top), count: 3)

  var body: some View {
    let sections = model.hubSections
    let rows = model.advancedRows
    VStack(alignment: .leading, spacing: 18) {
      ForEach([false, true], id: \.self) { tuning in
        let list = sections.filter { $0.tuning == tuning }
        if !list.isEmpty {
          VStack(alignment: .leading, spacing: 8) {
            Text(tuning ? "引擎參數" : "功能細項").font(.system(size: 13, weight: .semibold))
            LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
              ForEach(list) { section in
                let mine = rows.filter { $0.place.section == section.id }
                PenglaiAdvancedTile(section: section, count: mine.count, changed: mine.filter(\.row.isUserSet).count) {
                  model.openAdvanced(section.id)
                }
              }
            }
            if tuning {
              Text("這幾類是組字引擎的參數，改了會直接影響候選怎麼排。不確定時點「還原預設」就回到原本的值。")
                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
          }
        }
      }
      if model.changedCount > 0 {
        Button { model.filter = .changed; model.pageIndex = 0 } label: {
          HStack(spacing: 4) {
            Text("已自訂的項目（\(model.changedCount)）")
            Image(systemName: "chevron.right")
          }
        }
        .buttonStyle(.link)
        .font(.system(size: 12.5))
      }
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 30).padding(.top, 16)
  }
}

/// 總覽裡的一類：圖示、名稱、裡面有什麼、幾項（改過幾項）
struct PenglaiAdvancedTile: View {
  var section: PenglaiAdvanced.Section
  var count: Int
  var changed: Int
  var action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(alignment: .top, spacing: 10) {
        Image(systemName: section.symbol)
          .font(.system(size: 13, weight: .semibold)).foregroundColor(.white)
          .frame(width: 26, height: 26)
          .background(RoundedRectangle(cornerRadius: 6).fill(section.tint.gradient))
        VStack(alignment: .leading, spacing: 3) {
          Text(section.title).font(.system(size: 13, weight: .semibold))
          Text(section.desc).font(.system(size: 11)).foregroundStyle(.secondary)
            .lineLimit(2).fixedSize(horizontal: false, vertical: true)
          Text(changed > 0 ? "\(count) 項・已自訂 \(changed) 項" : "\(count) 項")
            .font(.system(size: 10.5).monospacedDigit())
            .foregroundColor(changed > 0 ? .accentColor : .secondary)
            .padding(.top, 1)
        }
        Spacer(minLength: 0)
        Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundColor(.secondary)
          .frame(height: 26)
      }
      .padding(10)
      .frame(maxWidth: .infinity, minHeight: 84, alignment: .topLeading)
      .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
      .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(nsColor: .separatorColor)))
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .penglaiHighlight(section.title)
  }
}

/// 進階頁的一類：有好幾組時上面一排分段按鈕，功能沒打開時頁首提醒
struct PenglaiAdvancedSectionPage: View {
  @EnvironmentObject var model: PenglaiSettingsModel
  var section: PenglaiAdvanced.Section

  var body: some View {
    let segments = model.advancedSegments(section.id)
    VStack(alignment: .leading, spacing: 0) {
      if segments.count > 1 {
        PenglaiSegmented(options: segments.map { ($0.id, $0.title) }, selection: model.advancedSegment) { choice in
          model.advancedSegment = choice
          model.pageIndex = 0
        }
        .padding(.horizontal, 30).padding(.top, 14)
      }
      if let banner = PenglaiAdvanced.banner(section.id, model: model) {
        HStack(spacing: 10) {
          Label(banner.text, systemImage: "info.circle.fill").font(.system(size: 12)).foregroundStyle(.secondary)
          Spacer(minLength: 0)
          Button("到「\(PenglaiSettingsModel.Page.typing.title)」打開") { model.go(toCopy: banner.item, page: .typing) }
        }
        .padding(.horizontal, 30).padding(.top, 12)
      }
      PenglaiAdvancedRows(listed: false,
                          footer: section.tuning ? "改了會直接影響候選怎麼排。不確定時點「還原預設」就回到原本的值。"
                            : (segments.first { $0.id == model.advancedSegment } ?? segments.first)?.footer)
    }
  }
}

/// 進階頁的設定列，超過一頁才出現上一頁、下一頁。listed 是已自訂的項目列表：標題不拿掉開頭，說明改成它在哪一類
struct PenglaiAdvancedRows: View {
  @EnvironmentObject var model: PenglaiSettingsModel
  var listed: Bool
  var footer: String? = nil

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Form {
        Section {
          if model.visibleRows.isEmpty {
            Text(listed ? "還沒有自訂過任何項目。" : "這一類沒有可以調整的項目。").foregroundStyle(.secondary)
          }
          ForEach(model.visibleRows) { row in
            PenglaiGenericRow(row: row, listed: listed)
          }
        } footer: {
          if let footer {
            Text(footer).font(.system(size: 11)).foregroundStyle(.secondary)
          }
        }
      }
      .penglaiForm()
      Spacer(minLength: 0)
      if model.pageCount > 1 {
        HStack(spacing: 10) {
          Button { model.pageIndex = max(0, model.pageIndex - 1) } label: { Label("上一頁", systemImage: "chevron.left").frame(minWidth: 70) }
            .disabled(model.pageIndex == 0)
          Text("第 \(min(model.pageIndex, model.pageCount - 1) + 1) 頁，共 \(model.pageCount) 頁").font(.system(size: 12).monospacedDigit())
            .foregroundStyle(.secondary).frame(minWidth: 110)
          Button { model.pageIndex = min(model.pageCount - 1, model.pageIndex + 1) } label: {
            HStack(spacing: 4) { Text("下一頁"); Image(systemName: "chevron.right") }.frame(minWidth: 70)
          }
          .disabled(model.pageIndex >= model.pageCount - 1)
        }
        .controlSize(.large)
        .frame(maxWidth: .infinity)
        .padding(.bottom, 12)
      }
    }
  }
}

/// 主頁某一列旁邊的「細部調整」：跳到那一類細項（在進階頁，或掛在別頁的分頁）
struct PenglaiDetailLink: View {
  @EnvironmentObject var model: PenglaiSettingsModel
  var section: String
  var segment: String? = nil

  var body: some View {
    if model.advancedSections.contains(where: { $0.id == section }) {
      Button { model.openAdvanced(section, segment: segment) } label: {
        HStack(spacing: 2) {
          Text("細部調整")
          Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold))
        }
      }
      .buttonStyle(.link)
      .font(.system(size: 11.5))
    }
  }
}

/// 進階頁的一列：依型別給控制項。
/// 模糊音的勾選框：一對一顆按鈕，按下是開（輸入頁、進階「打錯也對得到」共用）
struct PenglaiFuzzyPairs: View {
  @EnvironmentObject var model: PenglaiSettingsModel

  var body: some View {
    let state = model.fuzzyState
    let extra = state.pairs.filter { !PenglaiSettingsModel.fuzzyChoices.contains($0) }
    HStack(spacing: 4) {
      ForEach(PenglaiSettingsModel.fuzzyChoices, id: \.self) { pair in
        let on = state.pairs.contains(pair)
        Button { model.setFuzzyPair(pair, !on) } label: {
          HStack(spacing: 3) {
            Image(systemName: on ? "checkmark" : "plus").font(.system(size: 10, weight: .bold))
            Text(pair).font(.system(size: 14))
          }
          .padding(.horizontal, 10).padding(.vertical, 5)
          .foregroundStyle(on ? Color.white : Color.primary)
          .background(RoundedRectangle(cornerRadius: 7).fill(on ? Color.accentColor : Color.secondary.opacity(0.18)))
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("模糊音 \(pair)")
        .accessibilityValue(on ? "開" : "關")
      }
      if !extra.isEmpty {
        Text("＋" + extra.joined(separator: " ")).font(.system(size: 11)).foregroundStyle(.secondary)
          .help("設定檔裡另外寫的，這裡不改")
      }
    }
    .disabled(!state.enabled)
  }
}

struct PenglaiGenericRow: View {
  @EnvironmentObject var model: PenglaiSettingsModel
  var row: PenglaiSettingRow
  /// 已自訂的項目列表：標題不拿掉開頭，說明改成它在哪一類
  var listed = false
  @State private var draft = ""

  var body: some View {
    let hint = PenglaiAdvanced.hint(row, model: model)
    PenglaiFormRow(title: listed ? model.searchTitle(row) : model.displayTitle(row),
                   desc: listed ? model.advancedLocation(row) : PenglaiAdvanced.desc(row),
                   row: row, note: model.shortcutConflict(row), resettable: row.info?.noReset != true, hint: hint) {
      control.disabled(hint != nil)
    }
  }

  private func label(_ text: String) -> String {
    row.info?.labels?[text] ?? PenglaiSettingsModel.display(text)
  }

  @ViewBuilder private var control: some View {
    let enabled = row.blocked == nil
    switch row.type {
    case "bool":
      PenglaiSwitch(isOn: row.shownValue.map { $0 == "true" }, enabled: enabled) { model.set(row, .bool($0)) }
    case "int", "double":
      if let options = row.info?.options, options.count <= 6 {
        PenglaiSegmented(options: options.map { ($0.text, label($0.text)) }, selection: row.shownValue, enabled: enabled) { text in
          model.set(row, row.type == "int" ? .int(Int(text) ?? 0) : .double(Double(text) ?? 0))
        }
      } else {
        PenglaiStepper(value: row.shownValue.flatMap(Double.init), step: row.info?.step ?? (row.type == "int" ? 1 : 0.1),
                       range: (row.info?.min ?? -1_000_000)...(row.info?.max ?? 1_000_000), enabled: enabled) { value in
          model.set(row, row.type == "int" ? .int(Int(value)) : .double(value))
        }
      }
    default:
      if row.key == PenglaiSettingsModel.fuzzyPairsKey {
        PenglaiFuzzyPairs()
      } else if PenglaiShortcuts.keys.contains(row.key), let options = row.info?.options {
        // 快速鍵：選項全列（不限 6 個），設定檔手改成別的值時多列一個；選了別人的鍵就對調
        let current = model.shortcutValue(row)
        let values = options.map(\.text) + (options.contains { $0.text == current } ? [] : [current])
        PenglaiSegmented(options: values.map { ($0, label($0)) }, selection: current, enabled: enabled) {
          model.setShortcut(row, $0)
        }
      } else if let options = row.info?.options, options.count <= 6 {
        PenglaiSegmented(options: options.map { ($0.text, label($0.text)) }, selection: row.shownValue, enabled: enabled) {
          model.set(row, .string($0))
        }
      } else {
        HStack(spacing: 6) {
          TextField("", text: $draft).labelsHidden().frame(width: 220).textFieldStyle(.roundedBorder)
          Button("套用") { model.set(row, .string(draft)) }.disabled(!enabled || draft == (row.shownValue ?? ""))
        }
        .disabled(!enabled)
        .onAppear { draft = row.shownValue ?? "" }
        .onChange(of: row.shownValue) { draft = $0 ?? "" }
      }
    }
  }
}

// MARK: - 搜尋

/// 一筆搜尋結果：點下去跳到哪一頁、哪一項。
struct PenglaiSearchResult: Identifiable {
  var id: String
  var title: String
  var desc: String?
  var page: PenglaiSettingsModel.Page
  var location: String? = nil    // 右邊寫的位置；nil 是頁名
  var highlight: String          // 跳過去之後閃哪一列（那一列的標題，配色是配色名稱）
  var row: PenglaiSettingRow?    // 分類表裡的細項：要翻到它那一頁、那個分頁（進階頁是那一類、那一組）
  var darkColors: Bool?          // 配色：切到淺色或深色那一組
  var rank: Int                  // 標題符合排前面，主頁排在進階頁前面
}

enum PenglaiSearch {
  /// 常見的別的說法（兩岸用語、口語）
  static let synonyms: [String: [String]] = [
    "字體": ["字型", "字級"], "字型": ["字體"], "字號": ["字級"], "大小": ["字級"], "字大": ["字級"],
    "顏色": ["配色"], "主題": ["配色"], "皮膚": ["配色"], "外觀": ["配色", "樣式"],
    "候選詞": ["候選"], "候選字": ["候選"], "聯想": ["補完"], "模糊音": ["容錯", "漏打"], "糾錯": ["容錯", "糾錯"],
    "記憶": ["學習"], "詞頻": ["學習"], "快捷鍵": ["快速鍵"], "熱鍵": ["快速鍵"], "捷徑": ["快速鍵"], "簡體": ["簡化字", "繁簡"], "繁體": ["繁簡", "臺灣字形"],
  ]

  /// 搜尋範圍：主頁每一項（名稱、說明、別名）、配色名稱、輸入方案、進階頁列得出來的項目。設定鍵、檔名不搜。
  static func results(_ query: String, model: PenglaiSettingsModel) -> [PenglaiSearchResult] {
    let words = query.split(whereSeparator: \.isWhitespace).map(String.init)
    guard !words.isEmpty else { return [] }
    // 每個詞連同義詞一起比：空白隔開的每個詞都要對到（同一個詞的同義詞對到一個就算）
    func forms(_ word: String) -> [String] { [word] + (synonyms[word] ?? []) }
    func score(_ title: String, _ others: [String]) -> Int? {
      let titleHit = words.allSatisfy { word in forms(word).contains { title.localizedStandardContains($0) } }
      let anyHit = words.allSatisfy { word in forms(word).contains { form in ([title] + others).contains { $0.localizedStandardContains(form) } } }
      return titleHit ? 0 : anyHit ? 1 : nil
    }
    var results: [PenglaiSearchResult] = []
    func addCopy(_ item: PenglaiCopyItem, _ page: PenglaiSettingsModel.Page, dark: Bool? = nil, available: Bool = true) {
      guard available, let hit = score(item.title, [item.desc ?? "", page.title] + item.keywords) else { return }
      results.append(PenglaiSearchResult(id: "copy|\(item.title)", title: item.title, desc: item.desc, page: page,
                                         highlight: item.title, darkColors: dark, rank: hit * 10))
    }
    let schemaReady = !model.schemaID.isEmpty
    addCopy(PenglaiCopy.layout, .panel)
    addCopy(PenglaiCopy.fontSize, .panel)
    addCopy(PenglaiCopy.pageSize, .panel, available: schemaReady)
    addCopy(PenglaiCopy.inlineMode, .panel)
    addCopy(PenglaiCopy.statusIcon, .panel)
    addCopy(PenglaiCopy.lightScheme, .colors, dark: false)
    addCopy(PenglaiCopy.darkScheme, .colors, dark: true)
    // 讀音頁放在輸入頁前面：搜「讀音」時三個選項排在「筆畫查字」（別名也有讀音）前面
    let readingReady = model.readingSwitch != nil
    addCopy(PenglaiCopy.readingPage, .reading, available: readingReady)
    for option in model.readingSwitch?.options.filter(PenglaiReading.options.contains) ?? [] {
      addCopy(PenglaiCopy.readingOption(option), .reading, available: readingReady)
    }
    addCopy(PenglaiCopy.english, .typing, available: model.schemaRow(PenglaiSettingsModel.englishKey) != nil)
    addCopy(PenglaiCopy.prediction, .typing, available: model.predictionSwitch != nil)
    addCopy(PenglaiCopy.strokeLookup, .typing, available: model.schemaRow(PenglaiSettingsModel.reverseLookupKey) != nil)
    addCopy(PenglaiCopy.sentences, .typing, available: schemaReady)
    addCopy(PenglaiCopy.phraseLength, .typing, available: schemaReady)
    addCopy(PenglaiCopy.revertSeconds, .typing, available: schemaReady)
    addCopy(PenglaiCopy.keyModel, .correction, available: model.schemaRow(PenglaiSettingsModel.keyModelKey) != nil)
    addCopy(PenglaiCopy.fuzzy, .correction, available: model.schemaRow(PenglaiSettingsModel.keyModelKey) != nil)
    addCopy(PenglaiCopy.spacePunct, .punct, available: model.schemaRow(PenglaiSettingsModel.spacePunctKey) != nil)
    addCopy(PenglaiCopy.longPress, .punct, available: model.row(PenglaiSettingsModel.longPressKey, config: .squirrel) != nil)
    addCopy(PenglaiCopy.dictionary, .dictionary, available: schemaReady)
    addCopy(PenglaiCopy.schemes, .schemas, available: model.sidebarPages.contains(.schemas))
    addCopy(PenglaiCopy.history, .history)
    addCopy(PenglaiCopy.redeploy, .history)
    addCopy(PenglaiCopy.cleanup, .history, available: model.unusedCount > 0)
    for scheme in model.colorSchemes {
      guard let hit = score(scheme.name, []) else { continue }
      results.append(PenglaiSearchResult(id: "color|\(scheme.id)", title: "配色：\(scheme.name)", desc: "選字窗的配色，淺色、深色模式都能選。",
                                         page: .colors, highlight: scheme.name, rank: 20 + hit))
    }
    for schema in model.schemas where model.sidebarPages.contains(.schemas) {
      guard let hit = score(schema.name, []) else { continue }
      results.append(PenglaiSearchResult(id: "schema|\(schema.id)", title: "輸入方案：\(schema.name)", desc: "要不要列在方案選單裡。",
                                         page: .schemas, highlight: schema.name, rank: 20 + hit))
    }
    for (row, place) in model.advancedRows {
      let title = model.searchTitle(row)
      let desc = PenglaiAdvanced.desc(row)
      let location = model.advancedLocation(row)
      guard let hit = score(title, [desc ?? "", location ?? ""]) else { continue }
      results.append(PenglaiSearchResult(id: "row|\(row.id)", title: title, desc: desc, page: PenglaiAdvanced.section(place.section)?.page ?? .all,
                                         location: location, highlight: model.displayTitle(row), row: row,
                                         rank: 30 + hit * 10))
    }
    return results.enumerated().sorted { ($0.element.rank, $0.offset) < ($1.element.rank, $1.offset) }.map(\.element)
  }
}

struct PenglaiSearchPage: View {
  @EnvironmentObject var model: PenglaiSettingsModel
  static let perPage = 8

  var body: some View {
    let results = PenglaiSearch.results(model.searchText, model: model)
    let pages = max(1, (results.count + Self.perPage - 1) / Self.perPage)
    let index = min(model.searchPage, pages - 1)
    VStack(alignment: .leading, spacing: 0) {
      VStack(alignment: .leading, spacing: 4) {
        Text("搜尋結果").font(.system(size: 20, weight: .bold))
        Text(results.isEmpty ? "找不到「\(model.searchText)」。可以換個說法，例如「字體」「顏色」「英文」。"
                             : "「\(model.searchText)」找到 \(results.count) 項，點一下就跳過去。")
          .font(.system(size: 12)).foregroundStyle(.secondary)
      }
      .padding(.horizontal, 30).padding(.top, 18)
      if !results.isEmpty {
        Form {
          Section {
            ForEach(results[(index * Self.perPage)..<min(results.count, (index + 1) * Self.perPage)]) { result in
              Button { model.go(to: result) } label: {
                LabeledContent {
                  HStack(spacing: 4) {
                    Text(result.location ?? result.page.title)
                    Image(systemName: "chevron.right")
                  }
                  .font(.system(size: 12)).foregroundStyle(.secondary)
                } label: {
                  VStack(alignment: .leading, spacing: 3) {
                    Text(result.title)
                    if let desc = result.desc { Text(desc).font(.system(size: 11.5)).foregroundStyle(.secondary).lineLimit(1) }
                  }
                }
                .contentShape(Rectangle())
              }
              .buttonStyle(.plain)
            }
          }
        }
        .penglaiForm()
      }
      Spacer(minLength: 0)
      if pages > 1 {
        HStack(spacing: 10) {
          Button { model.searchPage = max(0, index - 1) } label: { Label("上一頁", systemImage: "chevron.left").frame(minWidth: 70) }
            .disabled(index == 0)
          Text("第 \(index + 1) 頁，共 \(pages) 頁").font(.system(size: 12).monospacedDigit()).foregroundStyle(.secondary).frame(minWidth: 110)
          Button { model.searchPage = min(pages - 1, index + 1) } label: {
            HStack(spacing: 4) { Text("下一頁"); Image(systemName: "chevron.right") }.frame(minWidth: 70)
          }
          .disabled(index >= pages - 1)
        }
        .controlSize(.large)
        .frame(maxWidth: .infinity)
        .padding(.bottom, 12)
      }
    }
  }
}

extension PenglaiSettingsModel {
  /// 點搜尋結果：清掉搜尋、換到那一頁（細項翻到它那個分頁、那一頁，配色切到淺色或深色），那一列閃 2.5 秒
  func go(to result: PenglaiSearchResult) {
    searchText = ""
    if let dark = result.darkColors { colorsDark = dark }
    if let row = result.row, let place = PenglaiAdvanced.place(row, model: self) {
      openAdvanced(place.section, segment: place.segment)
      pageIndex = (filteredRows.firstIndex { $0.id == row.id } ?? 0) / Self.rowsPerPage
    } else if page == result.page {
      showHome()
    } else {
      page = result.page
    }
    flash(result.highlight)
  }

  /// 跳到主頁的某一項（進階頁「到「一般」打開」）
  func go(toCopy item: PenglaiCopyItem, page: Page) {
    searchText = ""
    if self.page == page { showHome() } else { self.page = page }
    flash(item.title)
  }

  /// 那一列閃 2.5 秒
  func flash(_ title: String) {
    highlight = title
    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
      if self?.highlight == title { self?.highlight = nil }
    }
  }
}

// MARK: - 變更紀錄

struct PenglaiHistoryPage: View {
  @EnvironmentObject var model: PenglaiSettingsModel
  static let shown = 6

  var body: some View {
    Form {
      Section {
        if model.history.isEmpty {
          Text("還沒有從這個視窗做過變更。").foregroundStyle(.secondary)
        }
        ForEach(Array(model.history.suffix(Self.shown).reversed()), id: \.id) { entry in
          LabeledContent {
            Button("復原到這一步之前") { model.undo(through: entry.id) }
          } label: {
            VStack(alignment: .leading, spacing: 2) {
              Text(PenglaiSettingsModel.cleanSummary(entry.summary)).lineLimit(1)
              Text(PenglaiSettingsView.time(entry.time)).font(.system(size: 11).monospacedDigit()).foregroundStyle(.secondary)
            }
          }
        }
      } header: {
        Text(PenglaiCopy.history.title)
      } footer: {
        if model.history.count > Self.shown {
          Text("另有 \(model.history.count - Self.shown) 筆較早的紀錄，最多保留 \(PenglaiSettingsStore.historyLimit) 筆。")
            .font(.system(size: 11)).foregroundStyle(.secondary)
        }
      }
      Section("維護") {
        LabeledContent {
          Button("重新部署") { model.redeploy() }
        } label: {
          VStack(alignment: .leading, spacing: 3) {
            Text(PenglaiCopy.redeploy.title)
            Text(PenglaiCopy.redeploy.desc ?? "").font(.system(size: 11.5)).foregroundStyle(.secondary)
          }
        }
        .penglaiHighlight(PenglaiCopy.redeploy.title)
        if model.unusedCount > 0 {
          LabeledContent {
            Button("清除") { model.removeUnusedSettings() }
          } label: {
            VStack(alignment: .leading, spacing: 3) {
              Text("\(PenglaiCopy.cleanup.title)（\(model.unusedCount) 項）")
              Text(PenglaiCopy.cleanup.desc ?? "").font(.system(size: 11.5)).foregroundStyle(.secondary)
            }
          }
          .penglaiHighlight(PenglaiCopy.cleanup.title)
        }
      }
    }
    .penglaiForm()
  }
}

// MARK: - 視窗

final class PenglaiSettingsWindowController: NSWindowController, NSWindowDelegate {
  static var shared: PenglaiSettingsWindowController?
  let model: PenglaiSettingsModel

  init(model: PenglaiSettingsModel) {
    self.model = model
    let window = NSWindow(contentRect: NSRect(origin: .zero, size: PenglaiSettingsView.size), styleMask: [.titled, .closable, .miniaturizable],
                          backing: .buffered, defer: false)
    window.title = "蓬萊設定"
    window.isReleasedWhenClosed = false
    window.contentView = NSHostingView(rootView: PenglaiSettingsView(model: model))
    window.center()
    super.init(window: window)
    window.delegate = self
  }

  required init?(coder: NSCoder) { nil }

  /// 輸入法程序裡的設定資料：設定視窗和第一次使用的引導共用同一份（同一份變更紀錄）。
  /// 讀音這類方案選項要馬上生效時，通知每個輸入框的控制器改自己的 session（SquirrelInputController 收 .penglaiSetOptions）
  static let inputMethodModel: PenglaiSettingsModel = {
    let model = PenglaiSettingsModel(userDir: SquirrelApp.userDir,
                                     sharedDir: Bundle.main.sharedSupportURL,
                                     catalogURL: Bundle.main.url(forResource: "penglai-settings", withExtension: "json"),
                                     deployer: inputMethodDeployer)
    model.liveOptions = { NotificationCenter.default.post(name: .penglaiSetOptions, object: $0) }
    return model
  }()

  /// 輸入法選單呼叫：設定視窗開在輸入法自己的程序裡，直接用正在跑的 librime。
  static func showInInputMethod() {
    if shared == nil {
      shared = PenglaiSettingsWindowController(model: inputMethodModel)
    }
    shared?.model.reload()
    shared?.showWindow(nil)
    shared?.window?.makeKeyAndOrderFront(nil)
    shared?.window?.orderFrontRegardless()
    NSApp.activate(ignoringOtherApps: true)
  }

  /// 在輸入法程序裡部署：只改前端設定時只重讀 sable.yaml，不打斷打字；其他的整個重新部署，等 librime 回報結果。
  static let inputMethodDeployer: PenglaiSettingsModel.Deployer = { onlySquirrel, completion in
    let delegate = NSApp.squirrelAppDelegate
    if onlySquirrel {
      let ok = delegate.rimeAPI.deploy_config_file("sable.yaml", "config_version")
      delegate.loadSettings()
      completion(ok)
      return
    }
    final class Waiter {
      var token: NSObjectProtocol?
      var finished = false
      func finish() -> Bool {
        guard !finished else { return false }
        finished = true
        if let token { NotificationCenter.default.removeObserver(token) }
        return true
      }
    }
    let waiter = Waiter()
    waiter.token = NotificationCenter.default.addObserver(forName: .penglaiDeployMessage, object: nil, queue: .main) { note in
      guard let value = note.object as? String, value == "success" || value == "failure", waiter.finish() else { return }
      completion(value == "success")
    }
    SquirrelApplicationDelegate.quietDeploy = true
    delegate.deploy()
    // 15 秒還沒收到結果就當作做完了（例如沒有任何東西要重建時 librime 不回報）
    DispatchQueue.main.asyncAfter(deadline: .now() + 15) {
      guard waiter.finish() else { return }
      SquirrelApplicationDelegate.quietDeploy = false
      completion(!delegate.rimeAPI.is_maintenance_mode())
    }
  }

  func windowDidBecomeKey(_ notification: Notification) {
    // 回到視窗時重讀：手改了檔案也看得到
    model.reload()
  }
}

extension Notification.Name {
  static let penglaiDeployMessage = Notification.Name("PenglaiDeployMessage")
  /// 改每個輸入框 session 的選項：object 是 [選項名稱: 開或關]
  static let penglaiSetOptions = Notification.Name("PenglaiSetOptions")
}
