# Spine LÖVR Runtime

A complete Spine skeletal animation runtime for LÖVR, implementing the Spine animation system with efficient 3D rendering.

## Features

- **Complete Spine Runtime**: Full implementation of Spine's animation system (Spine 4.2.x compatible).
- **LÖVR Integration**: Native LÖVR graphics API integration using Pass-based rendering with dynamic Meshes and Buffers.
- **Batched Rendering**: Attachments are batched per texture page and render state — e.g. the 191-attachment tank demo draws in 3 draw calls.
- **Asset Caching**: `loadSkeleton` shares `SkeletonData` and atlas textures across instances (see `spine.clearAssetCache`).
- **Attachments**: Supports Region, Mesh, BoundingBox, and Path attachments.
- **Sequences**: Spine 4.2 sequence attachments and sequence timelines (hold/once/loop/pingpong modes).
- **Animation**: Timeline-based animations with crossfade mixing, multi-track layering (track alpha and mixBlend), draw-order timelines, and events (listener API).
- **Colors**: Skeleton, slot, and attachment tints are multiplied for every rendered attachment, including PMA and tint-black (dark color) shading.
- **Constraints**: IK, Transform, Path, and Physics constraints.
- **Skins**: Runtime skin switching, including skin-required bones and constraints.
- **3D Positioning**: Place skeletons anywhere in 3D space with full transform control.
- **Stencil Clipping**: Hardware-accelerated clipping attachments, including nested clips.
- **Custom Shaders**: Tint-black dual-color tinting (per-vertex dark color) and multiply blend mode shaders.

## Installation

1. Copy the `spine` folder and `init.lua` file to your LÖVR project directory.
2. Require the module in your code:

```lua
local spine = require("init")
```

## Quick Start

```lua
local spine = require("init")

local instance

function lovr.load()
  -- The scale argument converts Spine's pixel units to world units.
  -- Exports are usually authored at ~1000px, so 0.001-0.005 fits LÖVR scenes.
  instance = spine.loadSkeleton("assets/hero.json", "assets/hero.atlas", 0.005)
  if instance.animationState then
    instance.animationState:setAnimation(0, "walk", true)
  end
end

function lovr.update(dt)
  -- Updates animation state, applies it, advances skeleton time (needed for
  -- physics constraints), and updates world transforms.
  spine.update(instance, dt)
end

function lovr.draw(pass)
  -- Draw at position (0, 0, -3) with the given scale/rotation.
  spine.draw(instance, pass, 0, 0, -3, 0.005, 0.005, 0.005, 0)
end
```

`spine.loadSkeleton` accepts JSON as a path or decoded table, and the atlas as a
path, raw atlas text, or an already-built `Atlas`. The returned `instance` has
`skeleton`, `skeletonData`, `animationState`, `animationStateData`, `renderer`,
`atlas`, and `attachmentLoader` fields. The skeleton is initialized to its
setup pose automatically.

`SkeletonData` and atlas textures are cached and shared between instances, so
spawning many copies of the same character reuses textures and parsed data
(each call still gets its own `Skeleton`/renderer). Cache keys use the JSON path
plus the atlas path/text and scale; decoded table inputs and prebuilt `Atlas`
objects are caller-owned and are not cached by address.

Instances are reference-counted. Call `instance:release()` (or
`spine.release(instance)`) when you are done with one; per-instance renderer
resources are released immediately and shared textures are disposed when the
last user is gone. `spine.clearAssetCache()` detaches all cache entries; entries
still used by live instances stay alive until those instances are released.

### Animation events

```lua
instance.animationState:addListener({
  event = function(trackIndex, event)
    print("event", event.name, "on track", trackIndex, "int:", event.intValue)
  end,
  complete = function(trackIndex)
    print("track", trackIndex, "completed")
  end,
})

-- Crossfades between animations are automatic: the duration comes from
-- AnimationStateData (default 0.25s, configurable with setMix/setDefaultMix).
instance.animationState:setAnimation(0, "walk", true)
instance.animationState:setAnimation(0, "run", true) -- crossfades from walk
```

### Track layering

```lua
-- Play an additive upper-body animation on track 1 over the lower body.
instance.animationState:setAnimation(0, "run", true)
local upper = instance.animationState:setAnimation(1, "shoot", true)
upper.alpha = 0.8          -- track weight
upper.mixBlend = "add"     -- "setup", "first", "replace", or "add"
-- equivalently: setTrackAlpha(1, 0.8) / setTrackMixBlend(1, "add")
```

## Advanced Usage

