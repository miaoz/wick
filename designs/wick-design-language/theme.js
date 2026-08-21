/* Wick 设计语言 — 主题切换(弧光引擎演示)
   读取 localStorage 的 wick-scheme / wick-phase,写到 <html> 的 data 属性上,
   tokens.css 据此解析出对应锚点色板。所有页面共享,选择跨页面保持。 */
(function () {
  var root = document.documentElement;
  var q = new URLSearchParams(location.search);
  var scheme = q.get("scheme") || localStorage.getItem("wick-scheme") || "light";
  var phase = q.get("phase") || localStorage.getItem("wick-phase") || "day";

  function apply() {
    root.setAttribute("data-scheme", scheme);
    root.setAttribute("data-phase", phase);
    document.querySelectorAll("[data-set-scheme]").forEach(function (b) {
      b.classList.toggle("is-on", b.getAttribute("data-set-scheme") === scheme);
    });
    document.querySelectorAll("[data-set-phase]").forEach(function (b) {
      b.classList.toggle("is-on", b.getAttribute("data-set-phase") === phase);
    });
  }

  document.addEventListener("click", function (e) {
    var s = e.target.closest("[data-set-scheme]");
    var p = e.target.closest("[data-set-phase]");
    if (s) { scheme = s.getAttribute("data-set-scheme"); localStorage.setItem("wick-scheme", scheme); apply(); }
    if (p) { phase = p.getAttribute("data-set-phase"); localStorage.setItem("wick-phase", phase); apply(); }
  });

  /* 弧光条上的「此刻」光点 + 单调时钟 + 燃烧条的实时今日进度 */
  function tick() {
    var now = new Date();
    var dayT = (now.getHours() * 3600 + now.getMinutes() * 60 + now.getSeconds()) / 86400;
    document.querySelectorAll(".arc-strip .now").forEach(function (d) {
      d.style.left = (dayT * 100).toFixed(2) + "%";
    });
    document.querySelectorAll("[data-burn-day]").forEach(function (el) {
      el.style.setProperty("--p", (dayT * 100).toFixed(2) + "%");
    });
    document.querySelectorAll("[data-burn-day-label]").forEach(function (el) {
      el.textContent = ((1 - dayT) * 100).toFixed(1);
    });
    document.querySelectorAll("[data-burn-pct]").forEach(function (el) {
      el.textContent = (dayT * 100).toFixed(1);
    });
    document.querySelectorAll("[data-clock]").forEach(function (el) {
      el.textContent = now.getFullYear() + "年" + (now.getMonth() + 1) + "月" + now.getDate() +
        "日 周" + "日一二三四五六"[now.getDay()] + " " +
        String(now.getHours()).padStart(2, "0") + ":" + String(now.getMinutes()).padStart(2, "0");
    });
  }

  apply();
  tick();
  setInterval(tick, 1000);
})();
