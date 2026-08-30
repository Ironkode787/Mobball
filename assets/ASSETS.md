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
| `art/eastport/backglass.png` | Eastport backglass | built-in ImageGen | project-owned generated art | 2026-08-30 | [P1-01](art/PHASE1_PROMPTS.md#p1-01--eastport-backglass) | none; opaque plate | no | approved at 1080×1920 and 486×864 |
| `art/eastport/count_room.png` | Count room | built-in ImageGen | project-owned generated art | 2026-08-30 | [P1-02](art/PHASE1_PROMPTS.md#p1-02--count-room) | none; opaque full-bleed plate | no | approved at 1080×1920 and 486×864 |
| `art/eastport/trash_can_bumper.png` | table prop | built-in ImageGen | project-owned generated art | 2026-08-30 | [P1-03](art/PHASE1_PROMPTS.md#p1-03--trash-can-bumper) | runtime radial mask; source remains opaque | no | approved; collision-independent |
| `art/eastport/bicycle_spinner.png` | table prop | built-in ImageGen | project-owned generated art | 2026-08-30 | [P1-04](art/PHASE1_PROMPTS.md#p1-04--bicycle-spinner) | runtime radial mask; source remains opaque | no | approved; collision-independent |
| `art/eastport/payphone.png` | table prop | built-in ImageGen | project-owned generated art | 2026-08-30 | [P1-05](art/PHASE1_PROMPTS.md#p1-05--payphone-bank) | none; state overlay stays procedural | no | approved at table scale |
| `art/eastport/job_board.png` | Roll Call plate | built-in ImageGen | project-owned generated art | 2026-08-30 | [P1-06](art/PHASE1_PROMPTS.md#p1-06--job-board) | none; deterministic copy overlays | no | approved at 486×864 |
| `art/eastport/laundromat.png` | storefront | built-in ImageGen | project-owned generated art | 2026-08-30 | [P1-07](art/PHASE1_PROMPTS.md#p1-07--laundromat) | none; deterministic sign/state overlays | no | approved at table scale |
| `art/eastport/pizzeria.png` | storefront | built-in ImageGen | project-owned generated art | 2026-08-30 | [P1-08](art/PHASE1_PROMPTS.md#p1-08--pizzeria) | none; deterministic sign/state overlays | no | approved at table scale |
| `art/eastport/pawn_shop.png` | storefront | built-in ImageGen | project-owned generated art | 2026-08-30 | [P1-09](art/PHASE1_PROMPTS.md#p1-09--pawn-shop) | none; deterministic sign/state overlays | no | approved at table scale |
| `art/portraits/starter_01.png` | starter mugshot | built-in ImageGen | project-owned generated art | 2026-08-30 | [P1-10](art/PHASE1_PROMPTS.md#p1-10--starter-01) | none; opaque 4:5 card | no | fictional likeness approved |
| `art/portraits/starter_02.png` | starter mugshot | built-in ImageGen | project-owned generated art | 2026-08-30 | [P1-11](art/PHASE1_PROMPTS.md#p1-11--starter-02) | none; opaque 4:5 card | no | fictional likeness approved |
| `art/portraits/starter_03.png` | starter mugshot | built-in ImageGen | project-owned generated art | 2026-08-30 | [P1-12](art/PHASE1_PROMPTS.md#p1-12--starter-03) | none; opaque 4:5 card | no | fictional likeness approved |
| `art/portraits/starter_04.png` | starter mugshot | built-in ImageGen | project-owned generated art | 2026-08-30 | [P1-13](art/PHASE1_PROMPTS.md#p1-13--starter-04) | none; opaque 4:5 card | no | fictional likeness approved |
| `fonts/Oswald-SemiBold.ttf` | display type | Google Fonts repository | SIL Open Font License 1.1 | 2026-08-30 | `googlefonts/OswaldFont`, static TTF | none | yes; OFL text included | approved |
| `fonts/LibreFranklin-Regular.ttf` | body type | Libre Franklin repository | SIL Open Font License 1.1 | 2026-08-30 | `googlefonts/Libre-Franklin`, static TTF | none | yes; OFL text included | approved |
| `fonts/LibreFranklin-SemiBold.ttf` | UI type | Libre Franklin repository | SIL Open Font License 1.1 | 2026-08-30 | `googlefonts/Libre-Franklin`, static TTF | none | yes; OFL text included | approved |
| `fonts/CourierPrime-Regular.ttf` | annotation type | Courier Prime repository | SIL Open Font License 1.1 | 2026-08-30 | `quoteunquoteapps/CourierPrime`, static TTF | none | yes; OFL text included | approved |
| `fonts/CourierPrime-Bold.ttf` | card type | Courier Prime repository | SIL Open Font License 1.1 | 2026-08-30 | `quoteunquoteapps/CourierPrime`, static TTF | none | yes; OFL text included | approved |
| `fonts/OFL-Oswald.txt` | license text | Google Fonts repository | SIL Open Font License 1.1 | 2026-08-30 | Oswald upstream `OFL.txt` | renamed; trailing whitespace normalized | n/a | text preserved |
| `fonts/OFL-LibreFranklin.txt` | license text | Libre Franklin repository | SIL Open Font License 1.1 | 2026-08-30 | Libre Franklin upstream `OFL.txt` | renamed; trailing whitespace normalized | n/a | text preserved |
| `fonts/OFL-CourierPrime.txt` | license text | Courier Prime repository | SIL Open Font License 1.1 | 2026-08-30 | Courier Prime upstream `OFL.txt` | renamed; trailing whitespace normalized | n/a | text preserved |
| `../release/store/feature_graphic.png` | Google Play feature graphic | built-in ImageGen + deterministic title overlay | project-owned generated art; Oswald OFL | 2026-08-30 | [Phase 5 store prompt](../release/store/FEATURE_PROMPTS.md) | center crop to 1024×500; exact title overlaid by `tools/make_store_art.ps1` | no | approved; no fake UI or generated lettering |

## Generated-asset review checklist

- No accidental text, watermark, trademark, or recognizable real-person likeness.
- Alpha or deterministic mask edges and padding inspected at master and runtime resolution.
- Dirty red, clean green, heat ember, and cop blue remain semantically reserved.
- The runtime crop is legible at both 1080×1920 and 486×864.
- Prompt, reference hashes, model/provider, generation date, and post-process version recorded.
- Selected project assets live in this repository; generated-source folders are not runtime dependencies.
