(() => {
  "use strict";

  const byId = (id) => document.getElementById(id);

  function startResearchFilters() {
    const rows = [...document.querySelectorAll("#research-rows .research-row")];
    const search = byId("research-search");
    const searchField = byId("research-search-field");
    const project = byId("research-project-filter");
    const lifecycle = byId("research-lifecycle-filter");
    const approval = byId("research-approval-filter");
    const showLegacy = byId("show-legacy");
    const clear = byId("research-clear");
    const status = byId("research-filter-status");
    const count = byId("visible-research-count");
    const empty = byId("research-empty");
    if (!rows.length || !search || !searchField || !project || !lifecycle || !approval || !showLegacy) return;

    const render = () => {
      const query = search.value.trim().toLowerCase();
      const field = searchField.value;
      let visible = 0;

      for (const row of rows) {
        const legacyHidden = row.classList.contains("is-legacy") && !showLegacy.checked;
        const fieldValue = String(row.dataset[field] || "").toLowerCase();
        const matchesSearch = !query || fieldValue.includes(query);
        const matchesProject = !project.value || row.dataset.project === project.value;
        const matchesLifecycle = !lifecycle.value || row.dataset.lifecycle === lifecycle.value;
        const matchesApproval = !approval.value || row.dataset.approval === approval.value;
        const shouldShow = !legacyHidden && matchesSearch && matchesProject && matchesLifecycle && matchesApproval;
        row.hidden = !shouldShow;
        if (shouldShow) visible += 1;
      }

      count.textContent = String(visible);
      status.textContent = `${visible} review-ready item${visible === 1 ? "" : "s"} visible${showLegacy.checked ? " · legacy included" : " · canonical only"}`;
      empty.hidden = visible !== 0;
    };

    for (const control of [search, searchField, project, lifecycle, approval, showLegacy]) {
      control.addEventListener(control.type === "search" ? "input" : "change", render);
    }
    clear?.addEventListener("click", () => {
      search.value = "";
      searchField.value = "search";
      project.value = "";
      lifecycle.value = "";
      approval.value = "";
      showLegacy.checked = false;
      render();
      search.focus();
    });
    render();
  }

  const RESEARCH_APPROVAL_MARKER = "<!-- starintel-research-approval:v1 -->";
  const LEGACY_RESEARCH_REVIEW_HEADING = "## Human-gated ADARD review package";
  const SEARCH_QUERIES = [
    { query: 'user:lost-rob0t is:pr is:open "starintel-research-approval:v1" in:body', explicit: true },
    { query: 'org:starintel-labs is:pr is:open "starintel-research-approval:v1" in:body', explicit: true },
    { query: "user:lost-rob0t is:pr is:open head:research-approval", explicit: false },
    { query: "org:starintel-labs is:pr is:open head:research-approval", explicit: false },
    { query: "user:lost-rob0t is:pr is:open head:research/", explicit: false },
    { query: "org:starintel-labs is:pr is:open head:research/", explicit: false },
    { query: 'user:lost-rob0t is:pr is:open "Human-gated ADARD review package" in:body', explicit: false },
    { query: 'org:starintel-labs is:pr is:open "Human-gated ADARD review package" in:body', explicit: false },
  ];

  function branchName(item) {
    return String(item.head_ref || (item.head && item.head.ref) || "");
  }

  function hasResearchApprovalMarker(item) {
    return String(item.body || "").split(/\r?\n/).some((line) => line.trim() === RESEARCH_APPROVAL_MARKER);
  }

  function hasLegacyResearchReviewConvention(item) {
    const body = String(item.body || "");
    const branch = branchName(item);
    if (body.includes(LEGACY_RESEARCH_REVIEW_HEADING) && body.includes("Research and design only.")) {
      return true;
    }
    return branch.startsWith("research/") && /(?:^|[`\s])roam\/research\/[^`\s]+\.org(?:[`\s]|$)/.test(body);
  }

  function isResearchApprovalPr(item) {
    return hasResearchApprovalMarker(item)
      || branchName(item).startsWith("research-approval/")
      || hasLegacyResearchReviewConvention(item);
  }

  if (typeof globalThis !== "undefined") {
    globalThis.starintelResearchApproval = { RESEARCH_APPROVAL_MARKER, isResearchApprovalPr };
  }

  function repositoryFromUrl(value) {
    const match = String(value || "").match(/\/repos\/([^/]+\/[^/]+)$/);
    return match ? match[1] : "unknown/repository";
  }

  async function searchPullRequests() {
    const responses = await Promise.all(SEARCH_QUERIES.map(async ({ query }) => {
      const url = new URL("https://api.github.com/search/issues");
      url.searchParams.set("q", query);
      url.searchParams.set("sort", "updated");
      url.searchParams.set("order", "desc");
      url.searchParams.set("per_page", "50");
      const response = await fetch(url, {
        cache: "no-store",
        headers: { Accept: "application/vnd.github+json" },
      });
      if (!response.ok) {
        const remaining = response.headers.get("x-ratelimit-remaining");
        throw new Error(`${response.status} ${response.statusText}${remaining === "0" ? " · public GitHub rate limit reached" : ""}`);
      }
      return response.json();
    }));

    const candidates = new Map();
    responses.forEach((response, index) => {
      for (const item of response.items || []) {
        const candidate = {
          ...item,
          repository: repositoryFromUrl(item.repository_url),
          explicit: SEARCH_QUERIES[index].explicit,
        };
        const previous = candidates.get(item.html_url);
        candidates.set(item.html_url, previous ? { ...previous, ...candidate, explicit: previous.explicit || candidate.explicit } : candidate);
      }
    });

    const records = [];
    for (const candidate of candidates.values()) {
      if (isResearchApprovalPr(candidate) && (hasResearchApprovalMarker(candidate) || hasLegacyResearchReviewConvention(candidate))) {
        records.push(candidate);
        continue;
      }
      if (!candidate.explicit && candidate.pull_request && candidate.pull_request.url) {
        const response = await fetch(candidate.pull_request.url, {
          cache: "no-store",
          headers: { Accept: "application/vnd.github+json" },
        });
        if (response.ok) {
          const detail = await response.json();
          const enriched = { ...candidate, ...detail, repository: candidate.repository };
          if (isResearchApprovalPr(enriched)) records.push(enriched);
        }
      }
    }
    return records.sort((left, right) => String(right.updated_at).localeCompare(String(left.updated_at)));
  }

  function appendPr(container, item) {
    const article = document.createElement("article");
    article.className = "pr-row";

    const main = document.createElement("div");
    main.className = "pr-main";
    const title = document.createElement("h3");
    const link = document.createElement("a");
    link.href = item.html_url;
    link.textContent = item.title;
    title.append(link);

    const meta = document.createElement("p");
    meta.className = "pr-meta";
    const updated = item.updated_at ? new Date(item.updated_at).toLocaleString() : "unknown update time";
    meta.textContent = `${item.repository} #${item.number} · updated ${updated}`;

    const labels = document.createElement("div");
    labels.className = "pr-labels";
    for (const label of (item.labels || []).slice(0, 8)) {
      const badge = document.createElement("span");
      badge.textContent = typeof label === "string" ? label : label.name;
      labels.append(badge);
    }

    main.append(title, meta, labels);

    const actions = document.createElement("div");
    actions.className = "pr-actions";
    const files = document.createElement("a");
    files.href = `${item.html_url}/files`;
    files.textContent = "Review files";
    const open = document.createElement("a");
    open.href = item.html_url;
    open.textContent = "Merge / close ↗";
    actions.append(files, open);

    article.append(main, actions);
    container.append(article);
  }

  function appendFallbackLink(container, href, label) {
    const link = document.createElement("a");
    link.href = href;
    link.textContent = label;
    container.append(link);
  }

  function startPullRequests() {
    const container = byId("pr-list");
    const status = byId("pr-status");
    const search = byId("pr-search");
    const repoFilter = byId("pr-repository-filter");
    const refresh = byId("pr-refresh");
    if (!container || !status || !search || !repoFilter) return;

    let records = [];

    const render = () => {
      const query = search.value.trim().toLowerCase();
      const repo = repoFilter.value;
      const matches = records.filter((record) => {
        const haystack = [
          record.repository,
          record.title,
          record.body || "",
          ...(record.labels || []).map((label) => typeof label === "string" ? label : label.name),
        ].join(" ").toLowerCase();
        return (!query || haystack.includes(query)) && (!repo || record.repository === repo);
      });

      container.replaceChildren();
      for (const item of matches) appendPr(container, item);
      status.textContent = `${matches.length} open research-approval PR${matches.length === 1 ? "" : "s"} shown · live public GitHub data`;
      if (!matches.length && records.length) {
        const empty = document.createElement("p");
        empty.className = "review-empty";
        empty.textContent = "No pull requests match the current filters.";
        container.append(empty);
      }
    };

    const load = async () => {
      refresh && (refresh.disabled = true);
      status.textContent = "Loading public GitHub research PRs…";
      try {
        records = await searchPullRequests();
        const repositories = [...new Set(records.map((record) => record.repository))].sort();
        const previous = repoFilter.value;
        repoFilter.replaceChildren(new Option("All repositories", ""));
        for (const repository of repositories) repoFilter.add(new Option(repository, repository));
        if (repositories.includes(previous)) repoFilter.value = previous;
        render();
      } catch (error) {
        container.replaceChildren();
        container.classList.add("pr-fallback-links");
        status.textContent = `Could not load live PRs: ${error.message}`;
        appendFallbackLink(
          container,
          "https://github.com/pulls?q=is%3Aopen+is%3Apr+user%3Alost-rob0t+%22starintel-research-approval%3Av1%22+in%3Abody",
          "Search marked lost-rob0t approval PRs ↗"
        );
        appendFallbackLink(
          container,
          "https://github.com/pulls?q=is%3Aopen+is%3Apr+org%3Astarintel-labs+head%3Aresearch-approval",
          "Search legacy research-approval branches ↗"
        );
      } finally {
        refresh && (refresh.disabled = false);
      }
    };

    search.addEventListener("input", render);
    repoFilter.addEventListener("change", render);
    refresh?.addEventListener("click", load);
    load();
  }

  function start() {
    startResearchFilters();
    startPullRequests();
  }

  if (typeof document === "undefined") return;
  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", start, { once: true });
  } else {
    start();
  }
})();
