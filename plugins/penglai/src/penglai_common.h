// 蓬萊外掛模組的共用部分：鍵名表、UTF-8、游標旁的提示、輸入區提示、資料表、隱藏清單。
// 這些元件原本是 rime-config/lua/ 的 Lua（10/31 搬成 C++，a9581e0 之前的版本在 git 歷史裡），
// 行為逐條照 Lua 那版：設定的鍵、提示文字、context 屬性、檔案格式都一樣。
#ifndef PENGLAI_COMMON_H_
#define PENGLAI_COMMON_H_

#include <rime/common.h>
#include <cstdint>
#include <optional>
#include <string_view>

namespace rime {
class Context;
class Engine;
}  // namespace rime

namespace penglai {

using rime::an;
using rime::string;
using rime::vector;

// 修飾鍵點一下、數字選字的觸發鍵：設定的值 → 鍵碼。Down 只有數字選字能用（快速鍵的三件事選 Down 當成認不得）。
// 要加鍵：這裡和 settings/notes.json 那幾個鍵的 options、labels 一起改
const vector<int>* KeyCodesOf(const string& name, bool allow_down);

// Lua 5.4 的 utf8.codes／utf8.len（嚴格模式）：整串照順序解得開才算，失敗時回傳 false
bool DecodeUtf8(const string& text, vector<uint32_t>* code_points);
// 解開後每個字的位元組（跟 Lua 的 utf8.char(c) 一樣）
bool SplitUtf8(const string& text, vector<string>* chars);

// 游標旁的提示（原 penglai_notice.lua）：方案的 _penglai_notice 開關第二個狀態的標籤改成要說的話，打開再關掉。
// 貂毫只在選單收起來、輸入區是空的時候顯示；選單開著時用輸入區的 prompt（InputPrompt）
bool ShowNotice(rime::Engine* engine, const string& text);

// 輸入區（游標處）的提示：接在輸入後面，按下一個鍵就清掉。每個元件各記各的
class InputPrompt {
 public:
  void Set(rime::Context* ctx, const string& text);
  // 最後一段的提示還是自己設的那句才清
  void Clear(rime::Context* ctx);
  bool Showing(rime::Context* ctx) const;
  bool active() const { return text_.has_value(); }

 private:
  std::optional<string> text_;
};

// 使用者資料夾裡的檔案
string UserDataPath(const string& file);

// 排序好的鍵值表（.tbl，tools/penglai_tbl.py 產生），開檔時整份讀進記憶體、二分搜尋。格式（小端）：
//   "PLTB"、uint32 版本 1、uint32 值的型別（1＝int64，2＝float64）、uint32 筆數 n；
//   n 筆 {uint32 鍵的位移, uint32 鍵的長度, 8 位元組的值}，照鍵的位元組嚴格遞增；之後是所有鍵的位元組（鍵區）
// 讀不完、表頭不對、鍵指到鍵區外面、沒排好或有重複的，Open 都回傳空的（跟沒有這個檔一樣）
class SortedTable {
 public:
  enum Kind { kInteger = 1, kFloat = 2 };
  // 檔案不在、格式不對時回傳空的
  static an<SortedTable> Open(const string& file_path);

  Kind kind() const { return kind_; }
  size_t size() const { return count_; }
  // 找到時 value 是那一筆的值（整數表的值轉成 double 之前先看 FindInt）
  bool FindInt(std::string_view key, int64_t* value) const;
  bool FindFloat(std::string_view key, double* value) const;

 private:
  SortedTable() = default;
  const char* Lookup(std::string_view key) const;

  string data_;   // 整份檔案
  const char* base_ = nullptr;
  Kind kind_ = kInteger;
  uint32_t count_ = 0;
};

// 使用者自己的資料（App 不附）：使用者資料夾先找、再找共用資料夾。跟 Lua 的 require 一樣，
// 模組初始化之後第一次用時讀一次，之後沿用到模組結束（Sable --reload）
//   jason_voco_data.tbl：外部的詞頻表（整數；檔名是沿用下來的），重排和複製內容的 voco 欄用
//   penglai_punct_data.tbl：送出之後按空白補標點的問句模型（浮點）
an<SortedTable> FreqTable();
an<SortedTable> PunctTable();
// 資料表在模組結束時清掉（數字選字跨 session 的計數在 PenglaiNumsel::ResetShared）
void ResetSharedState();

// 隱藏詞典詞的清單 penglai_hidden.txt（原 penglai_hide.lua；隱藏本身在引擎，librime patch 0005）
namespace hidden_list {
// 清單裡有沒有這個詞（每次都讀檔：引擎會寫這個檔）
bool Has(const string& text);
// 從清單刪掉這個詞（BackSpace 復原用）
bool Remove(const string& text);
}  // namespace hidden_list

}  // namespace penglai

#endif  // PENGLAI_COMMON_H_
