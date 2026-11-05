// 單鍵快速鍵（原 penglai_tap.lua）：選單開著時，修飾鍵點一下（按下就放開，中間沒按別的鍵）。每個都有看得到的提示。
// 哪個鍵做哪件事讀方案設定 penglai_tap/copy、forget、second（沒設時是括號裡的預設）：
//   複製（Control，左右都可以）：目前的輸入和候選以 JSON 放進剪貼簿，接著清掉輸入（不送出），可以直接貼；
//     游標旁邊跳出「已複製輸入和候選」
//   刪學習紀錄（右 Command）：刪掉反白候選的學習紀錄，輸入區後面顯示〔已刪學習紀錄：…〕。
//     沒有學習紀錄的詞典詞（兩個字以上）由引擎改成隱藏（方案檔 translator/dictionary_exclude_file，
//     寫進 penglai_hidden.txt），顯示〔已隱藏：…〕；提示還在的時候（下一個鍵）按 BackSpace 復原，顯示〔已恢復：…〕。
//     單字、整句、自訂詞不刪也不隱藏，顯示〔沒有學習紀錄：…〕
//   選第二個（右 Option）：選這一頁的第二個候選。蓋住整段輸入就直接送出，游標旁邊跳出「已選第二個：…」；
//     只蓋住前面一部分（「可以」的第二個是「可」）就只選它，跟 Shift+2 一樣，後面的輸入留著繼續選，
//     輸入區顯示〔已選第二個：可〕
// 沒選單時不攔，照常交給系統。輸入區的提示按下一個鍵就消失。
// 另外接引擎「忘掉上一筆」的結果（translator/forget_last_code，打 77）：游標旁邊跳出「已忘掉：…」。
// 跟組合鍵分開：按下修飾鍵之後有別的鍵事件（Control+A、Command+C、Option+字母），或放開時還按著別的修飾鍵，就不觸發。
// Command 組合鍵、被選單或系統攔走的鍵、滑鼠點擊，貂毫不交給 librime；貂毫（patches/squirrel/0001）
// 會在放開修飾鍵之前補送一個 VoidSymbol 的放開事件，這裡照「別的鍵」處理。
//
// 掛法：engine/processors 的 ascii_composer 後面。方案檔照舊寫 lua_processor@*penglai_tap@penglai_tap
// （librime patch 0020 導到這個元件，命名空間是 @ 後面那段），也可以直接寫 penglai_tap。
//   penglai_tap/copy、forget、second：Control（左右都算）、Alt_L、Alt_R、Super_L、Super_R，空字串＝關。
//     認不得的鍵名當成關、記一筆錯誤；兩件事寫成同一個鍵時，照 copy、forget、second 的順序先寫的有作用
//   penglai_tap/limit：複製時最少列幾個候選（預設 18；反白候選所在的那一頁一定列完）
//   penglai_tap/clipboard：false 時只寫檔、不動剪貼簿（沙盒測試用）
//   penglai_tap/pasteboard：放進這個名字的剪貼簿，不放系統剪貼簿（沙盒測試用）
//
// 複製的輸出（使用者資料夾，不在 rime-backup 白名單）：penglai_dump.json 最近一次（覆蓋，剪貼簿放的就是這份）、
// penglai_dump.jsonl 每次一行。欄位：
//   input 輸入碼；zhuyin 輸入碼換成注音；preedit 輸入區顯示的文字；highlighted 反白的是第幾個（1 起算）
//   segments：輸入切成的段落（span 是輸入碼的起訖位置，selected 是這段目前的候選）
//   candidates：rank 第幾個；text 顯示的字；raw 臺灣字形轉換前的字（有差才列）
//     span、preedit：候選只蓋住一部分輸入時才列，是它蓋住的輸入碼位置和注音
//     type：user_phrase 學過的詞、phrase 詞典詞、sentence 整句、user_table／punct 等
//     commits：學習紀錄的送出次數；weight：詞條權重（取過 log，學過的詞含新近值）；quality：最後排序用的分數
//     voco：外部詞頻表的次數（使用者資料夾有 jason_voco_data.tbl 才有）；words：整句拆成的詞
#ifndef PENGLAI_TAP_H_
#define PENGLAI_TAP_H_

#include <map>
#include <rime/algo/algebra.h>
#include <rime/context.h>
#include <rime/processor.h>
#include "penglai_common.h"

namespace penglai {

class PenglaiTap : public rime::Processor {
 public:
  explicit PenglaiTap(const rime::Ticket& ticket);
  ~PenglaiTap() override;

  rime::ProcessResult ProcessKeyEvent(const rime::KeyEvent& key_event) override;

 private:
  bool Dump();
  void Copy(rime::Context* ctx);
  void Forget(rime::Context* ctx);
  void Second(rime::Context* ctx);
  void OnPropertyUpdate(rime::Context* ctx, const string& name);

  int limit_ = 18;
  bool clipboard_ = true;
  std::optional<string> pasteboard_;
  int page_size_ = 9;
  string dump_path_;
  std::optional<rime::Projection> preedit_format_;
  std::map<int, string> tap_;   // 鍵碼 → 哪件事
  std::optional<int> armed_;
  InputPrompt prompt_;
  struct UndoHide {
    string raw;   // 臺灣字形轉換前的字（清單裡的寫法）
    string text;  // 提示裡的字
  };
  std::optional<UndoHide> undo_hide_;
  an<SortedTable> freq_;
  rime::connection forget_connection_;
};

}  // namespace penglai

#endif  // PENGLAI_TAP_H_
