local constraintModule = require("spine.constraint")

local Bone = {}
Bone.__index = Bone

function Bone.new(boneData, parent, skeleton)
    local self = setmetatable({}, Bone)
    self.data = boneData
    self.skeleton = skeleton
    self.parent = parent
    self.children = {}
    self.active = not boneData.skinRequired
    
    self.x = boneData.x
    self.y = boneData.y
    self.rotation = boneData.rotation
    self.scaleX = boneData.scaleX
    self.scaleY = boneData.scaleY
    self.shearX = boneData.shearX
    self.shearY = boneData.shearY

    -- Applied values: the animation-local pose is x/y/rotation/..., while
    -- ax/ay/arotation/... hold the values actually used for this frame's
    -- world matrix after constraints.
    self.ax = self.x
    self.ay = self.y
    self.arotation = self.rotation
    self.ascaleX = self.scaleX
    self.ascaleY = self.scaleY
    self.ashearX = self.shearX
    self.ashearY = self.shearY
    
    self.worldX = 0
    self.worldY = 0
    self.worldRotation = 0
    self.worldScaleX = 1
    self.worldScaleY = 1
    self.worldFlipX = false
    self.worldFlipY = false
    self.a = 1
    self.b = 0
    self.c = 0
    self.d = 1
    
    if parent then
        table.insert(parent.children, self)
    end
    
    return self
end

function Bone:updateWorldTransformWithChildren()
    self:updateWorldTransform()
    if self.children then
        for _, child in ipairs(self.children) do
            child:updateWorldTransformWithChildren()
        end
    end
end

-- Updates descendants after a constraint has modified this bone's world
-- matrix directly, without recomputing this bone from its local fields.
function Bone:updateChildrenWorldTransform()
    for _, child in ipairs(self.children) do
        child:updateWorldTransform()
    end
end

-- Rebuilds the local/applied transform from the current world matrix, so
-- constraints that run later in the same frame see consistent local values.
function Bone:updateAppliedTransform()
    local parent = self.parent
    local skeleton = self.skeleton

    if not parent then
        local scaleX = skeleton.scaleX or 1
        local scaleY = skeleton.scaleY or 1
        if scaleX == 0 then scaleX = 1 end
        if scaleY == 0 then scaleY = 1 end

        self.x = (self.worldX - (skeleton.x or 0)) / scaleX
        self.y = (self.worldY - (skeleton.y or 0)) / scaleY
        self.rotation = math.deg(math.atan2(self.c, self.a))
        self.scaleX = math.sqrt(self.a * self.a + self.c * self.c) / math.abs(scaleX)
        self.scaleY = math.sqrt(self.b * self.b + self.d * self.d) / math.abs(scaleY)
        self.shearX = 0
        self.shearY = math.deg(math.atan2(
            self.a * self.b + self.c * self.d,
            self.a * self.d - self.b * self.c))
        self.ax, self.ay = self.x, self.y
        self.arotation = self.rotation
        self.ascaleX, self.ascaleY = self.scaleX, self.scaleY
        self.ashearX, self.ashearY = self.shearX, self.shearY
        return
    end

    local pa, pb, pc, pd = parent.a, parent.b, parent.c, parent.d
    local det = pa * pd - pb * pc
    if math.abs(det) < 1e-9 then return end
    local invDet = 1 / det

    local dx = self.worldX - parent.worldX
    local dy = self.worldY - parent.worldY
    self.x = (dx * pd - dy * pb) * invDet
    self.y = (dy * pa - dx * pc) * invDet

    local mode = self.data.transformMode
    if mode == "normal" then
        local ra = (pd * self.a - pb * self.c) * invDet
        local rb = (pd * self.b - pb * self.d) * invDet
        local rc = (-pc * self.a + pa * self.c) * invDet
        local rd = (-pc * self.b + pa * self.d) * invDet

        local sx = math.sqrt(ra * ra + rc * rc)
        local determinant = ra * rd - rb * rc
        self.rotation = math.deg(math.atan2(rc, ra))
        self.scaleX = sx
        self.scaleY = sx ~= 0 and (determinant / sx) or math.sqrt(rb * rb + rd * rd)
        self.shearX = 0
        self.shearY = -math.deg(math.atan2(ra * rb + rc * rd, determinant))
    end

    self.ax, self.ay = self.x, self.y
    self.arotation = self.rotation
    self.ascaleX, self.ascaleY = self.scaleX, self.scaleY
    self.ashearX, self.ashearY = self.shearX, self.shearY
