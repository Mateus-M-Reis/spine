-- Headless test suite for the Spine LÖVR runtime.
-- Run with: luajit tests/run.lua  (or lua tests/run.lua)
-- Requires a LÖVR-free environment; tests/stub.lua fakes the LÖVR API.

package.path = "./tests/?.lua;./?.lua;" .. package.path

local stub = require("stub")
local spine = require("init")

local passed, failed = 0, 0
local currentTest = ""

local function check(cond, message)
  if cond then
    passed = passed + 1
  else
    failed = failed + 1
    print(string.format("  FAIL [%s] %s", currentTest, message))
  end
end

local function section(name)
  currentTest = name
  print("== " .. name)
end

local ROOT = "./examples/"

local function assetPath(rel)
  return ROOT .. rel
end

local function countDrawable(skeleton)
  local n = 0
  for _, slot in ipairs(skeleton.drawOrder) do
    local a = slot.attachment
    if a and a.type ~= "clipping" and a.region and a.region.texture then
      n = n + 1
    end
  end
  return n
end

-- Load a skeleton through the high-level API.
local function loadHighLevel(jsonRel, atlasRel, scale)
  return spine.loadSkeleton(assetPath(jsonRel), assetPath(atlasRel), scale)
end

---------------------------------------------------------------------------
section("high-level loadSkeleton binds atlas and sets up pose")

