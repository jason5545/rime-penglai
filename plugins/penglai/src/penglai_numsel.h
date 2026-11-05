// ↓ 之後數字鍵直接選字（原 penglai_numsel.lua；docs/interface.md 建議 1；10/28 定觸發鍵用 ↓，10/30 起可以換）
// 選單開著時按觸發鍵（預設 ↓）進入「數字選字」狀態。↓ 照舊移反白（交給 selector）；
// 換成修飾鍵時是點一下（按下就放開，中間沒按別的鍵，跟 penglai_tap 一樣），反白不動：
//   1–9：選這一頁的第 N 個，跟 Shift+N（KP_N）一樣。
//     只蓋住前面一部分就只選它，後面的輸入留著，狀態也留著，可以接著用數字選下一段；
//     蓋住整段就接著送出（跟右 Option 選第二個一樣），所以任何候選都是 ↓、N 兩下。
//   ↑、↓：照舊移反白，狀態保留。
//   其他鍵（Return、BackSpace、注音鍵、修飾鍵…）：取消狀態，那個鍵照原本處理。
// 狀態中輸入區顯示〔選字：按數字〕，選字標籤從 ⇧1… 換成 1…，取消時換回。
// 沒按觸發鍵的時候，數字照舊是注音（1＝ㄅ、3＝ˇ…）。
// 狀態也寫在 context 的 penglai_numsel 屬性（on／off）：聯想（librime-predict patch）照它決定數字鍵留給選單還是先收掉聯想。
//
// 掛法：engine/processors 的 speller 前面（penglai_tap 後面）。方案檔照舊寫 lua_processor@*penglai_numsel@penglai_numsel
// （librime patch 0020 導到這個元件），也可以直接寫 penglai_numsel。
//   penglai_numsel/trigger：Down（↓，預設）、Control（左右都算）、Alt_L、Alt_R、Super_L、Super_R，空字串＝關。
//     認不得的鍵名當成關、記一筆錯誤。跟 penglai_tap 的三件事用同一個修飾鍵時，penglai_tap 排在前面先處理，這裡不會觸發
//   penglai_numsel/commit_whole：false 時蓋住整段也只選不送出（跟 Shift+N 完全一樣，再按 Return 送出）
//
// 實作注意：
//   - 標籤是 get_context 每次從方案設定的 menu/alternative_select_labels 讀的；這裡改記憶體裡的方案設定
//     （跟 ShowNotice 一樣，不會存檔）。同一個方案的各 session 共用這份設定，所以用計數（所有 session 共用）：
//     最後一個離開狀態的 session 才換回。
//   - 選單收起來（送出、清掉、切走 app 時送出組字）就離開狀態：update_notifier 裡檢查。
//     送出時另外在 commit_notifier 離開：聯想打開時，送出之後馬上跳出聯想選單，
//     狀態要是還留著，接著打的數字（↓1 送出後打 1＝ㄅ）會被當成選聯想。
//   - 自己送的 KP_N、Return 會再跑一次整串 processor，送的時候標記 busy，不當成「其他鍵」。
#ifndef PENGLAI_NUMSEL_H_
#define PENGLAI_NUMSEL_H_

#include <set>
#include <rime/context.h>
#include <rime/processor.h>
#include "penglai_common.h"

namespace penglai {

class PenglaiNumsel : public rime::Processor {
 public:
  explicit PenglaiNumsel(const rime::Ticket& ticket);
  ~PenglaiNumsel() override;

  rime::ProcessResult ProcessKeyEvent(const rime::KeyEvent& key_event) override;

  // 所有 session 共用的計數和換掉之前的標籤（模組結束時清掉）
  static void ResetShared();

 private:
  void Enter(rime::Context* ctx);
  void Leave(rime::Context* ctx);
  // 選這一頁的第 n 個；回傳 false 表示這一頁沒有第 n 個
  bool Select(rime::Context* ctx, int n);

  bool commit_whole_ = true;
  std::set<int> trigger_;
  bool tap_ = false;   // 修飾鍵：點一下才算
  std::optional<int> armed_;
  bool active_ = false;
  bool busy_ = false;
  InputPrompt prompt_;
  rime::connection update_connection_;
  rime::connection commit_connection_;
};

}  // namespace penglai

#endif  // PENGLAI_NUMSEL_H_
