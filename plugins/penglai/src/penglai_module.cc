// 蓬萊外掛模組：註冊元件。
// 原本是 Lua 的那幾個另外用「lua_processor:*<模組>」「lua_filter:*<模組>」的名字再註冊一次：方案檔照舊寫
// lua_processor@*penglai_tap@penglai_tap 時，librime patch 0020 先找這個名字，找到就用這裡的元件，不載 Lua，
// 命名空間照 librime-lua 的規則（@ 後面那段）。方案檔、custom 檔、設定視窗讀寫的鍵都不用改。
#include <rime/component.h>
#include <rime/registry.h>
#include <rime_api.h>
#include "penglai_common.h"
#include "penglai_freq_rerank.h"
#include "penglai_numsel.h"
#include "penglai_space.h"
#include "penglai_tap.h"

using namespace rime;
using namespace penglai;

static void rime_penglai_initialize() {
  Registry& r = Registry::instance();
  r.Register("penglai_tap", new Component<PenglaiTap>);
  r.Register("penglai_numsel", new Component<PenglaiNumsel>);
  r.Register("penglai_space", new Component<PenglaiSpace>);
  r.Register("penglai_freq_rerank", new Component<PenglaiFreqRerank>);
  r.Register("lua_processor:*penglai_tap", new Component<PenglaiTap>);
  r.Register("lua_processor:*penglai_numsel", new Component<PenglaiNumsel>);
  r.Register("lua_processor:*penglai_space", new Component<PenglaiSpace>);
  // 原本 Lua 版的寫法（jason_voco_rerank.lua），沿用這個名稱的設定照樣能用
  r.Register("lua_filter:*jason_voco_rerank", new Component<PenglaiFreqRerank>);
}

static void rime_penglai_finalize() {
  ResetSharedState();
  PenglaiNumsel::ResetShared();
}

RIME_REGISTER_MODULE(penglai)
