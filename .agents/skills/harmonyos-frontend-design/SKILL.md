---
name: harmonyos-frontend-design
description: 设计或改进鸿蒙风格界面，制作可交互 HTML 原型、还原参考图，或实现与评审原生 ArkUI/ArkTS 页面。用于鸿蒙视觉令牌、组件状态、跨窗口布局、动效及无障碍任务；按需读取具体规范。纯构建、签名、网络或其他平台设计任务不适用。
---

# HarmonyOS Frontend Design

Create interfaces that feel coherent with HarmonyOS while keeping product identity, accessibility, truthful interaction states, and target-project SDK constraints intact. This is an independently written synthesis of public guidance, not an official Huawei specification.

## 按任务读取具体规范

- 新页面、视觉改造或参考图还原：读取 [视觉与组件规范](references/visual-components.md)。项目尚无令牌时，可采用 [默认设计令牌](assets/design-tokens.json)，所有数值均为可调整的项目建议。
- HTML 原型：参考 [可交互 Demo](examples/demo.html)，复用同一套令牌；交付可用的控件、状态和窄宽窗口布局。
- 原生 ArkUI、异步操作或手势动效：读取 [ArkUI 与动效映射](references/arkui-motion.md)，以目标 SDK、本地组件和 V1/V2 写法为准。
- 评审现有页面或验收产物：读取 [评审与验证](references/review.md)。引用证据，按实际影响给结论。
- 需要确认官方规格、数值或平台版本：查阅 [来源与冲突处理](references/source-guide.md)。只读取当前任务需要的参考文件。

令牌可导出为 CSS 或 ArkUI 配色资源，执行方式见视觉规范。不要将默认令牌覆盖到已有品牌或设计系统上。

## Choose the deliverable first

- **Explore a visual direction:** describe page hierarchy, visual direction, key components, and unresolved choices. Make an HTML prototype only when useful or requested.
- **Interactive prototype:** deliver browser HTML/CSS/JavaScript. Label it as a prototype; do not imply it is native ArkUI or API-verified.
- **Native HarmonyOS page:** deliver ArkUI/ArkTS in the project's existing language version and component/state conventions. Inspect nearby pages, shared components, resources, and SDK/API constraints first.
- **Reference reconstruction:** use supplied screenshots/design files for product-specific layout and content. Use HarmonyOS guidance for platform behavior. Mark unreadable or missing details rather than inventing exact values.
- **Design review:** report evidence-based findings and suggested changes. Do not rewrite code unless asked.

When target, device, framework, or fidelity is unclear, ask only for information that blocks useful work. Otherwise state a brief assumption and proceed.

## Source and decision order

1. User requirements and supplied reference material.
2. Existing project design system, components, accessibility requirements, and supported SDK/API.
3. Current official HarmonyOS design and developer documentation linked in [references/source-guide.md](references/source-guide.md).
4. This skill's recommendations.

Do not present a suggestion, community repository, or remembered numeric value as an official rule. Verify version-sensitive ArkUI APIs against the project's SDK documentation. If a rule cannot be verified, say so and keep implementation conservative.

## Design workflow

1. **Understand the page.** Identify user goal, content priority, primary action, loading/empty/error/success states, device/window size, orientation, input method, and accessibility needs. Reuse project patterns.
2. **Set the visual baseline.** Define semantic tokens for surface, text, action, status, spacing, typography, shape, elevation, and motion. Prefer existing project tokens. Use restrained color and depth; use spatial or translucent materials only when they clarify hierarchy or interaction.
3. **Plan the layout.** Use available window space, not device labels alone. Consider safe/avoid areas, large text, split windows, fold state, and keyboard when relevant. On larger windows, expose useful content or task structure rather than merely enlarging a phone column.
4. **Choose components.** Prefer native system controls in ArkUI. In web prototypes, use semantic HTML and accessible controls; do not claim native-control equivalence. Keep related pages consistent without making every product look identical.
5. **Specify interactions.** Define pressed, focused, selected, disabled, loading, empty, error, and confirmed states as needed. A success state follows confirmed success; animation must not report an unconfirmed result.
6. **Implement the chosen output.** Keep HTML and ArkUI deliverables distinct. In ArkUI, follow existing V1/V2 state, navigation, resource, and component patterns; do not migrate the project as part of a page task.
7. **Review relevant sizes and states.** Inspect the actual preview when available. Check hierarchy, clipping, scrolling, contrast, focus/keyboard, dark mode if supported, and narrow/expanded windows when multi-device behavior is in scope. Report what was and was not previewed or run.

## Visual and interaction principles

- Use clear hierarchy, comfortable reading density, and consistent alignment.
- Prefer semantic, reusable tokens over scattered magic numbers. Exact dimensions belong to a verified project or official reference, not guesswork.
- Use platform-native controls and familiar interaction patterns for native apps. Avoid web-only hover behavior in touch-only contexts.
- Motion should explain state, continuity, or spatial relationships. Keep it interruptible and proportional; honor reduced-motion preferences when available.
- Make controls focusable where supported, provide accessible names for icon-only actions, and preserve contrast and text scaling.
- Use realistic content and meaningful empty/loading/error states. Avoid ornamental glass, gradients, shadows, or animation that compete with the task.
- Preserve product identity. HarmonyOS alignment does not require every app to use the same blue, card layout, or material effect.

## Deliverable rules

- **HTML:** keep the prototype runnable and self-contained where practical. Implement working controls, not decorative imitations. State browser/device assumptions.
- **ArkUI:** match repository SDK/API and conventions; prefer existing components and resources. Without a project, mark API-sensitive snippets illustrative and name version assumptions.
- Keep explanations concise. Include design decisions, changed files, and validation evidence needed for review.
- Do not install this skill globally or change agent configuration unless explicitly asked.

## Self-review

- [ ] Output type matches the user's goal; HTML is not represented as native ArkUI.
- [ ] Project tokens, components, language/state model, and target SDK were considered.
- [ ] Layout responds to requested window/device conditions and respects safe areas.
- [ ] Key actions have meaningful states and report only real operation outcomes.
- [ ] Accessibility, text scaling, focus, and contrast were considered.
- [ ] Motion and decorative effects have a clear purpose.
- [ ] Preview/build claims match what was actually inspected or run.

See [references/source-guide.md](references/source-guide.md) for provenance and source hierarchy, [examples/demo.html](examples/demo.html) for an interactive browser prototype, and [examples/arkui-starter.ets](examples/arkui-starter.ets) for an illustrative native starter.
