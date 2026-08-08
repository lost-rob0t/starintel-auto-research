(() => {
  "use strict";

  const AUTO_DIG_URL = "https://auto-dig.starintel.actor/";
  const current = document.currentScript;
  const base = current?.src ? new URL(".", current.src) : new URL("./", window.location.href);

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
