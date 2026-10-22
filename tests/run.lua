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

local function approx(a, b, epsilon)
  return math.abs(a - b) <= (epsilon or 1e-6)
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
  stub.counts.vertexFloatsUploaded = 0

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
  check(stub.counts.vertexFloatsUploaded == expectedVertices * stub.VERTEX_COMPONENTS,
    string.format("no duplicated vertex floats uploaded (%d == %d)", stub.counts.vertexFloatsUploaded, expectedVertices * stub.VERTEX_COMPONENTS))

  local materialsAfterFirst = stub.counts.materials
  check(materialsAfterFirst - materialsBefore == 1, "one material per texture page")

  -- Second frame must not create any new materials.
  pass.draws = 0
  stub.counts.vertexFloatsUploaded = 0
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
  stub.counts.vertexFloatsUploaded = 0
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
  check(stub.counts.vertexFloatsUploaded == expectedVertices * stub.VERTEX_COMPONENTS,
    string.format("no duplicated vertex floats inside clipping (%d == %d)", stub.counts.vertexFloatsUploaded, expectedVertices * stub.VERTEX_COMPONENTS))

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
  stub.counts.vertexFloatsUploaded = 0
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
  check(stub.counts.vertexFloatsUploaded == expectedVertices * stub.VERTEX_COMPONENTS,
    string.format("all vertices uploaded exactly once (%d == %d floats)", stub.counts.vertexFloatsUploaded, expectedVertices * stub.VERTEX_COMPONENTS))
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
section("render order: clipping and state changes keep attachment order")

do
  stub.passStencil = true

  local function drawOrderFor(data)
    local inst = spine.loadSkeleton(data,
      assetPath("basic_usage/assets/spineboy/spineboy.atlas"), 1)
    local order = {}
    local originalFlush = inst.renderer.flushBatches
    inst.renderer.flushBatches = function(self, batch, pass)
      for _, group in ipairs(batch.order) do
        table.insert(order, group.blendMode)
      end
      return originalFlush(self, batch, pass)
    end

    local pass = stub.newPass()
    spine.draw(inst, pass, 0, 0, -2, 1, 1, 1, 0)
    inst.renderer.flushBatches = originalFlush
    return order
  end

  local region = { type = "region", path = "eye_indifferent", width = 10, height = 10 }
  local clip = {
    type = "clipping", vertexCount = 4,
    vertices = { -50, -50, 50, -50, 50, 50, -50, 50 },
  }

  -- Interleaved normal/additive attachments must stay in slot order.
  local interleaved = {
    skeleton = { spine = "4.2.00", width = 100, height = 100 },
    bones = { { name = "root" } },
    slots = {
      { name = "a", bone = "root", attachment = "img" },
      { name = "b", bone = "root", attachment = "img", blend = "additive" },
      { name = "c", bone = "root", attachment = "img" },
    },
    skins = { default = {
      a = { img = region },
      b = { img = region },
      c = { img = region },
    } },
    animations = {},
  }

  local order = drawOrderFor(interleaved)
  check(table.concat(order, ",") == "normal,additive,normal",
    "interleaved states preserve order (got " .. table.concat(order, ",") .. ")")

  -- A clipping attachment must not jump ahead of attachments before the clip.
  local clipped = {
    skeleton = { spine = "4.2.00", width = 100, height = 100 },
    bones = { { name = "root" } },
    slots = {
      { name = "a", bone = "root", attachment = "img" },
      { name = "clip", bone = "root", attachment = "clip" },
      { name = "b", bone = "root", attachment = "img", blend = "additive" },
    },
    skins = { default = {
      a = { img = region },
      clip = { clip = clip },
      b = { img = region },
    } },
    animations = {},
  }

  order = drawOrderFor(clipped)
  check(table.concat(order, ",") == "normal,additive",
    "clipped attachments keep pre-clip order (got " .. table.concat(order, ",") .. ")")
end

---------------------------------------------------------------------------
section("colors: skeleton, slot, and attachment tints multiply")

