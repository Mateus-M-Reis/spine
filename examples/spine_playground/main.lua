-- Spine LÖVR Runtime - Interactive Playground
-- Load Spine exports and play animations interactively.
--
-- Run: cd examples/spine_playground && lovr .
--
-- This is a port of the original Love2D playground to LÖVR. The skeleton is
-- drawn in 3D world space, and the HUD panels are fixed in world space in
-- front of the default desktop camera. The UI is keyboard-driven.

-- Add parent directory to the package path so we can require the runtime.
package.path = package.path .. ";../../?.lua"
local spine = require("init")

-- Configuration: change these to load different Spine characters.
local CONFIG = {
    -- Current asset to load (any key of `assets` below).
    currentAsset = "spineboy_pro",

    assets = {
        mix_and_match = { atlas = "assets/mix-and-match/mix-and-match-pro.atlas", json = "assets/mix-and-match/mix-and-match-pro.json", scale = 0.004 },
        spineboy_pro  = { atlas = "assets/spineboy-pro/spineboy-pro.atlas",   json = "assets/spineboy-pro/spineboy-pro.json",   scale = 0.004 },
        spineboy_ess  = { atlas = "assets/spineboy_ess/spineboy.atlas",       json = "assets/spineboy_ess/spineboy-ess.json",  scale = 0.004 },
        stretchyman   = { atlas = "assets/stretchyman/stretchyman-pro.atlas",  json = "assets/stretchyman/stretchyman-pro.json", scale = 0.004 },
        coin          = { atlas = "assets/coin/coin.atlas",                    json = "assets/coin/coin-pro.json",             scale = 0.004 },
        alien         = { atlas = "assets/alien/alien.atlas",                  json = "assets/alien/alien.json",               scale = 0.003 },
        alien_pro     = { atlas = "assets/alien-pro/alien-pro.atlas",          json = "assets/alien-pro/alien-pro.json",       scale = 0.003 },
        windmill      = { atlas = "assets/windmill/windmill.atlas",            json = "assets/windmill/windmill-ess.json",     scale = 0.004 },
        tank          = { atlas = "assets/tank/tank-pro.atlas",                json = "assets/tank/tank-pro.json",             scale = 0.004 },
        sack          = { atlas = "assets/sack/sack.atlas",                    json = "assets/sack/sack-pro.json",             scale = 0.004 },
        cloud_pot     = { atlas = "assets/cloud-pot/cloud-pot.atlas",          json = "assets/cloud-pot/cloud-pot.json",       scale = 0.004 },
        powerup       = { atlas = "assets/powerup/powerup.atlas",              json = "assets/powerup/powerup-pro.json",       scale = 0.006 },
    },
}

local playground = {
    instance = nil, -- high-level instance from spine.loadSkeleton

    animations = {},
    currentAnimation = nil,
    currentAnimationIndex = 1,

    assetNames = {},
    currentAssetIndex = 1,
    currentAssetName = nil,

    showDebug = false,
    showHelp = true,
    showHud = true,
    loadError = nil,

    -- World-space placement of the skeleton (meters).
    x = 0,
    y = 0,
    z = -3,
    zoom = 1, -- draw scale multiplier

    fps = 0,
    scrollOffset = 0,
    maxVisibleItems = 20,
    itemHeight = 0.045,
}

-- HUD layout. Panels are drawn in a camera-anchored local space (x = right,
-- y = up, z = toward the viewer) 1.2m in front of the head, so the UI follows
-- the camera and always faces the user. Sizes are in meters at that distance.
local HUD = {
    distance = 2.0,
    textScale = 0.06, -- text height in meters (bitmap font)
    assetPanel = { x = -0.68, y = 0.45, w = 0.65, headerH = 0.09, itemH = 0.045 },
    animPanel  = { x = 0.68,  y = 0.45, w = 0.65, headerH = 0.09, itemH = 0.045 },
    infoPanel  = { x = -0.68, y = -0.45, w = 0.65, headerH = 0.065, itemH = 0.04 },
}

