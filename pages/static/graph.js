(() => {
  "use strict";

  const byId = (id) => document.getElementById(id);
  const currentScript = document.currentScript;
  const staticAssetBase = currentScript?.src ? new URL(".", currentScript.src) : null;

  const KIND_COLORS = Object.freeze({
    research: "#2de2e6",
    design: "#ff5ea8",
    implement: "#fba922",
    implementation: "#fba922",
    indexes: "#b487ff",
    index: "#b487ff",
    architecture: "#5ca9ff",
    specification: "#62ff00",
    spec: "#62ff00",
    decision: "#ff6b6b",
    operations: "#ffe66d",
    provider: "#00f5a0",
    actor: "#00d4ff",
    document: "#d9dde3",
  });

  const FALLBACK_COLORS = Object.freeze([
    "#2de2e6",
    "#ff5ea8",
    "#fba922",
    "#b487ff",
    "#62ff00",
    "#5ca9ff",
    "#ff6b6b",
    "#ffe66d",
    "#00f5a0",
    "#d9dde3",
  ]);

  async function loadJson(path) {
    const response = await fetch(path, { cache: "no-store" });
    if (!response.ok) throw new Error(`${response.status} ${response.statusText}`);
    return response.json();
  }

  function clamp(value, minimum, maximum) {
    return Math.min(maximum, Math.max(minimum, value));
  }

  function hashNumber(value) {
    let hash = 2166136261;
    for (let index = 0; index < value.length; index += 1) {
      hash ^= value.charCodeAt(index);
      hash = Math.imul(hash, 16777619);
    }
    return hash >>> 0;
  }

  function normalizeKind(node) {
    return String(node.kind || node.type || "document").trim().toLowerCase() || "document";
  }

  function labelKind(kind) {
    return kind.replace(/[-_]+/g, " ").replace(/\b\w/g, (character) => character.toUpperCase());
  }

  function colorForKind(kind) {
    return KIND_COLORS[kind] || FALLBACK_COLORS[hashNumber(kind) % FALLBACK_COLORS.length];
  }

  function loadGraphStyles() {
    if (!staticAssetBase || document.querySelector('link[data-starintel-graph-styles]')) return;
    const link = document.createElement("link");
    link.rel = "stylesheet";
    link.href = new URL("graph.css", staticAssetBase).href;
    link.dataset.starintelGraphStyles = "true";
    document.head.append(link);
  }

  function button(label, action, title = label) {
    const element = document.createElement("button");
    element.type = "button";
    element.className = "graph-action";
    element.textContent = label;
    element.title = title;
    element.setAttribute("aria-label", title);
    element.addEventListener("click", action);
    return element;
  }

  function createShell(canvas, status) {
    loadGraphStyles();

    const section = canvas.closest("section") || canvas.parentElement;
    section?.classList.add("graph-page");

    const intro = section
      ? [...section.querySelectorAll(":scope > p")].find((node) => !node.classList.contains("eyebrow") && node !== status)
      : null;
    if (intro) {
      intro.classList.add("graph-intro");
      intro.textContent = "Explore the research graph by type, relationship, and neighborhood. Search, filter, zoom, pan, or select any node for context.";
    }

    const workspace = document.createElement("div");
    workspace.className = "graph-workspace";

    const toolbar = document.createElement("div");
    toolbar.className = "graph-toolbar";

    const searchWrap = document.createElement("div");
    searchWrap.className = "graph-search-wrap";
    const searchLabel = document.createElement("label");
    searchLabel.htmlFor = "graph-search";
    searchLabel.textContent = "Find node";
    const search = document.createElement("input");
    search.id = "graph-search";
    search.className = "graph-search";
    search.type = "search";
    search.autocomplete = "off";
    search.placeholder = "title, tag, description, type…";
    const searchMeta = document.createElement("span");
    searchMeta.className = "graph-search-meta";
    searchMeta.textContent = "Press / to focus";
    searchWrap.append(searchLabel, search, searchMeta);

    const actionGroup = document.createElement("div");
    actionGroup.className = "graph-actions";

    const body = document.createElement("div");
    body.className = "graph-body";

    const stage = document.createElement("div");
    stage.className = "graph-stage-frame";

    const hud = document.createElement("div");
    hud.className = "graph-hud";
    const visibleHud = document.createElement("span");
    const linkHud = document.createElement("span");
    const zoomHud = document.createElement("span");
    hud.append(visibleHud, linkHud, zoomHud);

    const legend = document.createElement("div");
    legend.className = "graph-legend";
    const legendHeader = document.createElement("div");
    legendHeader.className = "graph-legend-header";
    const legendTitle = document.createElement("strong");
    legendTitle.textContent = "Node types";
    const legendHint = document.createElement("span");
    legendHint.textContent = "click to filter";
    legendHeader.append(legendTitle, legendHint);
    const legendItems = document.createElement("div");
    legendItems.className = "graph-legend-items";
    legend.append(legendHeader, legendItems);

    const inspector = document.createElement("aside");
    inspector.className = "graph-inspector";
    inspector.setAttribute("aria-hidden", "true");
    inspector.innerHTML = `
      <div class="graph-inspector-header">
        <div>
          <p class="eyebrow">Node inspector</p>
          <div class="graph-inspector-kind"></div>
        </div>
        <button class="graph-inspector-close" type="button" aria-label="Close node inspector">×</button>
      </div>
      <h2 class="graph-inspector-title">Select a node</h2>
      <p class="graph-inspector-meta"></p>
      <p class="graph-inspector-description"></p>
      <div class="graph-inspector-actions">
        <a class="graph-inspector-open" href="#">Open document</a>
        <button class="graph-focus-neighborhood" type="button">Focus neighborhood</button>
      </div>
      <section class="graph-inspector-section">
        <div class="graph-section-heading"><h3>Direct links</h3><span class="graph-related-count"></span></div>
        <ul class="graph-related-documents"></ul>
      </section>
    `;

    canvas.before(workspace);
    stage.append(canvas, hud, legend);
    body.append(stage, inspector);
    toolbar.append(searchWrap, actionGroup, status);
    workspace.append(toolbar, body);

    status.className = "graph-status";

    return {
      workspace,
      toolbar,
      search,
      searchMeta,
      actionGroup,
      stage,
      hud,
      visibleHud,
      linkHud,
      zoomHud,
      legendItems,
      inspector,
      inspectorClose: inspector.querySelector(".graph-inspector-close"),
      inspectorKind: inspector.querySelector(".graph-inspector-kind"),
      inspectorTitle: inspector.querySelector(".graph-inspector-title"),
      inspectorMeta: inspector.querySelector(".graph-inspector-meta"),
      inspectorDescription: inspector.querySelector(".graph-inspector-description"),
      inspectorOpen: inspector.querySelector(".graph-inspector-open"),
      focusNeighborhood: inspector.querySelector(".graph-focus-neighborhood"),
      relatedCount: inspector.querySelector(".graph-related-count"),
      related: inspector.querySelector(".graph-related-documents"),
    };
  }

  async function startGraph() {
    const canvas = byId("graph-canvas");
    const status = byId("graph-status");
    if (!canvas || !status) return;

    try {
      const graph = await loadJson("graph.json");
      const context = canvas.getContext("2d");
      if (!context) throw new Error("Canvas rendering is unavailable");

      const shell = createShell(canvas, status);
      let width = 1;
      let height = 1;
      let pixelRatio = 1;
      let alpha = 1;
      let dirty = true;
      let hovered = null;
      let selectedNode = null;
      let neighborhoodFocus = false;
      let interaction = null;
      let pointerDownAt = null;
      let searchMatches = new Set();
      let searchQuery = "";

      const camera = { x: 0, y: 0, scale: 1 };
      const hiddenKinds = new Set();

      const nodes = graph.nodes.map((raw, index) => {
        const kind = normalizeKind(raw);
        return {
          ...raw,
          kind,
          color: colorForKind(kind),
          index,
          x: 0,
          y: 0,
          anchorX: 0,
          anchorY: 0,
          vx: 0,
          vy: 0,
          ax: 0,
          ay: 0,
          radius: 7,
        };
      });

      const nodeById = new Map(nodes.map((node) => [node.id, node]));
      const links = graph.links
        .map((raw) => ({ ...raw, source: nodeById.get(raw.source), target: nodeById.get(raw.target) }))
        .filter((link) => link.source && link.target && link.source !== link.target);

      const degree = new Map(nodes.map((node) => [node.id, 0]));
      const relatedById = new Map(nodes.map((node) => [node.id, []]));
      for (const link of links) {
        degree.set(link.source.id, degree.get(link.source.id) + 1);
        degree.set(link.target.id, degree.get(link.target.id) + 1);
        relatedById.get(link.source.id).push(link.target);
        relatedById.get(link.target.id).push(link.source);
      }
      for (const node of nodes) {
        node.radius = clamp(5.5 + Math.sqrt(degree.get(node.id)) * 1.35, 5.5, 14);
      }

      const kindCounts = new Map();
      for (const node of nodes) kindCounts.set(node.kind, (kindCounts.get(node.kind) || 0) + 1);

      function nodeVisible(node) {
        return !hiddenKinds.has(node.kind);
      }

      function linkVisible(link) {
        return nodeVisible(link.source) && nodeVisible(link.target);
      }

      function visibleNodes() {
        return nodes.filter(nodeVisible);
      }

      function visibleLinks() {
        return links.filter(linkVisible);
      }

      function markDirty() {
        dirty = true;
      }

      function worldToScreen(point) {
        return {
          x: (point.x - camera.x) * camera.scale + width / 2,
          y: (point.y - camera.y) * camera.scale + height / 2,
        };
      }

      function screenToWorld(point) {
        return {
          x: (point.x - width / 2) / camera.scale + camera.x,
          y: (point.y - height / 2) / camera.scale + camera.y,
        };
      }

      function pointerPosition(event) {
        const bounds = canvas.getBoundingClientRect();
        return { x: event.clientX - bounds.left, y: event.clientY - bounds.top };
      }

      function nearest(screenPosition) {
        const world = screenToWorld(screenPosition);
        let nearestNode = null;
        let nearestDistance = Infinity;
        const extraWorldHitArea = 9 / camera.scale;
        for (const node of nodes) {
          if (!nodeVisible(node)) continue;
          const distance = Math.hypot(node.x - world.x, node.y - world.y);
          if (distance <= node.radius + extraWorldHitArea && distance < nearestDistance) {
            nearestNode = node;
            nearestDistance = distance;
          }
        }
        return nearestNode;
      }

      function seedLayout(force = false) {
        const targetWidth = Math.max(720, width);
        const targetHeight = Math.max(520, height);
        const goldenAngle = Math.PI * (3 - Math.sqrt(5));
        const spacing = clamp(Math.sqrt((targetWidth * targetHeight) / Math.max(1, nodes.length)) * 0.6, 24, 48);

        nodes.forEach((node, index) => {
          const seed = hashNumber(node.id);
          const angle = index * goldenAngle + ((seed % 720) / 720) * Math.PI * 0.35;
          const radius = spacing * Math.sqrt(index + 0.5);
          node.anchorX = Math.cos(angle) * radius;
          node.anchorY = Math.sin(angle) * radius;
          if (force || (node.x === 0 && node.y === 0)) {
            node.x = node.anchorX;
            node.y = node.anchorY;
            node.vx = 0;
            node.vy = 0;
          }
        });
        alpha = 1;
        markDirty();
      }

      function fitView(padding = 72) {
        const candidates = visibleNodes();
        if (candidates.length === 0) return;
        let minX = Infinity;
        let minY = Infinity;
        let maxX = -Infinity;
        let maxY = -Infinity;
        for (const node of candidates) {
          minX = Math.min(minX, node.x - node.radius);
          maxX = Math.max(maxX, node.x + node.radius);
          minY = Math.min(minY, node.y - node.radius);
          maxY = Math.max(maxY, node.y + node.radius);
        }
        const worldWidth = Math.max(80, maxX - minX);
        const worldHeight = Math.max(80, maxY - minY);
        camera.x = (minX + maxX) / 2;
        camera.y = (minY + maxY) / 2;
        camera.scale = clamp(Math.min((width - padding * 2) / worldWidth, (height - padding * 2) / worldHeight), 0.18, 3.5);
        markDirty();
        updateHud();
      }

      function setZoom(nextScale, anchorScreen = { x: width / 2, y: height / 2 }) {
        const before = screenToWorld(anchorScreen);
        camera.scale = clamp(nextScale, 0.18, 4.5);
        const after = screenToWorld(anchorScreen);
        camera.x += before.x - after.x;
        camera.y += before.y - after.y;
        markDirty();
        updateHud();
      }

      function addCollisionForces() {
        const cellSize = 34;
        const grid = new Map();
        for (const node of nodes) {
          const cellX = Math.floor(node.x / cellSize);
          const cellY = Math.floor(node.y / cellSize);
          const key = `${cellX}:${cellY}`;
          if (!grid.has(key)) grid.set(key, []);
          grid.get(key).push(node);
        }

        for (const node of nodes) {
          const cellX = Math.floor(node.x / cellSize);
          const cellY = Math.floor(node.y / cellSize);
          for (let offsetX = -1; offsetX <= 1; offsetX += 1) {
            for (let offsetY = -1; offsetY <= 1; offsetY += 1) {
              const candidates = grid.get(`${cellX + offsetX}:${cellY + offsetY}`) || [];
              for (const other of candidates) {
                if (other.index <= node.index) continue;
                let dx = other.x - node.x;
                let dy = other.y - node.y;
                let distance = Math.hypot(dx, dy);
                const minimum = node.radius + other.radius + 9;
                if (distance === 0) {
                  const angle = (hashNumber(`${node.id}:${other.id}`) % 360) * Math.PI / 180;
                  dx = Math.cos(angle) * 0.01;
                  dy = Math.sin(angle) * 0.01;
                  distance = 0.01;
                }
                if (distance < minimum) {
                  const force = ((minimum - distance) / minimum) * 0.8 * alpha;
                  const forceX = (dx / distance) * force;
                  const forceY = (dy / distance) * force;
                  node.ax -= forceX;
                  node.ay -= forceY;
                  other.ax += forceX;
                  other.ay += forceY;
                }
              }
            }
          }
        }
      }

      function simulate() {
        const linkDistance = 112;
        const springStrength = 0.012;
        const anchorStrength = 0.0014;
        const centerStrength = 0.00065;
        const velocityRetention = 0.7;
        const maxSpeed = 4.4;

        for (const node of nodes) {
          node.ax = (node.anchorX - node.x) * anchorStrength * alpha;
          node.ay = (node.anchorY - node.y) * anchorStrength * alpha;
          node.ax += -node.x * centerStrength * alpha;
          node.ay += -node.y * centerStrength * alpha;
        }

        for (const link of links) {
          const dx = link.target.x - link.source.x;
          const dy = link.target.y - link.source.y;
          const distance = Math.max(0.001, Math.hypot(dx, dy));
          const stretch = distance - linkDistance;
          const force = stretch * springStrength * alpha;
          const forceX = (dx / distance) * force;
          const forceY = (dy / distance) * force;
          link.source.ax += forceX;
          link.source.ay += forceY;
          link.target.ax -= forceX;
          link.target.ay -= forceY;
        }

        addCollisionForces();

        for (const node of nodes) {
          if (interaction?.mode === "node" && interaction.node === node) continue;
          node.vx = clamp((node.vx + node.ax) * velocityRetention, -maxSpeed, maxSpeed);
          node.vy = clamp((node.vy + node.ay) * velocityRetention, -maxSpeed, maxSpeed);
          node.x += node.vx;
          node.y += node.vy;
        }

        alpha *= 0.974;
        if (alpha < 0.006) alpha = 0;
        markDirty();
      }

      function connectedToSelected(node) {
        if (!selectedNode || !neighborhoodFocus) return true;
        if (node === selectedNode) return true;
        return (relatedById.get(selectedNode.id) || []).includes(node);
      }

      function searchMatch(node) {
        return searchMatches.has(node.id);
      }

      function draw() {
        context.clearRect(0, 0, width, height);
        context.save();
        context.translate(width / 2, height / 2);
        context.scale(camera.scale, camera.scale);
        context.translate(-camera.x, -camera.y);

        for (const link of links) {
          if (!linkVisible(link)) continue;
          const selectedLink = selectedNode && (link.source === selectedNode || link.target === selectedNode);
          const focused = !neighborhoodFocus || selectedLink;
          context.beginPath();
          context.globalAlpha = focused ? (selectedLink ? 0.88 : 0.34) : 0.05;
          context.strokeStyle = selectedLink ? selectedNode.color : "#7d6f99";
          context.lineWidth = (selectedLink ? 1.8 : 1) / camera.scale;
          context.moveTo(link.source.x, link.source.y);
          context.lineTo(link.target.x, link.target.y);
          context.stroke();
        }

        for (const node of nodes) {
          if (!nodeVisible(node)) continue;
          const focused = connectedToSelected(node);
          const matched = searchMatch(node);
          const active = node === selectedNode || node === hovered || interaction?.node === node;
          context.globalAlpha = focused ? 1 : 0.12;
          context.beginPath();
          context.fillStyle = active ? "#f3f4f5" : node.color;
          context.shadowColor = node.color;
          context.shadowBlur = active ? 15 / camera.scale : 7 / camera.scale;
          context.arc(node.x, node.y, node.radius, 0, Math.PI * 2);
          context.fill();
          context.shadowBlur = 0;

          if (node === selectedNode || matched) {
            context.beginPath();
            context.strokeStyle = node === selectedNode ? "#f3f4f5" : "#ffe66d";
            context.lineWidth = (node === selectedNode ? 2.1 : 1.5) / camera.scale;
            context.arc(node.x, node.y, node.radius + (node === selectedNode ? 5 : 4) / camera.scale, 0, Math.PI * 2);
            context.stroke();
          }
        }

        context.restore();
        context.globalAlpha = 1;

        const labelNode = hovered || selectedNode;
        if (labelNode && nodeVisible(labelNode)) {
          const screen = worldToScreen(labelNode);
          const title = String(labelNode.title || labelNode.id || "Untitled");
          const kind = labelKind(labelNode.kind);
          context.font = "600 12px ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace";
          const titleWidth = Math.min(300, context.measureText(title).width);
          context.font = "10px ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace";
          const kindWidth = context.measureText(kind).width;
          const boxWidth = Math.max(titleWidth, kindWidth) + 20;
          const boxHeight = 46;
          const boxX = clamp(screen.x + labelNode.radius * camera.scale + 10, 8, width - boxWidth - 8);
          const boxY = clamp(screen.y - boxHeight - 8, 8, height - boxHeight - 8);
          context.fillStyle = "rgba(17, 10, 39, 0.94)";
          context.strokeStyle = labelNode.color;
          context.lineWidth = 1;
          context.beginPath();
          context.roundRect(boxX, boxY, boxWidth, boxHeight, 6);
          context.fill();
          context.stroke();
          context.fillStyle = "#f3f4f5";
          context.font = "600 12px ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace";
          context.fillText(title, boxX + 10, boxY + 19, boxWidth - 20);
          context.fillStyle = labelNode.color;
          context.font = "10px ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace";
          context.fillText(kind, boxX + 10, boxY + 35, boxWidth - 20);
        }

        dirty = false;
      }

      function updateHud() {
        const shownNodes = visibleNodes().length;
        const shownLinks = visibleLinks().length;
        shell.visibleHud.textContent = `${shownNodes.toLocaleString()} / ${nodes.length.toLocaleString()} nodes`;
        shell.linkHud.textContent = `${shownLinks.toLocaleString()} links`;
        shell.zoomHud.textContent = `${Math.round(camera.scale * 100)}% zoom`;
        status.textContent = selectedNode
          ? selectedNode.title
          : `${shownNodes.toLocaleString()} visible nodes · wheel to zoom · drag background to pan`;
      }

      function closeInspector() {
        selectedNode = null;
        neighborhoodFocus = false;
        shell.workspace.classList.remove("has-inspector");
        shell.inspector.setAttribute("aria-hidden", "true");
        shell.focusNeighborhood.classList.remove("is-active");
        shell.focusNeighborhood.textContent = "Focus neighborhood";
        updateHud();
        markDirty();
      }

      function selectNode(node, reveal = true) {
        if (!node) {
          closeInspector();
          return;
        }
        selectedNode = node;
        neighborhoodFocus = false;
        shell.inspectorKind.textContent = labelKind(node.kind);
        shell.inspectorKind.style.setProperty("--type-color", node.color);
        shell.inspectorTitle.textContent = node.title || node.id;
        shell.inspectorMeta.textContent = [node.modified, ...(node.tags || [])].filter(Boolean).join(" · ");
        shell.inspectorDescription.textContent = node.description || "No description is available for this node.";
        shell.inspectorOpen.href = node.url;
        shell.related.replaceChildren();

        const related = [...(relatedById.get(node.id) || [])].sort((left, right) => {
          const degreeDifference = (degree.get(right.id) || 0) - (degree.get(left.id) || 0);
          return degreeDifference || String(left.title).localeCompare(String(right.title));
        });
        shell.relatedCount.textContent = related.length.toLocaleString();
        if (related.length === 0) {
          const empty = document.createElement("li");
          empty.className = "graph-related-empty";
          empty.textContent = "No direct links.";
          shell.related.append(empty);
        } else {
          for (const relatedNode of related) {
            const item = document.createElement("li");
            const link = document.createElement("button");
            link.type = "button";
            link.className = "graph-related-link";
            const dot = document.createElement("span");
            dot.className = "graph-related-dot";
            dot.style.setProperty("--type-color", relatedNode.color);
            const copy = document.createElement("span");
            const title = document.createElement("strong");
            title.textContent = relatedNode.title || relatedNode.id;
            const meta = document.createElement("small");
            meta.textContent = `${labelKind(relatedNode.kind)} · ${degree.get(relatedNode.id) || 0} links`;
            copy.append(title, meta);
            link.append(dot, copy);
            link.addEventListener("click", () => selectNode(relatedNode, true));
            item.append(link);
            shell.related.append(item);
          }
        }

        shell.workspace.classList.add("has-inspector");
        shell.inspector.setAttribute("aria-hidden", "false");
        shell.focusNeighborhood.classList.remove("is-active");
        shell.focusNeighborhood.textContent = "Focus neighborhood";
        updateHud();
        if (reveal) centerOnNode(node);
        markDirty();
      }

      function centerOnNode(node) {
        camera.x = node.x;
        camera.y = node.y;
        camera.scale = Math.max(camera.scale, 0.9);
        markDirty();
        updateHud();
      }

      function updateSearch() {
        searchQuery = shell.search.value.trim().toLowerCase();
        searchMatches = new Set();
        if (!searchQuery) {
          shell.searchMeta.textContent = "Press / to focus";
          markDirty();
          return;
        }
        const terms = searchQuery.split(/\s+/).filter(Boolean);
        const matches = nodes.filter((node) => {
          if (!nodeVisible(node)) return false;
          const haystack = [node.title, node.description, node.kind, ...(node.tags || [])].join(" ").toLowerCase();
          return terms.every((term) => haystack.includes(term));
        });
        searchMatches = new Set(matches.map((node) => node.id));
        shell.searchMeta.textContent = `${matches.length.toLocaleString()} match${matches.length === 1 ? "" : "es"}`;
        if (matches.length === 1) selectNode(matches[0], true);
        markDirty();
      }

      function buildLegend() {
        shell.legendItems.replaceChildren();
        const kinds = [...kindCounts.keys()].sort((left, right) => {
          return (kindCounts.get(right) || 0) - (kindCounts.get(left) || 0) || left.localeCompare(right);
        });
        for (const kind of kinds) {
          const item = document.createElement("button");
          item.type = "button";
          item.className = "graph-kind-filter";
          item.dataset.kind = kind;
          item.setAttribute("aria-pressed", "true");
          item.style.setProperty("--type-color", colorForKind(kind));
          const dot = document.createElement("span");
          dot.className = "graph-kind-dot";
          const label = document.createElement("span");
          label.className = "graph-kind-label";
          label.textContent = labelKind(kind);
          const count = document.createElement("span");
          count.className = "graph-kind-count";
          count.textContent = (kindCounts.get(kind) || 0).toLocaleString();
          item.append(dot, label, count);
          item.addEventListener("click", () => {
            const nowHidden = !hiddenKinds.has(kind);
            if (nowHidden) hiddenKinds.add(kind);
            else hiddenKinds.delete(kind);
            item.classList.toggle("is-disabled", nowHidden);
            item.setAttribute("aria-pressed", String(!nowHidden));
            if (selectedNode && hiddenKinds.has(selectedNode.kind)) closeInspector();
            updateSearch();
            updateHud();
            markDirty();
          });
          shell.legendItems.append(item);
        }
      }

      function resizeCanvas() {
        const rect = canvas.getBoundingClientRect();
        width = Math.max(1, rect.width);
        height = Math.max(1, rect.height);
        pixelRatio = Math.max(1, window.devicePixelRatio || 1);
        canvas.width = Math.max(1, Math.round(width * pixelRatio));
        canvas.height = Math.max(1, Math.round(height * pixelRatio));
        context.setTransform(pixelRatio, 0, 0, pixelRatio, 0, 0);
        markDirty();
      }

      shell.search.addEventListener("input", updateSearch);
      shell.search.addEventListener("keydown", (event) => {
        if (event.key === "Enter" && searchMatches.size > 0) {
          const first = nodes.find((node) => searchMatches.has(node.id));
          if (first) selectNode(first, true);
        }
      });
      shell.inspectorClose.addEventListener("click", closeInspector);
      shell.focusNeighborhood.addEventListener("click", () => {
        if (!selectedNode) return;
        neighborhoodFocus = !neighborhoodFocus;
        shell.focusNeighborhood.classList.toggle("is-active", neighborhoodFocus);
        shell.focusNeighborhood.textContent = neighborhoodFocus ? "Show full graph" : "Focus neighborhood";
        markDirty();
      });

      shell.actionGroup.append(
        button("Fit", () => fitView(), "Fit visible graph"),
        button("Reset", () => {
          seedLayout(true);
          camera.x = 0;
          camera.y = 0;
          camera.scale = 1;
          window.setTimeout(() => fitView(), 80);
        }, "Reset graph layout"),
        button("−", () => setZoom(camera.scale / 1.22), "Zoom out"),
        button("+", () => setZoom(camera.scale * 1.22), "Zoom in"),
      );

      canvas.addEventListener("wheel", (event) => {
        event.preventDefault();
        const position = pointerPosition(event);
        const factor = Math.exp(-event.deltaY * 0.0013);
        setZoom(camera.scale * factor, position);
      }, { passive: false });

      canvas.addEventListener("pointerdown", (event) => {
        const screen = pointerPosition(event);
        const node = nearest(screen);
        pointerDownAt = screen;
        canvas.setPointerCapture(event.pointerId);
        if (node) {
          const world = screenToWorld(screen);
          interaction = {
            mode: "node",
            node,
            offsetX: node.x - world.x,
            offsetY: node.y - world.y,
          };
          node.vx = 0;
          node.vy = 0;
          alpha = Math.max(alpha, 0.2);
        } else {
          interaction = {
            mode: "pan",
            startX: screen.x,
            startY: screen.y,
            cameraX: camera.x,
            cameraY: camera.y,
          };
        }
        markDirty();
      });

      canvas.addEventListener("pointermove", (event) => {
        const screen = pointerPosition(event);
        if (!interaction) {
          const nextHovered = nearest(screen);
          if (nextHovered !== hovered) {
            hovered = nextHovered;
            canvas.style.cursor = hovered ? "pointer" : "grab";
            markDirty();
          }
          return;
        }

        if (interaction.mode === "node") {
          const world = screenToWorld(screen);
          const node = interaction.node;
          node.x = world.x + interaction.offsetX;
          node.y = world.y + interaction.offsetY;
          node.anchorX = node.x;
          node.anchorY = node.y;
          node.vx = 0;
          node.vy = 0;
          alpha = Math.max(alpha, 0.14);
          canvas.style.cursor = "grabbing";
        } else if (interaction.mode === "pan") {
          camera.x = interaction.cameraX - (screen.x - interaction.startX) / camera.scale;
          camera.y = interaction.cameraY - (screen.y - interaction.startY) / camera.scale;
          canvas.style.cursor = "grabbing";
          updateHud();
        }
        markDirty();
      });

      canvas.addEventListener("pointerup", (event) => {
        const screen = pointerPosition(event);
        const moved = pointerDownAt && Math.hypot(screen.x - pointerDownAt.x, screen.y - pointerDownAt.y) > 5;
        const clickedNode = interaction?.mode === "node" ? interaction.node : nearest(screen);
        if (canvas.hasPointerCapture(event.pointerId)) canvas.releasePointerCapture(event.pointerId);
        interaction = null;
        pointerDownAt = null;
        canvas.style.cursor = hovered ? "pointer" : "grab";
        if (!moved) {
          if (clickedNode) selectNode(clickedNode, false);
          else closeInspector();
        }
        markDirty();
      });

      canvas.addEventListener("pointercancel", () => {
        interaction = null;
        pointerDownAt = null;
        canvas.style.cursor = "grab";
        markDirty();
      });

      canvas.addEventListener("pointerleave", () => {
        if (!interaction && hovered) {
          hovered = null;
          markDirty();
        }
      });

      canvas.addEventListener("dblclick", (event) => {
        const node = nearest(pointerPosition(event));
        if (node?.url) window.location.href = node.url;
      });

      document.addEventListener("keydown", (event) => {
        if (event.key === "Escape") {
          if (document.activeElement === shell.search && shell.search.value) {
            shell.search.value = "";
            updateSearch();
            shell.search.blur();
          } else {
            closeInspector();
          }
        }
        if (event.key === "/" && document.activeElement !== shell.search) {
          event.preventDefault();
          shell.search.focus();
        }
        if ((event.key === "f" || event.key === "F") && document.activeElement !== shell.search) fitView();
      });

      function animate() {
        const active = alpha > 0 || interaction?.mode === "node";
        if (active) simulate();
        if (dirty) draw();
        requestAnimationFrame(animate);
      }

      resizeCanvas();
      seedLayout(true);
      buildLegend();
      updateHud();
      canvas.style.cursor = "grab";
      if (typeof ResizeObserver === "function") {
        new ResizeObserver(() => {
          resizeCanvas();
          fitView();
        }).observe(canvas);
      } else {
        window.addEventListener("resize", () => {
          resizeCanvas();
          fitView();
        });
      }
      window.setTimeout(() => fitView(), 120);
      animate();
    } catch (error) {
      status.textContent = `Graph failed: ${error.message}`;
    }
  }

  startGraph();
})();
