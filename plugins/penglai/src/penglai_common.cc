#include "penglai_common.h"

#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>
#include <cstdio>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <mutex>
#include <rime/composition.h>
#include <rime/config.h>
#include <rime/context.h>
#include <rime/engine.h>
#include <rime/schema.h>
#include <rime_api.h>

namespace penglai {

namespace {

struct KeyName {
  const char* name;
  vector<int> codes;
  bool down;  // 只有數字選字的觸發鍵能選
};

// 修飾鍵點一下不會打出字，大千的注音鍵、數字、標點都不在這裡
const vector<KeyName>& KeyNames() {
  static const vector<KeyName> names = {
      {"Down", {0xff54, 0xff99}, true},       // Down、KP_Down（數字選字的預設：↓ 照舊移反白）
      {"Control", {0xffe3, 0xffe4}, false},   // Control_L、Control_R：MacBook 只有左邊有，左右當同一個
      {"Alt_L", {0xffe9}, false},             // 左 Option
      {"Alt_R", {0xffea}, false},             // 右 Option
      {"Super_L", {0xffeb}, false},           // 左 Command
      {"Super_R", {0xffec}, false},           // 右 Command
  };
  return names;
}

// Lua 5.4 lutf8lib.c 的 utf8_decode（strict）：s 要以 NUL 結尾，失敗回傳 nullptr
const char* Utf8Decode(const char* s, uint32_t* val) {
  static const uint32_t limits[] = {~(uint32_t)0, 0x80, 0x800, 0x10000u, 0x200000u, 0x4000000u};
  unsigned int c = (unsigned char)s[0];
  uint32_t res = 0;
  if (c < 0x80) {
    res = c;
  } else if (c >= 0xfe) {
    return nullptr;
  } else {
    int count = 0;
    for (; c & 0x40; c <<= 1) {
      unsigned int cc = (unsigned char)s[++count];
      if ((cc & 0xC0) != 0x80)
        return nullptr;
      res = (res << 6) | (cc & 0x3F);
    }
    res |= ((uint32_t)(c & 0x7F) << (count * 5));
    if (res > 0x7FFFFFFFu || res < limits[count])
      return nullptr;
    s += count;
  }
  if (res > 0x10FFFFu || (0xD800u <= res && res <= 0xDFFFu))
    return nullptr;
  if (val)
    *val = res;
  return s + 1;
}

std::mutex shared_mutex;
bool freq_loaded = false;
an<SortedTable> freq_table;
bool punct_loaded = false;
an<SortedTable> punct_table;

// 跟 Lua 的 require 一樣：使用者資料夾有這個檔就用它（讀不進來也不改找別處），沒有才找共用資料夾
an<SortedTable> LoadData(const string& file) {
  std::error_code ec;
  string path = UserDataPath(file);
  if (!std::filesystem::exists(path, ec)) {
    const char* shared = rime_get_api()->get_shared_data_dir();
    string shared_path = string(shared ? shared : "") + "/" + file;
    if (!std::filesystem::exists(shared_path, ec))
      return nullptr;
    path = shared_path;
  }
  auto table = SortedTable::Open(path);
  if (!table)
    LOG(ERROR) << "penglai: 讀不進 " << path << "（格式不對）";
  return table;
}

}  // namespace

const vector<int>* KeyCodesOf(const string& name, bool allow_down) {
  for (const auto& k : KeyNames()) {
    if (name == k.name && (allow_down || !k.down))
      return &k.codes;
  }
  return nullptr;
}

bool DecodeUtf8(const string& text, vector<uint32_t>* code_points) {
  const char* s = text.c_str();
  const char* end = s + text.size();
  code_points->clear();
  while (s < end) {
    uint32_t c = 0;
    const char* next = Utf8Decode(s, &c);
    if (!next)
      return false;
    code_points->push_back(c);
    s = next;
  }
  return true;
}

bool SplitUtf8(const string& text, vector<string>* chars) {
  const char* begin = text.c_str();
  const char* s = begin;
  const char* end = s + text.size();
  chars->clear();
  while (s < end) {
    const char* next = Utf8Decode(s, nullptr);
    if (!next)
      return false;
    chars->emplace_back(s, next - s);
    s = next;
  }
  return true;
}

bool ShowNotice(rime::Engine* engine, const string& text) {
  static const string kName = "_penglai_notice";
  rime::Config* config = engine->schema()->config();
  size_t n = config->GetListSize("switches");
  for (size_t i = 0; i < n; ++i) {
    string base = "switches/@" + std::to_string(i);
    string name;
    if (config->GetString(base + "/name", &name) && name == kName) {
      config->SetString(base + "/states/@1", text);
      config->SetString(base + "/abbrev/@1", text);
      engine->context()->set_option(kName, true);
      engine->context()->set_option(kName, false);
      return true;
    }
  }
  return false;
}

void InputPrompt::Set(rime::Context* ctx, const string& text) {
  auto& comp = ctx->composition();
  if (comp.empty())
    return;
  comp.back().prompt = text;
  text_ = text;
}

void InputPrompt::Clear(rime::Context* ctx) {
  if (!text_)
    return;
  auto& comp = ctx->composition();
  if (!comp.empty() && comp.back().prompt == *text_)
    comp.back().prompt.clear();
  text_.reset();
}

bool InputPrompt::Showing(rime::Context* ctx) const {
  const auto& comp = ctx->composition();
  return text_ && !comp.empty() && comp.back().prompt == *text_;
}

string UserDataPath(const string& file) {
  const char* dir = rime_get_api()->get_user_data_dir();
  return string(dir ? dir : "") + "/" + file;
}

an<SortedTable> SortedTable::Open(const string& file_path) {
  // 整個檔讀進自己的緩衝區，不用 mmap：檔案被原地蓋掉（cp 會先截斷）時，映射的頁會讓輸入法 SIGBUS；
  // 讀到一半被截斷的，下面的檢查會擋掉，當作沒有這個表
  int fd = open(file_path.c_str(), O_RDONLY);
  if (fd < 0)
    return nullptr;
  struct stat st;
  if (fstat(fd, &st) != 0 || st.st_size < 16) {
    close(fd);
    return nullptr;
  }
  an<SortedTable> t(new SortedTable);
  t->data_.resize((size_t)st.st_size);
  size_t got = 0;
  while (got < t->data_.size()) {
    ssize_t r = read(fd, &t->data_[got], t->data_.size() - got);
    if (r <= 0)
      break;
    got += (size_t)r;
  }
  // 讀的期間被原地重寫（同一個 inode 被截斷、改寫）：讀完再看一次，inode、大小、修改時間有不同就當作沒有這個表，
  // 跟舊 Lua 讀到一半的檔 require 失敗一樣。不重試、不加鎖
  struct stat after;
#ifdef __APPLE__
  const auto& m0 = st.st_mtimespec;
  const auto& m1 = after.st_mtimespec;
#else  // Linux、Android（penglai-android）
  const auto& m0 = st.st_mtim;
  const auto& m1 = after.st_mtim;
#endif
  bool same = fstat(fd, &after) == 0 && after.st_ino == st.st_ino && after.st_size == st.st_size &&
              m1.tv_sec == m0.tv_sec && m1.tv_nsec == m0.tv_nsec;
  close(fd);
  if (got != t->data_.size() || !same)
    return nullptr;
  const char* base = t->data_.data();
  size_t size = t->data_.size();
  uint32_t version, kind, count;
  memcpy(&version, base + 4, 4);
  memcpy(&kind, base + 8, 4);
  memcpy(&count, base + 12, 4);
  size_t keys_begin = 16 + (size_t)count * 16;
  if (memcmp(base, "PLTB", 4) != 0 || version != 1 || (kind != kInteger && kind != kFloat) || keys_begin > size)
    return nullptr;
  // 每個鍵都要落在鍵區（不能指到表頭或記錄區），而且照位元組嚴格遞增（二分搜尋才找得到；有重複、沒排好就整份不用）
  std::string_view prev;
  for (uint32_t i = 0; i < count; ++i) {
    uint32_t off, len;
    memcpy(&off, base + 16 + (size_t)i * 16, 4);
    memcpy(&len, base + 16 + (size_t)i * 16 + 4, 4);
    if ((size_t)off < keys_begin || (size_t)off + len > size)
      return nullptr;
    std::string_view key(base + off, len);
    if (i > 0 && !(prev < key))
      return nullptr;
    prev = key;
  }
  t->base_ = base;
  t->kind_ = (Kind)kind;
  t->count_ = count;
  return t;
}

const char* SortedTable::Lookup(std::string_view key) const {
  uint32_t lo = 0, hi = count_;
  while (lo < hi) {
    uint32_t mid = lo + (hi - lo) / 2;
    const char* rec = base_ + 16 + (size_t)mid * 16;
    uint32_t off, len;
    memcpy(&off, rec, 4);
    memcpy(&len, rec + 4, 4);
    int c = std::string_view(base_ + off, len).compare(key);
    if (c == 0)
      return rec + 8;
    if (c < 0)
      lo = mid + 1;
    else
      hi = mid;
  }
  return nullptr;
}

bool SortedTable::FindInt(std::string_view key, int64_t* value) const {
  if (kind_ != kInteger)
    return false;
  const char* v = Lookup(key);
  if (!v)
    return false;
  memcpy(value, v, 8);
  return true;
}

bool SortedTable::FindFloat(std::string_view key, double* value) const {
  const char* v = Lookup(key);
  if (!v)
    return false;
  if (kind_ == kFloat) {
    memcpy(value, v, 8);
  } else {
    int64_t i;
    memcpy(&i, v, 8);
    *value = (double)i;
  }
  return true;
}

an<SortedTable> FreqTable() {
  std::lock_guard<std::mutex> lock(shared_mutex);
  if (!freq_loaded) {
    freq_loaded = true;
    freq_table = LoadData("jason_voco_data.tbl");
  }
  return freq_table;
}

an<SortedTable> PunctTable() {
  std::lock_guard<std::mutex> lock(shared_mutex);
  if (!punct_loaded) {
    punct_loaded = true;
    punct_table = LoadData("penglai_punct_data.tbl");
  }
  return punct_table;
}

void ResetSharedState() {
  std::lock_guard<std::mutex> lock(shared_mutex);
  freq_loaded = punct_loaded = false;
  freq_table.reset();
  punct_table.reset();
}

namespace hidden_list {

static string ListPath() {
  return UserDataPath("penglai_hidden.txt");
}

bool Has(const string& text) {
  std::ifstream f(ListPath());
  if (!f)
    return false;
  string line;
  while (std::getline(f, line)) {
    // 註解（# 開頭）、Tab 開頭的行不算；詞是 Tab 前面那段
    if (line.empty() || line[0] == '\t' || line[0] == '#')
      continue;
    if (line.substr(0, line.find('\t')) == text)
      return true;
  }
  return false;
}

bool Remove(const string& text) {
  vector<string> keep;
  bool found = false;
  {
    std::ifstream f(ListPath());
    if (!f)
      return false;
    string line;
    while (std::getline(f, line)) {
      if (line.substr(0, line.find('\t')) == text)
        found = true;
      else
        keep.push_back(line);
    }
  }
  if (!found)
    return false;
  FILE* f = fopen(ListPath().c_str(), "w");
  if (!f) {
    LOG(ERROR) << "penglai_hide: 寫不進 " << ListPath();
    return false;
  }
  for (const auto& line : keep) {
    fwrite(line.data(), 1, line.size(), f);
    fputc('\n', f);
  }
  fclose(f);
  return true;
}

}  // namespace hidden_list

}  // namespace penglai