end

function Bone:updateWorldTransform(x, y, rotation, scaleX, scaleY, shearX, shearY)
    if x ~= nil then
        self.x, self.y = x, y
        self.rotation = rotation
        self.scaleX, self.scaleY = scaleX, scaleY
        self.shearX, self.shearY = shearX or 0, shearY or 0
    end

    self.ax, self.ay = self.x, self.y
    self.arotation = self.rotation
    self.ascaleX, self.ascaleY = self.scaleX, self.scaleY
    self.ashearX, self.ashearY = self.shearX, self.shearY

    local parent = self.parent
    
    -- 1. Compute Local Matrix (la, lb, lc, ld)
    -- Uses Spine's shear formula:
    -- la = cos(rot + shearX) * sx
    -- lc = sin(rot + shearX) * sx
    -- lb = cos(rot + 90 + shearY) * sy
    -- ld = sin(rot + 90 + shearY) * sy
    
    local rotation = self.rotation
    local shearX = self.shearX or 0
    local shearY = self.shearY or 0
    local scaleX = self.scaleX
    local scaleY = self.scaleY
    
    local rotX = math.rad(rotation + shearX)
    local rotY = math.rad(rotation + 90 + shearY)
    
    local la = math.cos(rotX) * scaleX
    local lc = math.sin(rotX) * scaleX
    local lb = math.cos(rotY) * scaleY
    local ld = math.sin(rotY) * scaleY
    
    local lx = self.x
    local ly = self.y
    
    if parent then
        local pa = parent.a
        local pb = parent.b
        local pc = parent.c
        local pd = parent.d
        local px = parent.worldX
        local py = parent.worldY
        
        -- Matrix used for rotation/scale inheritance (default to parent matrix)
        local ma = pa
        local mb = pb
        local mc = pc
        local md = pd
        
        local transformMode = self.data.transformMode
        
        if transformMode == "normal" then
            self.worldRotation = parent.worldRotation + self.rotation
            
        elseif transformMode == "onlyTranslation" then
            self.worldRotation = self.rotation
            -- Inherit only translation: reset rotation/scale part to identity
            ma = 1; mb = 0
            mc = 0; md = 1
            
        elseif transformMode == "noRotationOrReflection" then
            self.worldRotation = self.rotation
            local sX = math.sqrt(pa * pa + pc * pc)
            local sY = math.sqrt(pb * pb + pd * pd)
            
            -- Construct scale-only matrix (ignores rotation and reflection)
            ma = sX
            mb = 0
            mc = 0
            md = sY
            
        elseif transformMode == "noScale" or transformMode == "noScaleOrReflection" then
            self.worldRotation = parent.worldRotation + self.rotation
            
            local sX = math.sqrt(ma * ma + mc * mc)
            local sY = math.sqrt(mb * mb + md * md)
            
            if sX > 0.00001 then
                local invX = 1 / sX
                ma = ma * invX
                mc = mc * invX
            end
            if sY > 0.00001 then
                local invY = 1 / sY
                mb = mb * invY
                md = md * invY
            end
            
            if transformMode == "noScaleOrReflection" then
                local det = ma * md - mb * mc
                if det < 0 then
                    mb = -mb
                    md = -md
                end
            end
        end
        
        -- Calculate World Position (Always affected by parent transform)
        self.worldX = pa * lx + pb * ly + px
        self.worldY = pc * lx + pd * ly + py
        
        -- Calculate World Matrix (Affected by transform mode)
        self.a = ma * la + mb * lc
        self.b = ma * lb + mb * ld
        self.c = mc * la + md * lc
        self.d = mc * lb + md * ld
        
        -- Handle Flip (applied after inheritance)
        self.worldFlipX = parent.worldFlipX ~= (self.flipX or false)
        self.worldFlipY = parent.worldFlipY ~= (self.flipY or false)
        
    else
        -- Root bone
        local skeletonFlipX = self.skeleton.flipX
        local skeletonFlipY = self.skeleton.flipY
        local skeletonScaleX = self.skeleton.scaleX or 1
        local skeletonScaleY = self.skeleton.scaleY or 1

        lx = lx * skeletonScaleX
        ly = ly * skeletonScaleY
        la, lb = la * skeletonScaleX, lb * skeletonScaleX
        lc, ld = lc * skeletonScaleY, ld * skeletonScaleY

        if skeletonFlipX then
            lx = -lx
            la = -la
            lb = -lb
        end
        if skeletonFlipY then
            ly = -ly
            lc = -lc
            ld = -ld
        end
        
        self.worldX = lx + self.skeleton.x
        self.worldY = ly + self.skeleton.y
        self.a = la
        self.b = lb
        self.c = lc
        self.d = ld
        
        self.worldFlipX = skeletonFlipX ~= (self.flipX or false)
        self.worldFlipY = skeletonFlipY ~= (self.flipY or false)
    end
    
    -- Update children
    for _, child in ipairs(self.children) do
        child:updateWorldTransform()
    end
