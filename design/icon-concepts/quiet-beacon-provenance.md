# Quiet Beacon App Icon

- Selected source: top-row concept 03, “Quiet Beacon”, from `Screenshot 2026-07-17 at 11.00.11 AM.png`.
- Exact source crop: `quiet-beacon-icon.png` (156 × 156 px).
- Vector master: `quiet-beacon-app-icon.svg` (1024 × 1024 px, full-bleed square artwork).
- App-icon export: `quiet-beacon-app-icon-1024.png` (1024 × 1024 px, sRGB, opaque PNG).
- Small-size preview: `quiet-beacon-app-icon-60.png` (60 × 60 px).
- Installed destination: `HavenCircle/Assets.xcassets/AppIcon.appiconset/AppIcon.png`.

The vector master faithfully preserves the selected double-ring, central home, proportions, and sampled palette. The pre-rendered rounded tile and contact-sheet pixels are intentionally excluded so iOS can apply its own icon mask cleanly.

## Re-export

```sh
qlmanage -t -s 1024 -o /tmp design/icon-concepts/quiet-beacon-app-icon.svg
swift tools/flatten_app_icon.swift \
  /tmp/quiet-beacon-app-icon.svg.png \
  design/icon-concepts/quiet-beacon-app-icon-1024.png
sips --resampleHeightWidth 60 60 \
  design/icon-concepts/quiet-beacon-app-icon-1024.png \
  --out design/icon-concepts/quiet-beacon-app-icon-60.png
```
