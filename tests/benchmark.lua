-- Headless performance guard.
-- Run with: luajit tests/benchmark.lua
-- Thresholds are intentionally generous for shared CI machines; the goal is
-- to catch order-of-magnitude allocation/CPU regressions, not micro-benchmark
-- differences.

package.path = "./tests/?.lua;./?.lua;" .. package.path

local stub = require("stub")
local spine = require("init")

local CASES = {
  {
    name = "tank",
    json = "examples/spine_playground/assets/tank/tank-pro.json",
    atlas = "examples/spine_playground/assets/tank/tank-pro.atlas",
    scale = 0.004,
    draws = 200,
    maxMs = 5,
    maxKb = 200,
  },
  {
    name = "spineboy-pro",
    json = "examples/spine_playground/assets/spineboy-pro/spineboy-pro.json",
    atlas = "examples/spine_playground/assets/spineboy-pro/spineboy-pro.atlas",
    scale = 0.004,
    draws = 300,
    maxMs = 3,
    maxKb = 100,
  },
  {
    name = "coin-clipping",
    json = "examples/spine_playground/assets/coin/coin-pro.json",
    atlas = "examples/spine_playground/assets/coin/coin.atlas",
    scale = 0.005,
    draws = 300,
    maxMs = 3,
    maxKb = 100,
  },
}

local failures = 0

local function clearPass(pass)
  pass.blendModes = {}
  pass.shaders = {}
  pass.sends = {}
  pass.transforms = {}
  pass.draws = 0
  pass.polygons = 0
  pass.stencilWrites = {}
  pass.stencilTests = {}
  pass.colorWrites = {}
end

for _, case in ipairs(CASES) do
  local inst = spine.loadSkeleton(case.json, case.atlas, case.scale)
  local pass = stub.newPass()

  -- Warm up JIT and populate mesh/group caches.
  for _ = 1, 20 do
    inst.skeleton:updateWorldTransform()
    spine.draw(inst, pass, 0, 0, -2, case.scale, case.scale, case.scale, 0)
    clearPass(pass)
  end

  collectgarbage("collect")
  collectgarbage("stop")
  local kbBefore = collectgarbage("count")
  local started = os.clock()

  for _ = 1, case.draws do
    inst.skeleton:updateWorldTransform()
    spine.draw(inst, pass, 0, 0, -2, case.scale, case.scale, case.scale, 0)
    clearPass(pass)
  end

  local elapsedMs = (os.clock() - started) * 1000 / case.draws
  collectgarbage("restart")
  collectgarbage("collect")
  local kbPerDraw = (collectgarbage("count") - kbBefore) / case.draws

  local status = "ok"
  if elapsedMs > case.maxMs or kbPerDraw > case.maxKb then
    status = "FAIL"
    failures = failures + 1
  end

  print(string.format(
    "%-14s %s  %6.3f ms/draw  %7.1f KB/draw  draws=%d  verts=%d  (budget %g ms, %g KB)",
    case.name, status, elapsedMs, kbPerDraw, inst.renderer.drawCalls,
    inst.renderer.vertexCount, case.maxMs, case.maxKb))

  spine.release(inst)
end

if failures > 0 then
  print(string.format("%d benchmark case(s) exceeded budget", failures))
  os.exit(1)
end

print("benchmark budgets passed")
