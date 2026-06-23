-- Spine LOVR Runtime - Rendering System
-- Handles drawing Spine skeletons using LOVR's pass-based graphics API

local mathModule = require("spine.math")
local utilsModule = require("spine.utils")

local VERTEX_FORMAT = {
	{ "VertexPosition", "vec3" },
	{ "VertexUV", "vec2" },
	{ "VertexColor", "vec4" },
}

local function isValidNumber(n)
	return n == n and n ~= math.huge and n ~= -math.huge
end

local Renderer = {}
Renderer.__index = Renderer

function Renderer:drawSkeleton(skeleton, pass, transform)
	pass:push()
	if transform then
		pass:transform(transform)
	end

	local drawOrder = skeleton.drawOrder

	for i, slot in ipairs(drawOrder) do
		local attachment = slot.attachment
		if attachment then
			if attachment.type == "clipping" and self.hasStencil ~= false then
				local clipping = attachment
				local endSlot = clipping.endSlot

				local ok = pcall(pass.setStencilWrite, pass, "replace", 1)
				if not ok then
					self.hasStencil = false
				else
					self:drawClipping(slot, clipping, pass)
					pcall(pass.setStencilTest, pass, "equal", 1)

					for j = i + 1, #drawOrder do
						local innerSlot = drawOrder[j]
						if innerSlot.attachment and innerSlot.attachment.type ~= "clipping" then
							self:drawAttachment(innerSlot, innerSlot.attachment, pass)
						end
						if innerSlot.data.name == endSlot then
							break
						end
					end

					pcall(pass.setStencilTest, pass)
					pcall(pass.setStencilWrite, pass)
				end
			else
				self:drawAttachment(slot, attachment, pass)
			end
		end
	end

	if self.debug then
		self:drawDebugSkeleton(skeleton, pass)
		for _, slot in ipairs(drawOrder) do
			if slot.attachment and slot.attachment.type == "clipping" then
				local worldVertices = {}
				slot.attachment:computeWorldVertices(slot, worldVertices)
				pass:setColor(1, 0, 0)
				if #worldVertices >= 6 then
					local poly3d = {}
					for j = 1, #worldVertices, 2 do
						table.insert(poly3d, worldVertices[j])
						table.insert(poly3d, worldVertices[j + 1])
						table.insert(poly3d, 0)
					end
					pass:polygon("line", poly3d)
				end
			end
		end
	end

	pass:pop()
end

function Renderer:drawClipping(slot, clipping, pass)
	local worldVertices = {}
	clipping:computeWorldVertices(slot, worldVertices)

	if #worldVertices >= 6 then
		local valid = true
		for i = 1, #worldVertices do
			if not isValidNumber(worldVertices[i]) then
				valid = false
				break
			end
		end

		if valid then
			local triIndices = utilsModule.triangulate(worldVertices)
			pass:setColor(1, 1, 1)
			if #triIndices >= 3 then
				for j = 1, #triIndices, 3 do
					local poly = {
						worldVertices[triIndices[j] * 2 + 1],
						worldVertices[triIndices[j] * 2 + 2],
						0,
						worldVertices[triIndices[j + 1] * 2 + 1],
						worldVertices[triIndices[j + 1] * 2 + 2],
						0,
						worldVertices[triIndices[j + 2] * 2 + 1],
						worldVertices[triIndices[j + 2] * 2 + 2],
						0,
					}
					pass:polygon("fill", poly)
				end
			else
				local poly3d = {}
				for j = 1, #worldVertices, 2 do
					table.insert(poly3d, worldVertices[j])
					table.insert(poly3d, worldVertices[j + 1])
					table.insert(poly3d, 0)
				end
				pass:polygon("fill", poly3d)
			end
		end
	end
end

function Renderer:drawAttachment(slot, attachment, pass)
	local color = slot.color
	local pma = false
	if attachment.region and attachment.region.page and attachment.region.page.pma then
		pma = true
	end

	local r, g, b, a
	if pma then
		r, g, b, a = color.r * color.a, color.g * color.a, color.b * color.a, color.a
	else
		r, g, b, a = color.r, color.g, color.b, color.a
	end

	local atype = attachment.type
	if atype == "region" then
		self:drawRegionAttachment(slot, attachment, pass, r, g, b, a)
	elseif atype == "mesh" then
		self:drawMeshAttachment(slot, attachment, pass, r, g, b, a)
	end
end

function Renderer:makeSlotMesh(slot, vertexCount)
	if slot._lovrMesh then
		slot._lovrBuffer = slot._lovrMesh:getVertexBuffer()
		return slot._lovrMesh
	end

	local buffer = lovr.graphics.newBuffer(VERTEX_FORMAT, vertexCount)
	local mesh = lovr.graphics.newMesh(buffer)
	slot._lovrMesh = mesh
	slot._lovrBuffer = buffer
	return mesh
end