-- Head pose (position + quaternion), with a safe fallback for builds without
-- a headset module.
local function getHeadPose()
    if lovr.headset and lovr.headset.getPose then
        local ok, x, y, z, qx, qy, qz, qw = pcall(lovr.headset.getPose)
        if ok and x then
            return x, y, z, qx, qy, qz, qw
        end
    end
    return 0, 0, 0, 0, 0, 0, 1
end

-- Builds a Mat4 that maps HUD-local coordinates to world space, anchored
-- 1.2m in front of the head and oriented with the head. Panels/text drawn in
-- this space face the user.
local function getHudTransform()
    local hx, hy, hz, qx, qy, qz, qw = getHeadPose()

    local len = math.sqrt(qx * qx + qy * qy + qz * qz + qw * qw)
    if len > 0 then
        qx, qy, qz, qw = qx / len, qy / len, qz / len, qw / len
    end

    -- Forward direction of the head (rotate (0, 0, -1) by the quaternion).
    local fx = -2 * (qx * qz - qw * qy)
    local fy = -2 * (qy * qz + qw * qx)
    local fz = -1 + 2 * (qx * qx + qy * qy)

    local ox = hx + fx * HUD.distance
    local oy = hy + fy * HUD.distance
    local oz = hz + fz * HUD.distance

    local mat = lovr.math.newMat4()
    local ok = pcall(function()
        mat:setOrientation(qx, qy, qz, qw)
    end)
    if not ok then
        -- Build without setOrientation (keeps the panels axis-aligned).
    end
    mat:translate(ox, oy, oz)
    return mat
end

local keysDown = {}
local function isDown(key)
    return keysDown[key] == true
end

----------------------------------------------------------------------------
-- Tiny 5x7 bitmap font, drawn with colored quads through the mesh pipeline.
-- Some LÖVR builds cannot render pass:text at all, so the HUD uses its own
-- font. Each glyph row is a 5-character string of '#' and '.' (left to right).

