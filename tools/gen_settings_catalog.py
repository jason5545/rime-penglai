#!/usr/bin/env python3
"""產生蓬萊設定視窗用的設定目錄（settings catalog）。

Rime 的設定大多沒寫在任何 yaml 裡：程式讀得到、文件沒提、官方 yaml 也沒列（10/28 粗估 132 個鍵裡 74 個從沒出現在官方 yaml）。
這支程式掃 build.sh 抓下來的原始碼（librime、外掛、Squirrel），列出每個「程式會讀的設定鍵」：
型別、看得出來的程式內建預設值、哪個元件讀、在哪一行讀。再併上 settings/notes.json 手寫的中文說明、選項、範圍。
上游換版本（versions.env）後重跑，新舊目錄一比就知道多了、少了哪些設定。

用法：python3 -I tools/gen_settings_catalog.py [輸出路徑]   （預設 .build/penglai-settings.json；build.sh 會跑並放進 app）
"""
import json
import os
import re
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
B = os.path.join(REPO, ".build")
# librime 的工作區（10/31 起是 fork 的本機 clone，跟 build.sh 同一條規則；外掛在它的 plugins/ 底下）。來源欄照舊寫 librime/…
L = os.environ.get("LIBRIME_DIR", os.path.expanduser("~/GitHub/librime"))

# 掃哪些原始碼：(來源標籤, 資料夾, 語言)
SOURCES = [
    ("librime", "librime/src/rime", "cpp"),   # librime/… 是 L 底下（10/31 以前是 .build/librime）
    ("librime-octagram", "librime/plugins/octagram/src", "cpp"),
    ("librime-predict", "librime/plugins/predict/src", "cpp"),
    ("librime-lua", "librime/plugins/lua/src", "cpp"),
    ("sable", "squirrel/sources", "swift"),   # 貂毫：Squirrel 原始碼加 patches/squirrel、sable/（build.sh 連進 sources/），前端設定檔是 sable.yaml
]

# 讀「元件命名空間 + 相對路徑」的檔案屬於哪一類元件。執行時照方案的 engine 清單換成實際的鍵
# （script_translator@custom_phrase → custom_phrase/…；沒寫 @ 時用各類的預設命名空間）。
REL_FAMILY = {
    "script_translator.cc": "script_translator",
    "table_translator.cc": "table_translator",
    "translator_commons.cc": "translator",
    "dictionary.cc": "translator",
    "user_dictionary.cc": "translator",
    "corrector.cc": "translator",
    "reverse_lookup_dictionary.cc": "reverse_lookup",
    "reverse_lookup_translator.cc": "reverse_lookup_translator",
    "reverse_lookup_filter.cc": "reverse_lookup_filter",
    "history_translator.cc": "history_translator",
    "simplifier.cc": "simplifier",
    "recognizer.cc": "recognizer",
    "affix_segmentor.cc": "affix_segmentor",
    "filter_commons.cc": "filter",
}

# 寫死路徑的鍵：依第一段判斷屬於哪份設定。default.yaml 裡有的段落，方案沒寫時會沿用 default 的。
DEFAULT_ONLY = {"schema_list", "switcher"}
DEFAULT_SHARED = {"menu", "punctuator", "key_binder", "recognizer", "ascii_composer", "selector", "navigator"}
INTERNAL = {"var", "installation_id", "sync_dir", "distribution_code_name", "distribution_name",
            "distribution_version", "rime_version", "customization", "backup_config_files", "config_version",
            "schema", "__build_info", "unsafe", "dependencies"}

