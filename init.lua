-- Spine LÖVR Runtime - Main Entry Point
-- Version: 1.0.0

local spine = {}

-- Version information
spine.version = "1.0.0"
spine.spineVersion = "4.2.x"
spine.lovrVersion = "0.18+"

-- Core module loading
spine.utils = require("spine.utils")
spine.math = require("spine.math")
spine.data = require("spine.data")
spine.skeleton = require("spine.skeleton")
spine.animation = require("spine.animation")
spine.rendering = require("spine.rendering")
spine.atlas = require("spine.atlas")
spine.constraint = require("spine.constraint")

-- Convenient API wrappers
spine.Skeleton = spine.skeleton.Skeleton
spine.SkeletonData = spine.data.SkeletonData
spine.AnimationState = spine.animation.AnimationState
spine.AnimationStateData = spine.data.AnimationStateData
spine.TextureAtlas = spine.atlas.Atlas
spine.Renderer = spine.rendering.Renderer
spine.SkeletonRenderer = spine.rendering.SkeletonRenderer

-- Error handling
spine.errors = {
  INVALID_JSON = "spine_invalid_json_format",
  MISSING_BONE = "spine_bone_not_found",
  MISSING_ATTACHMENT = "spine_attachment_not_found",
  INVALID_ANIMATION = "spine_invalid_animation_data",
  TEXTURE_LOAD_FAILED = "spine_texture_load_failed",
  UNSUPPORTED_FEATURE = "spine_unsupported_feature",
  VERSION_MISMATCH = "spine_version_mismatch",
  INVALID_ATLAS = "spine_invalid_atlas_format"
}

-- Debug mode
spine.debug = false
spine.debugOptions = {
  showBones = false,
  showSlots = false,
  showAttachments = false,
  showBounds = false,
  showMesh = false,
  performanceStats = false
}

-- Performance monitoring
spine.performance = {
  skeletonUpdateTime = 0,
  animationUpdateTime = 0,
  renderTime = 0,
  drawCalls = 0,
  vertexCount = 0,
  triangleCount = 0
}

-- Initialization function
function spine.init()
  print(string.format("Spine LÖVR Runtime v%s initialized", spine.version))
  print(string.format("Compatible with Spine %s and LÖVR %s",
    spine.spineVersion, spine.lovrVersion))

  if spine.math.init then
    spine.math.init()
  end

  return true
end

-- Load Spine data files
function spine.loadSkeleton(jsonFile, atlasFile, scale)
  scale = scale or 1

  local jsonData
  if type(jsonFile) == "string" then
    local fileData = lovr.filesystem.read(jsonFile)
    if not fileData then
      error(string.format("Failed to read JSON file: %s", jsonFile))
    end
    jsonData = spine.utils.jsonDecode(fileData)
  else
    jsonData = jsonFile
  end

  if not jsonData then
    error("Invalid JSON data")
  end

  local atlas
  if atlasFile then
    local atlasData
    if type(atlasFile) == "string" then
      atlasData = lovr.filesystem.read(atlasFile)
      if not atlasData then
        error(string.format("Failed to read atlas file: %s", atlasFile))
      end
    else
      atlasData = atlasFile
    end
    atlas = spine.TextureAtlas.new()
    local imageRoot = nil
    if type(atlasFile) == "string" then
      imageRoot = atlasFile:match("^(.*)/[^/]+$") or ""
    end
    local ok, err = atlas:loadAtlasFile(atlasData, imageRoot)
    if not ok then
      error(string.format("Failed to load atlas: %s", err or "unknown error"))
    end
  end

  local skeletonData = spine.data.SkeletonData.new(jsonData, scale)
  local skeleton = spine.skeleton.Skeleton.new(skeletonData)
  local renderer = spine.Renderer.new()

  local animationState = nil
  if jsonData.animations and next(jsonData.animations) then
    local AnimationState = spine.animation.AnimationState
    animationState = AnimationState.new(skeletonData)
  end

  return {
    skeleton = skeleton,
    animationState = animationState,
    renderer = renderer,
    skeletonData = skeletonData,
    atlas = atlas
  }
end

-- Update animation state (framework-agnostic)
function spine.update(instance, deltaTime)
  local startTime = lovr.timer.getTime()

  if instance.animationState then
    instance.animationState:update(deltaTime)
    instance.animationState:apply(instance.skeleton)
  end

  instance.skeleton:updateWorldTransform()

  spine.performance.animationUpdateTime = lovr.timer.getTime() - startTime
end

-- Create a Mat4 transform from position, rotation, and scale parameters
-- Accepts: (x, y, z, sx, sy, sz, rotation) or a Mat4 or nil
local function buildTransform(x, y, z, sx, sy, sz, rotation)
  if type(x) == "userdata" then
    return x -- it's a Mat4
  end

  x = x or 0
  y = y or 0
  z = z or 0
  sx = sx or 1
  sy = sy or -1
  sz = sz or 1
  rotation = rotation or 0

  local mat = lovr.math.newMat4()
  mat:translate(x, y, z)
  mat:rotate(rotation, 0, 0, 1)
  mat:scale(sx, sy, sz)
  return mat