local FONT_GLYPHS = {
    ["A"] = ".##.." .. "#..#." .. "#..#." .. "#####" .. "#..#." .. "#..#." .. "#..#.",
    ["B"] = "####." .. "#..#." .. "#..#." .. "####." .. "#..#." .. "#..#." .. "####.",
    ["C"] = ".##.." .. "#..#." .. "#...." .. "#...." .. "#...." .. "#..#." .. ".##..",
    ["D"] = "####." .. "#..#." .. "#..#." .. "#..#." .. "#..#." .. "#..#." .. "####.",
    ["E"] = "#####" .. "#...." .. "#...." .. "####." .. "#...." .. "#...." .. "#####",
    ["F"] = "#####" .. "#...." .. "#...." .. "####." .. "#...." .. "#...." .. "#....",
    ["G"] = ".##.." .. "#..#." .. "#...." .. "#.###" .. "#..#." .. "#..#." .. ".###.",
    ["H"] = "#..#." .. "#..#." .. "#..#." .. "#####" .. "#..#." .. "#..#." .. "#..#.",
    ["I"] = "#####" .. "..#.." .. "..#.." .. "..#.." .. "..#.." .. "..#.." .. "#####",
    ["J"] = "..###" .. "...#." .. "...#." .. "...#." .. "...#." .. "#..#." .. ".##..",
    ["K"] = "#..#." .. "#.#.." .. "##..." .. "##..." .. "#.#.." .. "#..#." .. "#..#.",
    ["L"] = "#...." .. "#...." .. "#...." .. "#...." .. "#...." .. "#...." .. "#####",
    ["M"] = "#...#" .. "##.##" .. "#.#.#" .. "#.#.#" .. "#...#" .. "#...#" .. "#...#",
    ["N"] = "#...#" .. "##..#" .. "#.#.#" .. "#..##" .. "#...#" .. "#...#" .. "#...#",
    ["O"] = ".##.." .. "#..#." .. "#..#." .. "#..#." .. "#..#." .. "#..#." .. ".##..",
    ["P"] = "####." .. "#..#." .. "#..#." .. "####." .. "#...." .. "#...." .. "#....",
    ["Q"] = ".##.." .. "#..#." .. "#..#." .. "#..#." .. "#.#.#" .. "#..#." .. ".##.#",
    ["R"] = "####." .. "#..#." .. "#..#." .. "####." .. "#.#.." .. "#..#." .. "#..#.",
    ["S"] = ".####" .. "#...." .. "#...." .. ".###." .. "....#" .. "....#" .. "####.",
    ["T"] = "#####" .. "..#.." .. "..#.." .. "..#.." .. "..#.." .. "..#.." .. "..#..",
    ["U"] = "#..#." .. "#..#." .. "#..#." .. "#..#." .. "#..#." .. "#..#." .. ".##..",
    ["V"] = "#..#." .. "#..#." .. "#..#." .. "#..#." .. "#..#." .. ".#.#." .. "..#..",
    ["W"] = "#...#" .. "#...#" .. "#...#" .. "#.#.#" .. "#.#.#" .. "##.##" .. "#...#",
    ["X"] = "#..#." .. "#..#." .. ".#.#." .. "..#.." .. ".#.#." .. "#..#." .. "#..#.",
    ["Y"] = "#..#." .. "#..#." .. ".#.#." .. "..#.." .. "..#.." .. "..#.." .. "..#..",
    ["Z"] = "#####" .. "....#" .. "...#." .. "..#.." .. ".#..." .. "#...." .. "#####",
    ["0"] = ".##.." .. "#..#." .. "#..##" .. "#.#.#" .. "##..#" .. "#..#." .. ".##..",
    ["1"] = "..#.." .. ".##.." .. "..#.." .. "..#.." .. "..#.." .. "..#.." .. ".###.",
    ["2"] = ".##.." .. "#..#." .. "....#" .. "...#." .. "..#.." .. ".#..." .. "#####",
    ["3"] = "####." .. "....#" .. "....#" .. ".###." .. "....#" .. "....#" .. "####.",
    ["4"] = "...#." .. "..##." .. ".#.#." .. "#..#." .. "#####" .. "...#." .. "...#.",
    ["5"] = "#####" .. "#...." .. "#...." .. "####." .. "....#" .. "....#" .. "####.",
    ["6"] = ".##.." .. "#...." .. "#...." .. "####." .. "#..#." .. "#..#." .. ".##..",
    ["7"] = "#####" .. "....#" .. "...#." .. "..#.." .. ".#..." .. ".#..." .. ".#...",
    ["8"] = ".##.." .. "#..#." .. "#..#." .. ".##.." .. "#..#." .. "#..#." .. ".##..",
    ["9"] = ".##.." .. "#..#." .. "#..#." .. ".###." .. "....#" .. "....#" .. ".##..",
    [" "] = "....." .. "....." .. "....." .. "....." .. "....." .. "....." .. ".....",
    ["-"] = "....." .. "....." .. "....." .. "#####" .. "....." .. "....." .. ".....",
    [":"] = "....." .. ".##.." .. ".##.." .. "....." .. ".##.." .. ".##.." .. ".....",
    ["/"] = "....#" .. "...#." .. "...#." .. "..#.." .. ".#..." .. ".#..." .. "#....",
    ["+"] = "....." .. "..#.." .. "..#.." .. "#####" .. "..#.." .. "..#.." .. ".....",
    ["."] = "....." .. "....." .. "....." .. "....." .. "....." .. ".##.." .. ".##..",
    ["("] = "..#.." .. ".#..." .. "#...." .. "#...." .. "#...." .. ".#..." .. "..#..",
    [")"] = "..#.." .. "...#." .. "....#" .. "....#" .. "....#" .. "...#." .. "..#..",
    ["["] = ".###." .. ".#..." .. ".#..." .. ".#..." .. ".#..." .. ".#..." .. ".###.",
    ["]"] = ".###." .. "...#." .. "...#." .. "...#." .. "...#." .. "...#." .. ".###.",
    ["?"] = ".##.." .. "#..#." .. "....#" .. "...#." .. "..#.." .. "....." .. "..#..",
    ["!"] = "..#.." .. "..#.." .. "..#.." .. "..#.." .. "..#.." .. "....." .. "..#..",
    ["%"] = "##..#" .. "##..#" .. "...#." .. "..#.." .. ".#..." .. "#..##" .. "#..##",
    ["'"] = "..#.." .. "..#.." .. "....." .. "....." .. "....." .. "....." .. ".....",
    ['"'] = ".#.#." .. ".#.#." .. "....." .. "....." .. "....." .. "....." .. ".....",
    ["="] = "....." .. "....." .. "#####" .. "....." .. "#####" .. "....." .. ".....",
    ["_"] = "....." .. "....." .. "....." .. "....." .. "....." .. "....." .. "#####",
    [","] = "....." .. "....." .. "....." .. "....." .. ".##.." .. "..#.." .. ".#...",
}