do
  local inst = loadHighLevel("basic_usage/assets/spineboy/spineboy.json",
    "basic_usage/assets/spineboy/spineboy.atlas", 0.005)

  check(#inst.skeletonData.bones > 0, "skeleton data has bones")

  local withRegion = 0
  for _, slot in ipairs(inst.skeleton.drawOrder) do
    local a = slot.attachment
    if a and a.region and a.region.texture then
      withRegion = withRegion + 1
    end
  end
  check(withRegion > 0, "attachments are bound to atlas textures (got " .. withRegion .. ")")

  check(inst.animationState ~= nil, "animationState exists")
  check(inst.animationStateData ~= nil, "animationStateData exists")
  check(inst.animationState.data == inst.animationStateData,
    "AnimationState holds the AnimationStateData")
  check(inst.animationStateData.skeletonData == inst.skeletonData,
    "AnimationStateData holds the SkeletonData")

  inst.animationState:setAnimation(0, "walk", true)
  local track = inst.animationState.tracks[0]
  check(track ~= nil, "setAnimation('walk') created a track")
  check(track and track.animation and track.animation.name == "walk", "track plays 'walk'")
end

---------------------------------------------------------------------------
section("asset cache: skeleton data and textures are shared")

do
  spine.clearAssetCache()
  local texBefore = stub.counts.textures

  local a = loadHighLevel("basic_usage/assets/spineboy/spineboy.json",
    "basic_usage/assets/spineboy/spineboy.atlas", 0.005)
  local texturesAfterFirst = stub.counts.textures
  check(texturesAfterFirst > texBefore, "first load uploads textures")

  local b = loadHighLevel("basic_usage/assets/spineboy/spineboy.json",
    "basic_usage/assets/spineboy/spineboy.atlas", 0.005)

  check(a.skeletonData == b.skeletonData, "skeletonData shared across loads")
  check(a.atlas == b.atlas, "atlas shared across loads")
  check(a.skeleton ~= b.skeleton, "each load gets its own Skeleton instance")
  check(stub.counts.textures == texturesAfterFirst,
    "no new textures uploaded for repeated loads")

  spine.clearAssetCache()
  local c = loadHighLevel("basic_usage/assets/spineboy/spineboy.json",
    "basic_usage/assets/spineboy/spineboy.atlas", 0.005)
  check(c.skeletonData ~= a.skeletonData, "clearAssetCache forces a reload")
end

---------------------------------------------------------------------------
section("spine.update advances skeleton time and applies animation")

do
  local inst = loadHighLevel("basic_usage/assets/spineboy/spineboy.json",
    "basic_usage/assets/spineboy/spineboy.atlas", 0.005)
  inst.animationState:setAnimation(0, "walk", true)

  check(inst.skeleton.time == 0, "skeleton time starts at 0")

  local head = inst.skeleton:findBone("head")
  check(head ~= nil, "found head bone")

  local startX = head.worldX
  for _ = 1, 30 do
    spine.update(inst, 1 / 60)
  end

  check(inst.skeleton.time > 0, "skeleton.time advances via spine.update")
  check(head.worldX ~= startX, "animation changed the pose")
end

---------------------------------------------------------------------------
section("spine.draw renders batched and reuses materials across frames")

do
  stub.passStencil = true
  local inst = loadHighLevel("basic_usage/assets/spineboy/spineboy.json",
    "basic_usage/assets/spineboy/spineboy.atlas", 0.005)
  inst.animationState:setAnimation(0, "walk", true)
  spine.update(inst, 1 / 60)

  local pass = stub.newPass()
  local materialsBefore = stub.counts.materials
  stub.counts.verticesUploaded = 0

  spine.draw(inst, pass, 0, 0, -2, 0.005, 0.005, 0.005, 0)

  local expected = countDrawable(inst.skeleton)
  check(pass.draws >= 1 and pass.draws <= expected,
    string.format("attachments batched into few draws (1 <= %d <= %d)", pass.draws, expected))
  check(pass.transforms[1] ~= nil and type(pass.transforms[1]) ~= "number",
    "draw used a transform object, not a bare number")
  check(inst.renderer.drawCalls == pass.draws, "renderer.drawCalls counter populated")
  check(inst.renderer.vertexCount > 0 and inst.renderer.triangleCount > 0,
    "vertex/triangle counters populated")

  local expectedVertices = 0
  for _, slot in ipairs(inst.skeleton.drawOrder) do
    local a = slot.attachment
    if a and a.type == "region" and a.region and a.region.texture then
      expectedVertices = expectedVertices + 4
    elseif a and a.type == "mesh" and a.region and a.region.texture then
      expectedVertices = expectedVertices + #a.uvs / 2
    end
  end
  check(stub.counts.verticesUploaded == expectedVertices,
    string.format("no duplicated vertices uploaded (%d == %d)", stub.counts.verticesUploaded, expectedVertices))

  local materialsAfterFirst = stub.counts.materials
  check(materialsAfterFirst - materialsBefore == 1, "one material per texture page")

  -- Second frame must not create any new materials.
  pass.draws = 0
  stub.counts.verticesUploaded = 0
  spine.draw(inst, pass, 0, 0, -2, 0.005, 0.005, 0.005, 0)
  check(stub.counts.materials == materialsAfterFirst,
    "no new materials created on subsequent frames")
  check(pass.draws >= 1 and pass.draws <= expected, "stable draw count on subsequent frames")
end

---------------------------------------------------------------------------
section("SkeletonRenderer:draw accepts component transforms and Mat4")

do
  local inst = loadHighLevel("basic_usage/assets/spineboy/spineboy.json",
    "basic_usage/assets/spineboy/spineboy.atlas", 0.005)
  local pass = stub.newPass()
  local renderer = spine.SkeletonRenderer.new()

  renderer:draw(inst.skeleton, pass, 0, 1, -3, 0.005, 0.005, 0.005, 0)
  local t1 = pass.transforms[#pass.transforms]
  check(t1 ~= nil and type(t1) ~= "number", "component args build a transform")

  local mat = lovr.math.newMat4()
  renderer:draw(inst.skeleton, pass, mat)
  local t2 = pass.transforms[#pass.transforms]
  check(t2 == mat, "Mat4 arg passes through unchanged")
end

---------------------------------------------------------------------------
section("clipping: no double-draw, stencil is used and restored")

do
  stub.passStencil = true
  local inst = loadHighLevel("spine_playground/assets/coin/coin-pro.json",
    "spine_playground/assets/coin/coin.atlas", 0.005)

  local pass = stub.newPass()
  stub.counts.verticesUploaded = 0
  spine.draw(inst, pass, 0, 0, -2, 0.005, 0.005, 0.005, 0)

  local expected = countDrawable(inst.skeleton)
  check(pass.draws >= 1 and pass.draws <= expected,
    string.format("no double-draw inside clipping (%d draws <= %d attachments)", pass.draws, expected))

  local expectedVertices = 0
  for _, slot in ipairs(inst.skeleton.drawOrder) do
    local a = slot.attachment
    if a and a.type == "region" and a.region and a.region.texture then
      expectedVertices = expectedVertices + 4
    elseif a and a.type == "mesh" and a.region and a.region.texture then
      expectedVertices = expectedVertices + #a.uvs / 2
    end
  end
  check(stub.counts.verticesUploaded == expectedVertices,
    string.format("no duplicated vertices inside clipping (%d == %d)", stub.counts.verticesUploaded, expectedVertices))

  local increments, decrements = 0, 0
  for _, mode in ipairs(pass.stencilWrites) do
    if mode == "increment" then increments = increments + 1 end
    if mode == "decrement" then decrements = decrements + 1 end
  end
  check(increments > 0 and decrements > 0,
    string.format("stencil increment/decrement used (%d/%d)", increments, decrements))
  check(increments == decrements, "stencil writes are balanced")

  local colorWriteOff = false
  for _, cw in ipairs(pass.colorWrites) do
    if cw[1] == false and cw[2] == false and cw[3] == false and cw[4] == false then
      colorWriteOff = true
    end
  end
  check(colorWriteOff, "clip polygon drawn with color writes disabled")
end

---------------------------------------------------------------------------
section("clipping: falls back to unclipped drawing without stencil")

do
  stub.passStencil = false
  local inst = loadHighLevel("spine_playground/assets/coin/coin-pro.json",
    "spine_playground/assets/coin/coin.atlas", 0.005)

  local pass = stub.newPass()
  spine.draw(inst, pass, 0, 0, -2, 0.005, 0.005, 0.005, 0)

  local expected = countDrawable(inst.skeleton)
  check(pass.draws >= 1 and pass.draws <= expected,
    string.format("fallback draws everything unclipped (%d draws <= %d attachments)", pass.draws, expected))
  stub.passStencil = true
end

---------------------------------------------------------------------------
section("batching: tank's 144 attachments collapse to few draws")

do
  stub.passStencil = true
  local inst = loadHighLevel("spine_playground/assets/tank/tank-pro.json",
    "spine_playground/assets/tank/tank-pro.atlas", 0.005)

  local pass = stub.newPass()
  stub.counts.verticesUploaded = 0
  spine.draw(inst, pass, 0, 0, -2, 0.005, 0.005, 0.005, 0)

  local expected = countDrawable(inst.skeleton)
  check(expected > 100, "tank has many drawable attachments")
  check(pass.draws >= 1 and pass.draws < expected / 3,
    string.format("draw calls batched (%d < %d/3)", pass.draws, expected))

  local expectedVertices = 0
  for _, slot in ipairs(inst.skeleton.drawOrder) do
    local a = slot.attachment
    if a and a.type == "region" and a.region and a.region.texture then
      expectedVertices = expectedVertices + 4
    elseif a and a.type == "mesh" and a.region and a.region.texture then
      expectedVertices = expectedVertices + #a.uvs / 2
    end
  end
  check(stub.counts.verticesUploaded == expectedVertices,
    string.format("all vertices uploaded exactly once (%d == %d)", stub.counts.verticesUploaded, expectedVertices))
end

---------------------------------------------------------------------------
section("animation crossfade: previous animation is kept during mix")

do
  local inst = loadHighLevel("basic_usage/assets/spineboy/spineboy.json",
    "basic_usage/assets/spineboy/spineboy.atlas", 0.005)
  local state = inst.animationState

  state:setAnimation(0, "walk", true)
  for _ = 1, 30 do spine.update(inst, 1 / 60) end

  state:setAnimation(0, "run", true)
  local track = state.tracks[0]
  check(track ~= nil and track.animation.name == "run", "new animation set")
  check(track.previous ~= nil and track.previous.animation.name == "walk",
    "previous animation snapshotted for crossfade")
  check(track.mixDuration > 0, "mix duration applied from AnimationStateData")

  -- Mid-mix.
  for _ = 1, 7 do spine.update(inst, 1 / 60) end
  check(track.previous ~= nil, "previous still active mid-mix")
  check(track.mixTime > 0 and track.mixTime < track.mixDuration, "mix time advancing")

  -- Past the mix.
  for _ = 1, 20 do spine.update(inst, 1 / 60) end
  check(track.previous == nil, "previous cleared after mix completes")
end

---------------------------------------------------------------------------
section("track alpha and mixBlend layering")

do
  local inst = loadHighLevel("basic_usage/assets/spineboy/spineboy.json",
    "basic_usage/assets/spineboy/spineboy.atlas", 0.005)
  local ref = loadHighLevel("basic_usage/assets/spineboy/spineboy.json",
    "basic_usage/assets/spineboy/spineboy.atlas", 0.005)

  inst.animationState:setAnimation(0, "walk", true)
  ref.animationState:setAnimation(0, "walk", true)
  for _ = 1, 30 do
    spine.update(inst, 1 / 60)
    spine.update(ref, 1 / 60)
  end

  inst.animationState:setAnimation(1, "run", true)
  inst.animationState:setTrackAlpha(1, 0)
  check(inst.animationState.tracks[1].alpha == 0, "setTrackAlpha sets the track weight")

  spine.update(inst, 1 / 60)
  spine.update(ref, 1 / 60)
  local head, headRef = inst.skeleton:findBone("head"), ref.skeleton:findBone("head")
  check(math.abs(head.worldX - headRef.worldX) < 0.001,
    "track with alpha 0 leaves the pose unchanged")

  inst.animationState:setTrackAlpha(1, 1)
  inst.animationState:setTrackMixBlend(1, "add")
  check(inst.animationState.tracks[1].mixBlend == "add", "setTrackMixBlend sets the blend mode")
  spine.update(inst, 1 / 60)
  check(head.worldX ~= headRef.worldX, "full-weight additive track changes the pose")
end

---------------------------------------------------------------------------
section("animation events are parsed, fired once, and dispatched")

do
  local testData = {
    skeleton = { hash = "test", spine = "4.2.00", width = 100, height = 100 },
    bones = { { name = "root" } },
    slots = { { name = "s", bone = "root" } },
    skins = {
      default = {
        s = { img = { type = "region", x = 0, y = 0, width = 10, height = 10 } },
      },
    },
    events = {
      step = { int = 7 },
    },
    animations = {
      idle = {
        slots = {
          s = { attachment = { { time = 0, name = "img" } } },
        },
        events = {
          { time = 0.1, name = "step" },
          { time = 0.2, name = "step" },
        },
      },
    },
  }

  local inst = spine.loadSkeleton(testData)
  check(inst.animationState ~= nil, "synthetic skeleton loaded with animation")

  local received = {}
  inst.animationState:addListener({
    event = function(trackIndex, event)
      table.insert(received, { trackIndex = trackIndex, name = event.name, intValue = event.intValue })
    end,
  })

  inst.animationState:setAnimation(0, "idle", false)
  for _ = 1, 13 do spine.update(inst, 1 / 60) end -- 0.2167s: both events crossed

  check(#received == 2, "listener received 2 events (got " .. #received .. ")")
  check(received[1] and received[1].intValue == 7, "event data propagated")
  check(received[1] and received[1].trackIndex == 0, "event carries track index")

  -- The completed track is cleared on the update after its final apply.
  check(inst.animationState.tracks[0] ~= nil, "completed track applied final frame before clearing")
  spine.update(inst, 1 / 60)
  check(inst.animationState.tracks[0] == nil, "completed track cleared")
  check(#inst.animationState.events == 0, "pending events cleared after apply")
end

---------------------------------------------------------------------------
section("Spine 4.2 sequences: regions switch with the sequence timeline")

do
  local inst = spine.loadSkeleton("tests/fixtures/seq.json", "tests/fixtures/seq.atlas", 1)
  local slot = inst.skeleton:findSlot("s")
  check(slot ~= nil and slot.attachment ~= nil, "sequence attachment loaded")
  local attachment = slot.attachment
  check(attachment.sequence ~= nil, "attachment has a sequence")
  check(#attachment.sequence.regions == 3, "sequence resolved 3 atlas regions")
  check(slot.sequenceIndex == -1, "slot starts at setup sequence index")
  check(attachment.region == attachment.sequence.regions[1], "setup pose uses setup region")

  inst.animationState:setAnimation(0, "spin", true)

  for _ = 1, 3 do spine.update(inst, 1 / 60) end -- t = 0.05
  check(slot.sequenceIndex == 0, "index 0 before the first delay elapses")
  check(attachment.region == attachment.sequence.regions[1], "region 0 shown")

  for _ = 1, 6 do spine.update(inst, 1 / 60) end -- t = 0.15
  check(slot.sequenceIndex == 1, "index advances with time")
  check(attachment.region == attachment.sequence.regions[2], "region 1 shown")

  for _ = 1, 12 do spine.update(inst, 1 / 60) end -- t = 0.35
  check(slot.sequenceIndex == 0, "loop mode wraps around")
  check(attachment.region == attachment.sequence.regions[1], "wrapped back to region 0")
end

---------------------------------------------------------------------------
section("addAnimation honors delay")

do
  local inst = loadHighLevel("basic_usage/assets/spineboy/spineboy.json",
    "basic_usage/assets/spineboy/spineboy.atlas", 0.005)
  local state = inst.animationState

  state:setAnimation(0, "walk", true)
  state:addAnimation(0, "run", true, 0.5)

  spine.update(inst, 0.1)
  check(state.tracks[0].animation.name == "walk", "queued animation not started before delay")

  for _ = 1, 30 do spine.update(inst, 1 / 60) end
  check(state.tracks[0].animation.name == "run", "queued animation started after delay")
end

---------------------------------------------------------------------------
print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
