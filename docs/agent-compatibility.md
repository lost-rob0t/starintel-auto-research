# Agent Compatibility

The pack uses one canonical instruction source and thin adapters.

| Agent system | Adapter |
|---|---|
| OpenAI Codex | `AGENTS.md`, `CODEX.md`, `.codex/config.toml` |
| Claude Code | `CLAUDE.md` importing `AGENTS.md` |
| Agent Zero | `agent-zero/`, `.a0proj/`, installer script |
| GitHub Copilot | `.github/copilot-instructions.md` |
| Cursor | `.cursor/rules/starintel.mdc` |
| Windsurf | `.windsurfrules` |
| Cline | `.clinerules` |
| Roo | `.roo/rules/starintel.md` |
| Continue | `.continue/rules/starintel.md` |
| Aider | `.aider.conf.yml` |
| Gemini and generic agents | `GEMINI.md`, `.agent/rules/starintel.md` |
| Skill-aware systems | `skills/*/SKILL.md` |

Update `AGENTS.md` first. Keep adapters brief to prevent instruction drift.
