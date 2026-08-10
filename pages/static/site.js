(() => {
  "use strict";

  const AUTO_DIG_URL = "https://auto-dig.starintel.actor/";
  const current = document.currentScript;
  const base = current?.src ? new URL(".", current.src) : new URL("./", window.location.href);
  const ICONS = Object.freeze({
    Index: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M4 4h6v6H4zM14 4h6v6h-6zM4 14h6v6H4zM14 14h6v6h-6z"/></svg>',
    Search: '<svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="10.5" cy="10.5" r="5.5"/><path d="m15 15 5 5"/></svg>',
    Graph: '<svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="6" cy="12" r="2.5"/><circle cx="17" cy="6" r="2.5"/><circle cx="18" cy="18" r="2.5"/><path d="M8.3 10.8 14.7 7M8.5 13.2l7 3.4M17.4 8.5l.4 7"/></svg>',
    "Auto-Dig": '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M4 5h16v14H4zM8 9h8M8 13h5M16 13l3 3M19 13l-3 3"/></svg>'
  });

  function mountShellStyles() {
    if (document.querySelector('link[data-adar-shell="true"]')) return;
    const link = document.createElement("link");
    link.rel = "stylesheet";
    link.href = new URL("adar-shell.css", base).href;
    link.dataset.adarShell = "true";
    document.head.appendChild(link);
  }

  function labelFor(link) {
    return String(link.textContent || "").replace(/\s*↗\s*$/, "").trim();
  }

  function decorateLink(link, override = "") {
    const label = override || labelFor(link);
    const icon = ICONS[label];
    if (!icon) return;
    link.innerHTML = `${icon}<span>${label}${link.dataset.siblingSite ? " ↗" : ""}</span>`;
    const target = new URL(link.href, window.location.href);
    if (!link.dataset.siblingSite && target.pathname === window.location.pathname && target.hash === window.location.hash) {
      link.setAttribute("aria-current", "page");
    }
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

    [...nav.querySelectorAll("a")].forEach((link) => decorateLink(link));

    if (!nav.querySelector('[data-sibling-site="auto-dig"]')) {
      const link = document.createElement("a");
      link.href = AUTO_DIG_URL;
      link.dataset.siblingSite = "auto-dig";
      link.textContent = "Auto-Dig ↗";
      decorateLink(link, "Auto-Dig");
      nav.appendChild(link);
    }
  }

  mountShellStyles();
  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", mountSiblingNavigation, { once: true });
  } else {
    mountSiblingNavigation();
  }

  const runtime = document.createElement("script");
  runtime.src = new URL(document.getElementById("graph-canvas") ? "graph.js" : "site-core.js", base).href;
  runtime.async = false;
  document.head.appendChild(runtime);
})();
