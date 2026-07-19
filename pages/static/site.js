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

  async function startGraph() {
    const canvas = byId("graph-canvas");
    const status = byId("graph-status");
    if (!canvas || !status) return;

    try {
      const graph = await loadJson("graph.json");
      const context = canvas.getContext("2d");
      const pixelRatio = window.devicePixelRatio || 1;
      const rect = canvas.getBoundingClientRect();
      canvas.width = Math.max(1, Math.floor(rect.width * pixelRatio));
      canvas.height = Math.max(1, Math.floor(rect.height * pixelRatio));
      context.scale(pixelRatio, pixelRatio);

      const width = rect.width;
      const height = rect.height;
      const nodes = graph.nodes.map((node) => {
        const seed = hashNumber(node.id);
        return {
          ...node,
          x: 40 + (seed % Math.max(80, width - 80)),
          y: 40 + ((seed >>> 8) % Math.max(80, height - 80)),
          vx: 0,
          vy: 0,
          radius: 7,
        };
      });
      const nodeById = new Map(nodes.map((node) => [node.id, node]));
      const links = graph.links
        .map((link) => ({ source: nodeById.get(link.source), target: nodeById.get(link.target) }))
        .filter((link) => link.source && link.target);

      let dragged = null;
      let pointer = { x: 0, y: 0 };
      let frame = 0;

      function pointerPosition(event) {
        const bounds = canvas.getBoundingClientRect();
        return { x: event.clientX - bounds.left, y: event.clientY - bounds.top };
      }

      function nearest(position) {
        let selected = null;
        let distance = Infinity;
        for (const node of nodes) {
          const dx = node.x - position.x;
          const dy = node.y - position.y;
          const candidate = Math.hypot(dx, dy);
          if (candidate < Math.max(14, node.radius + 5) && candidate < distance) {
            selected = node;
            distance = candidate;
          }
        }
        return selected;
      }

      canvas.addEventListener("pointerdown", (event) => {
        pointer = pointerPosition(event);
        dragged = nearest(pointer);
        if (dragged) canvas.setPointerCapture(event.pointerId);
      });

      canvas.addEventListener("pointermove", (event) => {
        pointer = pointerPosition(event);
        if (dragged) {
          dragged.x = pointer.x;
          dragged.y = pointer.y;
          dragged.vx = 0;
          dragged.vy = 0;
        }
      });

      canvas.addEventListener("pointerup", (event) => {
        const selected = dragged || nearest(pointerPosition(event));
        if (dragged) canvas.releasePointerCapture(event.pointerId);
        dragged = null;
        if (selected && Math.hypot(selected.x - pointer.x, selected.y - pointer.y) < 16) {
          status.textContent = selected.title;
        }
      });

      canvas.addEventListener("dblclick", (event) => {
        const selected = nearest(pointerPosition(event));
        if (selected) window.location.href = selected.url;
      });

      function simulate() {
        for (const link of links) {
          const dx = link.target.x - link.source.x;
          const dy = link.target.y - link.source.y;
          const distance = Math.max(1, Math.hypot(dx, dy));
          const force = (distance - 110) * 0.0008;
          const fx = dx * force;
          const fy = dy * force;
          link.source.vx += fx;
          link.source.vy += fy;
          link.target.vx -= fx;
          link.target.vy -= fy;
        }

        for (let left = 0; left < nodes.length; left += 1) {
          const a = nodes[left];
          for (let right = left + 1; right < nodes.length; right += 1) {
            const b = nodes[right];
            const dx = b.x - a.x;
            const dy = b.y - a.y;
            const distanceSquared = Math.max(80, dx * dx + dy * dy);
            const force = 45 / distanceSquared;
            a.vx -= dx * force;
            a.vy -= dy * force;
            b.vx += dx * force;
            b.vy += dy * force;
          }
        }

        for (const node of nodes) {
          if (node !== dragged) {
            node.vx += (width / 2 - node.x) * 0.0002;
            node.vy += (height / 2 - node.y) * 0.0002;
            node.vx *= 0.88;
            node.vy *= 0.88;
            node.x = Math.min(width - 16, Math.max(16, node.x + node.vx));
            node.y = Math.min(height - 16, Math.max(16, node.y + node.vy));
          }
        }
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
          const colors = {
            design: "#2de2e6",
            research: "#62ff00",
            implement: "#fba922",
            indexes: "#f6019d",
          };
          context.fillStyle = colors[node.kind] || "#9700cc";
          context.shadowColor = context.fillStyle;
          context.shadowBlur = 8;
          context.arc(node.x, node.y, node.radius, 0, Math.PI * 2);
          context.fill();
          context.shadowBlur = 0;
        }

        frame += 1;
        if (frame < 800 || dragged) simulate();
        requestAnimationFrame(draw);
      }

      status.textContent = `${nodes.length} nodes · ${links.length} links · double-click a node to open it`;
      draw();
    } catch (error) {
      status.textContent = `Graph failed: ${error.message}`;
    }
  }

  startSearch();
  startGraph();
})();
