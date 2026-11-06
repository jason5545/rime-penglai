#include "penglai_freq_rerank.h"

#include <cmath>
#include <cstdio>
#include <ctime>
#include <map>
#include <set>
#include <rime/candidate.h>
#include <rime/config.h>
#include <rime/context.h>
#include <rime/engine.h>
#include <rime/gear/translator_commons.h>
#include <rime/schema.h>
#include <rime/translation.h>

namespace penglai {

using namespace rime;

namespace {

// 參與重排的候選類型（script_translator 產生的）；其他類型（custom_phrase 的 user_table 等）位置固定
bool IsMovable(const string& type) {
  return type == "user_phrase" || type == "phrase" || type == "sentence" || type == "completion";
}

// 這段輸入有沒有聲調鍵（大千：空白、6 3 4 7）
bool HasToneKey(const string& seg) {
  return seg.find_first_of(" 6347") != string::npos;
}

// Lua 的 input:sub(start + 1, end)
string Slice(const string& s, size_t start, size_t end) {
  if (end > s.size())
    end = s.size();
  if (start >= end)
    return "";
  return s.substr(start, end - start);
}

// 照 Lua 那版的 filter：先往後讀到第一頁（keylid 不算數）再重排、整批交出去，之後讀一個交一個。
// 跟 LuaTranslation 一樣，建好就先讀到第一個候選（重排在這時做完，之後不再碰 filter）
class RerankTranslation : public Translation {
 public:
  RerankTranslation(an<Translation> source, PenglaiFreqRerank* filter) : source_(source) {
    double window = filter->params().window;
    size_t counted = 0;
    bool flushed = false;
    while (!source_->exhausted()) {
      auto c = source_->Peek();
      source_->Next();
      if (!c)
        break;
      buffer_.push_back(c);
      if (Candidate::GetGenuineCandidate(c)->type() != "keylid")
        ++counted;
      if ((double)counted >= window) {
        Flush(filter);
        flushed = true;
        break;
      }
    }
    if (!flushed)
      Flush(filter);
    // 第一頁之後照原順序一個一個交
    pass_through_ = flushed;
    set_exhausted(false);
    Next();
  }

  bool Next() override {
    if (exhausted())
      return false;
    if (pos_ < buffer_.size()) {
      current_ = buffer_[pos_++];
      return true;
    }
    if (pass_through_ && !source_->exhausted()) {
      auto c = source_->Peek();
      source_->Next();
      if (c) {
        current_ = c;
        return true;
      }
    }
    set_exhausted(true);
    return false;
  }

  an<Candidate> Peek() override { return current_; }

 private:
  void Flush(PenglaiFreqRerank* filter) {
    if (buffer_.size() < 2)
      return;
    if (filter->timing()) {
      std::clock_t t0 = std::clock();
      filter->Rerank(&buffer_);
      filter->RecordTime((double)(std::clock() - t0) / CLOCKS_PER_SEC);
    } else {
      filter->Rerank(&buffer_);
    }
  }

