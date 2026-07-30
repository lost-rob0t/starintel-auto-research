(() => {
  "use strict";

  const STORAGE_KEY = "starintel-theme";
  const THEMES = [
    ["synthwave", "Synthwave"],
    ["midnight", "Midnight"],
    ["terminal", "Terminal"],
    ["paper", "Paper"],
  ];
  const allowedThemes = new Set(THEMES.map(([value]) => value));
  const root = document.documentElement;

  function storedTheme() {
    try {
      const value = window.localStorage.getItem(STORAGE_KEY);
      return allowedThemes.has(value) ? value : "synthwave";
    } catch (_error) {
      return "synthwave";
    }
  }

  function applyTheme(theme, persist = false) {
    const selected = allowedThemes.has(theme) ? theme : "synthwave";
    root.dataset.theme = selected;
    root.style.colorScheme = selected === "paper" ? "light" : "dark";

    if (persist) {
      try {
        window.localStorage.setItem(STORAGE_KEY, selected);
      } catch (_error) {
        // A blocked storage API should not break the selector.
      }
    }

    document.dispatchEvent(new CustomEvent("starintel:theme-change", {
      detail: { theme: selected },
    }));
    return selected;
  }

  function mountThemeSelector() {
    const header = document.querySelector(".site-header");
    if (!header || header.querySelector(".theme-control")) return;

    const control = document.createElement("label");
    control.className = "theme-control";

    const label = document.createElement("span");
    label.textContent = "Theme";

    const select = document.createElement("select");
    select.id = "theme-selector";
    select.setAttribute("aria-label", "Site theme");

    for (const [value, text] of THEMES) {
      const option = document.createElement("option");
      option.value = value;
      option.textContent = text;
      select.append(option);
    }

    select.value = root.dataset.theme || "synthwave";
    select.addEventListener("change", () => {
      select.value = applyTheme(select.value, true);
    });

    control.append(label, select);
    header.append(control);
  }

  applyTheme(storedTheme());

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", mountThemeSelector, { once: true });
  } else {
    mountThemeSelector();
  }
})();