end

function Bone:setToSetupPose()
    local data = self.data
    self.x = data.x
    self.y = data.y
    self.rotation = data.rotation
    self.scaleX = data.scaleX
    self.scaleY = data.scaleY
    self.shearX = data.shearX
    self.shearY = data.shearY
    
    -- if self.skeleton.time < 0.2 then -- Only print for first few frames
    --     print("Bone Reset: " .. self.data.name)
    -- end
end

local Slot = {}
Slot.__index = Slot

function Slot.new(slotData, bone)
    local self = setmetatable({}, Slot)
    self.data = slotData
    self.bone = bone
    self.color = {r = slotData.color.r, g = slotData.color.g, b = slotData.color.b, a = slotData.color.a}
    self.darkColor = slotData.darkColor and {
        r = slotData.darkColor.r, 
        g = slotData.darkColor.g, 
        b = slotData.darkColor.b, 
        a = slotData.darkColor.a
    } or nil
    self.attachment = nil
    self.attachmentTime = 0
    self.attachmentVertices = nil
    self.sequenceIndex = -1 -- Spine 4.2 sequence region index (-1 = setup)
    return self
end

function Slot:setAttachment(attachment)
    if self.attachment == attachment then return end
    self.attachment = attachment
    self.attachmentTime = self.bone.skeleton.time
    self.attachmentVertices = nil
end

function Slot:setToSetupPose()
    local data = self.data
    self.color = {r = data.color.r, g = data.color.g, b = data.color.b, a = data.color.a}
    if data.darkColor then
        self.darkColor = {r = data.darkColor.r, g = data.darkColor.g, b = data.darkColor.b, a = data.darkColor.a}
    else
        self.darkColor = nil
    end
    self.attachment = nil
    self.sequenceIndex = -1
end

local Skeleton = {}
Skeleton.__index = Skeleton

function Skeleton.new(skeletonData)
    local self = setmetatable({}, Skeleton)
    
    self.data = skeletonData
    self.bones = {}
    self.slots = {}
    self.drawOrder = {}
    self.ikConstraints = {}
    self.transformConstraints = {}
    self.pathConstraints = {}
    self.physicsConstraints = {}
    
    self.skin = nil
    self.x = 0
    self.y = 0
    self.scaleX = 1
    self.scaleY = 1
    self.r = 1
    self.g = 1
    self.b = 1
    self.a = 1
    self.time = 0
    self.flipX = false
    self.flipY = false
    
    for i, boneData in ipairs(skeletonData.bones) do
        local parent = nil
        if boneData.parent then
            local parentIndex = skeletonData:findBoneIndex(boneData.parent.name)
            if parentIndex ~= -1 then
                parent = self.bones[parentIndex]
            end
        end
        local bone = Bone.new(boneData, parent, self)
        table.insert(self.bones, bone)
    end
    
    for i, slotData in ipairs(skeletonData.slots) do
        local boneIndex = skeletonData:findBoneIndex(slotData.boneData.name)
        local bone = self.bones[boneIndex]
        local slot = Slot.new(slotData, bone)
        table.insert(self.slots, slot)
        table.insert(self.drawOrder, slot)
    end
    
    self.constraints = {} -- Initialize constraints list
    
    for i, ikConstraintData in ipairs(skeletonData.ikConstraints) do
        local ikConstraint = constraintModule.IkConstraint.new(ikConstraintData, self)
        table.insert(self.ikConstraints, ikConstraint)
        table.insert(self.constraints, ikConstraint)
    end
    
    for i, transformConstraintData in ipairs(skeletonData.transformConstraints) do
        local transformConstraint = constraintModule.TransformConstraint.new(transformConstraintData, self)
        table.insert(self.transformConstraints, transformConstraint)
        table.insert(self.constraints, transformConstraint)
    end
    
    for i, pathConstraintData in ipairs(skeletonData.pathConstraints) do
        local pathConstraint = constraintModule.PathConstraint.new(pathConstraintData, self)
        table.insert(self.pathConstraints, pathConstraint)
        table.insert(self.constraints, pathConstraint)
    end

    for i, physicsConstraintData in ipairs(skeletonData.physicsConstraints) do
        local physicsConstraint = constraintModule.PhysicsConstraint.new(physicsConstraintData, self)
        table.insert(self.physicsConstraints, physicsConstraint)
        table.insert(self.constraints, physicsConstraint)
    end
    
    -- Sort constraints by order
    table.sort(self.constraints, function(a, b)
        return a.data.order < b.data.order
    end)
    
    self:updateCache()
    return self
