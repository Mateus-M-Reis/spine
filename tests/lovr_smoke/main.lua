-- Real-LÖVR smoke test. tests/run_lovr_smoke.sh stages this project in a
-- temporary directory together with the runtime and one example asset set.
local spine = require("init")

local instance
local frames = 0

function lovr.load()
  instance = spine.loadSkeleton(
    "assets/spineboy/spineboy.json",
    "assets/spineboy/spineboy.atlas",
    0.005)
  assert(instance and instance.skeleton and instance.renderer, "loadSkeleton failed")
  assert(instance.animationState, "skeleton has no animation state")
  instance.animationState:setAnimation(0, "walk", true)
  print("LOVR_SMOKE_LOADED", #instance.skeletonData.bones, #instance.skeletonData.slots)
end

function lovr.update(dt)
  if instance then
    spine.update(instance, dt)
  end
end

function lovr.draw(pass)
  if not instance then return end

  spine.draw(instance, pass, 0, 0, -3, 0.005, 0.005, 0.005, 0)
  frames = frames + 1

  if frames == 5 then
    assert(instance.renderer.drawCalls > 0, "renderer issued no draw calls")
    assert(instance.renderer.vertexCount > 0, "renderer uploaded no vertices")
    print("LOVR_SMOKE_OK", instance.renderer.drawCalls, instance.renderer.vertexCount)
    lovr.event.quit()
  end
end