CPP_ABS = re.compile(r'Get(Bool|Int|Double|String|List|Map|Item|Value)\(\s*"([A-Za-z_][A-Za-z0-9_/@]*)"\s*,?\s*&?\s*([A-Za-z_][A-Za-z0-9_.>\-]*)?')
CPP_REL = re.compile(r'Get(Bool|Int|Double|String|List|Map|Item|Value)\(\s*(?:name_space_|ticket\.name_space)\s*\+\s*"/([A-Za-z_][A-Za-z0-9_/]*)"\s*,?\s*&?\s*([A-Za-z_][A-Za-z0-9_.>\-]*)?')
SWIFT = re.compile(r'get(Bool|Double|String|Color|Int)\("([A-Za-z_][A-Za-z0-9_/]*)"\)')

TYPE = {"Bool": "bool", "Int": "int", "Double": "double", "String": "string", "Value": "string",
        "List": "list", "Map": "map", "Item": "any", "Color": "color"}


def strip_dead(text):
    """`#if 0 … #endif` 裡的死碼換成空行（行號不變）：編譯時不存在，不能當成出處。
    巢狀的 #if 跟著死；`#if 0 … #else` 的 #else 之後照常掃。只處理字面上的 0，其他條件照常掃"""
    out, stack = [], []   # 每層 #if："zero"（#if 0 那一段）、"inner"（死碼裡的 #if）、"live"
    for ln in text.split("\n"):
        s = ln.strip()
        dead = "zero" in stack or "inner" in stack
        if re.match(r"#\s*if(n?def)?\b", s):
            stack.append("inner" if dead else "zero" if re.match(r"#\s*if\s+0\b", s) else "live")
        elif re.match(r"#\s*(else|elif)\b", s) and stack:
            if stack[-1] == "zero":
                stack[-1] = "live"
        elif re.match(r"#\s*endif\b", s) and stack:
            stack.pop()
        out.append("" if dead or "zero" in stack else ln)
    return "\n".join(out)


def guess_default(var, texts):
    """在同一個 .cc 和對應的 .h 找 `var = 字面值` 或 `var{字面值}`、`var(字面值)`。猜不到回 None。"""
    if not var:
        return None
    name = re.escape(var.split("->")[-1].split(".")[-1])
    literal = r'(true|false|-?\d+(?:\.\d+)?|"[^"]*")'
    for text in texts:
        for pat in (rf'\b{name}\s*=\s*{literal}\s*;', rf'\b{name}\s*\{{\s*{literal}\s*\}}', rf'\b{name}\s*\(\s*{literal}\s*\)'):
            m = re.search(pat, text)
            if m:
                value = m.group(1)
                return value.strip('"') if value.startswith('"') else value
    return None


def pinned_versions():
    """versions.env 鎖的上游 commit（目錄掃的就是這幾版加上我們的 patch）。"""
    names = {"LIBRIME_COMMIT": "librime", "SQUIRREL_COMMIT": "squirrel", "OCTAGRAM_COMMIT": "librime-octagram",
             "PREDICT_COMMIT": "librime-predict", "LUA_COMMIT": "librime-lua"}
    result = {}
    for line in open(os.path.join(REPO, "versions.env"), encoding="utf-8"):
        m = re.match(r"([A-Z_]+)=([0-9a-f]{7,40})", line)
        if m and m.group(1) in names:
            result[names[m.group(1)]] = m.group(2)[:7]
    return result