function Renderer:drawRegionAttachment(slot, attachment, pass, r, g, b, a)
	local region = attachment.region
	if not region then
		return
	end

	local texture = region.texture
	if not texture then
		return
	end

	local worldVertices = {}
	attachment:computeWorldVertices(slot.bone, worldVertices)

	for i = 1, #worldVertices do
		if not isValidNumber(worldVertices[i]) then
			return
		end
	end

    -- Build grouped vertex arrays: each attribute is a sub-table
    local vertices = {
        { { worldVertices[1],  worldVertices[2],  0 }, { worldVertices[3],  worldVertices[4]  }, { r, g, b, a } },
        { { worldVertices[5],  worldVertices[6],  0 }, { worldVertices[7],  worldVertices[8]  }, { r, g, b, a } },
        { { worldVertices[9],  worldVertices[10], 0 }, { worldVertices[11], worldVertices[12] }, { r, g, b, a } },
        { { worldVertices[13], worldVertices[14], 0 }, { worldVertices[15], worldVertices[16] }, { r, g, b, a } },
    }

	local mesh = self:makeSlotMesh(slot, 4)
	local buffer = slot._lovrBuffer
    buffer:setData(vertices, 1)
	mesh:setIndices({ 1, 2, 3, 1, 3, 4 })

	mesh:setMaterial(lovr.graphics.newMaterial({ texture = texture }))

	local alphaMode = (region.page and region.page.pma) and "premultiplied" or "alphamultiply"
	local blendMode = slot.data.blendMode or "normal"

	if blendMode == "multiply" then
		pass:setColor(1, 1, 1, 1)
	end

	if blendMode == "additive" then
		pass:setBlendMode("add", alphaMode)
	elseif blendMode == "multiply" then
		pass:setBlendMode("alpha", alphaMode)
	elseif blendMode == "screen" then
		pass:setBlendMode("add", alphaMode)
	else
		pass:setBlendMode("alpha", alphaMode)
	end

	local usedShader = false
	if blendMode == "multiply" and self.multiplyMaskShader then
		pass:setShader(self.multiplyMaskShader)
		usedShader = true
	elseif slot.darkColor and self.tintBlackShader then
		pass:setShader(self.tintBlackShader)
		pass:send("darkColor", {
			slot.darkColor.r or 0,
			slot.darkColor.g or 0,
			slot.darkColor.b or 0,
			slot.darkColor.a or 1,
		})
		usedShader = true
	end

	pass:draw(mesh)

	if usedShader then
		pass:setShader()
	end

	pass:setBlendMode("alpha", "alphamultiply")
end

function Renderer:drawMeshAttachment(slot, attachment, pass, r, g, b, a)
	local texture = attachment.region and attachment.region.texture
	if not texture then
		return
	end

	local uvs = attachment.uvs
	local triangles = attachment.triangles
	if not uvs or not triangles then
		return
	end

	local worldVertices = {}
	attachment:computeWorldVertices(slot, worldVertices)

	for i = 1, #worldVertices do
		if not isValidNumber(worldVertices[i]) then
			return
		end
	end

	local vertexCount = #worldVertices / 2
	if vertexCount == 0 then
		return
	end

	local vertices = {}
	for i = 1, vertexCount do
		local vx = worldVertices[i * 2 - 1] or 0
		local vy = worldVertices[i * 2] or 0
		local vu = uvs[i * 2 - 1] or 0
		local vv = uvs[i * 2] or 0
        table.insert(vertices, { { vx, vy, 0 }, { vu, vv }, { r, g, b, a } })
	end

	local mesh = self:makeSlotMesh(slot, vertexCount)
	local buffer = slot._lovrBuffer
    buffer:setData(vertices, 1)

	-- Convert Spine 0-based triangles to LOVR 1-based flat index array
	local indexList = {}
	for i = 1, #triangles do
		indexList[i] = triangles[i] + 1
	end
	mesh:setIndices(indexList)

	mesh:setMaterial(lovr.graphics.newMaterial({ texture = texture }))

	local alphaMode = (attachment.region and attachment.region.page and attachment.region.page.pma) and "premultiplied"
		or "alphamultiply"
	local blendMode = slot.data.blendMode or "normal"

	if blendMode == "multiply" then
		pass:setColor(1, 1, 1, 1)
	end

	if blendMode == "additive" then
		pass:setBlendMode("add", alphaMode)
	elseif blendMode == "multiply" then
		pass:setBlendMode("alpha", alphaMode)
	elseif blendMode == "screen" then
		pass:setBlendMode("add", alphaMode)
	else
		pass:setBlendMode("alpha", alphaMode)
	end

	local usedShader = false
	if blendMode == "multiply" and self.multiplyMaskShader then
		pass:setShader(self.multiplyMaskShader)
		usedShader = true
	elseif slot.darkColor and self.tintBlackShader then
		pass:setShader(self.tintBlackShader)
		pass:send("darkColor", {
			slot.darkColor.r or 0,
			slot.darkColor.g or 0,
			slot.darkColor.b or 0,
			slot.darkColor.a or 1,
		})
		usedShader = true
	end

	pass:draw(mesh)

	if usedShader then
		pass:setShader()
	end

	pass:setBlendMode("alpha", "alphamultiply")
