-- Spine LOVR Runtime - Rendering System
-- Handles drawing Spine skeletons using LOVR's pass-based graphics API

local mathModule = require("spine.math")
local utilsModule = require("spine.utils")

local VERTEX_FORMAT = {
	{ "VertexPosition", "vec3" },
	{ "VertexUV", "vec2" },
	{ "VertexColor", "vec4" },
	{ "VertexDarkColor", "vec4" }, -- used by the tint-black shader (0,0,0,0 when absent)
}

local function isValidNumber(n)
	return n == n and n ~= math.huge and n ~= -math.huge
end

-- Compatibility helpers: LÖVR 0.18 uses polygon(mode, vertices) and
-- box(mode, ...); some builds use polygon(vertices)/box(...) with no mode
-- string. Try the mode variant first, then fall back.
local function passPolygon(pass, mode, verts)
	local ok = pcall(pass.polygon, pass, mode, verts)
	if ok then return end
	ok = pcall(pass.polygon, pass, verts)
	if ok then return end
	pcall(pass.polygon, pass, unpack(verts))
end

local function passPolygonFlat(pass, mode, ...)
	local verts = { ... }
	local ok = pcall(pass.polygon, pass, mode, verts)
	if ok then return end
	ok = pcall(pass.polygon, pass, verts)
	if ok then return end
	pcall(pass.polygon, pass, unpack(verts))
end

local function passBox(pass, mode, x, y, z, sx, sy, sz)
	local ok = pcall(pass.box, pass, mode, x, y, z, sx, sy, sz)
	if ok then return end
	pcall(pass.box, pass, x, y, z, sx, sy, sz)
end

local Renderer = {}
Renderer.__index = Renderer

-- Fill a clipping attachment's polygon into the stencil buffer.
-- writeMode is "increment" (mark region) or "decrement" (unmark region).
-- Color writes are disabled while drawing the stencil polygon.
-- Returns false if the polygon could not be computed/triangulated.
function Renderer:stencilPolygon(slot, clipping, pass, writeMode)
	local worldVertices = {}
	clipping:computeWorldVertices(slot, worldVertices)

	if #worldVertices < 6 then
		return false
	end

	for i = 1, #worldVertices do
		if not isValidNumber(worldVertices[i]) then
			return false
		end
	end

	local triIndices = utilsModule.triangulate(worldVertices)
	if #triIndices < 3 then
		return false
	end

	local ok = pcall(pass.setStencilWrite, pass, writeMode, 1)
	if not ok then
		return false
	end

	local colorWriteOff = pcall(pass.setColorWrite, pass, false, false, false, false)
	pass:setColor(1, 1, 1)

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
		passPolygon(pass, "fill", poly)
	end

	if colorWriteOff then
		pcall(pass.setColorWrite, pass, true, true, true, true)
	end
	pcall(pass.setStencilWrite, pass)

	return true
end

