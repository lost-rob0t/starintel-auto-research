"use strict";

const fs = require("fs");
const vm = require("vm");

const adapterPath = process.argv[2];

if (!adapterPath) {
  throw new Error("Pass the path to quasar-cytoscape.js.");
}

const signals = [];
const bridge = {
  dataset: {},
  click() {
    signals.push({ ...this.dataset });
  }
};
const container = {};

global.window = global;
global.document = {
  getElementById(id) {
    if (id === "bridge") return bridge;
    if (id === "graph") return container;
    return null;
  },
  querySelector() {
    return null;
  },
  createElement() {
    const handlers = {};
    return {
      dataset: {},
      addEventListener(name, handler) {
        handlers[name] = handler;
      },
      handlers
    };
  },
  head: {
    appendChild(script) {
      global.cytoscape = function (options) {
        let elements = [];
        return {
          ready(handler) {
            handler();
          },
          startBatch() {},
          endBatch() {},
          elements() {
            return {
              remove() {
                elements = [];
              }
            };
          },
          add(nextElements) {
            elements = nextElements;
          },
          layout() {
            return { run() {} };
          },
          testElements() {
            return elements;
          },
          options
        };
      };
      script.handlers.load();
    }
  }
};

vm.runInThisContext(fs.readFileSync(adapterPath, "utf8"), {
  filename: adapterPath
});

async function main() {
  await global.QuasarCytoscape.load({
    containerId: "graph",
    readyBridgeId: "bridge",
    cytoscapeUrl: "fake-cytoscape.js"
  });

  if (signals.length !== 1 || signals[0].status !== "ready") {
    throw new Error("The renderer did not emit exactly one ready signal.");
  }

  global.QuasarCytoscape.setGraph({
    elements: [{ group: "nodes", data: { id: "node-a" } }]
  });

  if (global.QuasarCytoscape.getInstance().testElements().length !== 1) {
    throw new Error("The graph replacement payload was not applied.");
  }

  console.log("renderer harness passed");
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
