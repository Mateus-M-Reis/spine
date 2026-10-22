-- Spine LÖVR Runtime - Atlas Management
-- Handles texture atlas loading and region management

local utilsModule = require("spine.utils")

local AtlasRegion = {}
AtlasRegion.__index = AtlasRegion

function AtlasRegion.new()
	local self = setmetatable({}, AtlasRegion)
	self.name = ""
	self.x = 0
	self.y = 0
	self.width = 0
	self.height = 0
	self.u = 0
	self.v = 0
	self.u2 = 0
	self.v2 = 0
	self.rotate = false
	self.offsetX = 0
	self.offsetY = 0
	self.originalWidth = 0
	self.originalHeight = 0
	self.index = 0
	self.texture = nil
	self.page = nil
	return self
end

function AtlasRegion:setTexture(texture)
	self.texture = texture
	self._textureKey = texture and tostring(texture) or nil
	if texture then
		local texWidth, texHeight = texture:getDimensions()
		self.textureWidth = texWidth
		self.textureHeight = texHeight
		self.u = self.x / texWidth
		self.v = self.y / texHeight
		self.u2 = (self.x + self.width) / texWidth
		self.v2 = (self.y + self.height) / texHeight
	end
end

local AtlasPage = {}
AtlasPage.__index = AtlasPage

function AtlasPage.new(name)
	local self = setmetatable({}, AtlasPage)
	self.name = name
	self.texture = nil
	self.width = 0
	self.height = 0
	self.minFilter = "linear"
	self.magFilter = "linear"
	self.uWrap = "clamp"
	self.vWrap = "clamp"
	self.pma = false
	return self
end

local Atlas = {}
Atlas.__index = Atlas

function Atlas.new()
	local self = setmetatable({}, Atlas)
	self.pages = {}
	self.regions = {}
	self.regionsByName = {}
	return self
end

function Atlas:loadAtlasFile(atlasText, imagePath)
	if type(atlasText) ~= "string" then
		return nil, "Atlas data must be a string"
	end

	-- Reloading an Atlas should not leak the previous pages' textures.
	if #self.pages > 0 then
		self:dispose()
	end

	local lines = {}
	local normalized = atlasText:gsub("\r\n", "\n"):gsub("\r", "\n")
	for line in (normalized .. "\n"):gmatch("(.-)\n") do
		table.insert(lines, line)
	end

	local currentPage = nil
	local currentRegion = nil
	local expectPage = true
	local pageRegionStart = 0

	local function startPage(name)
		currentPage = AtlasPage.new(name)
		currentRegion = nil
		expectPage = false
		pageRegionStart = #self.regions
		table.insert(self.pages, currentPage)
	end

	local function startRegion(name)
		currentRegion = AtlasRegion.new()
		currentRegion.name = name
		currentRegion.page = currentPage
		table.insert(self.regions, currentRegion)
		self.regionsByName[name] = currentRegion
	end

	for _, line in ipairs(lines) do
		if line:match("^%s*$") then
			-- A blank line after regions ends the current page. A blank line
			-- between a page header and its first region does not. The next
			-- non-property line after the former is a new page name, so
			-- multi-page atlases do not turn page headers into regions.
			currentRegion = nil
			expectPage = currentPage ~= nil and #self.regions > pageRegionStart
		else
			local key, value = line:match("^%s*([%w_]+):%s*(.-)%s*$")
			if key then
				if currentRegion then
					self:parseRegionProperty(currentRegion, key, value)
				elseif currentPage then
					self:parsePageProperty(currentPage, key, value)
				else
					return nil, "Atlas property before page header: " .. line
				end
			else
				local name = line:gsub("^%s+", ""):gsub("%s+$", "")
				if expectPage or not currentPage then
					startPage(name)
				else
					startRegion(name)
				end
			end
		end
	end

	-- Post-process regions to handle defaults and rotation
	for _, region in ipairs(self.regions) do
		if region.rotate then
			-- Swap width and height because bounds in atlas are unrotated size,
			-- but we need packed size for UV calculations.
			local w = region.width
			local h = region.height
			region.width = h
			region.height = w

			if region.originalWidth == 0 then
				region.originalWidth = w
			end
			if region.originalHeight == 0 then
				region.originalHeight = h
			end
		else
			if region.originalWidth == 0 and region.width > 0 then
				region.originalWidth = region.width
			end
			if region.originalHeight == 0 and region.height > 0 then
				region.originalHeight = region.height
			end
		end
	end

	for _, page in ipairs(self.pages) do
		local ok, err = self:loadPageTexture(page, imagePath)
		if not ok then
			self:dispose()
			return nil, err
		end
	end

	return true
