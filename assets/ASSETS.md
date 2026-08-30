# KINGPIN asset manifest

Every production asset added under `assets/` must have a row here before it can ship.
Generated work is recorded even when it requires no attribution so its prompt and review
history remain reproducible. Third-party assets must be CC0, CC-BY, OFL, or public domain;
NC and ND material is not accepted.

| Path | Family | Source | Model / license | Created | Prompt or source | Post-process | Credit required | Review |
|---|---|---|---|---|---|---|---|---|
| `../icon.png` | launcher icon | repository original | project-owned | pre-manifest | existing project asset | none recorded | no | legacy asset; provenance review pending |
| `icon/icon_192.png` | launcher icon | repository original | project-owned | pre-manifest | existing project asset | none recorded | no | legacy asset; provenance review pending |
| `icon/adaptive_fg.png` | launcher icon | repository original | project-owned | pre-manifest | existing project asset | none recorded | no | legacy asset; provenance review pending |
| `icon/adaptive_bg.png` | launcher icon | repository original | project-owned | pre-manifest | existing project asset | none recorded | no | legacy asset; provenance review pending |

## Generated-asset review checklist

- No accidental text, watermark, trademark, or recognizable real-person likeness.
- Alpha edges and padding inspected at master and runtime resolution.
- Dirty red, clean green, heat ember, and cop blue remain semantically reserved.
- The runtime crop is legible at both 1080×1920 and 486×864.
- Prompt, reference hashes, model/provider, generation date, and post-process version recorded.
- Selected project assets live in this repository; generated-source folders are not runtime dependencies.