-- Draws drawOrder[startIndex..endIndex] with clipping support.
-- clipDepth is the number of enclosing clips (equals the stencil value of the
-- surrounding region). Clipping attachments mark their polygon with an
-- incrementing stencil write, draw their range against `equal (depth + 1)`,
-- then decrement the polygon back so enclosing clips are unaffected.
-- Nested clips work because each level uses a distinct stencil value.
function Renderer:drawDrawOrderRange(skeleton, pass, drawOrder, startIndex, endIndex, clipDepth)
	local batch = { groups = {}, order = {} }
	local i = startIndex
	while i <= endIndex do
		local slot = drawOrder[i]
		local attachment = slot.attachment

		if attachment and attachment.type == "clipping" and self.hasStencil ~= false then
			local clipping = attachment
			local clipEnd = endIndex
			local endName = clipping.endSlot
			if endName then
				for j = i + 1, endIndex do
					if drawOrder[j].data.name == endName then
						clipEnd = j
						break
					end
				end
			end

			-- Detect stencil support once per renderer ("keep" is a no-op write
			-- mode, so the probe leaves the stencil buffer untouched).
			if self.stencilOk == nil then
				self.stencilOk = pcall(pass.setStencilWrite, pass, "keep", 0)
				if not self.stencilOk then
					self.hasStencil = false
				end
			end

			local innerDepth = clipDepth + 1
			if self.stencilOk then
				if self:stencilPolygon(slot, clipping, pass, "increment") then
					local testOk = pcall(pass.setStencilTest, pass, "equal", innerDepth)
					if testOk then
						self:drawDrawOrderRange(skeleton, pass, drawOrder, i + 1, clipEnd, innerDepth)
						pcall(pass.setStencilTest, pass)
					else
						-- Stencil test unsupported: draw the range unclipped.
						self:drawDrawOrderRange(skeleton, pass, drawOrder, i + 1, clipEnd, clipDepth)
					end
					-- Restore the stencil buffer.
					self:stencilPolygon(slot, clipping, pass, "decrement")
				else
					-- Polygon unavailable: draw the range unclipped.
					self:drawDrawOrderRange(skeleton, pass, drawOrder, i + 1, clipEnd, clipDepth)
				end
			else
				-- Stencil writing unsupported: draw the range unclipped.
				self:drawDrawOrderRange(skeleton, pass, drawOrder, i + 1, clipEnd, clipDepth)
			end

		-- Skip the whole clipped range; the outer loop must not redraw it.
			i = clipEnd
		elseif attachment then
			self:collectAttachment(batch, slot, attachment)
		end

		i = i + 1
	end

	self:flushBatches(batch, pass)
end