end

function Atlas:parsePageProperty(page, key, value)
	if key == "size" then
		local width, height = value:match("(%d+),(%d+)")
		if width and height then
			page.width = tonumber(width)
			page.height = tonumber(height)
		end
	elseif key == "format" then
		-- RGBA8888, RGBA4444, etc. (not used in Love2D)
	elseif key == "filter" then
		local min, mag = value:match("^%s*(%w+)%s*,%s*(%w+)%s*$")
		if min and mag then
			page.minFilter = min
			page.magFilter = mag
		end
	elseif key == "repeat" then
		local wrap = value:match("^%s*(%w+)%s*$")
		if wrap == "x" then
			page.uWrap = "repeat"
		elseif wrap == "y" then
			page.vWrap = "repeat"
		elseif wrap == "xy" then
			page.uWrap = "repeat"
			page.vWrap = "repeat"
		end
	elseif key == "pma" then
		local pma = value:match("^%s*(%w+)%s*$")
		page.pma = (pma == "true")
	elseif key == "scale" then
		page.scale = tonumber(value)
	end
end

function Atlas:parseRegionProperty(region, key, value)
	if key == "rotate" then
		region.rotate = value == "true" or value == "90"
	elseif key == "xy" then
		local x, y = value:match("^%s*([+-]?%d+)%s*,%s*([+-]?%d+)")
		if x and y then
			region.x = tonumber(x)
			region.y = tonumber(y)
		end
	elseif key == "size" then
		local width, height = value:match("^%s*([+-]?%d+)%s*,%s*([+-]?%d+)")
		if width and height then
			region.width = tonumber(width)
			region.height = tonumber(height)
		end
	elseif key == "bounds" then
		local x, y, width, height = value:match(
			"^%s*([+-]?%d+)%s*,%s*([+-]?%d+)%s*,%s*([+-]?%d+)%s*,%s*([+-]?%d+)")
		if x and y and width and height then
			region.x = tonumber(x)
			region.y = tonumber(y)
			region.width = tonumber(width)
			region.height = tonumber(height)
		end
	elseif key == "orig" then
		local width, height = value:match("^%s*([+-]?%d+)%s*,%s*([+-]?%d+)")
		if width and height then
			region.originalWidth = tonumber(width)
			region.originalHeight = tonumber(height)
		end
	elseif key == "offset" then
		local x, y = value:match("^%s*([+-]?%d+)%s*,%s*([+-]?%d+)")
		if x and y then
			region.offsetX = tonumber(x)
			region.offsetY = tonumber(y)
		end
	elseif key == "offsets" then
		local x, y, width, height = value:match(
			"^%s*([+-]?%d+)%s*,%s*([+-]?%d+)%s*,%s*([+-]?%d+)%s*,%s*([+-]?%d+)")
		if x and y and width and height then
			region.offsetX = tonumber(x)
			region.offsetY = tonumber(y)
			region.originalWidth = tonumber(width)
			region.originalHeight = tonumber(height)
		end
	elseif key == "index" then
		region.index = tonumber(value)
	end
end

