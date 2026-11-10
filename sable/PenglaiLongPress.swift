//
//  PenglaiLongPress.swift
//  Squirrel
//
//  長按出符號（11/10）：數字列和 , . / ; - 這幾個鍵在蓬萊注音裡是注音或聲調，長按就當成按住 Shift 再按一下，
//  打出那個鍵 Shift 的符號（長按 . 是「。」、/ 是「？」、; 是「：；」選單、1 是「！」），跟 ⇧ 加那個鍵一模一樣，標點選單照方案。
//  手機的畫荻這幾個鍵也是長按出同一個符號。
//
//  什麼叫長按：鍵按著到系統開始自動重複（系統設定「鍵盤 › 重複前延遲」）。只看自動重複的 keyDown：重複只有鍵真的按著才會來，
//  App 卡住、事件晚到也不會把已經放開的鍵當成長按。原本這時候就會開始重複（ㄡㄡㄡ），放得比重複快的按法完全不變。
//  App 不送重複時（「按住出變音字母」攔下的鍵）沒有長按，系統關掉按鍵重複也沒有。
//  11/10 試過計時器（時間到看視窗伺服器的「上次放開鍵幾秒前」「按鍵次數」判斷還按著）：這兩個值在輸入法程序裡讀不準
//  （推測沒有輸入監控權限時讀不到鍵盤事件），點一下就換成符號，當天拿掉。
//
//  怎麼換：按下去的那一下照常交給 librime（注音先出來）。按下去之前、之後的輸入對得上「只多了這一鍵」，才記著；
//  時間到時輸入還是那樣，就把輸入換回按下去之前（set_input），再送一個帶 Shift 的符號鍵給 librime。
//  數字鍵組字中按 ⇧數字是選字，所以數字鍵先把組字區送出再送符號（標點鍵不用：⇧, ⇧. 本來就連前面的字一起送出，
//  有選單的 ⇧/ ⇧; ⇧- 選單接在組字區後面）。之後的自動重複都吃掉，按了別的鍵就結束。
//  這一下有別的作用（↓ 數字選字、聲調換聲調、送出了東西）時輸入對不上，就不換。
//  App 自己把組字送出（commitComposition）的情況（11/10 T3：單獨一個 / 顯示成「/」，T3 輸入框開頭出現 / 就開斜線指令選單、
//  把組字送出，iMessage 沒有）：送出去的就是這一鍵、按下去之前組字區是空的，記著；時間到時游標前面確實是它，就先刪掉再換。
//  診斷：每一步寫系統記錄（subsystem im.penglai.sable、category longpress，只記鍵和步驟，不記打的字；notice 等級才會存檔）：
//    log show --last 10m --predicate 'subsystem == "im.penglai.sable"'
//  修飾鍵沒變的 flagsChanged 不算（11/10 T3：輸入框開頭的 / 讓 T3 開斜線指令選單，長按被清掉，重複照一般鍵打成一串 /）。
//
//  設定：sable.yaml 的 long_press_symbols（預設開；蓬萊設定「輸入」頁）。
//

import AppKit
import os

final class PenglaiLongPress {
  /// 記著的這一鍵：按下去之前的輸入（換回去用）、按下去之後的輸入（核對還沒變），要送的符號
  struct Armed {
    let keyCode: UInt16
    let symbol: Character
    let digit: Bool
    let restore: String
    let restoreCaret: Int
    let input: String
    let caret: Int
    let downTime: TimeInterval        // 按下去的時間（NSEvent.timestamp，開機起算）
  }

  /// 鍵上的字 → 美式鍵盤 Shift 的符號。只收蓬萊注音裡是注音、聲調的非字母鍵
  static let shiftSymbols: [Character: Character] = [
    "1": "!", "2": "@", "3": "#", "4": "$", "5": "%", "6": "^", "7": "&", "8": "*", "9": "(", "0": ")",
    "-": "_", ",": "<", ".": ">", "/": "?", ";": ":",
  ]

  /// 沒寫就是開
  static var enabled: Bool {
    NSApp.squirrelAppDelegate.config?.getBool("long_press_symbols") ?? true
  }

  static let log = Logger(subsystem: "im.penglai.sable", category: "longpress")

  private(set) var armed: Armed?
  private var fired = false
  /// 時間到之前 App 把組字送出了（送出去的就是這一鍵）
  private(set) var clientCommitted = false
  /// 時間到、還按著時呼叫；回傳 false＝輸入已經變了，沒換
  var onFire: ((Armed) -> Bool)?

  /// 記著、還沒換的時候被清掉，記下原因（診斷用）
  func cancel(_ reason: StaticString) {
    if let a = armed, !fired {
      Self.log.notice("cancel \(String(a.symbol), privacy: .public): \(reason, privacy: .public)")
    }
    reset()
  }

  func reset() {
    armed = nil
    fired = false
    clientCommitted = false
  }

  /// 不是自動重複的 keyDown 交給 librime 之後：這一下只是在游標處多了這個鍵（或送出了前面、這個鍵自己開始組字），才記著
  func noteKey(keyCode: UInt16, char: Character, plain: Bool, handled: Bool, downTime: TimeInterval,
               before: (input: String, caret: Int), after: (input: String, caret: Int)) {
    reset()
    guard plain, handled, let symbol = Self.shiftSymbols[char], Self.enabled else { return }
    let bytes = Array(before.input.utf8)
    guard before.caret >= 0, before.caret <= bytes.count else { return }
    let inserted = String(decoding: bytes[..<before.caret] + Array(String(char).utf8) + bytes[before.caret...], as: UTF8.self)
    let restore: (String, Int)
    if after.input == inserted && after.caret == before.caret + 1 {
      restore = before
    } else if after.input == String(char) && after.caret == 1 {
      restore = ("", 0)   // 前面的已經送出，這一鍵自己開始組字
    } else {
      return
    }
    armed = Armed(keyCode: keyCode, symbol: symbol, digit: char.isNumber, restore: restore.0, restoreCaret: restore.1,
                  input: after.input, caret: after.caret, downTime: downTime)
    Self.log.notice("armed \(String(symbol), privacy: .public) fresh=\(restore.0.isEmpty, privacy: .public)")
  }

  enum Repeat {
    case pass     // 不是記著的鍵：照舊重複
    case swallow  // 記著的鍵、已經換過了：吃掉
    case fire     // 第一個重複：換成符號
  }

  /// App 要求送出組字（commitComposition）：送出去的是記著的這一鍵、按下去之前組字區是空的，才記著（之後換的時候要先刪掉它）
  func noteClientCommit(input: String) {
    guard let a = armed, !fired else { return }
    clientCommitted = input == a.input && a.restore.isEmpty
    Self.log.notice("client commit while armed \(String(a.symbol), privacy: .public) same=\(self.clientCommitted, privacy: .public)")
    if !clientCommitted { reset() }
  }

  /// 自動重複的 keyDown：重複只有鍵按著才會來
  func onRepeat(keyCode: UInt16, timestamp: TimeInterval) -> Repeat {
    guard let a = armed, a.keyCode == keyCode else { return .pass }
    return fired ? .swallow : .fire
  }

  /// 換成符號：換過就不再換
  func fire() {
    guard let a = armed, !fired else { return }
    fired = true
    let ok = onFire?(a) == true
    Self.log.notice("fire \(String(a.symbol), privacy: .public) ok=\(ok, privacy: .public) clientCommitted=\(self.clientCommitted, privacy: .public)")
    if !ok { reset() }
  }

}