do
  local inst = loadHighLevel("spine_playground/assets/mix-and-match/mix-and-match-pro.json",
    "spine_playground/assets/mix-and-match/mix-and-match-pro.atlas", 0.004)
  inst.skeleton:setSkin("full-skins/girl")
  inst.skeleton:setSlotsToSetupPose()
  inst.skeleton:setColor(0.5, 0.25, 1, 0.5)

  local slot = inst.skeleton:findSlot("hair-patch")
  local attachment = slot and slot.attachment
  check(slot ~= nil and attachment ~= nil and attachment.region ~= nil,
    "hair-patch attachment loaded from the girl skin")

  if attachment then
    slot.darkColor = { r = 0.2, g = 0.4, b = 0.6, a = 1 }
    local batch = { groups = {}, order = {}, lastKey = nil }
    inst.renderer:collectAttachment(batch, slot, attachment, stub.newPass())
    local group = batch.order[1]
    local color
    if group and group.vertices[9] then
      -- Flat layout: x,y,z, u,v, r,g,b,a, darkR,darkG,darkB,darkA.
      color = { group.vertices[6], group.vertices[7], group.vertices[8], group.vertices[9] }
    end
    check(color ~= nil, "collectAttachment produced a vertex color")

    local alpha = 0.5 * slot.color.a * attachment.color.a
    local expectedR = 0.5 * slot.color.r * attachment.color.r
    local expectedG = 0.25 * slot.color.g * attachment.color.g
    local expectedB = 1 * slot.color.b * attachment.color.b
    if group and group.pma then
      expectedR, expectedG, expectedB = expectedR * alpha, expectedG * alpha, expectedB * alpha
    end

    check(color and approx(color[1], expectedR) and approx(color[2], expectedG)
      and approx(color[3], expectedB) and approx(color[4], alpha),
      string.format("vertex color is skeleton*slot*attachment (got %.4f,%.4f,%.4f,%.4f)",
        color and color[1] or -1, color and color[2] or -1,
        color and color[3] or -1, color and color[4] or -1))

    if group and group.pma and group.darkColor then
      check(approx(group.darkColor.r, 0.2 * alpha)
        and approx(group.darkColor.g, 0.4 * alpha)
        and approx(group.darkColor.b, 0.6 * alpha),
        "dark color is premultiplied by the final alpha")
    end
  end
end

---------------------------------------------------------------------------
section("deform timeline vertices are scaled with the skeleton")

do
  local inst = loadHighLevel("spine_playground/assets/spineboy-pro/spineboy-pro.json",
    "spine_playground/assets/spineboy-pro/spineboy-pro.atlas", 0.004)
  local deformTimelines, maxAbs = 0, 0

  for _, animation in pairs(inst.skeletonData.animations) do
    for _, timeline in ipairs(animation.timelines) do
      if timeline.vertices then
        deformTimelines = deformTimelines + 1
        for _, vertices in pairs(timeline.vertices) do
          for _, value in ipairs(vertices) do
            maxAbs = math.max(maxAbs, math.abs(value))
          end
        end
      end
    end
  end

  check(deformTimelines > 0, "found deform timelines in spineboy-pro")
  check(maxAbs < 1, string.format(
    "deform offsets are in skeleton units, not pixels (max abs %.3f)", maxAbs))
end

---------------------------------------------------------------------------
section("drawOrder timelines reorder slots and reset with the setup pose")