end

function Skeleton:updateCache()
    local skin = self.skin

    -- Bones marked skin-required are inactive until the active skin lists
    -- them (or a descendant), matching the Spine 4.2 runtime behavior.
    for _, bone in ipairs(self.bones) do
        bone.active = not bone.data.skinRequired
    end

    if skin then
        for _, boneData in ipairs(skin.bones) do
            local bone = self:findBone(boneData.name)
            while bone do
                bone.active = true
                bone = bone.parent
            end
        end
    end

    local function skinHasConstraint(data)
        if not skin then return false end
        for _, constraintData in ipairs(skin.constraints) do
            if constraintData == data then return true end
        end
        return false
    end

    for _, constraint in ipairs(self.constraints) do
        local active = not constraint.data.skinRequired
            or skinHasConstraint(constraint.data)

        if active then
            -- A constraint is only active when its target (or its own bone
            -- for physics) is active.
            local target = constraint.target
            local targetBone
            if target then
                if target.bone then
                    targetBone = target.bone
                elseif target.data then
                    targetBone = target
                end
            elseif constraint.bone then
                targetBone = constraint.bone
            end
            if targetBone and targetBone.active == false then
                active = false
            end
        end

        constraint.active = active
    end

    for _, bone in ipairs(self.bones) do
        if not bone.parent then
            bone:updateWorldTransform()
        end
    end
end

function Skeleton:updateWorldTransform()
    -- Constraints may adjust local/applied bone values to build this frame's
    -- matrices. Keep the animation pose separate so relative/local constraints
    -- do not accumulate frame over frame.
    local snapshot = self._localSnapshot
    if not snapshot then
        snapshot = {}
        self._localSnapshot = snapshot
    end
    for i, bone in ipairs(self.bones) do
        local o = (i - 1) * 7
        snapshot[o + 1] = bone.x
        snapshot[o + 2] = bone.y
        snapshot[o + 3] = bone.rotation
        snapshot[o + 4] = bone.scaleX
        snapshot[o + 5] = bone.scaleY
        snapshot[o + 6] = bone.shearX
        snapshot[o + 7] = bone.shearY
    end

    -- 1. Update root bones (which recursively updates their children)
    for _, bone in ipairs(self.bones) do
        if not bone.parent then
            bone:updateWorldTransform()
        end
    end
    
    -- 2. Apply active Constraints (IK, Transform, Path, Physics) in order
    for _, constraint in ipairs(self.constraints) do
        if constraint.active ~= false then
            constraint:apply()

            -- Update children of constrained bones
            -- This ensures that bones not affected by the constraint but attached to constrained bones
            -- follow their parents correctly.
            if constraint.bones then
                for _, bone in ipairs(constraint.bones) do
                    for _, child in ipairs(bone.children) do
                        -- Check if child is also constrained by THIS constraint
                        local isChildConstrained = false
                        for _, cb in ipairs(constraint.bones) do
                            if cb == child then
                                isChildConstrained = true
                                break
                            end
                        end

                        if not isChildConstrained then
                            child:updateWorldTransform()
                        end
                    end
                end
            end
        end
    end

    -- Restore the animation-local pose. World matrices remain as constrained.
    for i, bone in ipairs(self.bones) do
        local o = (i - 1) * 7
        bone.x = snapshot[o + 1]
        bone.y = snapshot[o + 2]
        bone.rotation = snapshot[o + 3]
        bone.scaleX = snapshot[o + 4]
        bone.scaleY = snapshot[o + 5]
        bone.shearX = snapshot[o + 6]
        bone.shearY = snapshot[o + 7]
    end
