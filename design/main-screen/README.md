# Main-screen redesign — working files

Source for the Goalhorn main-screen design canvas.

- `build.mjs` — generates the artboards. The lamp's geometry (cage wrap,
  hoop perspective, dome meridians, metal banding) is computed here so every
  artboard stays consistent. Run `node design/main-screen/build.mjs`.
- `*.dc.html` — one artboard each; `Main` is the entry artboard.
- `canvas.json` — canvas layout, artboard titles and the sticky notes.
- `goalhorn-main-screen.html` — the assembled canvas that was published.

To change the design, edit `build.mjs`, re-run it, then re-seed and republish.
