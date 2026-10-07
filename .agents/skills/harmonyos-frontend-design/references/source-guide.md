# Source guide and provenance

This skill is an independent synthesis, not a copy or official endorsement of the projects or documentation below. Recheck live documentation for release-sensitive values and APIs.

## Source priority

1. User brief, supplied assets, and project-specific design system.
2. Official HarmonyOS Design and developer documentation for the target release.
3. Public community examples as implementation inspiration; verify claims before relying on them.
4. General recommendations in this skill.

If sources disagree, follow the higher-priority source and record assumptions that affect the deliverable. Do not copy official images, icon/font assets, or third-party code without checking their license and intended use.

## Official references

- [HarmonyOS Design portal](https://developer.huawei.com/consumer/cn/design/) — current design language, resources, and multi-device design material.
- [HarmonyOS Design concepts](https://developer.huawei.com/consumer/cn/design/concept/) — design concepts and visual resources.
- [HarmonyOS multi-device development best practices](https://developer.huawei.com/consumer/cn/best-practices/multidevice/) — responsive/adaptive layout and device scenarios.
- [HarmonyOS animation usage guide](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-animation-usage-guide) — ArkUI animation choices and performance. Confirm target API before using specific APIs.
- [HarmonyOS developer documentation](https://developer.huawei.com/consumer/cn/doc/) — select the target API version for ArkUI component and API details.

The official portal describes evolving design resources and device-specific guidance. Avoid freezing release-sensitive tokens or dimensions into this skill as universal truths. Spatial and translucent materials should follow the applicable guidance and serve the task.

## Community projects that informed the workflow

These are references for distinct methods, not authorities for official HarmonyOS behavior:

- [zhouqiaor/harmony-design-skill](https://github.com/zhouqiaor/harmony-design-skill) — design tokens, ArkUI snippets, and a broad single-page HTML component showcase.
- [aitool-plus/ui-design-aitool-plus](https://github.com/aitool-plus/ui-design-aitool-plus) — interactive HTML demos and a multi-platform design workflow, including a HarmonyOS example.
- [dososo/HarmonyOS-Design](https://github.com/dososo/HarmonyOS-Design) — ArkUI-oriented design/review rules, motion vocabulary, accessibility, device adaptation, and evaluation examples.

Repository statements about coverage, simulator runs, fidelity, and platform support are maintainer claims; verify them independently before treating them as guarantees.

## 综合范围与冲突处理（2026-10-07 核对）

综合范围为上面三个项目。原技能提供视觉令牌和组件覆盖，多平台技能提供交互原型及输出流程，HarmonyOS-Design 提供 ArkUI 映射、真实异步状态、动效连续性和证据评审。新包的规则、脚本和 Demo 独立编写，未复制第三方实现或品牌素材。

- 原技能将断点 600vp 的描述与 520vp 表项放在一起；本包不沿用这项冲突。示例 600/840 CSS px 仅为 Web 项目配置，原生断点查询目标 SDK。
- 原技能把 #20000000 描述为 20% 黑；ARGB 中 0x20/255 约为 12.5%。本包明确转换 Web RGBA 与 ArkUI ARGB，不混用两者。
- 两个视觉项目都采用蓝色，但这不意味着所有鸿蒙产品都必须用同一品牌色。本包采用可覆盖的语义操作色，并检查按钮文字对比度。
- 参考仓库中“100% 还原”“自动合规”等描述不作为本包承诺。以实际原型、构建和设备证据说明验证范围。

`assets/design-tokens.json` 的 authority 为 project-defaults。它不绑定未核验的平台发布版本；项目品牌或官方明确规格覆盖这些默认值。

## Numeric and API guidance

- Do not treat a community skill's sample token values or HTML dimensions as universal HarmonyOS specifications.
- Resolve ArkUI APIs, decorators, state behavior, breakpoints, component parameters, resource paths, and accessibility attributes against the target SDK and nearby project code.
- Keep design tokens semantic (for example, `surface-primary`, `text-secondary`, `action-primary`) so theme changes do not require rewriting component structure.
- If no source provides an exact value, propose one as a project choice and label it accordingly.