end

-- Render Spine instance
-- Usage: spine.draw(instance, pass, x, y, z, scaleX, scaleY, scaleZ, rotation)
--   or: spine.draw(instance, pass, mat4_transform)
function spine.draw(instance, pass, ...)
  local startTime = lovr.timer.getTime()

  spine.performance.drawCalls = 0
  spine.performance.vertexCount = 0
  spine.performance.triangleCount = 0

  local transform = buildTransform(...)

  instance.renderer.debug = spine.debug
  instance.renderer:drawSkeleton(instance.skeleton, pass, transform)

  spine.performance.renderTime = lovr.timer.getTime() - startTime
end

-- Debug rendering
function spine.drawDebug(instance, pass, ...)
  local transform = buildTransform(...)

  pass:push()
  if transform then
    pass:transform(transform)
  end

  instance.renderer:drawDebugSkeleton(instance.skeleton, pass)

  pass:pop()
end

-- Performance statistics
function spine.getPerformanceStats()
  return {
    skeletonUpdateTime = spine.performance.skeletonUpdateTime,
    animationUpdateTime = spine.performance.animationUpdateTime,
    renderTime = spine.performance.renderTime,
    totalTime = spine.performance.skeletonUpdateTime +
               spine.performance.animationUpdateTime +
               spine.performance.renderTime,
    drawCalls = spine.performance.drawCalls,
    vertexCount = spine.performance.vertexCount,
    triangleCount = spine.performance.triangleCount
  }
end

-- Error handling function
function spine.handleError(errorType, message, ...)
  local errorMessage = string.format("[Spine Runtime Error: %s] %s", errorType, message)
  if spine.debug then
    print(debug.traceback(errorMessage, 2))
  end
  return error(errorMessage)
end

-- Version compatibility check
function spine.checkVersion(spineVersion)
  local major, minor = spineVersion:match("(%d+)%.(%d+)")
  major = tonumber(major)
  minor = tonumber(minor)

  if major < 4 or (major == 4 and minor < 2) then
    spine.handleError(spine.errors.VERSION_MISMATCH,
      string.format("Spine version %s is not supported. Minimum required: 4.2.x", spineVersion))
  end
end

-- Set debug mode
function spine.setDebug(enabled, options)
  spine.debug = enabled
  if options then
    for key, value in pairs(options) do
      spine.debugOptions[key] = value
    end
  end
end

-- Utility function: Load JSON from file
function spine.loadJsonFromFile(filePath)
  local fileData = lovr.filesystem.read(filePath)
  if not fileData then
    return nil, "Failed to read file: " .. filePath
  end

  local success, result = pcall(spine.utils.jsonDecode, fileData)
  if not success then
    return nil, "Failed to parse JSON: " .. result
  end

  return result
end

-- Utility function: Load atlas from file
function spine.loadAtlasFromFile(filePath)
  local atlasData = lovr.filesystem.read(filePath)
  if not atlasData then
    return nil, "Failed to read atlas file: " .. filePath
  end

  local atlas = spine.TextureAtlas.new()
  local imageRoot = filePath:match("^(.*)/[^/]+$") or ""
  local ok, err = atlas:loadAtlasFile(atlasData, imageRoot)
  if not ok then
    return nil, err
  end
  return atlas
end

-- Utility function: Create test skeleton
function spine.createTestSkeleton()
  local testData = {
    skeleton = {
      hash = "test_skeleton",
      spine = "4.2.00",
      x = -50, y = -50,
      width = 100, height = 100
    },
    bones = {
      { name = "root", x = 0, y = 0 },
      { name = "torso", parent = "root", length = 30, x = 0, y = 0, rotation = 90 },
      { name = "head", parent = "torso", length = 20, x = 0, y = 30, rotation = 0 }
    },
    slots = {
      { name = "torso_slot", bone = "torso", attachment = "torso_img" },
      { name = "head_slot", bone = "head", attachment = "head_img" }
    },
    skins = {
      default = {
        torso_slot = { torso_img = { type = "region", x = 0, y = 0, width = 30, height = 40 } },
        head_slot = { head_img = { type = "region", x = 0, y = 0, width = 25, height = 25 } }
      }
    },
    animations = {
      idle = {
        bones = {
          head = {
            rotate = {
              { time = 0, angle = -5 },
              { time = 1, angle = 5 },
              { time = 2, angle = -5 }
            }
          }
        }
      }
    }
  }

  return spine.loadSkeleton(testData)
end

-- Initialize runtime
spine.init()

return spine
