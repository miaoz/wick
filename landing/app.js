/* Wick 落地页 — i18n / 外观 / 实时弧光 / 滚动显影 / 最新版本号 */
(function () {
  "use strict";
  var root = document.documentElement;

  /* ---------------- i18n ---------------- */
  /* 中文只保留 index.html 一份(首屏/无 JS 直接可见);启动时从 DOM 捕获为 zh,这里只维护英文 */
  var I18N_EN = {
    "nav.features": "Features",
    "nav.shots": "Screenshots",
    "nav.download": "Download",
    "eyebrow": "trader's almanac and review journal",
    "hero.title": "Wick",
    "hero.live.pre": "",
    "hero.live.post": "of today left.",
    "hero.lede": "A macro calendar, your trade history, and P&L tallied — new today, new every day, new again.",
    "cta.download": "Download for macOS",
    "cta.source": "Source on GitHub",
    "slip.title": "Now",
    "strip.day": "Day",
    "strip.week": "Week",
    "strip.month": "Month",
    "strip.year": "Year",
    "features.title": "What it does",
    "feat1.h": "Time, marked",
    "feat1.p": "Time flies — seize the day, seize the hour. What's left right now of the day, week, month and year, and when each ends, live on your computer and your phone — anywhere, at a glance.",
    "feat2.h": "A page a day",
    "feat2.p": "One page per day; entries carry tags and images. Review seals, entry-level search, daily reminders, import & export. Multiple journals, optional Dropbox sync.",
    "feat3.h": "Tear-off almanac",
    "feat3.p": "The day's major global macro events and earnings on a single page — it even throws in an almanac easter egg with real tear-off physics. And of course, you can keep it from ever disturbing you.",
    "feat4.h": "Exchange receipts",
    "feat4.p": "Read-only links to exchanges like Binance, OKX and Hyperliquid. Fills aggregate into positions pinned to the day's page. Keys never leave this Mac.",
    "shots.title": "Screenshots",
    "shot1.cap": "The main window — a page a day, receipts and seals in place",
    "shot2.cap": "The menu-bar slip — the day at a glance",
    "shot3.cap": "iPhone client — time arcs in your pocket",
    "dl.title": "Download",
    "dl.meta": "macOS 13 Ventura or later · Universal (Apple Silicon & Intel)",
    "dl.button": "macOS",
    "dl.ios.soon": "Coming soon",
    "dl.ios.button": "iOS",
    "footer.brand": "Wick",
    "footer.note": "Why not roam by candlelight"
  };
  var ZH_TITLE = document.title;
  var EN_TITLE = "Wick — a trader's almanac and review journal";
  var i18nEls = [];
  document.querySelectorAll("[data-i18n]").forEach(function (el) {
    i18nEls.push({ el: el, zh: el.textContent, en: I18N_EN[el.getAttribute("data-i18n")] });
  });

  var lang = root.getAttribute("lang") === "en" ? "en" : "zh";
  var langBtn = document.getElementById("lang-toggle");

  function applyLang() {
    root.setAttribute("lang", lang);
    i18nEls.forEach(function (it) {
      var t = lang === "zh" ? it.zh : it.en;
      if (t != null) it.el.textContent = t;
    });
    langBtn.textContent = lang === "zh" ? "EN" : "中文";
    document.title = lang === "zh" ? ZH_TITLE : EN_TITLE;
    tick(); // 条带数值与时钟也随语言重排
  }

  langBtn.addEventListener("click", function () {
    lang = lang === "zh" ? "en" : "zh";
    localStorage.setItem("wick-lp-lang", lang);
    applyLang();
  });

  /* ---------------- 亮 / 暗:跟随系统(?theme= 强制时不动) ---------------- */
  var forcedScheme = new URLSearchParams(location.search).get("theme");
  if (forcedScheme !== "light" && forcedScheme !== "dark") {
    window.matchMedia("(prefers-color-scheme: dark)").addEventListener("change", function (e) {
      root.setAttribute("data-scheme", e.matches ? "dark" : "light");
    });
  }

  /* ---------------- 顶栏滚动态 ---------------- */
  var header = document.querySelector(".site-header");
  function onScroll() { header.classList.toggle("is-solid", (window.scrollY || 0) > 24); }
  window.addEventListener("scroll", onScroll, { passive: true });
  onScroll();

  /* ---------------- 实时弧光 ---------------- */
  var strips = {
    day:   { bar: document.querySelector('[data-burn="day"]'),   val: document.querySelector('[data-val="day"]') },
    week:  { bar: document.querySelector('[data-burn="week"]'),  val: document.querySelector('[data-val="week"]') },
    month: { bar: document.querySelector('[data-burn="month"]'), val: document.querySelector('[data-val="month"]') },
    year:  { bar: document.querySelector('[data-burn="year"]'),  val: document.querySelector('[data-val="year"]') }
  };
  var dayLeftEls = document.querySelectorAll("[data-day-left]");
  var clockEls = document.querySelectorAll("[data-clock]");
  var WEEK_ZH = "日一二三四五六";
  var WEEK_EN = ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"];

  function leftText(pct) {
    return lang === "zh" ? "剩 " + pct + "%" : pct + "% left";
  }

  function tick() {
    var now = new Date();
    var secs = now.getHours() * 3600 + now.getMinutes() * 60 + now.getSeconds();
    var dayT = secs / 86400;
    var weekT = (now.getDay() * 86400 + secs) / 604800;      /* 与 app 默认一致:周日起算 */
    var dim = new Date(now.getFullYear(), now.getMonth() + 1, 0).getDate();
    var monthT = (now.getDate() - 1 + dayT) / dim;
    var jan1 = new Date(now.getFullYear(), 0, 1);
    var diy = ((now.getFullYear() % 4 === 0 && now.getFullYear() % 100 !== 0) || now.getFullYear() % 400 === 0) ? 366 : 365;
    var yearT = (Math.floor((now - jan1) / 86400000) + dayT) / diy;

    var dayLeft = (1 - dayT) * 100;
    dayLeftEls.forEach(function (el) { el.textContent = dayLeft.toFixed(1); });

    strips.day.bar.style.setProperty("--p", (dayT * 100).toFixed(2) + "%");
    strips.day.val.textContent = leftText(dayLeft.toFixed(0));
    strips.week.bar.style.setProperty("--p", (weekT * 100).toFixed(2) + "%");
    strips.week.val.textContent = leftText(((1 - weekT) * 100).toFixed(1));
    strips.month.bar.style.setProperty("--p", (monthT * 100).toFixed(2) + "%");
    strips.month.bar.style.setProperty("--ticks", String(dim));
    strips.month.val.textContent = leftText(((1 - monthT) * 100).toFixed(1));
    strips.year.bar.style.setProperty("--p", (yearT * 100).toFixed(2) + "%");
    strips.year.val.textContent = leftText(((1 - yearT) * 100).toFixed(1));

    var hh = String(now.getHours()).padStart(2, "0");
    var mm = String(now.getMinutes()).padStart(2, "0");
    clockEls.forEach(function (el) {
      el.textContent = lang === "zh"
        ? (now.getMonth() + 1) + "月" + now.getDate() + "日 周" + WEEK_ZH[now.getDay()] + " " + hh + ":" + mm
        : WEEK_EN[now.getDay()] + ", " + now.toLocaleString("en-US", { month: "short" }) + " " + now.getDate() + " · " + hh + ":" + mm;
    });

    /* 弧光时段随真实时间流动 */
    var h = now.getHours();
    var ph = (h >= 5 && h < 8) ? "dawn" : (h >= 8 && h < 17) ? "day" : (h >= 17 && h < 20) ? "dusk" : "night";
    if (root.getAttribute("data-phase") !== ph) root.setAttribute("data-phase", ph);
  }
  tick();
  setInterval(tick, 1000);

  /* ---------------- 滚动显影 ---------------- */
  var rvEls = document.querySelectorAll(".feat, .shot, .dl-body");
  if ("IntersectionObserver" in window) {
    var io = new IntersectionObserver(function (entries) {
      entries.forEach(function (en) {
        if (!en.isIntersecting) return;
        var el = en.target;
        el.classList.add("in");
        io.unobserve(el);
        /* 显影完成后清掉错位延迟,避免拖累 hover 过渡 */
        setTimeout(function () { el.style.transitionDelay = ""; }, 800);
      });
    }, { threshold: 0.12 });
    rvEls.forEach(function (el, i) {
      el.classList.add("rv");
      el.style.transitionDelay = (i % 4) * 70 + "ms";
      io.observe(el);
    });
  }

  /* ---------------- 最新版本号(GitHub Releases,失败静默) ---------------- */
  var verEl = document.querySelector("[data-version]");
  if (verEl && window.fetch) {
    fetch("https://api.github.com/repos/miaoz/wick/releases/latest")
      .then(function (r) { return r.ok ? r.json() : null; })
      .then(function (j) {
        if (j && j.tag_name) {
          verEl.textContent = j.tag_name;
          verEl.removeAttribute("hidden");
        }
      })
      .catch(function () { /* 离线或限流:不显示版本号 */ });
  }

  applyLang();
})();