function Atlas:loadPageTexture(page, imagePath)
	local textureName = page.name
	local texturePath = utilsModule.joinPath(imagePath, textureName)

	local texture = nil
	local triedPaths = {}

	-- Try the exact path first
	if lovr.filesystem.isFile(texturePath) then
		texture = lovr.graphics.newTexture(texturePath)
		table.insert(triedPaths, texturePath)
	else
		-- Try common image extensions
		local extensions = { "png", "jpg", "jpeg" }
		for _, ext in ipairs(extensions) do
			local path = texturePath .. "." .. ext
			table.insert(triedPaths, path)
			if lovr.filesystem.isFile(path) then
				texture = lovr.graphics.newTexture(path)
				break
			end
		end
	end

	if not texture then
		return nil,
			("Could not load texture '%s' from path '%s'. Tried paths: %s"):format(
				textureName,
				imagePath,
				table.concat(triedPaths, ", ")
			)
	end

	page.texture = texture

	local filter = (page.minFilter == "nearest" or page.magFilter == "nearest") and "nearest" or "linear"
	local wrapU = page.uWrap == "repeat" and "repeat" or "clamp"
	local wrapV = page.vWrap == "repeat" and "repeat" or "clamp"

	local sampler = lovr.graphics.newSampler({
		filter = { filter, filter, filter },
		wrap = { wrapU, wrapV, "clamp" }
	})
	texture:setSampler(sampler)

	-- Update region texture coordinates
	for _, region in ipairs(self.regions) do
		if region.page == page then
			region:setTexture(texture)
		end
	end

	return true
end

function Atlas:findRegion(name)
	return self.regionsByName[name]
end

function Atlas:getRegions()
	return self.regions
end

function Atlas:getPages()
	return self.pages
end

function Atlas:dispose()
	for _, page in ipairs(self.pages) do
		if page.texture then
			page.texture:release()
			page.texture = nil
		end
	end
	self.pages = {}
	self.regions = {}
	self.regionsByName = {}
end

local AtlasAttachmentLoader = {}
AtlasAttachmentLoader.__index = AtlasAttachmentLoader

function AtlasAttachmentLoader.new(atlas)
	local self = setmetatable({}, AtlasAttachmentLoader)
	self.atlas = atlas
	return self
end

-- Resolves a region (or a Spine 4.2 sequence of regions) from the atlas.
-- With a sequence, fills sequence.regions with the numbered regions and
-- returns the setup region.
local function resolveRegion(atlas, path, name, sequence)
	if sequence then
		sequence.regions = {}
		for i = 0, sequence.count - 1 do
			local fullPath = sequence:getPath(path or name, i)
			sequence.regions[i + 1] = atlas:findRegion(fullPath)
		end
		local region = sequence.regions[sequence.setupIndex + 1] or sequence.regions[1]
		if not region then
			-- Fall back to the unnumbered region name.
			region = atlas:findRegion(path or name)
		end
		return region
	end
	return atlas:findRegion(path or name)
end

function AtlasAttachmentLoader:newRegionAttachment(skin, name, path, sequence)
	local region = resolveRegion(self.atlas, path, name, sequence)
	if not region then
		return nil, ("Region not found in atlas: %s"):format(path or name)
	end

	local attachment = require("spine.data").RegionAttachment.new(name)

	-- Set region reference
	attachment.region = region
	attachment.path = path or name
	attachment.sequence = sequence

	-- Call updateRegion() to calculate offset and UVs with proper scaling
	attachment:updateRegion()

	return attachment
end

function AtlasAttachmentLoader:newMeshAttachment(skin, name, path, sequence)
	local region = resolveRegion(self.atlas, path, name, sequence)
	if not region then
		return nil, ("Region not found in atlas: %s"):format(path or name)
	end

	local attachment = require("spine.data").MeshAttachment.new(name)

	-- Set region properties.
	attachment.region = region
	attachment.sequence = sequence

	-- Width/height come from the JSON (geometry size), not the region size;
	-- the region's UVs are used by createAttachment/updateRegion.

	return attachment
end

function AtlasAttachmentLoader:findRegion(path)
	return self.atlas:findRegion(path)
end

function AtlasAttachmentLoader:newBoundingBoxAttachment(skin, name)
	return require("spine.data").BoundingBoxAttachment.new(name)
end

function AtlasAttachmentLoader:newPathAttachment(skin, name)
	return require("spine.data").PathAttachment.new(name)
end

function AtlasAttachmentLoader:newClippingAttachment(skin, name)
	return require("spine.data").ClippingAttachment.new(name)
end

-- Module exports
local atlasModule = {
	Atlas = Atlas,
	AtlasPage = AtlasPage,
	AtlasRegion = AtlasRegion,
	AtlasAttachmentLoader = AtlasAttachmentLoader,
}

return atlasModule
