-- Spine LOVR Runtime - Rendering System
-- Handles drawing Spine skeletons using LOVR's pass-based graphics API

local mathModule = require("spine.math")
local utilsModule = require("spine.utils")
local unpackValues = table.unpack or unpack

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
	pcall(pass.polygon, pass, unpackValues(verts))
end

local function passPolygonFlat(pass, mode, ...)
	local verts = { ... }
	local ok = pcall(pass.polygon, pass, mode, verts)
	if ok then return end
	ok = pcall(pass.polygon, pass, verts)
	if ok then return end
	pcall(pass.polygon, pass, unpackValues(verts))
end

local function passBox(pass, mode, x, y, z, sx, sy, sz)
	local ok = pcall(pass.box, pass, mode, x, y, z, sx, sy, sz)
	if ok then return end
	pcall(pass.box, pass, x, y, z, sx, sy, sz)
end

local Renderer = {}
Renderer.__index = Renderer

-- Draws a single stencil triangle, detecting the pass:polygon calling
-- convention once instead of probing it with pcall for every triangle.
function Renderer:drawStencilTriangle(pass, poly)
	if self.polygonStyle == nil then
		if pcall(pass.polygon, pass, "fill", poly) then
			self.polygonStyle = "mode"
			return true
		elseif pcall(pass.polygon, pass, poly) then
			self.polygonStyle = "table"
			return true
		elseif pcall(pass.polygon, pass, unpackValues(poly)) then
			self.polygonStyle = "unpacked"
			return true
		end
		return false
	end

	if self.polygonStyle == "mode" then
		pass:polygon("fill", poly)
	elseif self.polygonStyle == "table" then
		pass:polygon(poly)
	else
		pass:polygon(unpackValues(poly))
	end
	return true
end

