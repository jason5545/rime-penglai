// 依外部頻率表重排（原本是 Lua 的 jason_voco_rerank.lua，改成通用元件、只吃資料檔）：
// 用外部的詞頻（使用者資料夾的 jason_voco_data.tbl，例如自己平常打的字算出來的）修正簡拼時學習紀錄排錯的第一候選。沒有資料檔時不動。
//
// 放在 engine/filters 的 simplifier@zh_hant_tw、uniquifier 之後（候選已經是臺灣字形，跟詞頻表的文字一致）。
// 原本的寫法 lua_filter@*jason_voco_rerank@jason_voco_rerank 照樣可以用（librime patch 0020 導到這個元件），
// 也可以直接寫 penglai_freq_rerank@<命名空間>。
//
// 規則（同一段輸入 start/end 相同的候選才互相比；不刪候選、不改數量，沒翻轉就維持原順序）：
//   cc = 學習紀錄送出次數（只有 user_phrase 有），v = 詞頻（低於 min_voco 當 0）
//   V  = 同一段候選的 v 總和，scale = min(lambda, prior_total / V)
//   分數 = cc + v * scale        （詞頻當先驗，最多折合 prior_total 次打字）
//   原本第一名 t 換成挑戰者 c 的條件，全部成立才翻：
//     1. cc(t) <= max_top_commits                （第一名的學習紀錄證據弱）
//     2. v(c) >= min_ratio * (v(t) + 1)、v(c) >= min_voco   （詞頻支持 c）
//     3. 分數(c) > 分數(t) + margin               （打字次數加上先驗之後，c 還是比較多）
//   符合的挑戰者取分數最高的一個移到第一，其他候選相對順序不變。
//   不動的情況：每個字都打了聲調的輸入段（完整注音）、第一名是 custom_phrase 的輸入段、只看第一頁（window）。
//   按鍵層語言辨識的候選（類型 keylid，librime patch 0013）不算：不參加重排，數第一頁的 window 時也不算。
// 設定（<命名空間>/）：window 9、max_top_commits 8、min_voco 20、min_ratio 1、lambda 0.05、prior_total 6、margin 0.5；
//   timing_log：量時間用（沙盒 bench），設了才記，元件結束時寫出每次重排花的秒數
#ifndef PENGLAI_FREQ_RERANK_H_
#define PENGLAI_FREQ_RERANK_H_

#include <rime/filter.h>
#include <rime/gear/filter_commons.h>
#include "penglai_common.h"

namespace penglai {

class PenglaiFreqRerank : public rime::Filter, rime::TagMatching {
 public:
  explicit PenglaiFreqRerank(const rime::Ticket& ticket);
  ~PenglaiFreqRerank() override;

  an<rime::Translation> Apply(an<rime::Translation> translation, rime::CandidateList* candidates) override;
  bool AppliesToSegment(rime::Segment* segment) override { return TagsMatch(segment); }

  struct Params {
    double window = 9, max_top_commits = 8, min_voco = 20, min_ratio = 1, lambda = 0.05, prior_total = 6, margin = 0.5;
  };
  // 重排一段候選（第一頁）：回傳有沒有翻
  bool Rerank(vector<an<rime::Candidate>>* buf) const;
  const Params& params() const { return params_; }
  void RecordTime(double seconds);
  bool timing() const { return timing_log_.has_value(); }

 private:
  Params params_;
  an<SortedTable> data_;
  std::optional<string> timing_log_;
  vector<string> times_;
};

}  // namespace penglai

#endif  // PENGLAI_FREQ_RERANK_H_
