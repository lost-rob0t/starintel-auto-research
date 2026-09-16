(() => {
  "use strict";

  const current = document.currentScript;
  const base = current?.src ? new URL(".", current.src) : new URL("./", window.location.href);
  const ASSET_VERSION = "obsidian-gold-v1";
  const assetUrl = (name) => {
    const url = new URL(name, base);
    url.searchParams.set("v", ASSET_VERSION);
    return url.href;
  };
  const runtime = document.createElement("script");
  runtime.src = assetUrl(document.getElementById("graph-canvas") ? "graph.js" : "site-core.js");
  runtime.async = false;
  document.head.appendChild(runtime);
})();