-- Fill a clipping attachment's polygon into the stencil buffer.
-- writeMode is "increment" (mark region) or "decrement" (unmark region).
-- Color writes are disabled while drawing the stencil polygon.
-- Returns false if the polygon could not be computed/triangulated.
function Renderer:stencilPolygon(slot, clipping, pass, writeMode)
	local vertexCount = clipping.vertexCount or math.floor(#clipping.vertices / 2)
	local required = vertexCount * 2
	if required < 6 then
		return false
	end

	local worldVertices = self._clipVertices
	if not worldVertices then
		worldVertices = {}
		self._clipVertices = worldVertices
	end
	clipping:computeWorldVertices(slot, worldVertices)

	-- Truncate stale values from a previous, longer clipping polygon.
	for i = required + 1, #worldVertices do
		worldVertices[i] = nil
	end

	for i = 1, required do
		if not isValidNumber(worldVertices[i]) then
			return false
		end
	end

	-- Triangulation topology is stable for a given clipping attachment; only
	-- recompute it if the vertex count changes.
	local triIndices = clipping._lovrTriIndices
	if not triIndices or clipping._lovrTriVertexCount ~= required then
		triIndices = utilsModule.triangulate(worldVertices)
		clipping._lovrTriIndices = triIndices
		clipping._lovrTriVertexCount = required
	end
	if #triIndices < 3 then
		return false
	end

	local ok = pcall(pass.setStencilWrite, pass, writeMode, 1)
	if not ok then
		return false
	end

	local colorWriteOff = pcall(pass.setColorWrite, pass, false, false, false, false)
	pass:setColor(1, 1, 1)

	local poly = {}
	local drewAll = true
	for j = 1, #triIndices, 3 do
		poly[1] = worldVertices[triIndices[j] * 2 + 1]
		poly[2] = worldVertices[triIndices[j] * 2 + 2]
		poly[3] = 0
		poly[4] = worldVertices[triIndices[j + 1] * 2 + 1]
		poly[5] = worldVertices[triIndices[j + 1] * 2 + 2]
		poly[6] = 0
		poly[7] = worldVertices[triIndices[j + 2] * 2 + 1]
		poly[8] = worldVertices[triIndices[j + 2] * 2 + 2]
		poly[9] = 0

		if not self:drawStencilTriangle(pass, poly) then
			drewAll = false
			break
		end
	end

	if colorWriteOff then
		pcall(pass.setColorWrite, pass, true, true, true, true)
	end
	pcall(pass.setStencilWrite, pass)

	return drewAll
end

local function newBatch()
	return { groups = {}, order = {}, lastKey = nil }
end

-- Draws drawOrder[startIndex..endIndex] with clipping support.
-- clipDepth is the number of enclosing clips (equals the stencil value of the
-- surrounding region). Clipping attachments mark their polygon with an
-- incrementing stencil write, draw their range against `equal (depth + 1)`,
-- then decrement the polygon back so enclosing clips are unaffected.
-- Nested clips work because each level uses a distinct stencil value.
function Renderer:drawDrawOrderRange(skeleton, pass, drawOrder, startIndex, endIndex, clipDepth)
	local batch = newBatch()
	local i = startIndex
	while i <= endIndex do
		local slot = drawOrder[i]
		local attachment = slot.attachment

		if attachment and attachment.type == "clipping" and self.hasStencil ~= false then
			-- Everything collected before the clip must be drawn before the
			-- clipped range; otherwise the clip silently reorders the skeleton.
			if #batch.order > 0 then
				self:flushBatches(batch, pass)
				batch = newBatch()
			end

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
			self:collectAttachment(batch, slot, attachment, pass)
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

-- VertexPosition (3) + VertexUV (2) + VertexColor (4) + VertexDarkColor (4).
local VERTEX_COMPONENTS = 13

local function appendVertex(group, x, y, u, v, r, g, b, a, dr, dg, db, da)
	local verts = group.vertices
	local n = group.vertexCount * VERTEX_COMPONENTS
	verts[n + 1] = x
	verts[n + 2] = y
	verts[n + 3] = 0
	verts[n + 4] = u
	verts[n + 5] = v
	verts[n + 6] = r
	verts[n + 7] = g
	verts[n + 8] = b
	verts[n + 9] = a
	verts[n + 10] = dr
	verts[n + 11] = dg
	verts[n + 12] = db
	verts[n + 13] = da
	group.vertexCount = group.vertexCount + 1
end

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

-- Get (or create) a growable Buffer/Mesh pair for one batch group. Each
-- group needs its OWN buffer: LÖVR records draws and executes them later, so
-- overwriting a shared buffer between recorded draws would make every group
-- render the last group's vertices (garbage triangles).
function Renderer:getBatchMesh(groupKey, vertexCount)
	if not self.batchMeshes then
		self.batchMeshes = {}
	end
	local info = self.batchMeshes[groupKey]
	if not info then
		info = { capacity = 0 }
		self.batchMeshes[groupKey] = info
	end
	if info.capacity < vertexCount then
		local capacity = math.max(vertexCount, info.capacity * 2, 256)
		info.buffer = lovr.graphics.newBuffer(VERTEX_FORMAT, capacity)
		info.mesh = lovr.graphics.newMesh(info.buffer)
		info.capacity = capacity
	end
	return info
end

-- Returns a cleared group for the given render state. The group's backing
-- arrays are reused across frames; setData is given an explicit float count so
-- stale values left past the end are ignored.
function Renderer:acquireGroup(key, texture, blendMode, pma, hasDark, darkColor)
	local group = self.groupPool[key]
	if not group then
		group = {
			key = key,
			texture = texture,
			blendMode = blendMode,
			pma = pma,
			hasDark = hasDark,
			darkColor = darkColor,
			vertices = {},
			indices = {},
			vertexCount = 0,
			indexCount = 0,
		}
		self.groupPool[key] = group
	else
		-- Drop the previous index values so #indices matches indexCount.
		for i = group.indexCount, 1, -1 do
			group.indices[i] = nil
		end
		group.vertexCount = 0
		group.indexCount = 0
		group.hasDark = hasDark
		group.darkColor = darkColor
	end
	return group
end

-- Collects one attachment's vertices into the batch, grouped by texture page
-- and render state (blend mode, premultiplication, tint). Nothing is drawn yet;
-- flushBatches draws one mesh per group.
function Renderer:collectAttachment(batch, slot, attachment, pass)
	local region = attachment.region
	if not region or not region.texture then
		return
	end

	local pma = not not (region.page and region.page.pma)
	local skeleton = slot.bone and slot.bone.skeleton
	local slotColor = slot.color
	local attachmentColor = attachment.color
	local skeletonColor = skeleton or {}

	-- Spine multiplies skeleton, slot and attachment color. Alpha is the
	-- product of all three, and PMA textures get premultiplied RGB.
	local alpha = (skeletonColor.a or 1) * (slotColor.a or 1) * (attachmentColor and attachmentColor.a or 1)
	local r = (skeletonColor.r or 1) * (slotColor.r or 1) * (attachmentColor and attachmentColor.r or 1)
	local g = (skeletonColor.g or 1) * (slotColor.g or 1) * (attachmentColor and attachmentColor.g or 1)
	local b = (skeletonColor.b or 1) * (slotColor.b or 1) * (attachmentColor and attachmentColor.b or 1)
	local a = alpha
	if pma then
		r, g, b = r * alpha, g * alpha, b * alpha
	end

	local isRegion = attachment.type == "region"
	local vertexCount
	if isRegion then
		vertexCount = 4
	elseif attachment.type == "mesh" then
		vertexCount = math.floor(#attachment.uvs / 2)
	else
		return
	end
	if vertexCount == 0 then return end

	-- Reuse one scratch array; computeWorldVertices overwrites every value we
	-- read. This keeps steady-state rendering free of per-attachment garbage.
	local worldVertices = self._worldVertices
	if not worldVertices then
		worldVertices = {}
		self._worldVertices = worldVertices
	end
	if isRegion then
		attachment:computeWorldVertices(slot.bone, worldVertices)
	else
		attachment:computeWorldVertices(slot, worldVertices)
	end

	local requiredVertices = vertexCount * 2
	for i = 1, requiredVertices do
		if not isValidNumber(worldVertices[i]) then
			return
		end
	end

	local blendMode = slot.data.blendMode or "normal"
	local dark = slot.darkColor
	local dr, dg, db, da = 0, 0, 0, pma and 1 or 0
	if dark then
		dr, dg, db = dark.r or 0, dark.g or 0, dark.b or 0
		if pma then
			dr, dg, db = dr * alpha, dg * alpha, db * alpha
		end
	end

	local tintKey = ""
	if dark then
		if self.tintBlack and self.tintBlack.perVertex then
			tintKey = "tint"
		else
			tintKey = string.format("%.3f,%.3f,%.3f,%.3f", dr, dg, db, da)
		end
	end
	local textureKey = region._textureKey
	if not textureKey then
		textureKey = tostring(region.texture)
		region._textureKey = textureKey
	end
	local key = textureKey .. "|" .. blendMode .. "|" .. (pma and "1" or "0") .. "|" .. tintKey

	-- Preserve draw order: a batch may only contain adjacent attachments that
	-- share the same render state. Non-contiguous groups are flushed and
	-- restarted instead of being merged across other groups.
	if batch.lastKey and batch.lastKey ~= key then
		self:flushBatches(batch, pass)
		batch.groups = {}
		batch.order = {}
	end
	batch.lastKey = key

	local group = batch.groups[key]
	if not group then
		group = self:acquireGroup(key, region.texture, blendMode, pma,
			dark ~= nil, dark and { r = dr, g = dg, b = db, a = da } or nil)
		batch.groups[key] = group
		table.insert(batch.order, group)
	end

	local base = group.vertexCount
	local indices
	if isRegion then
		indices = REGION_INDICES
		-- Region worldVertices are interleaved: x, y, u, v per vertex.
		for i = 1, 4 do
			local o = (i - 1) * 4
			appendVertex(group,
				worldVertices[o + 1], worldVertices[o + 2],
				worldVertices[o + 3], worldVertices[o + 4],
				r, g, b, a, dr, dg, db, da)
		end
	else
		indices = attachment._lovrIndices
		if not indices then
			indices = {}
			for i = 1, #attachment.triangles do
				indices[i] = attachment.triangles[i] + 1
			end
			attachment._lovrIndices = indices
		end

		local uvs = attachment.uvs
		for i = 1, vertexCount do
			appendVertex(group,
				worldVertices[i * 2 - 1] or 0, worldVertices[i * 2] or 0,
				uvs and uvs[i * 2 - 1] or 0, uvs and uvs[i * 2] or 0,
				r, g, b, a, dr, dg, db, da)
		end
	end

	local groupIndices = group.indices
	local indexCount = group.indexCount
	for i = 1, #indices do
		indexCount = indexCount + 1
		groupIndices[indexCount] = indices[i] + base
	end
	group.indexCount = indexCount
end

-- Draws all collected groups: one draw call per (texture page, render state).
function Renderer:flushBatches(batch, pass)
	for _, group in ipairs(batch.order) do
		local material = self:getMaterial(group.texture)
		if not material then
			-- No way to create a material on this LÖVR version; skip the group.
			self.vertexCount = self.vertexCount + group.vertexCount
			self.triangleCount = self.triangleCount + group.indexCount / 3
			goto continue
		end

		local meshInfo = self:getBatchMesh(group.key, group.vertexCount)
		if not meshInfo or not meshInfo.mesh then
			self.vertexCount = self.vertexCount + group.vertexCount
			self.triangleCount = self.triangleCount + group.indexCount / 3
			goto continue
		end

		local buffer = meshInfo.buffer
		buffer:setData(group.vertices, 1, 1, group.vertexCount * VERTEX_COMPONENTS)
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
			pass:setBlendMode("screen", alphaMode)
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
		self.vertexCount = self.vertexCount + group.vertexCount
		self.triangleCount = self.triangleCount + group.indexCount / 3

		::continue::
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
	self.groupPool = {} -- reusable vertex/index tables keyed by render state
	self._worldVertices = {} -- scratch for attachment vertices
	self._clipVertices = {} -- scratch for clipping polygons
	self.polygonStyle = nil -- nil = not probed yet
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

-- Releases per-instance GPU resources (materials and batch buffers/meshes).
-- Shared atlas textures are owned by the asset cache and are not released here.
function Renderer:release()
	if self.materials then
		for _, material in pairs(self.materials) do
			if material and material.release then
				pcall(material.release, material)
			end
		end
	end
	self.materials = setmetatable({}, { __mode = "k" })

	if self.batchMeshes then
		for _, info in pairs(self.batchMeshes) do
			if info.mesh and info.mesh.release then
				pcall(info.mesh.release, info.mesh)
			end
			if info.buffer and info.buffer.release then
				pcall(info.buffer.release, info.buffer)
			end
		end
	end
	self.batchMeshes = setmetatable({}, { __mode = "k" })
	self.groupPool = {}
	self._worldVertices = {}
	self._clipVertices = {}
	self.polygonStyle = nil
	self.drawCalls, self.vertexCount, self.triangleCount = 0, 0, 0
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

function SkeletonRenderer:release()
	self.renderer:release()
end

local renderingModule = {
	Renderer = Renderer,
	SkeletonRenderer = SkeletonRenderer,
}

return renderingModule
