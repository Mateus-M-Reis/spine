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

-- HUD layout (world space, meters). Panels float in front of the desktop
-- camera at z = -1.4.
local HUD = {
    z = -1.4,
    textScale = 0.0035,
    assetPanel = { x = -1.05, y = 1.75, w = 0.5, headerH = 0.09, itemH = 0.04 },
    animPanel  = { x = -0.45, y = 1.75, w = 0.55, headerH = 0.09, itemH = 0.04 },
    infoPanel  = { x = 0.25,  y = 1.75, w = 0.55, headerH = 0.09, itemH = 0.04 },
}

local keysDown = {}
local function isDown(key)
    return keysDown[key] == true
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
    pass:setColor(r, g, b, a or 0.8)
    -- LÖVR 0.18 uses box(mode, ...); some builds use box(...) with no mode.
    local ok = pcall(pass.box, pass, "fill", panel.x, panel.y - totalHeight / 2, HUD.z, panel.w, totalHeight, 0.01)
    if not ok then
        pcall(pass.box, pass, panel.x, panel.y - totalHeight / 2, HUD.z, panel.w, totalHeight, 0.01)
    end
end

local function drawText(pass, str, x, y, r, g, b)
    pass:setColor(r or 1, g or 1, b or 1)
    pass:text(str, x, y, HUD.z + 0.011, HUD.textScale)
end

local function drawListPanel(pass, panel, title, count, items, currentIndex, scrollOffset, highlightColor, getExtra)
    local maxVisible = math.min(count, playground.maxVisibleItems)
    local headerH = panel.headerH
    local itemH = panel.itemH
    local totalHeight = headerH + maxVisible * itemH

    drawPanel(pass, panel, totalHeight, 0, 0, 0, 0.85)
    drawPanel(pass, { x = panel.x, y = panel.y - headerH / 2 }, headerH, 0.15, 0.3, 0.55, 1)

    drawText(pass, title, panel.x - panel.w / 2 + 0.02, panel.y - 0.03, 1, 1, 1)
    drawText(pass, count .. " total", panel.x - panel.w / 2 + 0.02, panel.y - 0.065, 0.6, 0.6, 0.6)

    local topY = panel.y - headerH - itemH / 2
    for row = 1, maxVisible do
        local i = scrollOffset + row
        if i > count then break end
        local y = topY - (row - 1) * itemH
        local isCurrent = i == currentIndex
        if isCurrent then
            drawPanel(pass, { x = panel.x, y = y }, itemH, highlightColor[1], highlightColor[2], highlightColor[3], 0.5)
        end
        local label = items[i]
        if getExtra then label = getExtra(i, label) end
        drawText(pass, label, panel.x - panel.w / 2 + 0.02, y - 0.012,
            isCurrent and highlightColor[1] or 0.9,
            isCurrent and highlightColor[2] or 0.9,
            isCurrent and highlightColor[3] or 0.9)
    end
end

local function drawUI(pass)
    if not playground.showHud then return end

    drawListPanel(pass, HUD.assetPanel, "ASSETS", #playground.assetNames,
        playground.assetNames, playground.currentAssetIndex, 0,
        { 0.3, 1, 0.3 })

    drawListPanel(pass, HUD.animPanel, "ANIMATIONS", #playground.animations,
        playground.animations, playground.currentAnimationIndex, playground.scrollOffset,
        { 0.3, 1, 0.3 }, function(i, name) return i .. ". " .. name end)

    -- Info panel.
    local lines = {
        "Spine Playground",
        "Asset: " .. (playground.currentAssetName or "none"),
        "Playing: " .. (playground.currentAnimation or "none"),
        string.format("FPS: %.0f", playground.fps),
        string.format("Zoom: %.2f", playground.zoom),
        string.format("Pos: %.2f, %.2f, %.2f", playground.x, playground.y, playground.z),
    }
    if playground.showHelp then
        local help = {
            "Controls:",
            "SPACE/1-9: animation",
            "UP/DOWN: navigate",
            "[/]: scroll list",
            "N/TAB: next asset",
            "ARROWS: move skeleton",
            "+/-: zoom",
            "D: debug  R: reset",
            "Y: flip  U: hud",
            "H: help  ESC: quit",
        }
        for _, line in ipairs(help) do table.insert(lines, line) end
    end

    local headerH = HUD.infoPanel.headerH
    local itemH = HUD.infoPanel.itemH
    local totalHeight = headerH + #lines * itemH
    drawPanel(pass, HUD.infoPanel, totalHeight, 0, 0, 0, 0.85)
    drawPanel(pass, { x = HUD.infoPanel.x, y = HUD.infoPanel.y - headerH / 2 }, headerH, 0.15, 0.3, 0.55, 1)
    drawText(pass, "INFO", HUD.infoPanel.x - HUD.infoPanel.w / 2 + 0.02, HUD.infoPanel.y - 0.03, 1, 1, 1)

    for i, line in ipairs(lines) do
        local y = HUD.infoPanel.y - headerH - i * itemH + itemH / 2
        drawText(pass, line, HUD.infoPanel.x - HUD.infoPanel.w / 2 + 0.02, y - 0.01,
            i == 1 and 1 or 0.8, i == 1 and 1 or 0.8, i == 1 and 1 or 0.8)
    end

    if playground.showDebug then
        drawText(pass, "DEBUG MODE", 0, 2.1, 1, 0.5, 0)
    end
end

function lovr.draw(pass)
    if playground.loadError then
        drawText(pass, "ERROR: Failed to load Spine assets", -0.6, 0.1, 1, 0.2, 0.2)
        drawText(pass, playground.loadError, -0.6, 0.0, 1, 1, 1)
        drawText(pass, "Check the console for details.", -0.6, -0.1, 0.7, 0.7, 0.7)
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
