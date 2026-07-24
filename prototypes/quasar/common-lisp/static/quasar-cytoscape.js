(function (global) {
  "use strict";

  const state = {
    cy: null,
    readyBridgeId: null
  };

  function signal(status, error) {
    const bridge = document.getElementById(state.readyBridgeId);

    if (!bridge) {
      console.error("Quasar renderer bridge element is missing.");
      return;
    }

    bridge.dataset.status = status;

    if (error) {
      bridge.dataset.error = String(error);
    } else {
      delete bridge.dataset.error;
    }

    bridge.click();
  }

  function ensureCytoscape(url) {
    if (global.cytoscape) {
      return Promise.resolve();
    }

    return new Promise(function (resolve, reject) {
      const previous = document.querySelector("script[data-quasar-cytoscape]");

      if (previous) {
        previous.addEventListener("load", resolve, { once: true });
        previous.addEventListener(
          "error",
          function () {
            reject(new Error("The existing Cytoscape script failed to load."));
          },
          { once: true }
        );
        return;
      }

      const script = document.createElement("script");
      script.src = url;
      script.async = true;
      script.dataset.quasarCytoscape = "true";
      script.addEventListener("load", resolve, { once: true });
      script.addEventListener(
        "error",
        function () {
          reject(new Error("Unable to load Cytoscape from " + url));
        },
        { once: true }
      );
      document.head.appendChild(script);
    });
  }

  function initialize(containerId) {
    const container = document.getElementById(containerId);

    if (!container) {
      throw new Error("Cytoscape container #" + containerId + " is missing.");
    }

    state.cy = global.cytoscape({
      container: container,
      elements: [],
      layout: { name: "preset" },
      style: [
        {
          selector: "node",
          style: {
            "background-color": "#334155",
            color: "#e2e8f0",
            label: "data(label)",
            "font-family": "ui-monospace, SFMono-Regular, Menlo, monospace",
            "font-size": 12,
            "text-valign": "bottom",
            "text-margin-y": 8,
            width: 46,
            height: 46
          }
        },
        {
          selector: "edge",
          style: {
            width: 2,
            "line-color": "#64748b",
            "target-arrow-color": "#64748b",
            "target-arrow-shape": "triangle",
            "curve-style": "bezier",
            label: "data(label)",
            color: "#cbd5e1",
            "font-size": 10,
            "text-background-color": "#0f172a",
            "text-background-opacity": 0.85,
            "text-background-padding": 3
          }
        }
      ]
    });

    state.cy.ready(function () {
      signal("ready");
    });
  }

  function setGraph(payload) {
    if (!state.cy) {
      throw new Error("The Cytoscape renderer is not ready.");
    }

    const elements = payload && Array.isArray(payload.elements)
      ? payload.elements
      : [];

    state.cy.startBatch();
    state.cy.elements().remove();
    state.cy.add(elements);
    state.cy.endBatch();
    state.cy.layout({ name: "preset", fit: true, padding: 48 }).run();
  }

  async function load(options) {
    state.readyBridgeId = options.readyBridgeId;

    try {
      await ensureCytoscape(options.cytoscapeUrl);
      initialize(options.containerId);
    } catch (error) {
      console.error(error);
      signal("error", error);
    }
  }

  global.QuasarCytoscape = {
    load: load,
    setGraph: setGraph,
    getInstance: function () {
      return state.cy;
    }
  };
})(window);
