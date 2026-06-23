-- Spine LOVR Runtime - Basic Usage Example

package.path = package.path .. ";../../?.lua"
local spine = require("init")

local skeleton, animationState, renderer
local animations = {}
local currentAnimIndex = 1

function lovr.load()
    -- Load atlas
    local atlasText = lovr.filesystem.read("assets/spineboy/spineboy.atlas")
    if not atlasText then
        print("ERROR: Could not load atlas file")
        return
    end

    local atlas = spine.atlas.Atlas.new()
    local success, err = atlas:loadAtlasFile(atlasText, "assets/spineboy")
    if not success then
        print("ERROR: Failed to load atlas:", err)
        return
    end
    print("Atlas loaded:", #atlas.pages, "pages,", #atlas.regions, "regions")

    -- Create attachment loader
    local attachmentLoader = spine.atlas.AtlasAttachmentLoader.new(atlas)

    -- Load skeleton data
    local skeletonJsonText = lovr.filesystem.read("assets/spineboy/spineboy.json")
    if not skeletonJsonText then
        print("ERROR: Could not load skeleton JSON")
        return
    end

    local skeletonJson = spine.utils.jsonDecode(skeletonJsonText)
    local skeletonData = spine.SkeletonData.new()
    local loadOk, loadErr = pcall(function()
        skeletonData:loadFromJson(skeletonJson, attachmentLoader)
    end)
    if not loadOk then
        print("ERROR: Failed to parse skeleton JSON:", loadErr)
        return
    end
    print("Skeleton loaded:", #skeletonData.bones, "bones,", #skeletonData.slots, "slots")

    -- Create skeleton instance
    skeleton = spine.skeleton.Skeleton.new(skeletonData)
    skeleton:setToSetupPose()
    skeleton:updateWorldTransform()

    -- Create animation state
    local animStateData = spine.data.AnimationStateData.new(skeletonData)
    animationState = spine.animation.AnimationState.new(animStateData)

    -- Collect animation names
    if skeletonData.animations then
        for name, _ in pairs(skeletonData.animations) do
            table.insert(animations, name)
        end
    end

    if #animations > 0 then
        animationState:setAnimation(0, animations[1], true)
        currentAnimIndex = 1
    end

    -- Create renderer
    renderer = spine.rendering.SkeletonRenderer.new()

    print("Demo loaded! Press SPACE to cycle animations, D for debug")
end

function lovr.update(dt)
    if not animationState then return end

    animationState:update(dt)
    animationState:apply(skeleton)
    skeleton:updateWorldTransform()
end

function lovr.draw(pass)
    if not renderer then
        pass:text("No skeleton loaded. Check console for errors.", 0, 1, 0, 0.5)
        return
    end

    -- Position the skeleton in 3D space
    -- (x, y, z, scaleX, scaleY, scaleZ, rotation)
    local x, y, z = 0, 0, -2
    local sx, sy, sz = 0.003, -0.003, 0.003
    local rotation = 0

    renderer:draw(skeleton, pass, x, y, z, sx, sy, sz, rotation)
end

function lovr.keypressed(key)
    if key == "space" and #animations > 1 then
        currentAnimIndex = (currentAnimIndex % #animations) + 1
        animationState:setAnimation(0, animations[currentAnimIndex], true)
        print("Animation:", animations[currentAnimIndex])
    elseif key == "d" then
        renderer:setDebug(not renderer.debug)
        print("Debug:", renderer.debug and "ON" or "OFF")
    elseif key == "escape" then
        lovr.event.quit()
    end
end
