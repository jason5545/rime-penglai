// 送出之後按空白補標點（原 penglai_space.lua，10/30）：很多人打字不加標點、用空白隔開。中文送出之後、組字區空著時按空白，
// 不出空白，直接送出猜的標點：剛送出的那一句像問句時是「？」，不然是「，」。
//   要真的空白：緊接著再按一次空白，剛補的標點換成空白（中文␣）；再按就是一般的空白。換標點是貂毫做的（patch 0023）：
//     這裡把 context 的 penglai_space 設成 replace（補標點那次設成 punct），空白照原本的路走；貂毫核對游標前面確實是剛補的標點才換，
//     核對不到的 App（終端機之類）、別的前端照舊把空白鍵交給 App（標點後面接空白）。也可以先按 BackSpace 刪掉標點再按空白
//   句子打完了：補了「，」之後緊接著按 Return，「，」換成「。」，Return 照舊交給 App（換段、送出）。也是貂毫換的（patch 0025）：
//     context 的 penglai_space 設成 period，Return 照原本的路走；貂毫核對游標前面確實是剛補的「，」才換。「？」不換
//   要別的標點：直接按標點鍵（Shift+, 是「，」、Shift+. 是「。」），組字區空著時照原本的標點處理
// 「剛送出的中文」：上一筆送出的字結尾是漢字，中間沒按過送出以外的鍵。BackSpace、方向鍵、Return 送出訊息、切中西文、
//   Command 組合鍵（貼上、移游標）、在選字窗以外點滑鼠（移動插入點；貂毫補送帶 Command 的 VoidSymbol）都算斷掉，
//   之後按空白照舊出空白。連著送出好幾筆中文算同一句（一句分幾次送出時，問句照整句看）。
// 游標前是別處的字（penglai_space/foreign，沒寫時關）：貼上的、語音輸入的、原本就在文件裡的字，貂毫沒送出過。組字區空著時
//   按空白，貂毫先讀游標前後的字（各最多 100 個 UTF-16）放進 context 的 penglai_space_before、penglai_space_after，這裡照它決定
//   （ForeignPunct）：游標前一個不是字（漢字、英文字母、數字以外，或沒有字）照舊出空白；「這一句」（游標前後到換行、句末標點）
//   英文詞佔八成以上補「, 」；游標後面緊接著是開引號（「『“）補「：」（引語前面，11/5）；不然補「，」或「？」。補了之後緊接著的空白、Return 跟上面一樣（「, 」換成空白、換成「.」）。
//   原本的補標點優先；剛送出過字（英文、數字也算）、之後還沒斷掉時照舊出空白，中英混打中間的空白不受影響（這件事不看游標前的字：
//   web view 給的文字會落後）。讀不到文字的 App（終端機）、有選取範圍時貂毫給空字串，照舊出空白
// 問句：有 penglai_punct_data.tbl（使用者自己的資料，App 不附）時照它的分數，
//   特徵跟 gen_punct.py 的 feats 同一套；沒有時（公開版）用規則：結尾是 kEnds 裡的（嗎、呢、對吧…），結尾是「X 不 X」「X 沒 X」，
//   或句中有 kWords、kRuleWords 裡的詞（docs/findings.md〈送出之後按空白補標點〉）；
//   再扣掉疑問詞不是在問的用法（任指「什麼都可以」、虛指「沒什麼區別」、嵌入「不知道他去哪」），句尾是嗎、呢、對吧、是吧的不扣
//   （11/5，docs/findings.md〈疑問詞的非疑問用法〉）。模型把這三種當特徵（n:任指、n:虛指、n:嵌入）
//
// 掛法：engine/processors 的 speller 前面（penglai_numsel 後面）。方案檔照舊寫 lua_processor@*penglai_space@penglai_space
// （librime patch 0020 導到這個元件），也可以直接寫 penglai_space。
//   penglai_space/punct：false＝關（按空白照舊出空白），沒寫時開
//   penglai_space/replace：false＝補了標點之後緊接著的空白不換掉標點（標點後面接空白），沒寫時開
//   penglai_space/period：false＝補了「，」之後緊接著的 Return 不換成「。」，沒寫時開
//   penglai_space/foreign：true＝游標前是別處的字時也照前後文補標點，沒寫時關；要先開 punct
#ifndef PENGLAI_SPACE_H_
#define PENGLAI_SPACE_H_

#include <rime/context.h>
#include <rime/processor.h>
#include "penglai_common.h"

namespace penglai {

// 這一句像不像問句：有模型照模型（分數 > 0），沒有照規則。tools/punct_check 也用這支
bool IsQuestion(const string& text, const SortedTable* model);
// 模型的分數（gen_punct.py 的 feats，同一個特徵只算一次，照這個順序加總）
double QuestionScore(const string& text, const vector<string>& chars, const SortedTable& model);
// 游標前是別處的字時按空白補什麼：before、after 是游標前後的字（UTF-8）。回傳「，」「？」「：」「, 」，空字串＝照舊出空白
string ForeignPunct(const string& before, const string& after, const SortedTable* model);

class PenglaiSpace : public rime::Processor {
 public:
  explicit PenglaiSpace(const rime::Ticket& ticket);
  ~PenglaiSpace() override;

  rime::ProcessResult ProcessKeyEvent(const rime::KeyEvent& key_event) override;

 private:
  bool on_ = true;
  bool replace_ = true;
  bool period_ = true;
  bool foreign_ = false;
  bool english_ = false;   // penglai_space/english：送出英文詞之後按空白也補標點（11/3，方案預設關）
  // 剛送出字（任何字，含自己補的標點），之後還沒有斷掉 clause_ 的事件：這時的空白不看游標前後文
  bool fresh_ = false;
  std::optional<string> clause_;   // 這一句貂毫送出的字（結尾是漢字的才接著算；english 開著時英文詞也算）
  std::optional<string> mark_;   // 剛補的標點：緊接著的空白、Return 把它換掉；之後任何鍵、送出、切中西文都清掉
  an<SortedTable> model_;
  rime::connection commit_connection_;
  rime::connection option_connection_;
};

}  // namespace penglai

#endif  // PENGLAI_SPACE_H_
