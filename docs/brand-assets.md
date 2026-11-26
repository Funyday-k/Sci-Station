# Brand assets

These local assets identify their corresponding products. No remote requests are needed when the UI renders. Marks remain the property of their respective owners; inclusion does not imply endorsement.

## Roundtable

The workbench, reading room and API page use the same pale Möbius ribbon. The original generated artwork is in `packaging/macos/roundtable-mark-source.png`. The web mark is stored in `static/roundtable-mark.png` and the macOS icon in `packaging/macos/roundtable.icns`.

## Codex

`static/codex-avatar.svg` is a **byte-for-byte copy** of the product-specific Codex asset distributed with the pinned Magpie source, not the generic OpenAI or ChatGPT knot.

- Source: [Magpie `codex-color.svg`, commit `4716a77ff9f8e6bd7ff64780f81674de0fee805e`](https://github.com/yetone/magpie/blob/4716a77ff9f8e6bd7ff64780f81674de0fee805e/internal/gui/assets/icons/codex-color.svg).
- Product identity: [OpenAI Codex](https://openai.com/codex/).
- Preserved: all original paths, gradient, 24 × 24 viewBox, original white background and proportions.
- SHA-256: `4a2f43ce46b5b6e3722c95088f88d26ef91e6a8c2e598e70642a1c54367386e4`.

This file's immediate provenance is Magpie's bundled asset. It is not represented as a direct download from OpenAI's brand distribution.

## Cursor

`static/cursor-avatar.svg` uses the **unaltered path** from `General Logos/Cube/SVG/CUBE_2D_LIGHT.svg` in Cursor's official brand archive. A square white SVG shell centers the original 466.73 × 532.09 artwork at the same aspect ratio; it is not a hand-drawn arrow or substitute mark.

- Official page: [Cursor brand guidelines](https://cursor.com/brand).
- Official page's download link: [Cursor brand assets ZIP](https://ptht05hbb1ssoooe.public.blob.vercel-storage.com/assets/brand/cursor-brand-assets.zip).
- The official page specifies 2D as the default logo and allows the cube separately.
- Retrieved: 2026-11-23.
- Source archive SHA-256: `97488a7751914e60f9ff532bc33810cdeaebdddc017548abe6ca2bc29bbc3928`.
- Local SVG SHA-256: `d929a0a2f34797e8eb5ebb8f24004bf5daa454638d436d4ba8ef8556b5f5eb36`.

## Magpie

`static/magpie-avatar.svg` preserves the complete original bird path from [Magpie `favicon.svg`, commit `4716a77ff9f8e6bd7ff64780f81674de0fee805e`](https://github.com/yetone/magpie/blob/4716a77ff9f8e6bd7ff64780f81674de0fee805e/internal/gui/assets/icons/favicon.svg).

- Adaptation: retain the original 44 × 44 viewBox, add a white background, and fix the original light-mode path color to `#1c1c1e` for legibility in both themes. The outline is unchanged.
- Local SHA-256: `689ed9b8401d489f4940603d152c3a84e209065ccd26720baebe895eaab5f7fd`.

## Identity policy

The reading UI selects Codex and Cursor avatars from the model catalog's exact `source` field. Historical records without a live catalog entry use the explicit source prefix in their saved full model ID. It never infers a vendor from an ambiguous model-name substring. Other sources retain their actual advertised name and a neutral avatar. The human author uses a generic person icon and the label “你”.

## Local CLI inventory — twelve product identities

The inventory maps the exact `/api/studio/clients` identifier to a local asset. It does not infer a brand from a binary path or a model-name substring. All twelve currently supported clients have their own corresponding mark. The client badges load **only same-origin `/static/*.svg` files**; it never contacts a vendor site for an image, font, style or script. No initials, generic AI marks or another product’s logo are substituted. The existing Codex and Cursor assets above are reused unchanged.

The immediate provenance of the four Magpie-distributed marks is the pinned Magpie source, not a claim that the files were downloaded directly from those vendors. The official product references confirm which CLI each identity belongs to. Pi specifically refers to the coding harness at `pi.dev` / `earendil-works/pi`; Kimi uses the dedicated Kimi Code product logo. Source and local SHA-256 values below pin the retrieved artwork even when a first-party website URL is mutable.

Retrieved and checked: **2026-11-23**.

| Client ID | Product | Local inventory asset | Immediate authoritative source | Product identity / source context |
| --- | --- | --- | --- | --- |
| `codex` | Codex | `static/codex-avatar.svg` | Pinned Magpie product asset, documented above | OpenAI Codex |
| `cursor` | Cursor Agent | `static/cursor-avatar.svg` | Official Cursor brand archive, documented above | Cursor CLI |
| `claude` | Claude Code | `static/cli-claude.svg` | [Source asset](https://github.com/yetone/magpie/blob/4716a77ff9f8e6bd7ff64780f81674de0fee805e/internal/gui/assets/icons/claudecode-color.svg) | [Official context](https://code.claude.com/docs/en/setup) |
| `gemini` | Gemini CLI | `static/cli-gemini.svg` | [Source asset](https://github.com/yetone/magpie/blob/4716a77ff9f8e6bd7ff64780f81674de0fee805e/internal/gui/assets/icons/geminicli-color.svg) | [Official context](https://geminicli.com/docs/get-started/installation/) |
| `copilot` | GitHub Copilot CLI | `static/cli-copilot.svg` | [Source asset](https://github.com/yetone/magpie/blob/4716a77ff9f8e6bd7ff64780f81674de0fee805e/internal/gui/assets/icons/githubcopilot.svg) | [Official context](https://docs.github.com/en/copilot/how-tos/copilot-cli/set-up-copilot-cli/install-copilot-cli) |
| `opencode` | OpenCode | `static/cli-opencode.svg` | [Source asset](https://github.com/yetone/magpie/blob/4716a77ff9f8e6bd7ff64780f81674de0fee805e/internal/gui/assets/icons/opencode.svg) | [Official context](https://opencode.ai/docs/) |
| `pi` | Pi | `static/cli-pi.svg` | [Source asset](https://pi.dev/favicon.svg) | [Official context](https://pi.dev/) |
| `amp` | Amp | `static/cli-amp.svg` | [Source asset](https://ampcode.com/app-icon.svg) | [Official context](https://ampcode.com/press-kit) |
| `droid` | Droid | `static/cli-droid.svg` | [Source asset](https://docs.factory.com/favicon.svg) | [Official context](https://docs.factory.com/droid-cli/quickstart) |
| `aider` | Aider | `static/cli-aider.svg` | [Source asset](https://raw.githubusercontent.com/Aider-AI/aider/5dc9490bb35f9729ef2c95d00a19ccd30c26339c/aider/website/assets/icons/safari-pinned-tab.svg) | [Official context](https://aider.chat/) |
| `kimi` | Kimi CLI / Kimi Code CLI | `static/cli-kimi.svg` | [Source asset](https://raw.githubusercontent.com/MoonshotAI/kimi-code/3a43c683de31440e496b9b926a03db93c2baa16f/KIMI%20CODE%20LOGO/Original%20Logo.svg) | [Official context](https://github.com/MoonshotAI/kimi-code/tree/3a43c683de31440e496b9b926a03db93c2baa16f/KIMI%20CODE%20LOGO) |
| `qwen` | Qwen Code | `static/cli-qwen.svg` | [Source asset](https://raw.githubusercontent.com/QwenLM/qwen-code/146e6a5f319266af3f2c0524473f2164581ac249/packages/desktop/bootstrap/qwen-code-logo.svg) | [Official context](https://github.com/QwenLM/qwen-code/blob/146e6a5f319266af3f2c0524473f2164581ac249/packages/desktop/bootstrap/qwen-code-logo.svg) |

### Inventory asset integrity and adaptations

- **Claude Code** (`static/cli-claude.svg`): Byte-for-byte copy of the product asset bundled by the pinned Magpie release. Monochrome SVG currentColor resolves to black on the inventory’s fixed white icon tile; no logo geometry or color has been rewritten.
  - Retrieved-source SHA-256: `670b3d8d749d0815ad8f7e62a59d51cb5e2053cb19403f3541a8aed7036a877f`.
  - Local SHA-256: `670b3d8d749d0815ad8f7e62a59d51cb5e2053cb19403f3541a8aed7036a877f`.
- **Gemini CLI** (`static/cli-gemini.svg`): Byte-for-byte copy of the product asset bundled by the pinned Magpie release. Monochrome SVG currentColor resolves to black on the inventory’s fixed white icon tile; no logo geometry or color has been rewritten.
  - Retrieved-source SHA-256: `c2f54ebaa4c3b9191c6a07f7b0c66bc78e4abe486003dc564469cf650672663e`.
  - Local SHA-256: `c2f54ebaa4c3b9191c6a07f7b0c66bc78e4abe486003dc564469cf650672663e`.
- **GitHub Copilot CLI** (`static/cli-copilot.svg`): Byte-for-byte copy of the product asset bundled by the pinned Magpie release. Monochrome SVG currentColor resolves to black on the inventory’s fixed white icon tile; no logo geometry or color has been rewritten.
  - Retrieved-source SHA-256: `bbc7fddc13448236e5edea8c399d2072dc40aa5da5bca07f7a2f412405c500a3`.
  - Local SHA-256: `bbc7fddc13448236e5edea8c399d2072dc40aa5da5bca07f7a2f412405c500a3`.
- **OpenCode** (`static/cli-opencode.svg`): Byte-for-byte copy of the product asset bundled by the pinned Magpie release. Monochrome SVG currentColor resolves to black on the inventory’s fixed white icon tile; no logo geometry or color has been rewritten.
  - Retrieved-source SHA-256: `7cfa6e9d6726f7c9fa26c7d9aef0dfec52d20a137380454340f30f12ccbfd302`.
  - Local SHA-256: `7cfa6e9d6726f7c9fa26c7d9aef0dfec52d20a137380454340f30f12ccbfd302`.
- **Pi** (`static/cli-pi.svg`): Fix the official favicon’s .mark fill to #111111 and remove its embedded system-theme media rule, so the unmodified path remains visible on a white icon tile in either application theme.
  - Retrieved-source SHA-256: `d266b2c1d2c7bf169ca30d438963b176fba16fea6263b9ac30c8302f34ad7ce7`.
  - Local SHA-256: `601e309ec5fe86c4987ca64888857fcbb1832264f65f894b719cfdca64b63f75`.
- **Amp** (`static/cli-amp.svg`): Unmodified official app icon linked by the first-party press kit.
  - Retrieved-source SHA-256: `40c79d8c7baa04c2fee214cc1c66a9797eb6aa96bec6c5b20c7d12cd66490696`.
  - Local SHA-256: `40c79d8c7baa04c2fee214cc1c66a9797eb6aa96bec6c5b20c7d12cd66490696`.
- **Droid** (`static/cli-droid.svg`): Unmodified icon served by Factory’s official Droid CLI documentation. This is the documentation’s own Factory/Droid identity, not a separately invented Droid mark.
  - Retrieved-source SHA-256: `416ea4962d7b0b8be8bec7f7190c13c22d5f20fdcac401aa72886fd5c81d2fb2`.
  - Local SHA-256: `416ea4962d7b0b8be8bec7f7190c13c22d5f20fdcac401aa72886fd5c81d2fb2`.
- **Aider** (`static/cli-aider.svg`): Remove only the XML declaration and external SVG DTD declaration; preserve the official pinned-tab silhouette, transforms, viewBox and black fill.
  - Retrieved-source SHA-256: `145269573c298162e3e032de7563d39e6db234d29fbb7a7312f251e28cc374a6`.
  - Local SHA-256: `42faec8b304665c8d261ddb2013a010bf6e879fefb7e89c8b83d6b369e11d69c`.
- **Kimi CLI / Kimi Code CLI** (`static/cli-kimi.svg`): Unmodified official Kimi Code product logo, including its blue gradient, robot face and original 86 × 76 proportions. It is not the generic Kimi chat K or Moonshot logo.
  - Retrieved-source SHA-256: `065fcf81c1920fe9c20edc847392d6b6bb419804975e97076d0e3524fe72930c`.
  - Local SHA-256: `065fcf81c1920fe9c20edc847392d6b6bb419804975e97076d0e3524fe72930c`.
- **Qwen Code** (`static/cli-qwen.svg`): Unmodified product logo from Qwen Code’s official desktop bootstrap, preserving its #082DFF paths and original square viewBox; not a third-party recreation of a Qwen model mark.
  - Retrieved-source SHA-256: `24156c849c9124505e13b38c6583a9d5d85a1f57d996c324d967f480a4d88696`.
  - Local SHA-256: `24156c849c9124505e13b38c6583a9d5d85a1f57d996c324d967f480a4d88696`.

### Rendering and verification

- Every mark uses a fixed-size, white icon tile in both application themes. This preserves monochrome contrast without inverting brand colors. SVG proportions are preserved with `object-fit: contain`; no logo is cropped, traced or redrawn.
- The name and installation status remain text next to the mark; the image is decorative for assistive technology so the same product name is not spoken twice. Long names truncate rather than overlap the status or disclosure affordance. Expanding a row keeps the icon/name/status aligned and exposes the existing command, path and installation link.
- The established installed-first ordering is retained, and expanded rows remain expanded when the local inventory is refreshed. This inventory does not add clients to the roundtable’s participant seats.
- All ten newly bundled files are SVG, require the existing `image/svg+xml` response type, contain no scripts/foreignObject, and reference no external resource. The application mark and favicon use the separate PNG response type.
- Asset integrity checks compare the pinned copies and recorded hashes. UI validation should cover all twelve rows, both themes, a narrow viewport, installed-first sorting and row disclosure; no CLI is invoked for these asset checks.

## Roundtable interface icons

The interface uses the local vector drawings in `static/ui-icons.js` for settings, project navigation, composer commands and participant roles. The 24-unit drawings share a 1.7-unit rounded stroke and inherit the control or tile foreground. Studio and the reading room use the same model icon for seats without a source mark. The subagent icon identifies delegated tasks and serves as the fallback in their detail panel.

Labels identify the action or participant. Decorative SVGs are hidden from assistive technology. Studio and the reading room share the same local source-to-mark mapping. Recognized CLI sources use their product images on white tiles.