do
  local inst = loadHighLevel("spine_playground/assets/alien/alien.json",
    "spine_playground/assets/alien/alien.atlas", 0.003)
  local function orderString()
    local names = {}
    for i, slot in ipairs(inst.skeleton.drawOrder) do names[i] = slot.data.name end
    return table.concat(names, ",")
  end

  local setupOrder = orderString()
  inst.animationState:setAnimation(0, "death", false)
  for _ = 1, 60 do spine.update(inst, 1 / 60) end -- t = 1.0: splat01 offset 7

  check(orderString() ~= setupOrder, "drawOrder timeline changed the slot order")
  local last = inst.skeleton.drawOrder[#inst.skeleton.drawOrder]
  check(last and last.data.name == "splat01",
    "splat01 moved to the end of the draw order (got " ..
    tostring(last and last.data.name) .. ")")

  inst.skeleton:setToSetupPose()
  check(orderString() == setupOrder, "setToSetupPose restores setup draw order")
end

---------------------------------------------------------------------------
section("events at time zero fire exactly once")

do
  local data = {
    skeleton = { spine = "4.2.00", width = 10, height = 10 },
    bones = { { name = "root" } },
    slots = {},
    skins = { default = {} },
    events = { step = {} },
    animations = {
      a = {
        events = {
          { time = 0, name = "step" },
          { time = 0.5, name = "step" },
        },
      },
    },
  }

  local inst = spine.loadSkeleton(data)
  local received = {}
  inst.animationState:addListener({
    event = function(_, event) table.insert(received, event.time) end,
  })

  inst.animationState:setAnimation(0, "a", false)
  inst.animationState:update(0)
  inst.animationState:apply(inst.skeleton)
  check(#received == 1 and received[1] == 0, "event at t=0 fired on the first apply")

  for _ = 1, 31 do
    inst.animationState:update(1 / 60)
    inst.animationState:apply(inst.skeleton)
  end
  check(#received == 2 and received[2] == 0.5,
    "event at t=0.5 fired once (" .. table.concat(received, ",") .. ")")

  -- Looping animations must not treat their first frame as a wrap-around.
  local looping = spine.loadSkeleton(data)
  local loopEvents = {}
  looping.animationState:addListener({
    event = function(_, event) table.insert(loopEvents, event.time) end,
  })
  looping.animationState:setAnimation(0, "a", true)
  looping.animationState:update(0)
  looping.animationState:apply(looping.skeleton)
  check(#loopEvents == 1 and loopEvents[1] == 0,
    "looping animation fires its t=0 event on the first apply")
end

---------------------------------------------------------------------------
section("atlas: multi-page parsing, filters, and raw atlas text")

do
  local atlas = spine.TextureAtlas.new()
  local text = [[spineboy.png
size: 64, 64
format: RGBA8888
filter: Linear, Linear
repeat: none

regionA
  rotate: false
  xy: 0, 0
  size: 32, 32
  orig: 32, 32
  offset: 0, 0
  index: -1

spineboy.png
size: 64, 64
format: RGBA8888
filter: Nearest, Linear
repeat: none
regionB
  rotate: false
  xy: 0, 0
  size: 32, 32
  orig: 32, 32
  offset: 0, 0
  index: -1
]]

  local ok, err = atlas:loadAtlasFile(text,
    assetPath("basic_usage/assets/spineboy"))
  check(ok, "multi-page atlas parsed: " .. tostring(err))
  check(#atlas.pages == 2, "multi-page atlas has 2 pages (got " .. #atlas.pages .. ")")
  check(#atlas.regions == 2, "multi-page atlas has 2 regions (got " .. #atlas.regions .. ")")
  check(atlas.regionsByName.regionA and atlas.regionsByName.regionA.page == atlas.pages[1],
    "regionA belongs to page 1")
  check(atlas.regionsByName.regionB and atlas.regionsByName.regionB.page == atlas.pages[2],
    "regionB belongs to page 2")
  check(atlas.pages[2].minFilter == "Nearest", "page 2 nearest filter parsed with spaces")
  atlas:dispose()

  local atlasPath = assetPath("basic_usage/assets/spineboy/spineboy.atlas")
  local rawAtlas = lovr.filesystem.read(atlasPath)
  check(rawAtlas ~= nil, "read raw atlas text")
  local inst = spine.loadSkeleton(
    assetPath("basic_usage/assets/spineboy/spineboy.json"), rawAtlas, 0.005)
  check(inst.atlas ~= nil and #inst.atlas.pages == 1,
    "raw atlas text loads an atlas")

  local drawable = 0
  for _, slot in ipairs(inst.skeleton.drawOrder) do
    if slot.attachment and slot.attachment.region and slot.attachment.region.texture then
      drawable = drawable + 1
    end
  end
  check(drawable > 0, "raw atlas text binds attachment regions")
  spine.release(inst)

  check(spine.utils.joinPath("", "spineboy.png") == "spineboy.png",
    "joinPath skips an empty image root")
end

---------------------------------------------------------------------------
section("bounding boxes: vertices are parsed and transformed")

do
  local inst = loadHighLevel("spine_playground/assets/spineboy-pro/spineboy-pro.json",
    "spine_playground/assets/spineboy-pro/spineboy-pro.atlas", 0.004)
  local skin = inst.skeletonData.skins.default
  local slotIndex = inst.skeleton:findSlotIndex("head-bb")
  local attachment = skin and skin:getAttachment(slotIndex, "head")
  check(attachment ~= nil and attachment.type == "boundingbox",
    "head-bb bounding box exists")
  check(attachment ~= nil and #attachment.vertices == 12,
    "bounding box vertices parsed (got " ..
    tostring(attachment and #attachment.vertices) .. ")")

  local slot = inst.skeleton:findSlot("head-bb")
  if attachment and slot then
    slot:setAttachment(attachment)
    local worldVertices = {}
    attachment:computeWorldVertices(slot, worldVertices)
    check(#worldVertices == 12, "bounding box produces 12 world coordinates")

    local bone = slot.bone
    local vx, vy = attachment.vertices[1], attachment.vertices[2]
    local expectedX = vx * bone.a + vy * bone.b + bone.worldX
    local expectedY = vx * bone.c + vy * bone.d + bone.worldY
    check(approx(worldVertices[1], expectedX) and approx(worldVertices[2], expectedY),
      "bounding box is transformed by its slot bone")
  end

  spine.release(inst)
end

---------------------------------------------------------------------------
section("skeleton scale and physics reference units")

do
  local inst = loadHighLevel("spine_playground/assets/sack/sack-pro.json",
    "spine_playground/assets/sack/sack.atlas", 0.004)
  check(approx(inst.skeletonData.referenceScale, 0.4),
    "referenceScale defaults to 100 * skeleton scale (got " ..
    tostring(inst.skeletonData.referenceScale) .. ")")
  local physics = inst.skeletonData.physicsConstraints[1]
  check(physics ~= nil and approx(physics._x, 1) and approx(physics._y, 1),
    "physics channel strengths are not scaled by world units")
  spine.release(inst)

  local data = {
    skeleton = { spine = "4.2.00", width = 10, height = 10 },
    bones = { { name = "root", x = 10, y = 5 } },
    slots = {},
    skins = { default = {} },
    animations = {},
  }
  local scaled = spine.loadSkeleton(data)
  scaled.skeleton:setScale(2, 3)
  scaled.skeleton:updateWorldTransform()
  local root = scaled.skeleton.bones[1]
  check(approx(root.worldX, 20) and approx(root.worldY, 15),
    "skeleton scale moves root bones")
  check(approx(root.a, 2) and approx(root.d, 3),
    "skeleton scale multiplies root bone axes")
  spine.release(scaled)
end

---------------------------------------------------------------------------
section("reference poses: bone matrices match Spine 4.2")

do
  local input = lovr.filesystem.read("tests/fixtures/reference/pose_input.json")
  local expectedText = lovr.filesystem.read("tests/fixtures/reference/pose_expected.json")
  check(input ~= nil and expectedText ~= nil, "reference fixtures readable")

  local data = spine.utils.jsonDecode(input)
  local expected = spine.utils.jsonDecode(expectedText)
  check(data ~= nil and expected ~= nil, "reference fixtures parse")

  local inst = spine.loadSkeleton(data)
  local state = inst.animationState
  state:setAnimation(0, "move", false)

  local previousTime = 0
  for _, time in ipairs(expected.times) do
    state:update(time - previousTime)
    state:apply(inst.skeleton)
    inst.skeleton:updateWorldTransform()
    previousTime = time

    local expectedBones = expected.bones[tostring(time)]
    local mismatch = nil
    for _, bone in ipairs(inst.skeleton.bones) do
      local reference = expectedBones and expectedBones[bone.data.name]
      if not reference then
        mismatch = "missing reference for " .. bone.data.name
        break
      end

      local actual = { bone.worldX, bone.worldY, bone.a, bone.b, bone.c, bone.d }
      for i = 1, 6 do
        if not approx(actual[i], reference[i], 1e-5) then
          mismatch = string.format("%s[%d] at t=%.3f: %.6f ~= %.6f",
            bone.data.name, i, time, actual[i], reference[i])
          break
        end
      end
      if mismatch then break end
    end

    check(mismatch == nil, mismatch or ("reference pose matches at t=" .. time))
  end

  spine.release(inst)
end

---------------------------------------------------------------------------
section("reference timelines: looping and multi-track playback")

do
  local input = lovr.filesystem.read("tests/fixtures/reference/timeline_input.json")
  local expectedText = lovr.filesystem.read("tests/fixtures/reference/timeline_expected.json")
  check(input ~= nil and expectedText ~= nil, "timeline reference fixtures readable")

  local data = spine.utils.jsonDecode(input)
  local expected = spine.utils.jsonDecode(expectedText)
  check(data ~= nil and expected ~= nil, "timeline reference fixtures parse")

  local function compareBone(bone, reference, label, time)
    local actual = { bone.worldX, bone.worldY, bone.a, bone.b, bone.c, bone.d }
    for i = 1, 6 do
      if not approx(actual[i], reference[i], 1e-4) then
        return string.format("%s[%d] at t=%.3f: %.6f ~= %.6f",
          label, i, time, actual[i], reference[i])
      end
    end
    return nil
  end

  local loopInst = spine.loadSkeleton(data)
  local loopState = loopInst.animationState
  loopState:setAnimation(0, "loop", true)
  local previousTime = 0
  for _, time in ipairs(expected.loop.times) do
    loopState:update(time - previousTime)
    loopState:apply(loopInst.skeleton)
    loopInst.skeleton:updateWorldTransform()
    previousTime = time
    local mismatch = compareBone(loopInst.skeleton:findBone("child"),
      expected.loop.bones[tostring(time)].child, "loop child", time)
    check(mismatch == nil, mismatch or ("looping reference matches at t=" .. time))
  end
  spine.release(loopInst)

  local multiInst = spine.loadSkeleton(data)
  local multiState = multiInst.animationState
  multiState:setAnimation(0, "base", true)
  multiState:setAnimation(1, "overlay", true)
  multiState.tracks[1].alpha = 0.5
  previousTime = 0
  for _, time in ipairs(expected.multitrack.times) do
    multiState:update(time - previousTime)
    multiState:apply(multiInst.skeleton)
    multiInst.skeleton:updateWorldTransform()
    previousTime = time
    local mismatch = compareBone(multiInst.skeleton:findBone("child"),
      expected.multitrack.bones[tostring(time)].child, "multitrack child", time)
    check(mismatch == nil, mismatch or ("multi-track reference matches at t=" .. time))
  end
  spine.release(multiInst)
end

---------------------------------------------------------------------------
section("reference constraints: IK")

do
  local input = lovr.filesystem.read("tests/fixtures/reference/ik_input.json")
  local expectedText = lovr.filesystem.read("tests/fixtures/reference/ik_expected.json")
  check(input ~= nil and expectedText ~= nil, "IK reference fixtures readable")

  local data = spine.utils.jsonDecode(input)
  local expected = spine.utils.jsonDecode(expectedText)
  check(data ~= nil and expected ~= nil, "IK reference fixtures parse")

  local inst = spine.loadSkeleton(data)
  inst.skeleton:updateWorldTransform()
  local mismatch = nil
  for _, bone in ipairs(inst.skeleton.bones) do
    local reference = expected[bone.data.name]
    if not reference then
      mismatch = "missing IK reference for " .. bone.data.name
      break
    end
    local actual = { bone.worldX, bone.worldY, bone.a, bone.b, bone.c, bone.d }
    for i = 1, 6 do
      if not approx(actual[i], reference[i], 1e-4) then
        mismatch = string.format("IK %s[%d]: %.6f ~= %.6f",
          bone.data.name, i, actual[i], reference[i])
        break
      end
    end
    if mismatch then break end
  end
  check(mismatch == nil, mismatch or "IK reference pose matches")
  spine.release(inst)
end

---------------------------------------------------------------------------
section("transform constraints: world/local and relative modes")

do
  local function skeletonWithTransform(transform)
    return {
      skeleton = { spine = "4.2.00", width = 100, height = 100 },
      bones = {
        { name = "root" },
        { name = "target", parent = "root", x = 10, y = 20, rotation = 45,
          scaleX = 2, scaleY = 1.5 },
        { name = "bone", parent = "root", x = 1, y = 2, rotation = 10,
          scaleX = 1.5, scaleY = 1.5 },
      },
      slots = {},
      skins = { default = {} },
      transform = { transform },
      animations = {},
    }
  end

  local absoluteLocal = spine.loadSkeleton(skeletonWithTransform({
    name = "t", bones = { "bone" }, target = "target",
    ["local"] = true, x = 3, y = 4, rotation = 5,
    scaleX = 0.5, scaleY = 0.25,
    mixRotate = 1, mixX = 1, mixY = 1,
    mixScaleX = 1, mixScaleY = 1, mixShearY = 0,
  }))
  absoluteLocal.skeleton:updateWorldTransform()
  local bone = absoluteLocal.skeleton:findBone("bone")
  check(approx(bone.ax, 13) and approx(bone.ay, 24),
    "absolute local translation follows target + offset")
  check(approx(bone.arotation, 50), "absolute local rotation follows target + offset")
  check(approx(bone.ascaleX, 5/3, 1e-5) and approx(bone.ascaleY, 7/6, 1e-5),
    "absolute local scale follows target + offset")
  spine.release(absoluteLocal)

  local relativeLocal = spine.loadSkeleton(skeletonWithTransform({
    name = "t", bones = { "bone" }, target = "target",
    ["local"] = true, relative = true, x = 3, y = 4, rotation = 5,
    scaleX = 0.5, scaleY = 0.25,
    mixRotate = 1, mixX = 1, mixY = 1,
    mixScaleX = 1, mixScaleY = 1, mixShearY = 0,
  }))
  relativeLocal.skeleton:updateWorldTransform()
  bone = relativeLocal.skeleton:findBone("bone")
  check(approx(bone.ax, 14) and approx(bone.ay, 26),
    "relative local translation adds target + offset")
  check(approx(bone.arotation, 60), "relative local rotation adds target + offset")
  check(approx(bone.ascaleX, 3.75) and approx(bone.ascaleY, 2.625),
    "relative local scale multiplies target scale")

  -- Relative local constraints must not accumulate across frames.
  relativeLocal.skeleton:updateWorldTransform()
  check(approx(bone.ax, 14) and approx(bone.arotation, 60),
    "relative local constraint is stable across repeated updates")
  spine.release(relativeLocal)

  local world = spine.loadSkeleton({
    skeleton = { spine = "4.2.00", width = 100, height = 100 },
    bones = {
      { name = "root" },
      { name = "target", parent = "root", x = 100, y = 0 },
      { name = "bone", parent = "root", x = 0, y = 0 },
    },
    slots = {},
    skins = { default = {} },
    transform = { {
      name = "t", bones = { "bone" }, target = "target",
      x = 10,
      mixRotate = 0, mixX = 1, mixY = 0,
      mixScaleX = 0, mixScaleY = 0, mixShearY = 0,
    } },
    animations = {},
  })
  world.skeleton:updateWorldTransform()
  bone = world.skeleton:findBone("bone")
  check(approx(bone.worldX, 110) and approx(bone.worldY, 0),
    "absolute world translation uses target world transform")
  spine.release(world)

  local shear = spine.loadSkeleton({
    skeleton = { spine = "4.2.00", width = 100, height = 100 },
    bones = {
      { name = "root" },
      { name = "target", parent = "root", shearY = 30 },
      { name = "bone", parent = "root" },
    },
    slots = {},
    skins = { default = {} },
    transform = { {
      name = "t", bones = { "bone" }, target = "target",
      mixRotate = 0, mixX = 0, mixY = 0,
      mixScaleX = 0, mixScaleY = 0, mixShearY = 1,
    } },
    animations = {},
  })
  shear.skeleton:updateWorldTransform()
  bone = shear.skeleton:findBone("bone")
  check(approx(bone.ashearY, 30, 1e-4), "world shear follows target shear")
  spine.release(shear)
end

---------------------------------------------------------------------------
section("physics: global timelines honor per-constraint Global flags")

do
  local data = {
    skeleton = { spine = "4.2.00", width = 100, height = 100 },
    bones = {
      { name = "root" },
      { name = "bob", parent = "root", length = 10 },
      { name = "tail", parent = "root", length = 10 },
    },
    slots = {},
    skins = { default = {} },
    physics = {
      { name = "p", bone = "bob", x = 1, y = 1, inertia = 1, strength = 100,
        damping = 1, mass = 1, wind = 0, gravity = 0, mix = 1, inertiaGlobal = true },
      { name = "q", bone = "tail", x = 1, y = 1, inertia = 1, strength = 100,
        damping = 1, mass = 1, wind = 0, gravity = 0, mix = 1, inertiaGlobal = false },
    },
    animations = {
      a = {
        physics = {
          [""] = { inertia = {
            { time = 0, value = 0.2 },
            { time = 1, value = 0.8 },
          } },
          p = { strength = {
            { time = 0, value = 33 },
            { time = 1, value = 44 },
          } },
        },
      },
    },
  }

  local inst = spine.loadSkeleton(data)
  check(#inst.skeletonData.physicsConstraints == 2, "loaded two physics constraints")
  check(inst.skeletonData.physicsConstraints[1].inertiaGlobal == true,
    "inertiaGlobal flag parsed")

  inst.animationState:setAnimation(0, "a", false)
  inst.animationState:update(0)
  inst.animationState:apply(inst.skeleton)

  check(approx(inst.skeleton.physicsConstraints[1].inertia, 0.2),
    "global timeline applies to opted-in constraint")
  check(approx(inst.skeleton.physicsConstraints[2].inertia, 1),
    "global timeline ignores non-global constraint")
  check(approx(inst.skeleton.physicsConstraints[1].strength, 33),
    "specific physics timeline still applies")

  spine.release(inst)
end

---------------------------------------------------------------------------
section("mesh UVs account for trimmed and rotated atlas regions")

do
  local inst = loadHighLevel("spine_playground/assets/mix-and-match/mix-and-match-pro.json",
    "spine_playground/assets/mix-and-match/mix-and-match-pro.atlas", 0.004)
  local target

  for _, skin in pairs(inst.skeletonData.skins) do
    for _, attachments in pairs(skin.attachments) do
      for _, attachment in pairs(attachments) do
        if not target and attachment.type == "mesh" and attachment.name == "bag-strap-back" then
          target = attachment
        end
      end
    end
  end

  check(target ~= nil and target.region ~= nil, "found trimmed rotated mesh")
  if target then
    local region = target.region
    check(region.rotate == true, "bag-strap-back uses a rotated region")
    check((region.offsetX or 0) ~= 0 or (region.offsetY or 0) ~= 0,
      "bag-strap-back region is trimmed")

    local minU, maxU, minV, maxV = math.huge, -math.huge, math.huge, -math.huge
    for i = 1, #target.uvs, 2 do
      local u, v = target.uvs[i], target.uvs[i + 1]
      minU, maxU = math.min(minU, u), math.max(maxU, u)
      minV, maxV = math.min(minV, v), math.max(maxV, v)
    end

    local expectedUSpan = region.originalHeight / region.textureWidth
    local expectedVSpan = region.originalWidth / region.textureHeight
    check(maxU - minU > expectedUSpan * 0.9 and maxU - minU <= expectedUSpan * 1.01,
      string.format("rotated U span uses original height (%.5f vs %.5f)",
        maxU - minU, expectedUSpan))
    check(maxV - minV > expectedVSpan * 0.9 and maxV - minV <= expectedVSpan * 1.01,
      string.format("rotated V span uses original width (%.5f vs %.5f)",
        maxV - minV, expectedVSpan))
  end

  spine.release(inst)
end

---------------------------------------------------------------------------
section("triangulation handles reflex vertices on ear edges")

do
  local points = { 0, 0, 100, 0, 100, 50, 50, 50, 50, 100, 0, 100 }
  local indices = spine.utils.triangulate(points)
  check(#indices == 12, "L-shaped polygon triangulates into 4 triangles")

  local area = 0
  for i = 1, #indices, 3 do
    local a, b, c = indices[i] * 2 + 1, indices[i + 1] * 2 + 1, indices[i + 2] * 2 + 1
    local x1, y1 = points[a], points[a + 1]
    local x2, y2 = points[b], points[b + 1]
    local x3, y3 = points[c], points[c + 1]
    area = area + math.abs((x2 - x1) * (y3 - y1) - (x3 - x1) * (y2 - y1)) / 2
  end
  check(approx(area, 7500, 1e-6), "triangulated area matches the L-shaped polygon")
end

---------------------------------------------------------------------------
section("skins: activate skin bones and constraints")

do
  local inst = loadHighLevel("spine_playground/assets/mix-and-match/mix-and-match-pro.json",
    "spine_playground/assets/mix-and-match/mix-and-match-pro.atlas", 0.004)

  local bone = inst.skeleton:findBone("hat-base")
  local hatConstraint, skirtConstraint
  for _, constraint in ipairs(inst.skeleton.transformConstraints) do
    if constraint.data.name == "hat-control" then hatConstraint = constraint end
    if constraint.data.name == "skirt-rotation-front" then skirtConstraint = constraint end
  end

  check(bone ~= nil and bone.active == false,
    "skin-required bone starts inactive without a skin")
  check(hatConstraint ~= nil and hatConstraint.active == false,
    "skin-required constraint starts inactive without a skin")

  inst.skeleton:setSkin("full-skins/girl")
  check(bone.active == true, "skin activates its listed bones")
  check(hatConstraint.active == true, "skin activates its listed constraints")
  check(skirtConstraint ~= nil and skirtConstraint.active == false,
    "constraints from other skins stay inactive")

  spine.release(inst)
end

---------------------------------------------------------------------------
section("asset cache: hits skip JSON parsing; table inputs are not address-keyed")

do
  spine.clearAssetCache()
  local originalDecode = spine.utils.jsonDecode
  local parses = 0
  spine.utils.jsonDecode = function(text)
    parses = parses + 1
    return originalDecode(text)
  end

  local ok, err = pcall(function()
    local a = loadHighLevel("basic_usage/assets/spineboy/spineboy.json",
      "basic_usage/assets/spineboy/spineboy.atlas", 0.005)
    local b = loadHighLevel("basic_usage/assets/spineboy/spineboy.json",
      "basic_usage/assets/spineboy/spineboy.atlas", 0.005)
    check(parses == 1, "second cached load does not parse JSON (parses=" .. parses .. ")")
    check(a.skeletonData == b.skeletonData, "cached path loads share SkeletonData")
    spine.release(a)
    spine.release(b)
  end)
  spine.utils.jsonDecode = originalDecode
  check(ok, "cache test completed: " .. tostring(err))

  local function tableAsset(boneName)
    return {
      skeleton = { spine = "4.2.00", width = 10, height = 10 },
      bones = { { name = boneName } },
      slots = {},
      skins = { default = {} },
      animations = {},
    }
  end

  local first = spine.loadSkeleton(tableAsset("boneA"))
  local second = spine.loadSkeleton(tableAsset("boneB"))
  check(first.skeletonData ~= second.skeletonData,
    "distinct decoded tables are not merged by address")
  check(first.skeletonData.bones[1].name == "boneA"
    and second.skeletonData.bones[1].name == "boneB",
    "decoded table inputs keep their own skeleton data")
  spine.release(first)
  spine.release(second)
end

---------------------------------------------------------------------------
section("lifecycle: release defers texture disposal until the last instance")

do
  spine.clearAssetCache()
  local a = loadHighLevel("basic_usage/assets/spineboy/spineboy.json",
    "basic_usage/assets/spineboy/spineboy.atlas", 0.005)
  local b = loadHighLevel("basic_usage/assets/spineboy/spineboy.json",
    "basic_usage/assets/spineboy/spineboy.atlas", 0.005)
  local texture = a.atlas.pages[1].texture

  check(a.atlas == b.atlas, "lifecycle test instances share the atlas")
  check(not texture.released, "shared texture starts alive")

  spine.release(a)
  check(not texture.released, "releasing one instance keeps shared texture alive")

  local pass = stub.newPass()
  spine.draw(b, pass, 0, 0, -2, 0.005, 0.005, 0.005, 0)
  check(not texture.released, "remaining instance can still draw")

  spine.release(b)
  check(texture.released, "texture is released after the last instance")

  local c = loadHighLevel("basic_usage/assets/spineboy/spineboy.json",
    "basic_usage/assets/spineboy/spineboy.atlas", 0.005)
  local texture2 = c.atlas.pages[1].texture
  check(texture2 ~= texture, "released cache entry is reloaded on demand")

  spine.clearAssetCache()
  check(not texture2.released,
    "clearAssetCache keeps textures used by live instances alive")

  spine.release(c)
  check(texture2.released, "live instance release disposes its detached entry")
  check(spine.release(c) == false, "release is idempotent")
  check(not pcall(spine.draw, c, stub.newPass(), 0, 0, -2, 1, 1, 1, 0),
    "released instances cannot be drawn")
end

---------------------------------------------------------------------------
print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
