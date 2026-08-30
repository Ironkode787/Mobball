# Store feature graphic provenance

## Background generation

- Provider: built-in ImageGen
- Date: 2026-08-30
- Use case: `ads-marketing`
- Style reference: `assets/art/eastport/backglass.png`
- Generated source: `feature_graphic_source.png` (1794×877)
- Final: `feature_graphic.png` (1024×500)

Prompt:

> An original premium key-art illustration for a portrait mobile pinball crime-satire game,
> showing a gleaming steel pinball racing through a miniature 1972 noir city built directly
> onto a pinball table, with brass rails suggesting a crown silhouette. Paperback Noir ×
> Electric Brass; wide 2.048:1 composition; action on the right, clean dark title-safe area on
> the left; ink, felt, aged brass, wood, newsprint, minimal rose/teal neon. Background only: no
> text, logo, UI, phone, trademark, watermark, weapon, blood, smoking, casino chips, playing
> cards, or recognizable landmark.

`tools/make_store_art.ps1` center-crops/resamples the source and overlays the exact title with
the repository's OFL Oswald font. The generated image contains no generated lettering or fake
gameplay.
