#include "penglai_tap.h"

#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <ctime>
#include <rime/candidate.h>
#include <rime/composition.h>
#include <rime/config.h>
#include <rime/engine.h>
#include <rime/gear/translator_commons.h>
#include <rime/key_event.h>
#include <rime/menu.h>
#include <rime/schema.h>

namespace penglai {

using namespace rime;

namespace {

const int kBackSpace = 0xff08;

// 三件事和預設的鍵（照這個順序：同一個鍵寫給兩件事時，先列的有作用）
const vector<std::pair<string, string>> kDefaultKeys = {
    {"copy", "Control"},
    {"forget", "Super_R"},
    {"second", "Alt_R"},
};

// JSON：照 Lua 那版的 enc／pretty。整數和浮點分開記（Lua 的 integer 用 %d、float 用 %.6g）
struct Json {
  enum Type { kString, kInt, kNumber, kArray, kObject } type;
  string s;
  long long i = 0;
  double d = 0;
  vector<Json> items;                      // 陣列
  vector<std::pair<string, Json>> fields;  // 物件（照放進去的順序）

  static Json Str(const string& v) { Json j{kString}; j.s = v; return j; }
  static Json Int(long long v) { Json j{kInt}; j.i = v; return j; }
  static Json Num(double v) { Json j{kNumber}; j.d = v; return j; }
  static Json Arr() { return Json{kArray}; }
  static Json Obj() { return Json{kObject}; }
  void Put(const string& key, Json value) { fields.emplace_back(key, std::move(value)); }
};

// 不用 iscntrl：輸入法程序的語系會把 UTF-8 的 0x80–0x9F 位元組也當控制字元
string JsonString(const string& s) {
  string out = "\"";
  for (unsigned char c : s) {
    if (c == '"') {
      out += "\\\"";
    } else if (c == '\\') {
      out += "\\\\";
    } else if (c == '\n') {
      out += "\\n";
    } else if (c == '\t') {
      out += "\\t";
    } else if (c <= 31) {
      char buf[8];
      snprintf(buf, sizeof(buf), "\\u%04x", c);
      out += buf;
    } else {
      out += (char)c;
    }
  }
  return out + "\"";
}

string JsonNumber(const Json& v) {
  char buf[64];
  if (v.type == Json::kInt) {
    snprintf(buf, sizeof(buf), "%lld", v.i);
    return buf;
  }
  if (std::isnan(v.d) || std::isinf(v.d))
    return "null";
  snprintf(buf, sizeof(buf), "%.6g", v.d);
  return buf;
}

string Encode(const Json& v) {
  switch (v.type) {
    case Json::kString:
      return JsonString(v.s);
    case Json::kInt:
    case Json::kNumber:
      return JsonNumber(v);
    case Json::kObject: {
      string out = "{";
      for (size_t k = 0; k < v.fields.size(); ++k) {
        if (k)
          out += ",";
        out += JsonString(v.fields[k].first) + ":" + Encode(v.fields[k].second);
      }
      return out + "}";
    }
    case Json::kArray: {
      string out = "[";
      for (size_t k = 0; k < v.items.size(); ++k) {
        if (k)
          out += ",";
        out += Encode(v.items[k]);
      }
      return out + "]";
    }
  }
  return "null";
}

// 第一層一個鍵一行，陣列一個元素一行，貼進對話好讀
string Pretty(const Json& o) {
  string out = "{\n";
  for (size_t k = 0; k < o.fields.size(); ++k) {
    const Json& v = o.fields[k].second;
    string s;
    if (v.type == Json::kArray && !v.items.empty()) {
      s = "[\n";
      for (size_t j = 0; j < v.items.size(); ++j) {
        if (j)
          s += ",\n";
        s += "    " + Encode(v.items[j]);
      }
      s += "\n  ]";
    } else {
      s = Encode(v);
    }
    if (k)
      out += ",\n";
    out += "  " + JsonString(o.fields[k].first) + ": " + s;
  }
  return out + "\n}\n";
}

const char* StatusName(Segment::Status status) {
  switch (status) {
    case Segment::kVoid: return "kVoid";
    case Segment::kGuess: return "kGuess";
    case Segment::kSelected: return "kSelected";
    case Segment::kConfirmed: return "kConfirmed";
  }
  return "";
}

Json CandidateInfo(long long rank, const an<Candidate>& c, const Segment& seg, const an<SortedTable>& freq) {
  Json o = Json::Obj();
  auto g = Candidate::GetGenuineCandidate(c);
  bool partial = c->start() != seg.start || c->end() != seg.end;
  o.Put("rank", Json::Int(rank));
  o.Put("text", Json::Str(c->text()));
  if (g->text() != c->text())
    o.Put("raw", Json::Str(g->text()));
  o.Put("type", Json::Str(g->type()));
  if (partial) {
    Json span = Json::Arr();
    span.items.push_back(Json::Int((long long)c->start()));
    span.items.push_back(Json::Int((long long)c->end()));
    o.Put("span", span);
  }
  auto s = As<Sentence>(g);
  auto ph = As<Phrase>(g);
  if (s) {
    o.Put("weight", Json::Num(s->weight()));
  } else if (ph) {
    const DictEntry& e = ph->entry();
    if (g->type() == "user_phrase" || e.commit_count > 0)
      o.Put("commits", Json::Int(e.commit_count));
    o.Put("weight", Json::Num(ph->weight()));
  }
  o.Put("quality", Json::Num(c->quality()));
  int64_t v;
  if (freq && freq->FindInt(c->text(), &v))
    o.Put("voco", Json::Int(v));
  if (s) {
    Json words = Json::Arr();
    for (const auto& e : s->components()) {
      Json w = Json::Obj();
      w.Put("text", Json::Str(e.text));
      if (e.commit_count > 0)
        w.Put("commits", Json::Int(e.commit_count));
      w.Put("weight", Json::Num(e.weight));
      words.items.push_back(w);
    }
    o.Put("words", words);
  }
  if (partial && !c->preedit().empty())
    o.Put("preedit", Json::Str(c->preedit()));
  if (!c->comment().empty())
    o.Put("comment", Json::Str(c->comment()));
  return o;
}

// 從檔案讀 UTF-8 再放進剪貼簿（JXA）：輸入法的程序沒有 LANG，pbcopy 會把中文當 MacRoman 讀成亂碼
std::optional<string> CopyCommand(const string& path, const std::optional<string>& name) {
  if ((path + name.value_or("")).find_first_of("'\"\\") != string::npos)
    return std::nullopt;
  string pb = "$.NSPasteboard.generalPasteboard";
  if (name)
    pb = "$.NSPasteboard.pasteboardWithName(\"" + *name + "\")";
  string js = "ObjC.import(\"AppKit\");"
              "var s=$.NSString.stringWithContentsOfFileEncodingError(\"" + path + "\",4,null);"
              "var p=" + pb + ";p.clearContents;p.setStringForType(s,$.NSPasteboardTypeString)";
  return "/usr/bin/osascript -l JavaScript -e '" + js + "' >/dev/null 2>&1 &";
}

string LocalTime() {
  std::time_t now = std::time(nullptr);
  std::tm tm;
  localtime_r(&now, &tm);
  char buf[32];
  std::strftime(buf, sizeof(buf), "%Y-%m-%d %H:%M:%S", &tm);
  return buf;
}

// 「forgotten／gone／none<Tab>送出的文字」（librime patch 0006）：狀態是英文字母，Tab 後面整段是文字
bool ParseForgetLast(const string& value, string* status, string* text) {
  size_t tab = value.find('\t');
  if (tab == string::npos || tab == 0)
    return false;
  for (size_t k = 0; k < tab; ++k) {
    char c = value[k];
    if (!((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')))
      return false;
  }
  *status = value.substr(0, tab);
  *text = value.substr(tab + 1);
  return true;
}

}  // namespace

PenglaiTap::PenglaiTap(const Ticket& ticket) : Processor(ticket) {
  Config* config = engine_->schema()->config();
  const string& ns = name_space_;
  config->GetInt(ns + "/limit", &limit_);
  bool clipboard;
  if (config->GetBool(ns + "/clipboard", &clipboard) && !clipboard)
    clipboard_ = false;
  string pasteboard;
  if (config->GetString(ns + "/pasteboard", &pasteboard) && !pasteboard.empty())
    pasteboard_ = pasteboard;
  page_size_ = engine_->schema()->page_size();
  if (page_size_ < 1)
    page_size_ = 9;
  dump_path_ = UserDataPath("penglai_dump.json");
  if (auto list = config->GetList("translator/preedit_format")) {
    Projection p;
    if (p.Load(list))
      preedit_format_ = p;
  }
  // 鍵碼 → 哪件事（沒寫時用 kDefaultKeys 的預設）
  std::map<string, std::optional<string>> names;
  string value;
  if (config->GetString(ns + "/copy", &value))
    names["copy"] = value;
  if (config->GetString(ns + "/forget", &value))
    names["forget"] = value;
  if (config->GetString(ns + "/second", &value))
    names["second"] = value;
  for (const auto& item : kDefaultKeys) {
    const string& action = item.first;
    string name = names[action].value_or(item.second);
    const vector<int>* codes = KeyCodesOf(name, false);
    if (!name.empty() && !codes) {
      LOG(ERROR) << "penglai_tap: " << ns << "/" << action << " 的鍵「" << name << "」認不得，這件事當成關";
    }
    if (!codes)
      continue;
    for (int code : *codes) {
      if (tap_.count(code)) {
        LOG(ERROR) << "penglai_tap: " << name << " 已經給了 " << tap_[code] << "，" << action << " 不用它";
      } else {
        tap_[code] = action;
      }
    }
  }
  freq_ = FreqTable();
  // 引擎忘掉上一筆之後設 forget_last 屬性
  forget_connection_ = engine_->context()->property_update_notifier().connect(
      [this](Context* ctx, const string& name) { OnPropertyUpdate(ctx, name); });
}

PenglaiTap::~PenglaiTap() {
  forget_connection_.disconnect();
}

void PenglaiTap::OnPropertyUpdate(Context* ctx, const string& name) {
  if (name != "forget_last")
    return;
  string status, text;
  if (!ParseForgetLast(ctx->get_property("forget_last"), &status, &text))
    return;
  if (status == "forgotten") {
    ShowNotice(engine_, "已忘掉：" + text);
  } else if (status == "gone") {
    ShowNotice(engine_, "學習紀錄裡已經沒有：" + text);
  } else if (status == "none") {
    ShowNotice(engine_, "沒有可忘掉的紀錄");
  }
}

bool PenglaiTap::Dump() {
  Context* ctx = engine_->context();
  auto& comp = ctx->composition();
  if (comp.empty())
    return false;
  Segment& seg = comp.back();
  auto menu = seg.menu;
  if (!menu)
    return false;

  Json o = Json::Obj();
  o.Put("time", Json::Str(LocalTime()));
  o.Put("input", Json::Str(ctx->input()));
  if (preedit_format_) {
    string zhuyin = ctx->input();
    preedit_format_->Apply(&zhuyin);
    o.Put("zhuyin", Json::Str(zhuyin));
  }
  o.Put("preedit", Json::Str(ctx->GetPreedit().text));
  long long idx = (long long)seg.selected_index;
  o.Put("highlighted", Json::Int(idx + 1));
  o.Put("page_size", Json::Int(page_size_));

  Json segs = Json::Arr();
  for (const Segment& s : comp) {
    Json so = Json::Obj();
    Json span = Json::Arr();
    span.items.push_back(Json::Int((long long)s.start));
    span.items.push_back(Json::Int((long long)s.end));
    so.Put("span", span);
    so.Put("status", Json::Str(StatusName(s.status)));
    if (auto sc = s.GetSelectedCandidate())
      so.Put("selected", Json::Str(sc->text()));
    segs.items.push_back(so);
  }
  o.Put("segments", segs);

  long long page_end = (idx / page_size_ + 1) * page_size_;
  size_t n = menu->Prepare((size_t)std::max<long long>(limit_, page_end));
  Json cands = Json::Arr();
  for (size_t i = 0; i < n; ++i) {
    auto c = menu->GetCandidateAt(i);
    if (!c)
      break;
    cands.items.push_back(CandidateInfo((long long)i + 1, c, seg, freq_));
  }
  o.Put("candidates", cands);

  FILE* f = fopen(dump_path_.c_str(), "w");
  if (!f) {
    LOG(ERROR) << "penglai_tap: 寫不進 " << dump_path_;
    return false;
  }
  string pretty = Pretty(o);
  fwrite(pretty.data(), 1, pretty.size(), f);
  fclose(f);
  if (FILE* h = fopen((dump_path_ + "l").c_str(), "a")) {
    string line = Encode(o) + "\n";
    fwrite(line.data(), 1, line.size(), h);
    fclose(h);
  }
  if (clipboard_) {
    if (auto cmd = CopyCommand(dump_path_, pasteboard_))
      std::system(cmd->c_str());
  }
  return true;
}

// 複製完清掉輸入（10/27：不用再按 Esc 就能直接貼）；失敗就留著輸入、在輸入區提示
void PenglaiTap::Copy(Context* ctx) {
  if (Dump()) {
    ctx->Clear();
    ShowNotice(engine_, "已複製輸入和候選");
  } else {
    prompt_.Set(ctx, "〔複製失敗〕");
  }
}

// 跟 Shift+Delete／Ctrl+K 走同一條路（Context::DeleteCurrentSelection）：學過的詞，引擎刪學習紀錄；
// 沒有學習紀錄的詞典詞（script_translator 的 phrase，兩個字以上），引擎寫進隱藏清單、重建候選
// （translator/dictionary_exclude_file）。整句、自訂詞（custom_phrase）、單字只提示
void PenglaiTap::Forget(Context* ctx) {
  auto c = ctx->GetSelectedCandidate();
  if (!c)
    return;
  auto g = Candidate::GetGenuineCandidate(c);
  vector<uint32_t> cps;
  if (g->type() == "phrase" && DecodeUtf8(g->text(), &cps) && cps.size() >= 2) {
    string raw = g->text();
    string text = c->text();
    ctx->DeleteCurrentSelection();
    // 引擎沒設 dictionary_exclude_file（或寫不進檔案）時不會寫進清單
    if (!hidden_list::Has(raw)) {
      prompt_.Set(ctx, "〔隱藏失敗：" + text + "〕");
      return;
    }
    prompt_.Set(ctx, "〔已隱藏：" + text + "〕");
    undo_hide_ = UndoHide{raw, text};
    return;
  }
  if (g->type() != "user_phrase") {
    prompt_.Set(ctx, "〔沒有學習紀錄：" + c->text() + "〕");
    return;
  }
  auto ph = As<Phrase>(g);
  int n = ph ? ph->entry().commit_count : 0;
  string text = c->text();
  ctx->DeleteCurrentSelection();
  prompt_.Set(ctx, "〔已刪學習紀錄：" + text + (n > 0 ? "（" + std::to_string(n) + " 次）" : "") + "〕");
}

// 選這一頁的第二個（KP_2，跟 Shift+2 一樣）。蓋住整段輸入就再送出（原本 key_binder 的 {KP_2}{Return}）；
// 只蓋住前面一部分就停在這裡讓後面的輸入繼續選（10/27 選的；原本會連後面的第一候選一起送出，「可以」變「可已」）
void PenglaiTap::Second(Context* ctx) {
  Segment& seg = ctx->composition().back();
  size_t i = seg.selected_index / page_size_ * page_size_ + 1;
  seg.menu->Prepare(i + 1);
  auto c = seg.menu->GetCandidateAt(i);
  if (!c) {
    prompt_.Set(ctx, "〔沒有第二個候選〕");
    return;
  }
  string text = c->text();
  // 後段沒有候選時（謝謝打全碼，ㄒㄧㄝ˙ 查不到）選完也沒有選單，要看候選有沒有蓋到輸入結尾，不然會連按鍵字母一起送出
  bool whole = c->end() == ctx->input().length();
  bool prediction = seg.HasTag("prediction");
  engine_->ProcessKey(KeyEvent("KP_2"));
  // 聯想（librime-predict）選了就送出，不用再送 Return（送了會當成交給 App 的 Return，清掉送出紀錄）
  if (prediction) {
    ShowNotice(engine_, "已選第二個：" + text);
    return;
  }
  if (ctx->HasMenu() || !whole) {
    prompt_.Set(ctx, "〔已選第二個：" + text + "〕");
    return;
  }
  engine_->ProcessKey(KeyEvent("Return"));
  ShowNotice(engine_, "已選第二個：" + text);
}

ProcessResult PenglaiTap::ProcessKeyEvent(const KeyEvent& key) {
  Context* ctx = engine_->context();
  // 剛隱藏完（〔已隱藏：…〕還在）的下一個鍵：BackSpace 就復原，其他鍵照常
  if (undo_hide_ && !key.release()) {
    UndoHide undo = *undo_hide_;
    undo_hide_.reset();
    bool shown = prompt_.Showing(ctx);
    if (shown && key.keycode() == kBackSpace && !(key.shift() || key.ctrl() || key.alt() || key.super())) {
      prompt_.Clear(ctx);
      hidden_list::Remove(undo.raw);
      ctx->RefreshNonConfirmedComposition();
      prompt_.Set(ctx, "〔已恢復：" + undo.text + "〕");
      return kAccepted;
    }
  }
  prompt_.Clear(ctx);
  auto it = tap_.find(key.keycode());
  if (it == tap_.end()) {
    armed_.reset();
    return kNoop;
  }
  if (!key.release()) {
    armed_ = key.keycode();
    return kNoop;
  }
  auto armed = armed_;
  armed_.reset();
  // 放開時還按著別的修飾鍵（例如 Control＋右 Command）也不算
  if (armed != key.keycode() || key.shift() || key.ctrl() || key.alt() || key.super())
    return kNoop;
  if (!ctx->HasMenu())
    return kNoop;
  const string action = it->second;
  if (action == "copy")
    Copy(ctx);
  else if (action == "forget")
    Forget(ctx);
  else if (action == "second")
    Second(ctx);
  return kAccepted;
}

}  // namespace penglai