```lua
local spine = require("init")

local skeleton, animationState, renderer

function lovr.load()
  -- 1. Load Atlas
  local atlas = spine.TextureAtlas.new()
  atlas:loadAtlasFile(lovr.filesystem.read("assets/hero.atlas"), "assets")

  -- 2. Load Skeleton Data
  local attachmentLoader = spine.atlas.AtlasAttachmentLoader.new(atlas)
  local json = spine.utils.jsonDecode(lovr.filesystem.read("assets/hero.json"))
  local skeletonData = spine.SkeletonData.new(nil, 1)
  skeletonData:loadFromJson(json, attachmentLoader)

  -- 3. Create Skeleton
  skeleton = spine.Skeleton.new(skeletonData)
  skeleton:setToSetupPose()

  -- 4. Create Animation State
  local animStateData = spine.AnimationStateData.new(skeletonData)
  animationState = spine.AnimationState.new(animStateData)
  animationState:setAnimation(0, "walk", true)

  -- 5. Create Renderer
  renderer = spine.SkeletonRenderer.new()
  renderer:setDebug(false)
end

function lovr.update(dt)
  animationState:update(dt)
  animationState:apply(skeleton)
  skeleton:update(dt) -- advance skeleton time (physics constraints need it)
  skeleton:updateWorldTransform()
end

function lovr.draw(pass)
  -- Component form: x, y, z, scaleX, scaleY, scaleZ, rotation
  renderer:draw(skeleton, pass, 0, 1, -3, 0.005, 0.005, 0.005, 0)
end
```

### Using a Mat4 transform

```lua
function lovr.draw(pass)
  local transform = lovr.math.newMat4()
  transform:translate(0, 1, -3)
  transform:rotate(math.pi / 4, 0, 0, 1)
  transform:scale(0.005, -0.005, 0.005)

  renderer:draw(skeleton, pass, transform)
end
```

## Project Structure

- `init.lua`: Main entry point and high-level API.
- `spine/`: Core runtime modules:
  - `data.lua` - Skeleton data model and JSON parser
  - `skeleton.lua` - Bone, Slot, and Skeleton runtime
  - `animation.lua` - Animation timeline system and state machine
  - `constraint.lua` - IK, Transform, Path, and Physics constraints
  - `atlas.lua` - Texture atlas loading and region management
  - `rendering.lua` - LÖVR Pass-based rendering with dynamic meshes
  - `math.lua` - Vector, matrix, and interpolation math utilities
  - `utils.lua` - JSON parser, profiler, cache, and triangulation utilities
  - `tintblack_shader.lua` - Dual-color tinting fragment shader
  - `multiply_mask_shader.lua` - Multiply blend mode fragment shader
- `examples/`: Example projects.
- `tests/`: Headless test suite (see Testing below).

## Testing

The runtime can be tested without LÖVR using the bundled LÖVR stub:

```bash
luajit tests/run.lua          # runtime test suite
luajit tests/run_examples.lua # loads/updates/draws both example projects
```

The suite covers high-level loading (atlas binding, setup pose), asset caching
(including parse-free cache hits and reference-counted release), multi-page and
raw-text atlas loading, skeleton time advancement, batched rendering call
counts, material caching, draw-order preservation across batch-state changes
and clipping, skeleton/slot/attachment color multiplication, deform offset
scaling, bounding-box parsing, skeleton scale, physics reference units and
global physics timelines, trimmed/rotated mesh UVs, stencil clipping (including
concave-polygon triangulation and the no-stencil fallback), draw-order
timelines, skin-required bones/constraints, animation crossfades, track
layering, event dispatch (including time-zero events), Spine 4.2 sequences, and
queued animations.

## Requirements

- LÖVR 0.18 or higher is the primary target
- Spine 4.2.x compatible JSON exports

### Compatibility notes

The renderer degrades gracefully across LÖVR versions:

- Shader dialects are detected at load time (LÖVR 0.18 `texture`/`VertexUV`
  style and the `getPixel`/`Color`/`UV` style used by older/newer builds); the
  tint-black shader falls back to a per-dark-color uniform when per-vertex
  dark colors are unavailable.
- `pass:polygon`/`pass:box` are called with and without a mode argument as
  needed (older builds have no mode string).
- Material creation tries both `newMaterial({ texture = ... })` and
  `newMaterial(texture)`.
- If the pass has no stencil-capable depth format, clipping attachments simply
  render unclipped instead of using the stencil buffer.

## License

This runtime is released under the MIT License (see [LICENSE](LICENSE)).
Please ensure you have the appropriate licenses for the Spine software and any
Spine assets you use; the bundled sample assets remain under their original
licensing terms.
