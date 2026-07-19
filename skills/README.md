# Core Intelligence Operations

Skills are short operation contracts, not general documentation.

## Layout

```text
skills/<operation>/SKILL.md
skills/<operation>/run.el      # optional, bootstrapped later
skills/<operation>/fixtures/   # optional test material
```

## Rules

- Keep `SKILL.md` focused on one intelligence operation: input, output, steps, stop condition.
- Put global agent rules in `AGENTS.md`; do not repeat them in every skill.
- Do not create language, framework, Git, product, or generic reasoning skills.
- When an operation repeats and its contract is stable, create `run.el` beside the skill.
- A script must expose `star/skill-<operation>-run`, validate inputs, preserve provenance, be restart-safe, and report exact outputs.
- External tools may be called from Elisp, but orchestration remains visible in `run.el`.
- Add fixtures before claiming automation is reliable.

Use `star/research-open-skill`, `star/research-bootstrap-skill-script`, and `star/research-run-skill` from Emacs.
