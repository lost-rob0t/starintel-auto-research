(() => {
  "use strict";

  const byId = (id) => document.getElementById(id);

  async function loadJson(path) {
    const response = await fetch(path, { cache: "no-store" });
    if (!response.ok) {
      throw new Error(`${response.status} ${response.statusText}`);
    }
    return response.json();
  }

  function escapeHtml(value) {
    const node = document.createElement("span");
    node.textContent = value ?? "";
    return node.innerHTML;
  }

  async function startSearch() {
    const input = byId("search-input");
    const results = byId("search-results");
    const status = byId("search-status");
    if (!input || !results || !status) return;

    try {
      const records = await loadJson("search-index.json");
      const normalized = records.map((record) => ({
        ...record,
        haystack: [
          record.title,
          record.description,
          record.kind,
          ...(record.tags || []),
          record.text,
        ].join(" ").toLowerCase(),
      }));

      const render = () => {
        const terms = input.value.trim().toLowerCase().split(/\s+/).filter(Boolean);
        const matches = terms.length
          ? normalized.filter((record) => terms.every((term) => record.haystack.includes(term)))
          : normalized.slice(0, 50);

        status.textContent = `${matches.length} page${matches.length === 1 ? "" : "s"}`;
        results.innerHTML = matches.slice(0, 100).map((record) => `
          <li class="search-result">
            <h2><a href="${escapeHtml(record.url)}">${escapeHtml(record.title)}</a></h2>
            <div class="meta">${escapeHtml(record.kind)} · ${escapeHtml(record.modified)} · ${escapeHtml((record.tags || []).join(" "))}</div>
            <p>${escapeHtml(record.description || record.text.slice(0, 240))}</p>
          </li>
        `).join("");
      };

      input.addEventListener("input", render);
      render();
    } catch (error) {
      status.textContent = `Search failed: ${error.message}`;
    }
  }

  function hashNumber(value) {
    let hash = 2166136261;
    for (let index = 0; index < value.length; index += 1) {
      hash ^= value.charCodeAt(index);
      hash = Math.imul(hash, 16777619);
    }
    return hash >>> 0;
  }

  function clamp(value, minimum, maximum) {
    return Math.min(maximum, Math.max(minimum, value));
  }

  async function startGraph() {
    const canvas = byId("graph-canvas");
    const status = byId("graph-status");
    if (!canvas || !status) return;

    try {
      const graph = await loadJson("graph.json");
      const context = canvas.getContext("2d");
      if (!context) throw new Error("Canvas rendering is unavailable");

      let width = 1;
      let height = 1;
      let pixelRatio = 1;
      let alpha = 1;
      let dragged = null;
      let hovered = null;
      let pointerDownAt = null;
      let dragOffset = { x: 0, y: 0 };

      const nodes = graph.nodes.map((node, index) => ({
        ...node,
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
      }));
      const nodeById = new Map(nodes.map((node) => [node.id, node]));
      const links = graph.links
        .map((link) => ({ source: nodeById.get(link.source), target: nodeById.get(link.target) }))
        .filter((link) => link.source && link.target && link.source !== link.target);

      const degree = new Map(nodes.map((node) => [node.id, 0]));
      for (const link of links) {
        degree.set(link.source.id, degree.get(link.source.id) + 1);
        degree.set(link.target.id, degree.get(link.target.id) + 1);
      }
      for (const node of nodes) {
        node.radius = clamp(6 + Math.sqrt(degree.get(node.id)) * 1.4, 6, 13);
      }

      function seedLayout() {
        const centerX = width / 2;
        const centerY = height / 2;
        const goldenAngle = Math.PI * (3 - Math.sqrt(5));
        const spacing = Math.max(22, Math.min(42, Math.sqrt((width * height) / Math.max(1, nodes.length)) * 0.45));

        nodes.forEach((node, index) => {
          const seed = hashNumber(node.id);
          const angle = index * goldenAngle + (seed % 360) * (Math.PI / 180) * 0.08;
          const radius = spacing * Math.sqrt(index + 0.5);
          node.anchorX = clamp(centerX + Math.cos(angle) * radius, 24, width - 24);
          node.anchorY = clamp(centerY + Math.sin(angle) * radius, 24, height - 24);
          if (node.x === 0 && node.y === 0) {
            node.x = node.anchorX;
            node.y = node.anchorY;
          }
        });
      }

      function resizeCanvas() {
        const oldWidth = width;
        const oldHeight = height;
        const rect = canvas.getBoundingClientRect();
        width = Math.max(1, rect.width);
        height = Math.max(1, rect.height);
        pixelRatio = Math.max(1, window.devicePixelRatio || 1);
        canvas.width = Math.max(1, Math.round(width * pixelRatio));
        canvas.height = Math.max(1, Math.round(height * pixelRatio));
        context.setTransform(pixelRatio, 0, 0, pixelRatio, 0, 0);

        if (oldWidth > 1 && oldHeight > 1) {
          const scaleX = width / oldWidth;
          const scaleY = height / oldHeight;
          for (const node of nodes) {
            node.x *= scaleX;
            node.y *= scaleY;
          }
        }
        seedLayout();
        alpha = Math.max(alpha, 0.35);
      }

      function pointerPosition(event) {
        const bounds = canvas.getBoundingClientRect();
        return { x: event.clientX - bounds.left, y: event.clientY - bounds.top };
      }

      function nearest(position) {
        let selected = null;
        let distance = Infinity;
        for (const node of nodes) {
          const candidate = Math.hypot(node.x - position.x, node.y - position.y);
          if (candidate <= node.radius + 7 && candidate < distance) {
            selected = node;
            distance = candidate;
          }
        }
        return selected;
      }

      function addCollisionForces() {
        const cellSize = 32;
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
                const minimum = node.radius + other.radius + 8;

                if (distance === 0) {
                  const angle = (hashNumber(`${node.id}:${other.id}`) % 360) * Math.PI / 180;
                  dx = Math.cos(angle) * 0.01;
                  dy = Math.sin(angle) * 0.01;
                  distance = 0.01;
                }

                if (distance < minimum) {
                  const force = ((minimum - distance) / minimum) * 0.9 * alpha;
                  const fx = (dx / distance) * force;
                  const fy = (dy / distance) * force;
                  node.ax -= fx;
                  node.ay -= fy;
                  other.ax += fx;
                  other.ay += fy;
                }
              }
            }
          }
        }
      }

      function simulate() {
        const centerX = width / 2;
        const centerY = height / 2;
        const linkDistance = 120;
        const springStrength = 0.012;
        const anchorStrength = 0.0018;
        const centerStrength = 0.0006;
        const damping = 0.82;
        const maxSpeed = 7;

        for (const node of nodes) {
          node.ax = (node.anchorX - node.x) * anchorStrength * alpha;
          node.ay = (node.anchorY - node.y) * anchorStrength * alpha;
          node.ax += (centerX - node.x) * centerStrength * alpha;
          node.ay += (centerY - node.y) * centerStrength * alpha;
        }

        for (const link of links) {
          const dx = link.target.x - link.source.x;
          const dy = link.target.y - link.source.y;
          const distance = Math.max(0.001, Math.hypot(dx, dy));
          const stretch = distance - linkDistance;
          const force = stretch * springStrength * alpha;
          const fx = (dx / distance) * force;
          const fy = (dy / distance) * force;
          link.source.ax += fx;
          link.source.ay += fy;
          link.target.ax -= fx;
          link.target.ay -= fy;
        }

        addCollisionForces();

        for (const node of nodes) {
          if (node === dragged) continue;
          node.vx = clamp((node.vx + node.ax) * damping, -maxSpeed, maxSpeed);
          node.vy = clamp((node.vy + node.ay) * damping, -maxSpeed, maxSpeed);
          node.x = clamp(node.x + node.vx, node.radius + 3, width - node.radius - 3);
          node.y = clamp(node.y + node.vy, node.radius + 3, height - node.radius - 3);
        }

        alpha *= 0.986;
        if (alpha < 0.008) alpha = 0;
      }

      function draw() {
        context.clearRect(0, 0, width, height);
        context.strokeStyle = "rgba(146, 64, 110, 0.52)";
        context.lineWidth = 1;

        for (const link of links) {
          context.beginPath();
          context.moveTo(link.source.x, link.source.y);
          context.lineTo(link.target.x, link.target.y);
          context.stroke();
        }

        for (const node of nodes) {
          context.beginPath();
          context.fillStyle = node === hovered || node === dragged ? "#f3f4f5" : "#2de2e6";
          context.arc(node.x, node.y, node.radius, 0, Math.PI * 2);
          context.fill();
        }

        if (hovered) {
          context.font = "12px ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace";
          context.fillStyle = "#f3f4f5";
          context.textBaseline = "bottom";
          const labelX = clamp(hovered.x + hovered.radius + 7, 8, width - 220);
          const labelY = clamp(hovered.y - hovered.radius - 3, 18, height - 8);
          context.fillText(hovered.title, labelX, labelY, 210);
        }
      }

      function animate() {
        if (alpha > 0 || dragged) simulate();
        draw();
        requestAnimationFrame(animate);
      }

      canvas.addEventListener("pointerdown", (event) => {
        const position = pointerPosition(event);
        const selected = nearest(position);
        pointerDownAt = position;
        if (!selected) return;
        dragged = selected;
        dragOffset = { x: selected.x - position.x, y: selected.y - position.y };
        selected.vx = 0;
        selected.vy = 0;
        alpha = Math.max(alpha, 0.35);
        canvas.setPointerCapture(event.pointerId);
      });

      canvas.addEventListener("pointermove", (event) => {
        const position = pointerPosition(event);
        hovered = nearest(position);
        canvas.style.cursor = hovered ? "pointer" : "default";
        if (!dragged) return;
        dragged.x = clamp(position.x + dragOffset.x, dragged.radius + 3, width - dragged.radius - 3);
        dragged.y = clamp(position.y + dragOffset.y, dragged.radius + 3, height - dragged.radius - 3);
        dragged.anchorX = dragged.x;
        dragged.anchorY = dragged.y;
        dragged.vx = 0;
        dragged.vy = 0;
        alpha = Math.max(alpha, 0.25);
      });

      canvas.addEventListener("pointerleave", () => {
        if (!dragged) hovered = null;
      });

      canvas.addEventListener("pointerup", (event) => {
        const position = pointerPosition(event);
        const selected = dragged || nearest(position);
        const moved = pointerDownAt && Math.hypot(position.x - pointerDownAt.x, position.y - pointerDownAt.y) > 5;
        if (dragged && canvas.hasPointerCapture(event.pointerId)) {
          canvas.releasePointerCapture(event.pointerId);
        }
        dragged = null;
        pointerDownAt = null;
        alpha = Math.max(alpha, 0.18);
        if (selected && !moved) status.textContent = selected.title;
      });

      canvas.addEventListener("pointercancel", () => {
        dragged = null;
        pointerDownAt = null;
        alpha = Math.max(alpha, 0.18);
      });

      canvas.addEventListener("dblclick", (event) => {
        const selected = nearest(pointerPosition(event));
        if (selected) window.location.href = selected.url;
      });

      resizeCanvas();
      if (typeof ResizeObserver === "function") {
        new ResizeObserver(resizeCanvas).observe(canvas);
      } else {
        window.addEventListener("resize", resizeCanvas);
      }

      status.textContent = `${nodes.length} nodes · ${links.length} links · drag to arrange · double-click to open`;
      animate();
    } catch (error) {
      status.textContent = `Graph failed: ${error.message}`;
    }
  }

  startSearch();
  startGraph();
})();
