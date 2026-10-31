// 打字示範：播 demo.json（tools/gen_site_demo.py 在沙盒裡逐鍵錄的引擎輸出），這裡不自己算候選。
(() => {
  const ROWS = [
    "1ㄅ 2ㄉ 3ˇ 4ˋ 5ㄓ 6ˊ 7˙ 8ㄚ 9ㄞ 0ㄢ -ㄦ",
    "qㄆ wㄊ eㄍ rㄐ tㄔ yㄗ uㄧ iㄛ oㄟ pㄣ",
    "aㄇ sㄋ dㄎ fㄑ gㄕ hㄘ jㄨ kㄜ lㄠ ;ㄤ",
    "zㄈ xㄌ cㄏ vㄒ bㄖ nㄙ mㄩ ,ㄝ .ㄡ /ㄥ",
  ];
  const CAPTIONS = {
    fresh: (s) => `「今天天氣很好」每個字只按第一個注音：${zhuyin(s)}。還沒學過，第一候選是「${last(s).cands[0]}」。`,
    full: () => "照完整的注音打一次，空白鍵選字、Return 送出。這一整句就記下來了。",
    learned: (s) => `同樣按 ${zhuyin(s).length} 個注音，整句排第一，⇧1 選、Return 送出。`,
  };
  const STEP_MS = 420, HOLD_MS = 2600;

  const root = document.querySelector("[data-ime]");
  if (!root) return;
  const $ = (sel) => root.querySelector(sel);
  const tabs = [...root.querySelectorAll("[data-scene]")];
  const reduce = matchMedia("(prefers-reduced-motion: reduce)").matches;
  let data, scene = 0, timer = null, auto = true;

  const keyName = (k) => (k === " " || k === "{space}") ? "space" : k === "{Return}" ? "return" : k === "⇧1" ? "shift+1" : k;
  const last = (s) => s.steps.filter((x) => x.cands.length).at(-1);
  const zhuyin = (s) => s.steps.map((x) => x.key).filter((k) => k.length === 1 && k !== " ")
    .map((k) => (ROWS.join(" ").split(" ").find((p) => p[0] === k) || "")[1] || "").join("");

  function buildKeyboard() {
    const kbd = $(".kbd");
    const row = (cells) => `<div class="row">${cells}</div>`;
    const key = (k, z, cls = "") => `<span class="k ${cls}" data-k="${k}"><span class="a">${k}</span><span class="z">${z}</span></span>`;
    const rows = ROWS.map((r) => r.split(" ").map((p) => key(p[0], p.slice(1))).join(""));
    rows[2] += key("return", "Return", "ret");
    rows[3] = key("shift", "⇧", "shift") + rows[3];
    rows.push(key("space", "空白（一聲）", "space"));
    kbd.innerHTML = rows.map(row).join("");
  }

  function press(k) {
    root.querySelectorAll(".k.on").forEach((e) => e.classList.remove("on"));
    for (const name of keyName(k).split("+")) root.querySelector(`.k[data-k="${CSS.escape(name)}"]`)?.classList.add("on");
  }

  function render(s, i) {
    const steps = s.steps.slice(0, i + 1);
    const st = steps.at(-1);
    const committed = steps.map((x) => x.commit || "").join("");
    $(".ime-committed").textContent = committed;
    const panel = $(".ime-panel");
    panel.hidden = !st || (!st.preedit && !st.cands.length);
    if (st) {
      $(".ime-preedit").textContent = st.preedit;
      $(".ime-cands").innerHTML = st.cands.map((c, n) => `<li><span class="n">${n + 1}</span>${c}</li>`).join("");
      press(st.key);
    }
    $(".ime-count b").textContent = steps.length;
  }

  function show(n, play = true) {
    clearTimeout(timer);
    scene = n;
    tabs.forEach((t, i) => t.setAttribute("aria-selected", String(i === n)));
    const s = data.scenes[n];
    $(".ime-caption").textContent = CAPTIONS[s.id]?.(s) ?? s.title;
    if (!play || reduce) {
      render(s, s.steps.length - 1);
      root.querySelectorAll(".k.on").forEach((e) => e.classList.remove("on"));
      return;
    }
    let i = -1;
    render(s, -1);
    const tick = () => {
      i += 1;
      render(s, i);
      if (i < s.steps.length - 1) timer = setTimeout(tick, STEP_MS);
      else timer = setTimeout(() => {
        root.querySelectorAll(".k.on").forEach((e) => e.classList.remove("on"));
        if (auto && n < data.scenes.length - 1) show(n + 1);
      }, HOLD_MS);
    };
    timer = setTimeout(tick, STEP_MS);
  }

  function readings() {
    const box = document.querySelector("[data-readings]");
    if (!box) return;
    box.querySelector("thead tr").insertAdjacentHTML("beforeend",
      data.policies.map((p) => `<th scope="col">${p.name}</th>`).join(""));
    box.querySelector("tbody").innerHTML = data.readings.map((r) => `<tr><th scope="row">${r.note}</th>${
      data.policies.map((p) => {
        const [a, ...rest] = r.policies[p.id].slice(0, 3);
        return `<td><span class="first">${a}</span><span class="rest">${rest.join(" ")}</span></td>`;
      }).join("")}</tr>`).join("");
  }

  function extras() {
    for (const box of document.querySelectorAll("[data-extra]")) {
      const e = data.extras?.find((x) => x.id === box.dataset.extra);
      if (!e) continue;
      box.querySelector(".mini-cands").innerHTML = e.cands.map((c, n) =>
        `<li${c === box.dataset.hl ? ' class="hl"' : ""}><span class="n">${n + 1}</span>${c}</li>`).join("");
    }
  }

  buildKeyboard();
  fetch("/demo.json").then((r) => r.json()).then((d) => {
    data = d;
    readings();
    extras();
    tabs.forEach((t, i) => t.addEventListener("click", () => { auto = false; show(i); }));
    $(".ime-replay").addEventListener("click", () => { auto = scene === 0; show(scene); });
    show(0, false);
    if (reduce) return;
    const io = new IntersectionObserver((entries) => {
      if (entries.some((e) => e.isIntersecting)) { io.disconnect(); show(0); }
    }, { threshold: 0.5 });
    io.observe(root);
  });
})();
