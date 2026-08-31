# Agent Zero Support — worker profiles retired

The autonomous StarIntel product-worker chain in this repository is **retired**.

Worker ownership moved to `lost-rob0t/hackmode` under Hackmode issue #30. The live Auto-RAGE development profiles are:

- `hackmode-rage-database` — Hackmode database, execution graph and KB persistence.
- `hackmode-rage-hackpert` — Hackpert expert/orchestration, active/passive engine, plans/playbooks and LISH integration.

The old profile directories remain only as fail-closed migration tombstones so existing Agent Zero installations get an explicit stop/migration instruction instead of silently continuing StarIntel product work.

## StarIntel boundary

Migrated Hackmode workers must not use StarIntel repositories as a product backlog. They may touch StarIntel only for an explicitly authorized cyber / BBP purpose such as source-assisted security review, attack-surface/recon analysis, authorized security testing, security integration validation, or security finding/evidence projection.

If cyber work discovers a StarIntel product defect, record/handoff the security finding. Do not implement the StarIntel product fix from the Hackmode RAGE worker.

The research/design corpus and skills in this repository remain historical/useful artifacts; retiring the autonomous worker profiles does not invalidate prior approved research/design records.
