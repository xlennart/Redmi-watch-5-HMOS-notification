# HarmonyOS Frontend Design

Project-local Agent Skill for HarmonyOS-style UI design, browser prototyping, native ArkUI implementation, and review.

## Contents

- `SKILL.md` — trigger description, output routing, workflow, principles, and review checklist.
- `references/source-guide.md` — evidence hierarchy, official documentation links, and community-project provenance.
- `references/visual-components.md` — concrete visual baseline, component states, and window adaptation.
- `references/arkui-motion.md` — native implementation, async state, and motion decisions.
- `references/review.md` — evidence-based review and validation.
- `assets/design-tokens.json` — configurable light/dark project defaults.
- `scripts/export_tokens.py` — export tokens to CSS or isolated ArkUI color resource files.
- `examples/demo.html` — self-contained interactive browser prototype.
- `examples/arkui-starter.ets` — illustrative ArkUI starter that must be adapted to the target project's SDK and conventions.

## Use

Ask the coding agent to use the `harmonyos-frontend-design` skill for an applicable task. Select the output explicitly when useful: an HTML prototype, a native ArkUI page, a reference-based reconstruction, or a design review.

This folder is project-local. It does not install or register a global skill and does not modify agent configuration.

## Preview

Open `examples/demo.html` directly in a modern browser, keeping `examples/tokens.css` beside it. It demonstrates responsive layout, light/dark theme switching, filtering and empty results, a switch, segmented selection, a modal, and simulated save/success/failure/retry states. Its simulated requests never send data.

To refresh CSS after editing the token JSON, run `python scripts/export_tokens.py --target css --out examples/tokens.css` from this skill folder. To export native colors into a separate directory, use `--target arkui-colors --out <output-directory>`; inspect and merge resources rather than replacing existing project resources.