end

function Skeleton:setToSetupPose()
    self:setBonesToSetupPose()
    self:setSlotsToSetupPose()
    self:setConstraintsToSetupPose()
end

function Skeleton:setBonesToSetupPose()
    for _, bone in ipairs(self.bones) do
        bone:setToSetupPose()
    end
    self:updateCache()
end

function Skeleton:setSlotsToSetupPose()
    for i, slot in ipairs(self.slots) do
        slot:setToSetupPose()
        self.drawOrder[i] = slot
    end
    
    -- Apply skin attachments (including default skin fallback)
    for i, slot in ipairs(self.slots) do
        local attachmentName = slot.data.attachmentName
        if attachmentName then
            -- Use getAttachment to handle skin fallback correctly
            local attachment = self:getAttachment(slot.data.name, attachmentName)
            if attachment then
                slot:setAttachment(attachment)
            end
        end
    end
end

function Skeleton:setConstraintsToSetupPose()
    for _, constraint in ipairs(self.constraints) do
        constraint:setToSetupPose()
    end
end

function Skeleton:getRootBone()
    return self.bones[1]
end

-- Sets the skeleton-wide tint applied to every slot/attachment.
function Skeleton:setColor(r, g, b, a)
    self.r = r or 1
    self.g = g or 1
    self.b = b or 1
    self.a = a or 1
end

-- Sets the skeleton-wide scale applied to root bones.
function Skeleton:setScale(scaleX, scaleY)
    self.scaleX = scaleX or 1
    self.scaleY = scaleY or self.scaleX
end

function Skeleton:findBone(boneName)
    for _, bone in ipairs(self.bones) do
        if bone.data.name == boneName then return bone end
    end
    return nil
end

function Skeleton:findBoneIndex(boneName)
    for i, bone in ipairs(self.bones) do
        if bone.data.name == boneName then return i end
    end
    return -1
end

function Skeleton:findSlot(slotName)
    for _, slot in ipairs(self.slots) do
        if slot.data.name == slotName then return slot end
    end
    return nil
end

function Skeleton:findSlotIndex(slotName)
    for i, slot in ipairs(self.slots) do
        if slot.data.name == slotName then return i end
    end
    return -1
end

function Skeleton:setSkin(skin)
    local newSkin = skin
    if type(skin) == "string" then
        newSkin = self.data.skins[skin]
        if not newSkin then
            print("Error: Skin not found: " .. skin)
            return
        end
    end

    self.skin = newSkin

    -- Apply the new skin to the skeleton slots
    -- This ensures that any currently active attachments are updated to the new skin
    for i, slot in ipairs(self.slots) do
        local name = slot.data.attachmentName
        if name then
            local attachment = self:getAttachment(slot.data.name, name)
            if attachment then
                slot:setAttachment(attachment)
            end
        end
    end

    self:updateCache()
end

function Skeleton:getAttachment(slotName, attachmentName)
    local slotIndex = self:findSlotIndex(slotName)
    if slotIndex == -1 then return nil end
    
    local attachment = nil
    local skin = self.skin
    if skin then
        attachment = skin:getAttachment(slotIndex, attachmentName)
    end
    
    if not attachment and self.data.defaultSkin then
        attachment = self.data.defaultSkin:getAttachment(slotIndex, attachmentName)
    end
    
    return attachment
end

function Skeleton:setAttachment(slotName, attachmentName)
    local slot = self:findSlot(slotName)
    if not slot then return end
    
    local attachment = nil
    if attachmentName then
        attachment = self:getAttachment(slotName, attachmentName)
        if not attachment then
            error("Attachment not found: " .. attachmentName .. ", slot: " .. slotName)
        end
    end
    
    slot:setAttachment(attachment)
end

function Skeleton:update(timeDelta)
    self.time = self.time + timeDelta
end

return {
    Bone = Bone,
    Slot = Slot,
    Skeleton = Skeleton
}
