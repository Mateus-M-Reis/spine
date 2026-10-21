# Spine Playground - Interactive Animation Viewer

An interactive LÖVR demo for loading and playing Spine animations with an
in-world HUD. Pick an asset, play any of its animations, move/zoom the
skeleton, and inspect bones.

## Quick Start

```bash
cd examples/spine_playground
lovr .
```

## Features

- **Animation List**: All animations from the loaded Spine export, shown on the
  left HUD panel.
- **Keyboard Driven UI**: 1-9 or Up/Down to select animations, Tab/N to switch
  assets, arrows to move the skeleton, +/- to zoom.
- **Smooth Transitions**: All animation switches crossfade over 0.2s.
- **Debug Rendering**: Press D to draw bones, slots, and attachment bounds.
- **Mix & Match**: The `mix_and_match` asset auto-applies the
  `full-skins/girl` skin.

## Controls

| Key            | Action                                  |
| -------------- | --------------------------------------- |
| `1`-`9`        | Play animation by number                |
| `Space`        | Cycle to the next animation             |
| `Up`/`Down`    | Previous / next animation               |
| `[` / `]`      | Scroll the animation list               |
| `Tab` or `N`   | Next asset                              |
| `P`            | Previous asset                          |
| `Arrow keys`   | Move the skeleton (hold)                |
| `+` / `-`      | Zoom in / out                           |
| `D`            | Toggle debug rendering                  |
| `Y`            | Flip the skeleton vertically            |
| `B`            | Print bone hierarchy/transforms to console |
| `R`            | Reset position and zoom                 |
| `H`            | Toggle help text                        |
| `U`            | Toggle the HUD                          |
| `Esc`          | Quit                                    |

## Loading Different Assets

Edit `CONFIG` at the top of `main.lua`:

```lua
local CONFIG = {
    currentAsset = "spineboy_pro", -- change this
    assets = {
        spineboy_pro = {
            atlas = "assets/spineboy-pro/spineboy-pro.atlas",
            json  = "assets/spineboy-pro/spineboy-pro.json",
            scale = 0.004, -- world units; ~0.003-0.006 fits LÖVR scenes
        },
        -- add your own exports here
    },
}
```

To add your own character, place its `.json`, `.atlas`, and `.png` files in
`assets/your_character/`, add an entry to `CONFIG.assets`, and set
`currentAsset = "your_character"`.

## Notes

- The skeleton is drawn in 3D world space at `(0, 0, -3)`; the HUD panels are
  anchored to the camera, 2m in front of it, so they follow the view and always
  face you.
- The HUD text uses a small built-in bitmap font, because `pass:text` does not
  render on some LÖVR builds.
- Drag & drop file loading is not supported in this port; use `CONFIG` instead.
- The demo uses the high-level `spine.loadSkeleton` API, so it doubles as an
  example of the quick-start workflow.

## Default Assets

The playground ships with several Spine sample exports: spineboy variants,
stretchyman, coin, alien, windmill, tank, sack, cloud-pot, powerup, and the
mix-and-match demo.
