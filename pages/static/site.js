(() => {
  "use strict";

  const AUTO_DIG_URL = "https://auto-dig.starintel.actor/";
  const current = document.currentScript;
  const base = current?.src ? new URL(".", current.src) : new URL("./", window.location.href);

  function mountShellStyles() {
    if (document.querySelector('link[data-adar-shell="true"]')) return;
    const link = document.createElement("link");
    link.rel = "stylesheet";
    link.href = new URL("adar-shell.css", base).href;
    link.dataset.adarShell = "true";
    document.head.appendChild(link);
  }

  function mountSiblingNavigation() {
    const header = document.querySelector(".site-header");
    if (!header) return;
    const title = header.querySelector(".site-title");
    if (title) title.textContent = "StarIntel Research";
    let nav = header.querySelector("nav");
    if (!nav) {
      nav = document.createElement("nav");
      header.appendChild(nav);
    }
    if (!nav.querySelector('[data-sibling-site="auto-dig"]')) {
      const link = document.createElement("a");
      link.href = AUTO_DIG_URL;
      link.textContent = "Auto-Dig ↗";
      link.dataset.siblingSite = "auto-dig";
      nav.appendChild(link);
    }
  }

  mountShellStyles();
  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", mountSiblingNavigation, { once: true });
  } else {
    mountSiblingNavigation();
  }

  const core = document.createElement("script");
  core.src = new URL("site-core.js", base).href;
  core.async = false;
  document.head.appendChild(core);
})();