end

function Renderer:drawDebugSkeleton(skeleton, pass)
	pass:push()
	pass:setBlendMode("alpha", "alphamultiply")

	-- Draw bones as red lines
	pass:setColor(1, 0, 0)
	for _, bone in ipairs(skeleton.bones) do
		if bone.parent then
			if
				isValidNumber(bone.parent.worldX)
				and isValidNumber(bone.parent.worldY)
				and isValidNumber(bone.worldX)
				and isValidNumber(bone.worldY)
			then
				pass:line(bone.parent.worldX, bone.parent.worldY, 0, bone.worldX, bone.worldY, 0)
			end
		end
	end

	-- Draw bone origins as green points
	pass:setColor(0, 1, 0)
	for _, bone in ipairs(skeleton.bones) do
		pass:points(bone.worldX, bone.worldY, 0)
	end

	-- Draw attachment bounds as blue polygons
	pass:setColor(0, 0, 1)
	for _, slot in ipairs(skeleton.drawOrder) do
		if slot.attachment then
			self:drawDebugAttachment(slot, slot.attachment, pass)
		end
	end

	pass:pop()
end

function Renderer:drawDebugAttachment(slot, attachment, pass)
	local bone = slot.bone

	if not (isValidNumber(bone.worldX) and isValidNumber(bone.worldY)) then
		return
	end

	pass:push()
	pass:translate(bone.worldX, bone.worldY, 0)
	pass:rotate(bone.worldRotation and math.rad(bone.worldRotation) or 0, 0, 0, 1)
	pass:scale(bone.worldScaleX or 1, bone.worldScaleY or 1, 1)

	if attachment.type == "region" then
		local verts = attachment.offset
		if verts and #verts >= 8 then
			local valid = true
			for i = 1, #verts do
				if not isValidNumber(verts[i]) then
					valid = false
					break
				end
			end
			if valid then
				pass:polygon(
					"line",
					verts[1],
					verts[2],
					0,
					verts[3],
					verts[4],
					0,
					verts[5],
					verts[6],
					0,
					verts[7],
					verts[8],
					0
				)
			end
		end
	elseif attachment.type == "mesh" then
		local verts = attachment.vertices
		if verts and #verts >= 4 then
			local minX, maxX = verts[1], verts[1]
			local minY, maxY = verts[2], verts[2]
			local valid = true
			for i = 1, #verts do
				if not isValidNumber(verts[i]) then
					valid = false
					break
				end
			end
			if valid then
				for i = 3, #verts, 2 do
					minX = math.min(minX, verts[i])
					maxX = math.max(maxX, verts[i])
					minY = math.min(minY, verts[i + 1])
					maxY = math.max(maxY, verts[i + 1])
				end
				local cx = (minX + maxX) / 2
				local cy = (minY + maxY) / 2
				pass:box("line", cx, cy, 0, maxX - minX, maxY - minY, 0.01)
			end
		end
	elseif attachment.type == "boundingbox" then
		local verts = attachment.vertices
		if verts and #verts >= 4 then
			local valid = true
			for i = 1, #verts do
				if not isValidNumber(verts[i]) then
					valid = false
					break
				end
			end
			if valid then
				local poly = {}
				for i = 1, #verts, 2 do
					table.insert(poly, verts[i])
					table.insert(poly, verts[i + 1])
					table.insert(poly, 0)
				end
				if #poly >= 9 then
					pass:polygon("line", poly)
				end
			end
		end
	end

	pass:pop()
end

local SkeletonRenderer = {}
SkeletonRenderer.__index = SkeletonRenderer

function Renderer.new()
	local self = setmetatable({}, Renderer)
	self.debug = false
	self.tintBlackShader = nil
	self.multiplyMaskShader = nil

	local ok, result = pcall(require, "spine.tintblack_shader")
	if ok then
		self.tintBlackShader = result
	end

	local ok2, result2 = pcall(require, "spine.multiply_mask_shader")
	if ok2 then
		self.multiplyMaskShader = result2
	end

	return self
end

function SkeletonRenderer.new()
	local self = setmetatable({}, SkeletonRenderer)
	self.renderer = Renderer.new()
	self.debug = false
	return self
end

function SkeletonRenderer:draw(skeleton, pass, transform)
	self.renderer:drawSkeleton(skeleton, pass, transform)

	if self.debug then
		self.renderer.debug = true
		self.renderer:drawDebugSkeleton(skeleton, pass)
	end
end

function SkeletonRenderer:setDebug(debug)
	self.debug = debug
end

local renderingModule = {
	Renderer = Renderer,
	SkeletonRenderer = SkeletonRenderer,
}

return renderingModule
