//
//  PenglaiLongPress.swift
//  Squirrel
//
//  長按出符號（11/10）：數字列和 , . / ; - 這幾個鍵在蓬萊注音裡是注音或聲調，長按就當成按住 Shift 再按一下，
//  打出那個鍵 Shift 的符號（長按 . 是「。」、/ 是「？」、; 是「：；」選單、1 是「！」），跟 ⇧ 加那個鍵一模一樣，標點選單照方案。
//  手機的畫荻這幾個鍵本來就是長按出符號。
//
//  什麼叫長按：鍵按著到系統開始自動重複（系統設定「鍵盤 › 重複前延遲」）。只看自動重複的 keyDown，不用計時器：
//  重複只有鍵真的按著才會來，App 卡住、事件晚到也不會把已經放開的鍵當成長按，也不用讀鍵盤狀態（那要輸入監控權限）。
//  原本這時候就會開始重複（ㄡㄡㄡ），放得比重複快的按法完全不變。系統關掉按鍵重複時就沒有長按。
//
//  怎麼換：按下去的那一下照常交給 librime（注音先出來）。按下去之前、之後的輸入對得上「只多了這一鍵」，才記著；
//  第一個自動重複來的時候輸入還是那樣，就把輸入換回按下去之前（set_input），再送一個帶 Shift 的符號鍵給 librime。
//  數字鍵組字中按 ⇧數字是選字，所以數字鍵先把組字區送出再送符號（標點鍵不用：⇧, ⇧. 本來就連前面的字一起送出，
//  有選單的 ⇧/ ⇧; ⇧- 選單接在組字區後面）。之後的自動重複都吃掉，鍵放開、按了別的鍵就結束。
//  這一下有別的作用（77 忘掉上一筆、↓ 數字選字、標點選單接著打、送出了東西）時輸入對不上，就不換，照舊重複。
//
//  設定：sable.yaml 的 long_press_symbols（預設開；蓬萊設定「輸入」頁）。
//

import AppKit

struct PenglaiLongPress {
  /// 記著的這一鍵：按下去之前的輸入（換回去用）、按下去之後的輸入（核對還沒變），要送的符號
  struct Armed {
    let keyCode: UInt16
    let symbol: Character
    let digit: Bool
    let restore: String
    let restoreCaret: Int
    let input: String
    let caret: Int
    var fired = false
  }

  /// 鍵上的字 → 美式鍵盤 Shift 的符號。只收蓬萊注音裡是注音、聲調的非字母鍵
  static let shiftSymbols: [Character: Character] = [
    "1": "!", "2": "@", "3": "#", "4": "$", "5": "%", "6": "^", "7": "&", "8": "*", "9": "(", "0": ")",
    "-": "_", ",": "<", ".": ">", "/": "?", ";": ":",
  ]

  private(set) var armed: Armed?

  /// 沒寫就是開
  static var enabled: Bool {
    NSApp.squirrelAppDelegate.config?.getBool("long_press_symbols") ?? true
  }

  mutating func reset() {
    armed = nil
  }

  /// 不是自動重複的 keyDown 交給 librime 之後：這一下只是在游標處多了這個鍵（或送出了前面、這個鍵自己開始組字），才記著
  mutating func noteKey(keyCode: UInt16, char: Character, plain: Bool, handled: Bool,
                        before: (input: String, caret: Int), after: (input: String, caret: Int)) {
    armed = nil
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
                  input: after.input, caret: after.caret)
  }

  enum Repeat {
    case pass        // 不是記著的鍵：照舊重複
    case swallow     // 已經換過了：吃掉
    case fire(Armed) // 第一個重複：換成符號
  }

  mutating func onRepeat(keyCode: UInt16) -> Repeat {
    guard var a = armed, a.keyCode == keyCode else { return .pass }
    if a.fired { return .swallow }
    a.fired = true
    armed = a
    return .fire(a)
  }
}
