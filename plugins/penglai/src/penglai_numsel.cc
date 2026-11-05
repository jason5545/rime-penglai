#include "penglai_numsel.h"

#include <map>
#include <rime/composition.h>
#include <rime/config.h>
#include <rime/engine.h>
#include <rime/key_event.h>
#include <rime/menu.h>
#include <rime/schema.h>

namespace penglai {

using namespace rime;

namespace {

const char kPrompt[] = "〔選字：按數字〕";
const char kProperty[] = "penglai_numsel";
const char kLabels[] = "menu/alternative_select_labels";

bool IsMove(int code) {
  // Up、Down、KP_Up、KP_Down
  return code == 0xff52 || code == 0xff54 || code == 0xff97 || code == 0xff99;
}

// 所有 session 共用：目前在狀態中的 session 數、換成數字之前的標籤（讀不到字串的那幾個不記，換回時也不動）
int active_count = 0;
std::optional<std::map<int, string>> saved_labels;

void SetLabels(Config* config, bool digits) {
  int n = (int)config->GetListSize(kLabels);
  if (digits) {
    saved_labels.emplace();
    for (int i = 0; i < n; ++i) {
      string path = string(kLabels) + "/@" + std::to_string(i);
      string label;
      if (config->GetString(path, &label))
        (*saved_labels)[i] = label;
      config->SetString(path, std::to_string((i + 1) % 10));
    }
  } else if (saved_labels) {
    for (const auto& item : *saved_labels)
      config->SetString(string(kLabels) + "/@" + std::to_string(item.first), item.second);
    saved_labels.reset();
  }
}

}  // namespace

void PenglaiNumsel::ResetShared() {
  active_count = 0;
  saved_labels.reset();
}

PenglaiNumsel::PenglaiNumsel(const Ticket& ticket) : Processor(ticket) {
  Config* config = engine_->schema()->config();
  bool commit_whole;
  if (config->GetBool(name_space_ + "/commit_whole", &commit_whole) && !commit_whole)
    commit_whole_ = false;
  string name;
  if (!config->GetString(name_space_ + "/trigger", &name))
    name = "Down";
  const vector<int>* codes = KeyCodesOf(name, true);
  if (!name.empty() && !codes) {
    LOG(ERROR) << "penglai_numsel: " << name_space_ << "/trigger 的鍵「" << name << "」認不得，數字選字當成關";
  }
  if (codes)
    trigger_.insert(codes->begin(), codes->end());
  tap_ = name != "Down";
  // 有掛這個 processor 就寫 off：聯想看到屬性就照這裡的狀態，沒有屬性時才照舊用「移過反白」判斷
  engine_->context()->set_property(kProperty, "off");
  update_connection_ = engine_->context()->update_notifier().connect([this](Context* ctx) {
    if (!active_)
      return;
    if (ctx->HasMenu())
      prompt_.Set(ctx, kPrompt);
    else
      Leave(ctx);
  });
  commit_connection_ = engine_->context()->commit_notifier().connect([this](Context* ctx) { Leave(ctx); });
}

PenglaiNumsel::~PenglaiNumsel() {
  update_connection_.disconnect();
  commit_connection_.disconnect();
  if (active_)
    Leave(engine_->context());
  // 切到沒掛這個 processor 的方案時 context 不換，屬性留著會讓聯想以為數字選字是關的；清成空字串＝沒有屬性，聯想照舊判斷
  engine_->context()->set_property(kProperty, "");
}

void PenglaiNumsel::Enter(Context* ctx) {
  if (active_)
    return;
  active_ = true;
  engine_->context()->set_property(kProperty, "on");
  active_count += 1;
  if (active_count == 1)
    SetLabels(engine_->schema()->config(), true);
  prompt_.Set(ctx, kPrompt);
}

void PenglaiNumsel::Leave(Context* ctx) {
  if (!active_)
    return;
  active_ = false;
  ctx->set_property(kProperty, "off");
  active_count -= 1;
  if (active_count <= 0) {
    active_count = 0;
    SetLabels(engine_->schema()->config(), false);
  }
  prompt_.Clear(ctx);
}

bool PenglaiNumsel::Select(Context* ctx, int n) {
  Segment& seg = ctx->composition().back();
  int page_size = engine_->schema()->page_size();
  if (page_size < 1)
    page_size = 9;
  size_t first = seg.selected_index / page_size * page_size;
  if (seg.menu->Prepare(first + n) < first + n)
    return false;
  // 蓋住整段＝候選一直蓋到輸入結尾。不能只看選完有沒有選單：後段沒有候選時（謝謝打全碼，ㄒㄧㄝ˙ 查不到）選單也會消失
  bool whole = seg.menu->GetCandidateAt(first + n - 1)->end() == ctx->input().length();
  busy_ = true;
  engine_->ProcessKey(KeyEvent("KP_" + std::to_string(n)));
  if (whole && commit_whole_ && !ctx->HasMenu() && ctx->IsComposing())
    engine_->ProcessKey(KeyEvent("Return"));
  // 只選了前段：後段的段落是選完才建的，提示要補在新的最後一段
  if (active_ && ctx->HasMenu())
    prompt_.Set(ctx, kPrompt);
  busy_ = false;
  return true;
}

ProcessResult PenglaiNumsel::ProcessKeyEvent(const KeyEvent& key) {
  if (busy_)
    return kNoop;
  Context* ctx = engine_->context();
  int code = key.keycode();
  // 修飾鍵點一下：按下記著，中間有別的鍵（含貂毫補送的 VoidSymbol）就不算；放開時還按著別的修飾鍵也不算
  if (tap_) {
    if (trigger_.count(code)) {
      if (!key.release()) {
        armed_ = code;
        return kNoop;
      }
      auto armed = armed_;
      armed_.reset();
      if (armed != code || key.shift() || key.ctrl() || key.alt() || key.super() || !ctx->HasMenu())
        return kNoop;
      Enter(ctx);
      return kAccepted;
    }
    armed_.reset();
  }
  if (key.release())
    return kNoop;
  bool plain = !(key.shift() || key.ctrl() || key.alt() || key.super());
  if (plain && IsMove(code)) {
    if (ctx->HasMenu() && !tap_ && trigger_.count(code))
      Enter(ctx);
    return kNoop;
  }
  if (!active_)
    return kNoop;
  if (plain && code >= 0x31 && code <= 0x39 && ctx->HasMenu()) {
    int n = code - 0x30;
    bool done = Select(ctx, n);
    busy_ = false;
    if (!done)
      prompt_.Set(ctx, "〔這一頁沒有第 " + std::to_string(n) + " 個〕");
    return kAccepted;
  }
  Leave(ctx);
  return kNoop;
}

}  // namespace penglai