function Renderer:drawSkeleton(skeleton, pass, transform)
	pass:push()
	if transform then
		pass:transform(transform)
	end

	self.drawCalls = 0
	self.vertexCount = 0
	self.triangleCount = 0

	self:drawDrawOrderRange(skeleton, pass, skeleton.drawOrder, 1, #skeleton.drawOrder, 0)

	if self.debug then
		self:drawDebugSkeleton(skeleton, pass)
		for _, slot in ipairs(skeleton.drawOrder) do
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
					passPolygon(pass, "line", poly3d)
				end
			end
		end
	end

	pass:pop()
end

local REGION_INDICES = { 1, 2, 3, 1, 3, 4 }

-- Get or create a cached Material for a texture. Materials are cached per
-- texture (weak keys) so they are not reallocated every frame per attachment.
-- LÖVR 0.11 creates materials with newMaterial(texture), newer versions with
-- newMaterial({ texture = ... }); the working style is detected once.
function Renderer:getMaterial(texture)
	if not self.materials then
		self.materials = setmetatable({}, { __mode = "k" })
	end
	local material = self.materials[texture]
	if not material then
		if self.materialStyle == nil then
			local ok, candidate = pcall(lovr.graphics.newMaterial, { texture = texture })
			if ok then
				self.materialStyle = "options"
				material = candidate
			else
				local ok2, candidate2 = pcall(lovr.graphics.newMaterial, texture)
				if ok2 then
					self.materialStyle = "texture"
					material = candidate2
				end
			end
		elseif self.materialStyle == "options" then
			local ok, candidate = pcall(lovr.graphics.newMaterial, { texture = texture })
			if ok then
				material = candidate
			end
		else
			local ok, candidate = pcall(lovr.graphics.newMaterial, texture)
			if ok then
				material = candidate
			end
		end

		if material then
			self.materials[texture] = material
		end
	end
	return material
end

-- Get (or create) a growable Buffer/Mesh pair for a texture page. Batches for
-- the same texture reuse the buffer across frames and instances of the
-- renderer; it is recreated only when the batch outgrows it.
function Renderer:getBatchMesh(texture, vertexCount)
	if not self.batchMeshes then
		self.batchMeshes = setmetatable({}, { __mode = "k" })
	end
	local info = self.batchMeshes[texture]
	if not info then
		info = { capacity = 0 }
		self.batchMeshes[texture] = info
	end
	if info.capacity < vertexCount then
		local capacity = math.max(vertexCount, info.capacity * 2, 256)
		info.buffer = lovr.graphics.newBuffer(VERTEX_FORMAT, capacity)
		info.mesh = lovr.graphics.newMesh(info.buffer)
		info.capacity = capacity
	end
	return info
end

-- Collects one attachment's vertices into the batch, grouped by texture page
-- and render state (blend mode, premultiplication, tint). Nothing is drawn yet;
-- flushBatches draws one mesh per group.
function Renderer:collectAttachment(batch, slot, attachment)
	local region = attachment.region
	if not region or not region.texture then
		return
	end

	local color = slot.color
	local pma = not not (region.page and region.page.pma)

	local r, g, b, a
	if pma then
		r, g, b, a = color.r * color.a, color.g * color.a, color.b * color.a, color.a
	else
		r, g, b, a = color.r, color.g, color.b, color.a
	end

	local worldVertices = {}
	if attachment.type == "region" then
		attachment:computeWorldVertices(slot.bone, worldVertices)
	elseif attachment.type == "mesh" then
		attachment:computeWorldVertices(slot, worldVertices)
	else
		return
	end

	for i = 1, #worldVertices do
		if not isValidNumber(worldVertices[i]) then
			return
		end
	end

	local blendMode = slot.data.blendMode or "normal"
	local dark = slot.darkColor
	local tintKey = ""
	if dark then
		if self.tintBlack and self.tintBlack.perVertex then
			tintKey = "tint"
		else
			tintKey = string.format("%.3f,%.3f,%.3f,%.3f", dark.r or 0, dark.g or 0, dark.b or 0, dark.a or 0)
		end
	end
	local key = tostring(region.texture) .. "|" .. blendMode .. "|" .. (pma and "1" or "0") .. "|" .. tintKey

	local group = batch.groups[key]
	if not group then
		group = {
			texture = region.texture,
			blendMode = blendMode,
			pma = pma,
			hasDark = dark ~= nil,
			darkColor = dark,
			vertices = {},
			indices = {},
		}
		batch.groups[key] = group
		table.insert(batch.order, group)
	end

	local base = #group.vertices
	local vertexCount
	local indices
	if attachment.type == "region" then
		vertexCount = 4
		indices = REGION_INDICES
	else
		vertexCount = #worldVertices / 2
		indices = attachment._lovrIndices
		if not indices then
			indices = {}
			for i = 1, #attachment.triangles do
				indices[i] = attachment.triangles[i] + 1
			end
			attachment._lovrIndices = indices
		end
	end

	local dr, dg, db, da = 0, 0, 0, 0
	if dark then
		dr, dg, db, da = dark.r or 0, dark.g or 0, dark.b or 0, dark.a or 0
	end

	if attachment.type == "region" then
		-- Region worldVertices are interleaved: x, y, u, v per vertex.
		for i = 1, 4 do
			local o = (i - 1) * 4
			table.insert(group.vertices, {
				{ worldVertices[o + 1], worldVertices[o + 2], 0 },
				{ worldVertices[o + 3], worldVertices[o + 4] },
				{ r, g, b, a },
				{ dr, dg, db, da },
			})
		end
	else
		local uvs = attachment.uvs
		for i = 1, vertexCount do
			local vx = worldVertices[i * 2 - 1] or 0
			local vy = worldVertices[i * 2] or 0
			local vu = uvs and uvs[i * 2 - 1] or 0
			local vv = uvs and uvs[i * 2] or 0
			table.insert(group.vertices, { { vx, vy, 0 }, { vu, vv }, { r, g, b, a }, { dr, dg, db, da } })
		end
	end

	for i = 1, #indices do
		group.indices[#group.indices + 1] = indices[i] + base
	end
end

-- Draws all collected groups: one draw call per (texture page, render state).
function Renderer:flushBatches(batch, pass)
	for _, group in ipairs(batch.order) do
		local material = self:getMaterial(group.texture)
		if not material then
			-- No way to create a material on this LÖVR version; skip the group.
			self.vertexCount = self.vertexCount + #group.vertices
			self.triangleCount = self.triangleCount + #group.indices / 3
			break
		end

		local meshInfo = self:getBatchMesh(group.texture, #group.vertices)
		if not meshInfo or not meshInfo.mesh then
			self.vertexCount = self.vertexCount + #group.vertices
			self.triangleCount = self.triangleCount + #group.indices / 3
			break
		end

		local buffer = meshInfo.buffer
		buffer:setData(group.vertices, 1)
		local mesh = meshInfo.mesh
		mesh:setIndices(group.indices)
		mesh:setMaterial(material)

		local alphaMode = group.pma and "premultiplied" or "alphamultiply"

		if group.blendMode == "multiply" then
			pass:setColor(1, 1, 1, 1)
		end

		if group.blendMode == "additive" then
			pass:setBlendMode("add", alphaMode)
		elseif group.blendMode == "multiply" then
			pass:setBlendMode("alpha", alphaMode)
		elseif group.blendMode == "screen" then
			pass:setBlendMode("add", alphaMode)
		else
			pass:setBlendMode("alpha", alphaMode)
		end

		local usedShader = false
		if group.blendMode == "multiply" and self.multiplyMaskShader then
			pass:setShader(self.multiplyMaskShader)
			usedShader = true
		elseif group.hasDark and self.tintBlack and self.tintBlack.shader then
			pass:setShader(self.tintBlack.shader)
			if not self.tintBlack.perVertex and group.darkColor then
				pass:send("darkColor", {
					group.darkColor.r or 0,
					group.darkColor.g or 0,
					group.darkColor.b or 0,
					group.darkColor.a or 1,
				})
			end
			usedShader = true
		end

		pass:draw(mesh)

		if usedShader then
			pass:setShader()
		end

		pass:setBlendMode("alpha", "alphamultiply")

		self.drawCalls = self.drawCalls + 1
		self.vertexCount = self.vertexCount + #group.vertices
		self.triangleCount = self.triangleCount + #group.indices / 3
	end
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
				passPolygonFlat(pass,
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
				passBox(pass, "line", cx, cy, 0, maxX - minX, maxY - minY, 0.01)
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
					passPolygon(pass, "line", poly)
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
	self.tintBlack = nil -- { shader = ..., perVertex = bool } or nil
	self.multiplyMaskShader = nil
	self.drawCalls = 0
	self.vertexCount = 0
	self.triangleCount = 0
	self.materials = setmetatable({}, { __mode = "k" })
	self.batchMeshes = setmetatable({}, { __mode = "k" })
	self.stencilOk = nil -- nil = not probed yet
	self.hasStencil = true

	local ok, result = pcall(require, "spine.tintblack_shader")
	if ok and type(result) == "table" and result.shader then
		self.tintBlack = result
	end

	local ok2, result2 = pcall(require, "spine.multiply_mask_shader")
	if ok2 and type(result2) == "userdata" then
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

-- Draw the skeleton. Accepts either a Mat4 transform or the same positional
-- arguments as spine.draw: (x, y, z, scaleX, scaleY, scaleZ, rotation).
function SkeletonRenderer:draw(skeleton, pass, ...)
	local transform = mathModule.buildTransform(...)
	self.renderer.debug = self.debug
	self.renderer:drawSkeleton(skeleton, pass, transform)
end

function SkeletonRenderer:drawDebug(skeleton, pass, ...)
	local transform = mathModule.buildTransform(...)
	pass:push()
	if transform then
		pass:transform(transform)
	end
	self.renderer:drawDebugSkeleton(skeleton, pass)
	pass:pop()
end

function SkeletonRenderer:setDebug(debug)
	self.debug = debug
end

local renderingModule = {
	Renderer = Renderer,
	SkeletonRenderer = SkeletonRenderer,
}

return renderingModule
