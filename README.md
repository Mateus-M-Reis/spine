# Spine LÖVR Runtime

A complete Spine skeletal animation runtime for LÖVR, implementing the Spine animation system with efficient 3D rendering.

## Features

- **Complete Spine Runtime**: Full implementation of Spine's animation system (Spine 4.2.x compatible).
- **LÖVR Integration**: Native LÖVR graphics API integration using Pass-based rendering with dynamic Meshes and Buffers.
- **Attachments**: Supports Region, Mesh, BoundingBox, and Path attachments.
- **Animation**: Timeline-based animations with mixing, blending, and events.
- **Constraints**: IK, Transform, Path, and Physics constraints.
- **Skins**: Runtime skin switching.
- **3D Positioning**: Place skeletons anywhere in 3D space with full transform control.
- **Stencil Clipping**: Hardware-accelerated clipping attachment support.
- **Custom Shaders**: Tint-black dual-color tinting and multiply blend mode shaders.

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
  instance = spine.loadSkeleton("assets/hero.json", "assets/hero.atlas", 0.5)
  if instance.animationState then
    instance.animationState:setAnimation(0, "walk", true)
  end
end

function lovr.update(dt)
  spine.update(instance, dt)
end

function lovr.draw(pass)
  -- Draw at position (0, 0, -3) with default scale/rotation
  spine.draw(instance, pass, 0, 0, -3)
end
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
  skeleton:updateWorldTransform()
end

function lovr.draw(pass)
  -- Draw with full transform control: x, y, z, scaleX, scaleY, scaleZ, rotation
  renderer:draw(skeleton, pass, 0, 1, -3, 0.005, -0.005, 0.005, 0)
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
  - `alpha_clip_shader.lua` - Alpha clipping fragment shader
- `examples/`: Example projects.

## Requirements

- LÖVR 0.18 or higher
- Spine 4.2.x compatible JSON exports

## License

This runtime is provided for use with Spine animations. Please ensure you have the appropriate licenses for the Spine software and any Spine assets you use.
