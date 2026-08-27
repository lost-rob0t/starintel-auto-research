#!/usr/bin/env python3
"""Generate the static /research-pending review dashboard."""

from __future__ import annotations

import argparse
import html
from pathlib import Path

from research_queue import REPOSITORY, load_items, relative_website_url, repository_root, source_url


def _escape(value: str) -> str:
    return html.escape(value, quote=True)


def _options(values: list[str], label: str) -> str:
    unique = sorted({value for value in values if value})
    return f'<option value="">All {label}</option>' + "".join(
        f'<option value="{_escape(value)}">{_escape(value)}</option>' for value in unique
    )


def _row(root: Path, item) -> str:
    classes = "research-row is-legacy" if item.legacy else "research-row"
    hidden = " hidden" if item.legacy else ""
    search_blob = " ".join(
        [
            REPOSITORY,
            item.project,
            item.status,
            item.approval_state,
            item.title,
            item.relative_path.as_posix(),
        ]
    ).lower()
    kind = "Legacy" if item.legacy else "Canonical"
    return (
        f'<tr class="{classes}"{hidden}'
        f' data-repository="{_escape(REPOSITORY)}"'
        f' data-project="{_escape(item.project)}"'
        f' data-lifecycle="{_escape(item.status)}"'
        f' data-approval="{_escape(item.approval_state)}"'
        f' data-title="{_escape(item.title.lower())}"'
        f' data-path="{_escape(item.relative_path.as_posix().lower())}"'
        f' data-search="{_escape(search_blob)}">'
        '<td class="research-title-cell">'
        f'<a href="{_escape(relative_website_url(root, item.path))}">{_escape(item.title)}</a>'
        f'<span class="research-path">{_escape(item.relative_path.as_posix())}</span>'
        '</td>'
        f'<td>{_escape(item.project)}</td>'
        f'<td><span class="state-pill">{_escape(item.status)}</span></td>'
        f'<td><span class="approval-pill{(" legacy" if item.legacy else "")}">{_escape(item.approval_state)}</span></td>'
        f'<td>{_escape(kind)}</td>'
        '<td class="research-actions">'
        f'<a href="{_escape(source_url(root, item.path))}">Source ↗</a>'
        '</td>'
        '</tr>'
    )


def render_dashboard(root: Path) -> str:
    items = load_items(root)
    canonical = [item for item in items if not item.legacy]
    legacy = [item for item in items if item.legacy]
    rows = "".join(_row(root, item) for item in sorted(items, key=lambda value: (value.legacy, value.project, value.title.lower())))

    project_options = _options([item.project for item in items], "projects")
    lifecycle_options = _options([item.status for item in items], "lifecycles")
    approval_options = _options([item.approval_state for item in items], "approval states")

    return f'''<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>Research review — StarIntel Research</title>
  <link rel="stylesheet" href="../assets/site.css">
  <script defer src="../assets/site.js"></script>
  <script defer src="../assets/research-pending.js"></script>
</head>
<body>
<header class="site-header">
  <a class="site-title" href="../index.html">StarIntel Research</a>
  <nav>
    <a href="../index.html">Index</a>
    <a href="../search.html">Search</a>
    <a href="../graph.html">Graph</a>
    <a href="./" aria-current="page">Review</a>
  </nav>
</header>
<main class="site-main research-review-main">
  <section class="review-hero">
    <p class="eyebrow">Human approval queue</p>
    <div class="review-hero-grid">
      <div>
        <h1>Research pending</h1>
        <p>Review-ready research from the durable Org corpus, plus live public research PRs across lost-rob0t repositories. Approval state and lifecycle remain separate.</p>
      </div>
      <div class="review-metrics" aria-label="Research queue summary">
        <div><strong>{len(canonical)}</strong><span>canonical pending</span></div>
        <div><strong>{len(legacy)}</strong><span>legacy review-ready</span></div>
        <div><strong id="visible-research-count">{len(canonical)}</strong><span>visible now</span></div>
      </div>
    </div>
  </section>

  <section class="review-section" aria-labelledby="queue-heading">
    <div class="section-heading-row">
      <div>
        <p class="eyebrow">Repository queue</p>
        <h2 id="queue-heading">Pending decisions</h2>
      </div>
      <label class="legacy-toggle"><input id="show-legacy" type="checkbox"> Show unmigrated legacy research</label>
    </div>

    <div class="review-controls" role="search" aria-label="Filter pending research">
      <label>Search field
        <select id="research-search-field">
          <option value="search">All fields</option>
          <option value="repository">Repository</option>
          <option value="project">Project</option>
          <option value="lifecycle">Lifecycle</option>
          <option value="approval">Approval</option>
          <option value="title">Title</option>
          <option value="path">Path</option>
        </select>
      </label>
      <label>Search
        <input id="research-search" type="search" autocomplete="off" placeholder="filter queue…">
      </label>
      <label>Project
        <select id="research-project-filter">{project_options}</select>
      </label>
      <label>Lifecycle
        <select id="research-lifecycle-filter">{lifecycle_options}</select>
      </label>
      <label>Approval
        <select id="research-approval-filter">{approval_options}</select>
      </label>
      <button id="research-clear" type="button">Clear</button>
    </div>

    <p id="research-filter-status" class="review-status" aria-live="polite">{len(canonical)} canonical pending item(s)</p>
    <div class="review-table-wrap">
      <table class="review-table">
        <thead><tr><th>Research</th><th>Project</th><th>Lifecycle</th><th>Approval</th><th>Mode</th><th>Review</th></tr></thead>
        <tbody id="research-rows">{rows}</tbody>
      </table>
    </div>
    <p id="research-empty" class="review-empty" hidden>No research matches the current filters.</p>
  </section>

  <section class="review-section" aria-labelledby="pr-heading">
    <div class="section-heading-row">
      <div>
        <p class="eyebrow">Live GitHub view</p>
        <h2 id="pr-heading">Open research PRs</h2>
      </div>
      <span class="public-api-note">Public API only · no browser token</span>
    </div>
    <div class="review-controls pr-controls">
      <label>Search PRs
        <input id="pr-search" type="search" autocomplete="off" placeholder="repo, title, label…">
      </label>
      <label>Repository
        <select id="pr-repository-filter"><option value="">All repositories</option></select>
      </label>
      <button id="pr-refresh" type="button">Refresh</button>
    </div>
    <p id="pr-status" class="review-status" aria-live="polite">Loading public GitHub research PRs…</p>
    <div id="pr-list" class="pr-list"></div>
    <p class="review-footnote">This static site never receives a GitHub credential. Review, merge, and close actions intentionally open GitHub's authenticated UI.</p>
  </section>
</main>
</body>
</html>
'''


def write_dashboard(site: Path, root: Path) -> Path:
    output = site / "research-pending" / "index.html"
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(render_dashboard(root), encoding="utf-8")
    return output


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("site", type=Path, help="generated site directory")
    args = parser.parse_args()
    root = repository_root(Path(__file__))
    output = write_dashboard(args.site, root)
    print(f"research_pending=PASS output={output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