  an<Translation> source_;
  vector<an<Candidate>> buffer_;
  size_t pos_ = 0;
  bool pass_through_ = false;
  an<Candidate> current_;
};

}  // namespace

PenglaiFreqRerank::PenglaiFreqRerank(const Ticket& ticket) : Filter(ticket), TagMatching(ticket) {
  Config* config = engine_->schema()->config();
  const string& ns = name_space_;
  auto get = [&](const char* key, double* value) {
    double v;
    if (config->GetDouble(ns + "/" + key, &v))
      *value = v;
  };
  get("window", &params_.window);
  params_.window = std::floor(params_.window);
  get("max_top_commits", &params_.max_top_commits);
  get("min_voco", &params_.min_voco);
  get("min_ratio", &params_.min_ratio);
  get("lambda", &params_.lambda);
  get("prior_total", &params_.prior_total);
  get("margin", &params_.margin);
  string log;
  if (config->GetString(ns + "/timing_log", &log) && !log.empty())
    timing_log_ = log;
  data_ = FreqTable();
  if (!data_)
    LOG(ERROR) << "penglai_freq_rerank: 讀不到 jason_voco_data.tbl";
}

PenglaiFreqRerank::~PenglaiFreqRerank() {
  if (timing_log_ && !times_.empty()) {
    if (FILE* f = fopen(timing_log_->c_str(), "a")) {
      for (const auto& t : times_) {
        fwrite(t.data(), 1, t.size(), f);
        fputc('\n', f);
      }
      fclose(f);
    }
  }
}

void PenglaiFreqRerank::RecordTime(double seconds) {
  char buf[32];
  snprintf(buf, sizeof(buf), "%.7f", seconds);
  times_.push_back(buf);
}

an<Translation> PenglaiFreqRerank::Apply(an<Translation> translation, CandidateList* candidates) {
  return New<RerankTranslation>(translation, this);
}

bool PenglaiFreqRerank::Rerank(vector<an<Candidate>>* buf) const {
  const string& input = engine_->context()->input();
  struct Item {
    size_t i;
    int cc;
    int64_t v;
  };
  std::map<uint64_t, vector<Item>> groups;
  vector<uint64_t> order;
  std::set<uint64_t> blocked;
  for (size_t i = 0; i < buf->size(); ++i) {
    const auto& c = (*buf)[i];
    uint64_t key = (uint64_t)c->start() * 65536 + c->end();
    auto g = Candidate::GetGenuineCandidate(c);
    const string& gt = g->type();
    auto phrase = As<Phrase>(g);
    if (gt == "keylid") {
      // 按鍵層語言辨識的候選：不參加
    } else if (phrase && phrase->correction() && !HasToneKey(Slice(input, c->start(), c->end()))) {
      // 按鍵模型修過的詞、那段輸入沒有聲調鍵（沒打聲調的模糊音）：不參加（不會被詞頻拉到第一個，也不算進這組的總數）。
      // 沒打聲調的跟只打首注音分不出來：ㄨㄛ ㄗ ㄚ（我在啊）修成 ㄓㄚ 的「我查」詞頻高，原本會被拉到第一個。
      // 有聲調鍵的（ㄧㄤˇ ㄒ 修成「影響」）照舊參加
    } else if (!IsMovable(gt)) {
      // 這段輸入的第一個候選是 custom_phrase 之類：整組不動
      if (!groups.count(key))
        blocked.insert(key);
    } else if (!blocked.count(key)) {
      auto found = groups.find(key);
      if (found == groups.end()) {
        found = groups.emplace(key, vector<Item>()).first;
        order.push_back(key);
      }
      int cc = 0;
      if (gt == "user_phrase") {
        if (auto ph = As<Phrase>(g))
          cc = ph->entry().commit_count;
        if (cc < 0)
          cc = 0;
      }
      int64_t v = 0;
      if (data_)
        data_->FindInt(c->text(), &v);
      if ((double)v < params_.min_voco)
        v = 0;
      found->second.push_back({i, cc, v});
    }
  }

  bool changed = false;
  for (uint64_t key : order) {
    const auto& grp = groups[key];
    if (grp.size() < 2)
      continue;
    const Item& top = grp[0];
    const auto& first = (*buf)[top.i];
    // 完整注音（每個字都打了聲調）不重排：這時 Rime 的詞典和語言模型比詞頻可靠
    string seg = Slice(input, first->start(), first->end());
    size_t tones = 0;
    for (char ch : seg) {
      if (ch == ' ' || ch == '6' || ch == '3' || ch == '4' || ch == '7')
        ++tones;
    }
    vector<uint32_t> cps;
    size_t len = DecodeUtf8(first->text(), &cps) ? cps.size() : first->text().size();
    if (!(tones < len && (double)top.cc <= params_.max_top_commits))
      continue;
    int64_t total = 0;
    for (const auto& x : grp)
      total += x.v;
    if (total <= 0)
      continue;
    double scale = std::min(params_.lambda, params_.prior_total / (double)total);
    double st = (double)top.cc + (double)top.v * scale + params_.margin;
    double need = params_.min_ratio * (double)(top.v + 1);
    std::optional<size_t> best;
    double best_s = 0;
    for (size_t j = 1; j < grp.size(); ++j) {
      const Item& x = grp[j];
      if ((double)x.v >= need && (double)x.v >= params_.min_voco) {
        double s = (double)x.cc + (double)x.v * scale;
        if (s > st && (!best || s > best_s)) {
          best = j;
          best_s = s;
        }
      }
    }
    if (best) {
      // 挑戰者移到這組的第一個位置，其他照原順序往後
      vector<an<Candidate>> cands;
      cands.push_back((*buf)[grp[*best].i]);
      for (size_t j = 0; j < grp.size(); ++j) {
        if (j != *best)
          cands.push_back((*buf)[grp[j].i]);
      }
      for (size_t j = 0; j < grp.size(); ++j)
        (*buf)[grp[j].i] = cands[j];
      changed = true;
    }
  }
  return changed;
}

}  // namespace penglai
