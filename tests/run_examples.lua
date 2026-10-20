-- Headless smoke test for the example projects.
-- Loads each example's main.lua with a LÖVR stub, then runs load/update/draw
-- loops to catch runtime errors without a real LÖVR installation.
--
-- Run with: luajit tests/run_examples.lua

package.path = "./tests/?.lua;./?.lua;" .. package.path

local stub = require("stub")

local examples = {
  { dir = "examples/basic_usage", file = "main.lua" },
  { dir = "examples/spine_playground", file = "main.lua" },
}

local realRead = lovr.filesystem.read
local realIsFile = lovr.filesystem.isFile
local failures = 0

local function withExampleDir(dir, fn)
  -- Redirect relative filesystem reads to the example's directory.
  lovr.filesystem.read = function(path)
    if not path:match("^/") then
      path = dir .. "/" .. path
    end
    return realRead(path)
  end
  lovr.filesystem.isFile = function(path)
    if not path:match("^/") then
      path = dir .. "/" .. path
    end
    return realIsFile(path)
  end
  local ok, err = pcall(fn)
  lovr.filesystem.read = realRead
  lovr.filesystem.isFile = realIsFile
  return ok, err
end

for _, ex in ipairs(examples) do
  local ok, err = withExampleDir(ex.dir, function()
    local chunk = assert(loadfile(ex.dir .. "/" .. ex.file, "t",
      setmetatable({ lovr = lovr }, { __index = _G })))
    chunk()

    assert(lovr.load, "example did not define lovr.load")
    lovr.load()

    assert(lovr.update, "example did not define lovr.update")
    for _ = 1, 120 do
      lovr.update(1 / 60)
    end

    assert(lovr.draw, "example did not define lovr.draw")
    local pass = stub.newPass()
    for _ = 1, 5 do
      lovr.draw(pass)
    end
  end)

  if ok then
    print("OK   " .. ex.dir)
  else
    failures = failures + 1
    print("FAIL " .. ex.dir .. ": " .. tostring(err))
  end
end

print(string.format("\n%d example(s) failed", failures))
os.exit(failures == 0 and 0 or 1)