-- Precomputed pixel offsets per glyph.
local FONT_PIXELS = {}
for ch, glyph in pairs(FONT_GLYPHS) do
    local pixels = {}
    for row = 1, 7 do
        local line = glyph:sub((row - 1) * 5 + 1, row * 5)
        for col = 1, 5 do
            if line:sub(col, col) == "#" then
                table.insert(pixels, { col - 1, row - 1 })
            end
        end
    end
    FONT_PIXELS[ch] = pixels
end

-- UI text collected each frame and drawn with small colored boxes. Boxes are
-- used because they render reliably across LÖVR builds (unlike text/meshes on
-- some versions).
local uiTextCmds = {}
local uiTextCount = 0

local function uiTextReset()
    uiTextCount = 0
    for i = #uiTextCmds, 1, -1 do
        uiTextCmds[i] = nil
    end
end

local function uiTextAdd(str, x, y, z, scale, r, g, b, a)
    uiTextCount = uiTextCount + 1
    uiTextCmds[uiTextCount] = { str, x, y, z, scale, r, g, b, a }
end

local function uiTextFlush(pass)
    if uiTextCount == 0 then return end
    for i = 1, uiTextCount do
        local cmd = uiTextCmds[i]
        local str, x, y, z, scale, r, g, b, a = cmd[1], cmd[2], cmd[3], cmd[4], cmd[5], cmd[6], cmd[7], cmd[8], cmd[9]
        local cell = scale / 7
        pass:setColor(r, g, b, a)
        pass:setColor(r, g, b, a)
        for c = 1, #str do
            local pixels = FONT_PIXELS[str:sub(c, c)] or FONT_PIXELS["?"]
            local cx = x + (c - 1) * cell * 6
            for _, px in ipairs(pixels) do
                local bx = cx + (px[1] + 0.5) * cell
                local by = y - (px[2] + 0.5) * cell
                local ok = pcall(pass.box, pass, bx, by, z, cell, cell, 0.005)
                if not ok then
                    pcall(pass.box, pass, bx, by, z, cell, cell, 0.005)
                end
            end
        end
    end
    uiTextReset()
end

---------------------------------------------------------------------------
-- Asset loading

local function setupMixAndMatch(skeleton, skeletonData)
    print("Applying Mix and Match skins...")
    local skinName = "full-skins/girl"
    if skeletonData.skins[skinName] then
        skeleton:setSkin(skinName)
    elseif skeletonData.skins["skin-base"] then
        print("Skin '" .. skinName .. "' not found; falling back to 'skin-base'")
        skeleton:setSkin("skin-base")
    else
        print("Warning: no mix-and-match skin found")
        return
    end
    print("Set skin: " .. skinName)
    skeleton:setSlotsToSetupPose()
    skeleton:updateWorldTransform()
