#include "penglai_space.h"

#include <cstring>
#include <set>
#include <unordered_set>
#include <rime/config.h>
#include <rime/engine.h>
#include <rime/key_event.h>
#include <rime/schema.h>

namespace penglai {

using namespace rime;

namespace {

// 告訴貂毫這次送出的是什麼（punct／foreign／replace／period），下一個鍵清掉；不能用 _ 開頭（貂毫當成保留給前端的）
const char kProperty[] = "penglai_space";
// penglai_space/foreign：開著時元件建好就寫成方案 id，貂毫看到跟目前的方案相同才在空白之前讀游標前後的字，
// 寫進 penglai_space_before、penglai_space_after（各最多 100 個 UTF-16，讀不到是空字串）；這裡下一個鍵讀了就清掉
const char kForeignProperty[] = "penglai_space_foreign";
const char kBeforeProperty[] = "penglai_space_before";
const char kAfterProperty[] = "penglai_space_after";
const char* const kEnds[] = {"嗎", "麼", "呢", "誰", "哪", "多少", "如何", "對吧", "是吧"};
const char* const kWords[] = {"什麼", "怎麼", "為什麼", "為何", "哪", "誰", "多少", "如何", "是不是", "有沒有",
                              "要不要", "會不會", "能不能", "可不可以", "對不對", "好不好"};
// 規則另外看的詞（不是模型的特徵，加了不用重新訓練）：口語語料和公開語料（Tatoeba、Common Voice）兩邊都多半是問句的才收
const char* const kRuleWords[] = {"幹嘛", "多久", "多大", "了沒", "難道", "多遠"};
// 疑問詞不是在問的三種用法（11/5；gen_punct.py 的 negations 同一套，tools/punct_check.py 逐句比）：
//   任指：疑問詞後面 0–4 個字內接「都／也」（什麼都可以、誰也不知道）
//   虛指：沒（有）／不＋什麼、誰、哪，點什麼、些什麼，結尾「什麼的」（沒什麼區別、吃點什麼、買菜什麼的）
//   嵌入：前面是不知道、看看、不管…，後面才出現疑問詞、正反問（我不知道他去哪、看看怎麼做）
// 規則：句中疑問詞判成問句、又有這三種之一時不算問句（句尾是嗎、呢、對吧、是吧照舊算）；模型：n:任指 這種特徵
const char* const kNegWh[] = {"什麼", "怎麼", "誰", "哪", "多少", "為什麼", "幾"};
const char* const kNegAnyTail[] = {"都", "也"};
const char* const kNegSome[] = {"沒什麼", "沒誰", "沒哪", "沒有什麼", "沒有誰", "沒有哪",
                                "不什麼", "不誰",   "不哪", "點什麼",   "些什麼"};
const char* const kNegEmbedVerbs[] = {"不知道", "看看", "問問", "想想", "不管", "無論", "不論", "忘了", "記得",
                                      "決定",   "研究", "討論", "商量", "告訴我", "告訴你", "說明", "解釋"};
const char* const kNegEmbedTargets[] = {"什麼", "怎麼", "誰", "哪", "多少", "為什麼", "幾",
                                        "是不是", "有沒有", "要不要", "會不會", "能不能"};
const char* const kNegKeepEnds[] = {"嗎", "呢", "對吧", "是吧"};
// 嘆詞開頭（11/6）：前一段只有一個招呼、感嘆的嘆詞，這一段不是問句、8 個字以內，補「！」不補「，」。
// 嘆詞開頭的句子是對人說的，嘆詞後面那一段多半就是整句的重點（嘿，好主意／哇，好冷／喂，和好吧），收尾用「！」讀得通，
// 「，」反而像話還沒說完。應答的嘆詞（喔、哦、嗯）不收：「喔，好！」口氣變了；長的一段（嘿，俺那婆娘要是知道……）多半還沒說完
const char* const kInterjections[] = {"嘿", "哇", "哇塞", "喂", "哎呀", "哎喲", "哎唷", "天啊"};
const size_t kInterjectionMax = 8;
const uint32_t kBu = 0x4e0d;   // 不
const uint32_t kMei = 0x6c92;  // 沒

bool IsModifier(int code) {
  static const std::set<int> modifiers = {0xffe1, 0xffe2, 0xffe3, 0xffe4, 0xffe5, 0xffe7,
                                          0xffe8, 0xffe9, 0xffea, 0xffeb, 0xffec};
  return modifiers.count(code) > 0;
}

bool IsHan(uint32_t cp) {
  return (cp >= 0x3400 && cp <= 0x9fff) || (cp >= 0xf900 && cp <= 0xfaff) || (cp >= 0x20000 && cp <= 0x3ffff);
}

bool EndsWith(const string& text, const string& suffix) {
  return text.size() >= suffix.size() && text.compare(text.size() - suffix.size(), suffix.size(), suffix) == 0;
}

bool Contains(const string& text, const char* word) {
  return text.find(word) != string::npos;
}

// UTF-8 一個字的位元組數（text 是解得開的 UTF-8）
size_t Utf8Len(unsigned char lead) {
  return lead < 0x80 ? 1 : lead < 0xe0 ? 2 : lead < 0xf0 ? 3 : 4;
}

// 疑問詞的非疑問用法（gen_punct.py 的 negations）：回傳「任指」「虛指」「嵌入」裡有的，照這個順序。
// 用位元組找：UTF-8 不會從一個字的中間對到另一個字，找到的位置一定是字的開頭
vector<string> Negations(const string& text) {
  vector<string> out;
  bool any = false;
  for (const char* w : kNegWh) {
    size_t len = strlen(w);
    for (size_t p = text.find(w); p != string::npos && !any; p = text.find(w, p + 1)) {
      size_t q = p + len;
      for (int k = 0; k < 5 && q < text.size() && !any; ++k) {
        for (const char* t : kNegAnyTail) {
          if (text.compare(q, strlen(t), t) == 0)
            any = true;
        }
        q += Utf8Len(static_cast<unsigned char>(text[q]));
      }
    }
  }
  if (any)
    out.push_back("任指");
  bool some = EndsWith(text, "什麼的");
  for (const char* w : kNegSome)
    some = some || Contains(text, w);
  if (some)
    out.push_back("虛指");
  bool embed = false;
  for (const char* v : kNegEmbedVerbs) {
    size_t p = text.find(v);   // 最前面那個：後面有的話，從更前面開始找一定也有
    if (p == string::npos)
      continue;
    for (const char* t : kNegEmbedTargets)
      embed = embed || text.find(t, p + strlen(v)) != string::npos;
  }
  if (embed)
    out.push_back("嵌入");
  return out;
}

bool RuleHit(const string& text, const vector<uint32_t>& cps) {
  for (const char* e : kEnds) {
    if (EndsWith(text, e))
      return true;
  }
  size_t n = cps.size();
  if (n >= 3 && cps[n - 1] == cps[n - 3] && (cps[n - 2] == kBu || cps[n - 2] == kMei))
    return true;
  for (const char* w : kWords) {
    if (Contains(text, w))
      return true;
  }
  for (const char* w : kRuleWords) {
    if (Contains(text, w))
      return true;
  }
  return false;
}

// 公開版（沒有模型）：像問句，而且不是疑問詞的非疑問用法（句尾是嗎、呢、對吧、是吧照舊算問句）
bool Rule(const string& text, const vector<uint32_t>& cps) {
  if (!RuleHit(text, cps))
    return false;
  for (const char* e : kNegKeepEnds) {
    if (EndsWith(text, e))
      return true;
  }
  return Negations(text).empty();
}

bool EndsWithHan(const string& text) {
  vector<uint32_t> cps;
  return DecodeUtf8(text, &cps) && !cps.empty() && IsHan(cps.back());
}

bool IsAsciiLetter(uint32_t cp) {
  return (cp >= 'A' && cp <= 'Z') || (cp >= 'a' && cp <= 'z');
}

bool IsAsciiAlnum(uint32_t cp) {
  return IsAsciiLetter(cp) || (cp >= '0' && cp <= '9');
}

// 英文詞（[A-Za-z][A-Za-z0-9'’-]* 連續一段）裡、字母開頭之後的字
bool InEnglishWord(uint32_t cp) {
  return IsAsciiAlnum(cp) || cp == '\'' || cp == 0x2019 || cp == '-';
}

// [begin, end) 裡的英文詞數和漢字數
void CountWords(const vector<uint32_t>& cps, size_t begin, size_t end, size_t* english, size_t* han) {
  *english = *han = 0;
  for (size_t i = begin; i < end;) {
    if (IsAsciiLetter(cps[i])) {
      ++*english;
      for (++i; i < end && InEnglishWord(cps[i]); ++i) {
      }
    } else {
      *han += IsHan(cps[i]) ? 1 : 0;
      ++i;
    }
  }
}

// 補英文的「, 」：英文詞至少兩個、佔八成以上（英文詞 ÷（英文詞＋漢字）≥ 0.8）。只有一個英文詞（縮寫、單字）補中文標點
bool MostlyEnglish(size_t english, size_t han) {
  return english >= 2 && english >= 4 * han;
}

// 結尾是英文詞（最後一段 [A-Za-z0-9'’-] 是字母開頭）：數字結尾（0912345678）、空白結尾（「agent 」）不算
bool EndsWithEnglish(const string& text) {
  vector<uint32_t> cps;
  if (!DecodeUtf8(text, &cps) || cps.empty() || !IsAsciiAlnum(cps.back()))
    return false;
  size_t i = cps.size();
  while (i > 0 && InEnglishWord(cps[i - 1]))
    --i;
  while (i < cps.size() && !IsAsciiLetter(cps[i]))
    ++i;
  return i < cps.size();
}

// 「字」：漢字、英文字母、數字（全形的字母、數字也算）。游標前一個不是字時照舊出空白
bool IsWordChar(uint32_t cp) {
  return IsHan(cp) || IsAsciiAlnum(cp) || (cp >= 0xff10 && cp <= 0xff19) || (cp >= 0xff21 && cp <= 0xff3a) ||
         (cp >= 0xff41 && cp <= 0xff5a);
}

bool IsNewline(uint32_t cp) {
  return cp == '\n' || cp == '\r' || cp == 0x0b || cp == 0x0c || cp == 0x85 || cp == 0x2028 || cp == 0x2029;
}

// 標點（全形、半形）：問句只看最後一個標點之後的那一段
bool IsPunct(uint32_t cp) {
  return (cp >= 0x21 && cp <= 0x2f) || (cp >= 0x3a && cp <= 0x40) || (cp >= 0x5b && cp <= 0x60) ||
         (cp >= 0x7b && cp <= 0x7e) || (cp >= 0xa1 && cp <= 0xbf) || (cp >= 0x2010 && cp <= 0x205e) ||
         (cp >= 0x3001 && cp <= 0x3004) || (cp >= 0x3008 && cp <= 0x301f) || cp == 0x3030 || cp == 0x30fb ||
         (cp >= 0xfe10 && cp <= 0xfe19) || (cp >= 0xfe30 && cp <= 0xfe6b) || (cp >= 0xff01 && cp <= 0xff0f) ||
         (cp >= 0xff1a && cp <= 0xff20) || (cp >= 0xff3b && cp <= 0xff40) || (cp >= 0xff5b && cp <= 0xff65);
}

// 半形標點夾在英文字母、數字中間（3.5、Node.js、don't、e-mail）不算切開；「!」「?」夾在中間照樣切開（OK!hello）
bool InWord(const vector<uint32_t>& cps, size_t i) {
  return cps[i] < 0x80 && cps[i] != '!' && cps[i] != '?' && i > 0 && i + 1 < cps.size() &&
         IsAsciiAlnum(cps[i - 1]) && IsAsciiAlnum(cps[i + 1]);
}

// 句子的界線：換行，或句末的「。．！？｡」「. ! ?」（半形的夾在英文、數字中間不算）
bool IsSentenceEnd(const vector<uint32_t>& cps, size_t i) {
  uint32_t c = cps[i];
  if (IsNewline(c) || c == 0x3002 || c == 0xff0e || c == 0xff01 || c == 0xff1f || c == 0xff61)
    return true;
  return (c == '.' || c == '!' || c == '?') && !InWord(cps, i);
}

string EncodeUtf8(const vector<uint32_t>& cps, size_t begin, size_t end) {
  string out;
  for (size_t i = begin; i < end; ++i) {
    uint32_t c = cps[i];
    if (c < 0x80) {
      out += static_cast<char>(c);
    } else if (c < 0x800) {
      out += static_cast<char>(0xc0 | (c >> 6));
      out += static_cast<char>(0x80 | (c & 0x3f));
    } else if (c < 0x10000) {
      out += static_cast<char>(0xe0 | (c >> 12));
      out += static_cast<char>(0x80 | ((c >> 6) & 0x3f));
      out += static_cast<char>(0x80 | (c & 0x3f));
    } else {
      out += static_cast<char>(0xf0 | (c >> 18));
      out += static_cast<char>(0x80 | ((c >> 12) & 0x3f));
      out += static_cast<char>(0x80 | ((c >> 6) & 0x3f));
      out += static_cast<char>(0x80 | (c & 0x3f));
    }
  }
  return out;
}

bool IsSpace(uint32_t cp) {
  return cp == ' ' || cp == '\t' || cp == 0xa0 || cp == 0x3000 || (cp >= 0x2000 && cp <= 0x200b);
}

// 讀了就清掉（只清有值的，沒值時不動 context）
string TakeProperty(Context* ctx, const char* name) {
  string value = ctx->get_property(name);
  if (!value.empty())
    ctx->set_property(name, "");
  return value;
}

// [?, end) 這一段的開頭：往前到最後一個標點（英文、數字中間的半形標點不算）或換行之後，再跳過開頭的空白
size_t SegmentStart(const vector<uint32_t>& cps, size_t end) {
  size_t from = end;
  while (from > 0 && !IsNewline(cps[from - 1]) && !(IsPunct(cps[from - 1]) && !InWord(cps, from - 1)))
    --from;
  while (from < end && IsSpace(cps[from]))
    ++from;
  return from;
}

// 兩段之間的「，」「！」（半形的也算）：前一段是嘆詞時，這一段可能補「！」
bool IsClauseBreak(uint32_t cp) {
  return cp == 0xff0c || cp == 0xff01 || cp == ',' || cp == '!';
}

// 去掉頭尾的空白
string Trim(const string& text) {
  vector<uint32_t> cps;
  if (!DecodeUtf8(text, &cps))
    return text;
  size_t b = 0, e = cps.size();
  while (b < e && IsSpace(cps[b]))
    ++b;
  while (e > b && IsSpace(cps[e - 1]))
    --e;
  return EncodeUtf8(cps, b, e);
}

}  // namespace

bool AfterInterjection(const string& prev, const string& clause) {
  string head = Trim(prev);
  bool hit = false;
  for (const char* w : kInterjections)
    hit = hit || head == w;
  if (!hit)
    return false;
  vector<uint32_t> cps;
  if (!DecodeUtf8(clause, &cps))
    return false;
  size_t n = 0;
  for (uint32_t c : cps)
    n += IsSpace(c) ? 0 : 1;
  return n > 0 && n <= kInterjectionMax;
}

string ForeignPunct(const string& before, const string& after, const SortedTable* model) {
  vector<uint32_t> all, tail;
  if (!DecodeUtf8(before, &all) || all.empty() || !IsWordChar(all.back()))
    return "";
  size_t caret = all.size();
  if (DecodeUtf8(after, &tail))
    all.insert(all.end(), tail.begin(), tail.end());
  // 這一句：游標前後各到換行、句末標點為止
  size_t start = caret;
  while (start > 0 && !IsSentenceEnd(all, start - 1))
    --start;
  size_t end = caret;
  while (end < all.size() && !IsSentenceEnd(all, end))
    ++end;
  // 英文詞（[A-Za-z][A-Za-z0-9'’-]* 連續一段算一個）跟漢字（一個字算一個）的比
  size_t english, han;
  CountWords(all, start, end, &english, &han);
  if (MostlyEnglish(english, han))
    return ", ";
  // 游標後面緊接著是開引號（「『“）：引語前面用冒號（教育部《重訂標點符號手冊》：冒號用於總起下文、引語）。
  // 11/5：引號一個鍵就打得出來，游標移到引號前面按空白就補「：」（他說｜「明天見」→ 他說：「明天見」）
  if (caret < all.size() && (all[caret] == 0x300c || all[caret] == 0x300e || all[caret] == 0x201c))
    return "：";
  // 中文標點：問句看游標前、最後一個標點（或換行）之後那一段，跟送出之後補標點看的範圍一樣
  size_t from = SegmentStart(all, caret);
  // 前一段：這一段前面緊接著是「，」「！」（半形的也算）時，再往前到上一個標點（或換行）為止
  size_t gap = from;
  while (gap > 0 && IsSpace(all[gap - 1]))
    --gap;
  string prev;
  if (gap > 0 && IsClauseBreak(all[gap - 1]))
    prev = EncodeUtf8(all, SegmentStart(all, gap - 1), gap - 1);
  return GuessPunct(EncodeUtf8(all, from, caret), prev, model);
}

string GuessPunct(const string& clause, const string& prev, const SortedTable* model) {
  if (IsQuestion(clause, model))
    return "？";
  return AfterInterjection(prev, clause) ? "！" : "，";
}

double QuestionScore(const string& text, const vector<string>& chars, const SortedTable& model) {
  std::unordered_set<string> seen;
  double z = 0;
  auto add = [&](const string& k) {
    if (!seen.insert(k).second)
      return;
    double w;
    if (model.FindFloat(k, &w))
      z = z + w;
  };
  add("b");
  size_t n = chars.size();
  for (size_t k = 1; k <= 3; ++k) {
    if (n >= k) {
      string s = "s" + std::to_string(k) + ":";
      for (size_t i = n - k; i < n; ++i)
        s += chars[i];
      add(s);
    }
  }
  for (const char* w : kWords) {
    if (Contains(text, w))
      add(string("w:") + w);
  }
  for (const string& k : Negations(text))
    add("n:" + k);
  for (size_t i = 0; i < n; ++i)
    add("u:" + chars[i]);
  for (size_t i = 0; i + 1 < n; ++i)
    add("g:" + chars[i] + chars[i + 1]);
  return z;
}

bool IsQuestion(const string& text, const SortedTable* model) {
  vector<uint32_t> cps;
  if (!DecodeUtf8(text, &cps))
    return false;
  if (model) {
    vector<string> chars;
    SplitUtf8(text, &chars);
    return QuestionScore(text, chars, *model) > 0;
  }
  return Rule(text, cps);
}

PenglaiSpace::PenglaiSpace(const Ticket& ticket) : Processor(ticket) {
  Config* config = engine_->schema()->config();
  bool value;
  if (config->GetBool(name_space_ + "/punct", &value) && !value)
    on_ = false;
  if (config->GetBool(name_space_ + "/replace", &value) && !value)
    replace_ = false;
  if (config->GetBool(name_space_ + "/period", &value) && !value)
    period_ = false;
  if (config->GetBool(name_space_ + "/foreign", &value) && value)
    foreign_ = on_;   // 要先開 punct
  if (config->GetBool(name_space_ + "/english", &value) && value)
    english_ = on_;   // 要先開 punct
  model_ = PunctTable();
  Context* ctx = engine_->context();
  // 告訴貂毫要不要在空白之前讀游標前後的字：值是方案 id，換到沒有這個元件的方案時貂毫看得出來不是同一個
  string announce = foreign_ ? engine_->schema()->schema_id() : "";
  if (ctx->get_property(kForeignProperty) != announce)
    ctx->set_property(kForeignProperty, announce);
  commit_connection_ = ctx->commit_notifier().connect([this](Context* c) {
    string text = c->GetCommitText();
    mark_.reset();   // 滑鼠點候選也會送出，不經過按鍵
    if (!text.empty())
      fresh_ = true;
    // penglai_space/english：結尾是英文詞也接著算這一句（例如「CTO」之後按空白也補標點；要空白就按兩下）
    if (EndsWithHan(text) || (english_ && EndsWithEnglish(text))) {
      clause_ = clause_.value_or("") + text;
      return;
    }
    // 標點鍵送出「，」「！」：前一段留著（前一段是嘆詞時，下一段可能補「！」）
    vector<uint32_t> cps;
    if (clause_ && DecodeUtf8(text, &cps) && cps.size() == 1 && IsClauseBreak(cps[0]))
      prev_ = clause_;
    else
      prev_.reset();
    clause_.reset();
  });
  option_connection_ = ctx->option_update_notifier().connect([this](Context* c, const string& name) {
    if (name == "ascii_mode") {
      clause_.reset();
      prev_.reset();
      mark_.reset();
      fresh_ = false;
    }
  });
}

PenglaiSpace::~PenglaiSpace() {
  commit_connection_.disconnect();
  option_connection_.disconnect();
}

ProcessResult PenglaiSpace::ProcessKeyEvent(const KeyEvent& key) {
  if (!on_)
    return kNoop;
  // 貂毫補送的 VoidSymbol 放開事件：
  //   patches/squirrel/0001：放開修飾鍵前，上次修飾鍵變化之後有任何按鍵或滑鼠點擊就補送，帶著還按著的修飾鍵。
  //     Shift、Control、Option 的組合鍵 librime 自己收得到（Shift＋字母、Shift＋數字選字也會補送），不算；
  //     只有 Command 組合鍵被貂毫直接交給 App（貼上、移游標…）
  //   patches/squirrel/0022：送下一個鍵之前，上一鍵之後有交給 App 的 Command 組合鍵，或在選字窗以外點過滑鼠，就先補送一個帶 Command 的
  // 帶 Command 的才當成輸入框已經變了，「剛送出的中文」不算了，剛補的標點也不換了
  if (key.keycode() == 0xffffff) {
    if (key.super()) {
      clause_.reset();
      prev_.reset();
      mark_.reset();
      fresh_ = false;
    }
    return kNoop;
  }
  if (key.release() || IsModifier(key.keycode()))
    return kNoop;
  Context* ctx = engine_->context();
  if (!ctx->get_property(kProperty).empty())
    ctx->set_property(kProperty, "");
  // 貂毫在這個空白之前給的游標前後文：只給這一鍵用
  string before, after;
  if (foreign_) {
    before = TakeProperty(ctx, kBeforeProperty);
    after = TakeProperty(ctx, kAfterProperty);
  }
  int code = key.keycode();
  bool plain = !(key.shift() || key.ctrl() || key.alt() || key.super());
  bool composing = ctx->IsComposing();
  auto mark = mark_;
  mark_.reset();
  // 補了「，」之後緊接著按 Return：標成 period，Return 照舊交給 App（換段、送出）；貂毫先把「，」換成「。」
  // （「, 」換成「.」），換不了的 App 照舊是「，」。「？」不換
  if (code == 0xff0d && plain && !composing && period_ && mark && (*mark == "，" || *mark == ", ")) {
    ctx->set_property(kProperty, "period");
    clause_.reset();
    prev_.reset();
    fresh_ = false;
    return kNoop;
  }
  if (code == 0x20 && plain && !composing && !ctx->get_option("ascii_mode")) {
    if (mark && replace_) {
      // 緊接著再按一次空白：標成 replace，空白照原本的路走（半形沒人收、交給貂毫，全形是 punctuator 送出「　」），
      // 貂毫用它換掉剛補的標點；換不了就照舊交給 App。再按就沒有 mark、也沒有 clause
      ctx->set_property(kProperty, "replace");
      prev_.reset();   // 標點換成空白了，前一段跟這一段不再用標點隔開
      fresh_ = false;
      return kNoop;
    }
    if (clause_) {
      // 這一句是貂毫送出的字：english 開著時英文詞至少兩個、佔八成以上補「, 」，
      // 不然像問句補「？」，前一段是嘆詞補「！」，其他補「，」
      vector<uint32_t> cps;
      size_t english = 0, han = 0;
      if (english_ && DecodeUtf8(*clause_, &cps))
        CountWords(cps, 0, cps.size(), &english, &han);
      string punct = MostlyEnglish(english, han) ? ", " : GuessPunct(*clause_, prev_.value_or(""), model_.get());
      prev_ = clause_;   // 補的標點隔開了這一段：下一段的前一段就是它
      clause_.reset();
      mark_ = punct;
      fresh_ = true;
      ctx->set_property(kProperty, "punct");
      engine_->CommitText(punct);
      return kAccepted;
    }
    // 游標前是別處的字（penglai_space/foreign）：剛送出過字、之後還沒斷掉時不算（中英混打「Claude Code」中間的空白），
    // 照貂毫給的游標前後文決定；不是字、沒給（讀不到）就照舊出空白。標成 foreign：貂毫核對的是剛給的前文，不是上一筆送出的字
    if (foreign_ && !fresh_) {
      string punct = ForeignPunct(before, after, model_.get());
      if (!punct.empty()) {
        mark_ = punct;
        fresh_ = true;
        ctx->set_property(kProperty, "foreign");
        engine_->CommitText(punct);
        return kAccepted;
      }
    }
  }
  // 組字區空著時按了會交給 App 的鍵（BackSpace、方向鍵、Return、空白、Control 組合鍵…）就斷掉；
  // 組字中的鍵、開始組字的鍵（注音、數字）不算。標點鍵送出標點時 commit_notifier 會斷掉（剛送出的還算）
  bool printable = code >= 0x21 && code <= 0x7e && !(key.ctrl() || key.alt() || key.super());
  if (!composing && !printable) {
    clause_.reset();
    prev_.reset();
    fresh_ = false;
  }
  return kNoop;
}

}  // namespace penglai