def scan():
    entries = {}

    def add(key, rec):
        old = entries.get(key)
        if old:
            old["sources"] = sorted(set(old["sources"] + rec["sources"]))
            if old["type"] in ("any", "string") and rec["type"] not in ("any", "string"):
                old["type"] = rec["type"]
            if old.get("default") is None and rec.get("default") is not None:
                old["default"] = rec["default"]
        else:
            entries[key] = rec

    for label, sub, lang in SOURCES:
        root = os.path.join(L, sub[len("librime/"):]) if sub.startswith("librime/") else os.path.join(B, sub)
        for dirpath, _, files in os.walk(root):
            for fn in sorted(files):
                if not fn.endswith((".cc", ".h", ".swift")):
                    continue
                path = os.path.join(dirpath, fn)
                text = open(path, encoding="utf-8", errors="ignore").read()
                if lang == "cpp":
                    text = strip_dead(text)
                header = os.path.splitext(path)[0] + ".h"
                texts = [text] + ([strip_dead(open(header, encoding="utf-8", errors="ignore").read())]
                                  if os.path.exists(header) and header != path else [])
                rel_path = (os.path.join("librime", os.path.relpath(path, L)) if sub.startswith("librime/")
                            else os.path.relpath(path, B))
                if lang == "swift":
                    for m in SWIFT.finditer(text):
                        line = text.count("\n", 0, m.start()) + 1
                        key = m.group(2)
                        if key.split("/")[0] in INTERNAL:
                            continue
                        add(("sable", key), {"config": "sable", "key": key, "type": TYPE[m.group(1)],
                                             "default": None, "sources": [f"{rel_path}:{line}"]})
                    continue
                for m in CPP_REL.finditer(text):
                    family = REL_FAMILY.get(fn)
                    if not family:
                        continue
                    line = text.count("\n", 0, m.start()) + 1
                    key = m.group(2)
                    add((family, key), {"config": "schema", "component": family, "key": key, "relative": True,
                                        "type": TYPE[m.group(1)], "default": guess_default(m.group(3), texts),
                                        "sources": [f"{rel_path}:{line}"]})
                for m in CPP_ABS.finditer(text):
                    key = m.group(2)
                    top = key.split("/")[0]
                    # 只有一段的（when、accept、formula…）是清單項目裡的欄位，不是設定
                    if top in INTERNAL or ("/" not in key and top not in DEFAULT_ONLY) or key.endswith("/") or "/lever/" in path:
                        continue
                    if "/config/" in path or fn in ("deployment_tasks.cc", "deployer.cc", "signature.cc"):
                        continue
                    config = "default" if top in DEFAULT_ONLY else "schema"
                    line = text.count("\n", 0, m.start()) + 1
                    rec = {"config": config, "key": key, "type": TYPE[m.group(1)],
                           "default": guess_default(m.group(3), texts), "sources": [f"{rel_path}:{line}"]}
                    if top in DEFAULT_SHARED:
                        rec["default_section"] = True
                    add((config, key), rec)
    return list(entries.values())


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(B, "penglai-settings.json")
    notes = json.load(open(os.path.join(REPO, "settings", "notes.json"), encoding="utf-8"))
    keys = scan()
    by_id = {}
    for rec in keys:
        rid = (rec.get("component") + ":" if rec.get("relative") else rec["config"] + ":") + rec["key"]
        rec["id"] = rid
        by_id[rid] = rec
    missing = []
    for rid, note in notes["keys"].items():
        if rid in by_id:
            by_id[rid].update(note)
        elif note.get("extra"):
            # 程式碼掃不到、但確定有人讀的（例如 Squirrel 用字串插值組出來的鍵、外掛模組 Lua 讀的鍵），手寫補上
            rec = dict(note)
            rec["id"] = rid
            rec.setdefault("sources", [])
            keys.append(rec)
            by_id[rid] = rec
        else:
            missing.append(rid)
    if missing:
        print("notes.json 裡有、原始碼掃不到的鍵（上游改名或拿掉了？）：", ", ".join(missing), file=sys.stderr)
    keys.sort(key=lambda r: (r["config"], r.get("component", ""), r["key"]))
    catalog = {
        "versions": pinned_versions(),
        "families": notes["families"],
        "data_sections": notes["data_sections"],
        "recipes": notes["recipes"],
        "keys": keys,
    }
    with open(out, "w", encoding="utf-8") as f:
        json.dump(catalog, f, ensure_ascii=False, indent=1, sort_keys=True)
        f.write("\n")
    described = sum(1 for r in keys if r.get("title"))
    print(f"{out}：{len(keys)} 個鍵，{described} 個有說明")


if __name__ == "__main__":
    main()