end

local function loadSpineAsset(assetName)
    local asset = CONFIG.assets[assetName]
    if not asset then
        return nil, "Unknown asset: " .. assetName
    end

    -- Load via the high-level API (atlas binding and setup pose are handled).
    local ok, instance = pcall(spine.loadSkeleton, asset.json, asset.atlas, asset.scale)
    if not ok then
        return nil, tostring(instance)
    end
    playground.instance = instance
    playground.currentAssetName = assetName

    -- Animation list (sorted).
    playground.animations = {}
    for name in pairs(instance.skeletonData.animations) do
        table.insert(playground.animations, name)
    end
    table.sort(playground.animations)
    if #playground.animations == 0 then
        return nil, "No animations found in skeleton data"
    end

    -- Smooth all-to-all transitions.
    local stateData = instance.animationStateData
    for _, a in ipairs(playground.animations) do
        for _, b in ipairs(playground.animations) do
            if a ~= b then
                stateData:setMix(a, b, 0.2)
            end
        end
    end

    if assetName == "mix_and_match" then
        setupMixAndMatch(instance.skeleton, instance.skeletonData)
    end

    playground.scrollOffset = 0
    playground.zoom = 1
    setAnimation(1)

    print(string.format("Loaded %s: %d bones, %d animations", assetName,
        #instance.skeletonData.bones, #playground.animations))
    return true
end

local function setAssetByIndex(index)
    if index < 1 or index > #playground.assetNames then return end
    if index == playground.currentAssetIndex and playground.instance then return end

    playground.currentAssetIndex = index
    local ok, err = loadSpineAsset(playground.assetNames[index])
    playground.loadError = ok and nil or (err or "Failed to load assets")
end

local function shouldLoop(name)
    local n = name:lower()
    return not n:find("death") and not n:find("jump") and not n:find("shoot")
end

function setAnimation(index)
    if index < 1 or index > #playground.animations then return end
    playground.currentAnimationIndex = index
    playground.currentAnimation = playground.animations[index]
    local loop = shouldLoop(playground.currentAnimation)
    playground.instance.animationState:setAnimation(0, playground.currentAnimation, loop)
    print("Playing animation: " .. playground.currentAnimation .. (loop and " (looping)" or " (once)"))
end

---------------------------------------------------------------------------
-- LÖVR callbacks

function lovr.load()
    playground.assetNames = {}
    for name in pairs(CONFIG.assets) do
        table.insert(playground.assetNames, name)
    end
    table.sort(playground.assetNames)

    playground.currentAssetIndex = 1
    for i, name in ipairs(playground.assetNames) do
        if name == CONFIG.currentAsset then
            playground.currentAssetIndex = i
            break
        end
    end

    local ok, err = loadSpineAsset(CONFIG.currentAsset)
    if not ok then
        playground.loadError = err or "Failed to load assets"
        print("ERROR: " .. playground.loadError)
    end

    print("Spine Playground loaded. Press H for help.")
end

function lovr.update(dt)
    if playground.loadError or not playground.instance then return end

    -- Smoothed FPS estimate.
    playground.fps = playground.fps * 0.95 + (1 / math.max(dt, 1e-4)) * 0.05

    local state, skeleton = playground.instance.animationState, playground.instance.skeleton
    state:update(dt)
    state:apply(skeleton)
    skeleton:update(dt) -- advance skeleton time (physics constraints need it)
    skeleton:updateWorldTransform()

    -- Continuous input.
    local speed = 0.6 * dt
    if isDown("left") then playground.x = playground.x - speed end
    if isDown("right") then playground.x = playground.x + speed end
    if isDown("up") then playground.y = playground.y + speed end
    if isDown("down") then playground.y = playground.y - speed end
end

local function drawPanel(pass, panel, totalHeight, r, g, b, a)
    -- Some builds apply pass:setColor one draw late; call it twice so the
    -- box gets the intended color.
    pass:setColor(r, g, b, a or 1)
    pass:setColor(r, g, b, a or 1)
    -- LÖVR 0.18 uses box(mode, ...); some builds use box(...) with no mode.
    -- Try the no-mode form first: on some builds a failed mode-form call
    -- breaks later draws.
    local ok = pcall(pass.box, pass, panel.x, panel.y - totalHeight / 2, 0, panel.w, totalHeight, 0.01)
    if not ok then
        pcall(pass.box, pass, "fill", panel.x, panel.y - totalHeight / 2, 0, panel.w, totalHeight, 0.01)
    end
end

local function drawText(pass, str, x, y, r, g, b)
    uiTextAdd(str, x, y, 0.012, HUD.textScale, r or 1, g or 1, b or 1, 1)
end

local function drawListPanel(pass, panel, title, count, items, currentIndex, scrollOffset, highlightColor, getExtra)
    local maxVisible = math.min(count, playground.maxVisibleItems)
    local headerH = panel.headerH
    local itemH = panel.itemH
    local totalHeight = headerH + maxVisible * itemH

    drawPanel(pass, panel, totalHeight, 0.85, 0.85, 0.9, 1)
    drawPanel(pass, { x = panel.x, y = panel.y - headerH / 2 }, headerH, 0.15, 0.3, 0.55, 1)

    drawText(pass, title, panel.x - panel.w / 2 + 0.02, panel.y - 0.038, 1, 1, 1)
    drawText(pass, count .. " total", panel.x - panel.w / 2 + 0.02, panel.y - 0.078, 0.75, 0.75, 0.85)

    local topY = panel.y - headerH - itemH / 2
    for row = 1, maxVisible do
        local i = scrollOffset + row
        if i > count then break end
        local y = topY - (row - 1) * itemH
        local isCurrent = i == currentIndex
        if isCurrent then
            drawPanel(pass, { x = panel.x, y = y }, itemH, highlightColor[1], highlightColor[2], highlightColor[3], 1)
        end
        local label = items[i]
        if getExtra then label = getExtra(i, label) end
        drawText(pass, label, panel.x - panel.w / 2 + 0.02, y - 0.02,
            isCurrent and 1.0 or 1.0,
            isCurrent and 1.0 or 1.0,
            isCurrent and 0.9 or 1.0)
    end
end

local function drawUI(pass)
    if not playground.showHud then return end

    -- Anchor the HUD to the camera so panels always face the user.
    pass:push()
    pass:transform(getHudTransform())

    -- Reserve nothing: panels draw first, then text (see below).

    drawListPanel(pass, HUD.assetPanel, "ASSETS (N/TAB)", #playground.assetNames,
        playground.assetNames, playground.currentAssetIndex, 0,
        { 0.3, 1, 0.3 })

    drawListPanel(pass, HUD.animPanel, "ANIMS (1-9)", #playground.animations,
        playground.animations, playground.currentAnimationIndex, playground.scrollOffset,
        { 0.3, 1, 0.3 }, function(i, name) return i .. ". " .. name end)

    -- Info panel.
    local lines = {
        "Asset: " .. (playground.currentAssetName or "none"),
        "Playing: " .. (playground.currentAnimation or "none"),
        string.format("FPS: %.0f  Zoom: %.2f", playground.fps, playground.zoom),
    }
    if playground.showHelp then
        local help = {
            "KEYS: 1-9 anim",
            "[/]: scroll",
            "N/TAB: asset",
            "ARROWS: move",
            "+/-: zoom",
            "D debug  R reset",
            "Y flip  U/H hide",
        }
        for _, line in ipairs(help) do table.insert(lines, line) end
    end

    local headerH = HUD.infoPanel.headerH
    local itemH = HUD.infoPanel.itemH
    local totalHeight = headerH + #lines * itemH
    drawPanel(pass, HUD.infoPanel, totalHeight, 0.85, 0.85, 0.9, 1)
    drawPanel(pass, { x = HUD.infoPanel.x, y = HUD.infoPanel.y - headerH / 2 }, headerH, 0.15, 0.3, 0.55, 1)
    drawText(pass, "INFO", HUD.infoPanel.x - HUD.infoPanel.w / 2 + 0.02, HUD.infoPanel.y - 0.03, 1, 1, 1)

    for i, line in ipairs(lines) do
        local y = HUD.infoPanel.y - headerH - i * itemH + itemH / 2
        drawText(pass, line, HUD.infoPanel.x - HUD.infoPanel.w / 2 + 0.02, y - 0.013,
            1, 1, 1)
    end

    -- Flush all collected text quads as one mesh.
    uiTextFlush(pass)

    pass:pop()
end

function lovr.draw(pass)
    if playground.loadError then
        uiTextReset()
        uiTextAdd("ERROR: Failed to load Spine assets", -0.5, 0.15, -1.2, 0.05, 1, 0.2, 0.2, 1)
        uiTextAdd(playground.loadError, -0.5, 0.05, -1.2, 0.04, 1, 1, 1, 1)
        uiTextAdd("Check the console for details.", -0.5, -0.05, -1.2, 0.04, 0.7, 0.7, 0.7, 1)
        uiTextFlush(pass)
        return
    end

    if not playground.instance then return end

    -- Draw the skeleton in world space.
    local inst = playground.instance
    local s = playground.zoom
    inst.renderer.debug = playground.showDebug
    inst.renderer:drawSkeleton(inst.skeleton, pass,
        spine.buildTransform(playground.x, playground.y, playground.z, s, s, s, 0))

    drawUI(pass)
end

function lovr.keypressed(key)
    keysDown[key] = true

    local count = #playground.animations

    if key >= "1" and key <= "9" then
        setAnimation(tonumber(key))
    elseif key == "space" then
        setAnimation((playground.currentAnimationIndex % count) + 1)
    elseif key == "up" then
        setAnimation(playground.currentAnimationIndex - 1)
    elseif key == "down" then
        setAnimation(playground.currentAnimationIndex + 1)
    elseif key == "[" then
        playground.scrollOffset = math.max(0, playground.scrollOffset - 1)
    elseif key == "]" then
        playground.scrollOffset = math.min(
            playground.scrollOffset + 1,
            math.max(0, count - playground.maxVisibleItems))
    elseif key == "n" or key == "tab" then
        setAssetByIndex(playground.currentAssetIndex + 1)
    elseif key == "p" then
        setAssetByIndex(playground.currentAssetIndex - 1)
    elseif key == "+" or key == "=" then
        playground.zoom = math.min(playground.zoom + 0.25, 5)
    elseif key == "-" or key == "_" then
        playground.zoom = math.max(playground.zoom - 0.25, 0.05)
    elseif key == "r" then
        playground.x, playground.y, playground.z, playground.zoom = 0, 0, -3, 1
        print("Position and zoom reset")
    elseif key == "d" then
        playground.showDebug = not playground.showDebug
        print("Debug rendering: " .. tostring(playground.showDebug))
    elseif key == "y" then
        local skeleton = playground.instance and playground.instance.skeleton
        if skeleton then
            skeleton.flipY = not skeleton.flipY
            skeleton:updateWorldTransform()
            print("Flip Y: " .. tostring(skeleton.flipY))
        end
    elseif key == "b" then
        local skeleton = playground.instance and playground.instance.skeleton
        if skeleton then
            local debug_bones = require("spine.debug_bones")
            print("\n--- Debug Bone Info ---")
            debug_bones.printBoneHierarchy(skeleton)
            debug_bones.printAllBoneTransforms(skeleton)
        end
    elseif key == "h" then
        playground.showHelp = not playground.showHelp
    elseif key == "u" then
        playground.showHud = not playground.showHud
    elseif key == "escape" then
        lovr.event.quit()
    end
end

function lovr.keyreleased(key)
    keysDown[key] = nil
end
