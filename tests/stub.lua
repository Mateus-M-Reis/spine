-- Minimal LÖVR stub for headless testing of the Spine runtime.
-- It simulates just enough of the LÖVR API to load skeletons, run animation
-- state, and exercise the rendering pipeline, while recording call counts.

local M = {
  graphics = {},
  filesystem = {},
  math = {},
  timer = {},
  event = {
    quit = function() end,
  },
}

-- Counters
M.counts = {
  materials = 0,
  buffers = 0,
  meshes = 0,
  textures = 0,
  verticesUploaded = 0, -- legacy alias for float count
  vertexFloatsUploaded = 0,
}

M.VERTEX_COMPONENTS = 13

M.timer.getTime = function()
  return os.clock()
end

M.filesystem.read = function(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local data = f:read("*a")
  f:close()
  return data
end

M.filesystem.isFile = function(path)
  local f = io.open(path, "rb")
  if f then
    f:close()
    return true
  end
  return false
end

M.filesystem.getSource = function()
  return "."
end

-- Mat4 stub: records the operations so tests can verify transform usage.
M.math.newMat4 = function()
  local mat = { ops = {} }
  function mat:translate(x, y, z)
    table.insert(self.ops, { "translate", x, y, z })
    return self
  end
  function mat:rotate(angle, x, y, z)
    table.insert(self.ops, { "rotate", angle, x, y, z })
    return self
  end
  function mat:scale(x, y, z)
    table.insert(self.ops, { "scale", x, y, z })
    return self
  end
  return mat
end

M.graphics.newShader = function()
  return { isShader = true }
end

M.graphics.newTexture = function(path)
  M.counts.textures = M.counts.textures + 1
  local texture = {
    path = path,
    released = false,
    getDimensions = function() return 2048, 2048 end,
    getWidth = function() return 2048 end,
    getHeight = function() return 2048 end,
    setSampler = function() end,
    setFilter = function() end,
  }
  function texture:release()
    self.released = true
  end
  return texture
end

M.graphics.newSampler = function()
  return { isSampler = true }
end

M.graphics.newBuffer = function(format, vertexCount)
  M.counts.buffers = M.counts.buffers + 1
  local buffer = {
    format = format,
    vertexCount = vertexCount,
    data = nil,
  }
  function buffer:setData(data, start, source, count)
    self.data = data
    self.start = start
    local n = count or #data
    M.counts.verticesUploaded = M.counts.verticesUploaded + n
    M.counts.vertexFloatsUploaded = M.counts.vertexFloatsUploaded + n
  end
  function buffer:getVertexBuffer()
    return self
  end
  return buffer
end

M.graphics.newMesh = function(buffer)
  M.counts.meshes = M.counts.meshes + 1
  local mesh = {
    buffer = buffer,
    indices = nil,
    material = nil,
  }
  function mesh:setIndices(indices)
    self.indices = indices
  end
  function mesh:setMaterial(material)
    self.material = material
  end
  function mesh:getVertexBuffer()
    return self.buffer
  end
  function mesh:getVertexCount()
    return self.buffer.vertexCount
  end
  return mesh
end

M.graphics.newMaterial = function(options)
  M.counts.materials = M.counts.materials + 1
  return { texture = options and options.texture }
end

-- Pass stub. If M.passStencil is false, setStencilWrite returns nil,error so
-- the runtime falls back to unclipped drawing.
M.newPass = function()
  local pass = {
    draws = 0,
    polygons = 0,
    stencilWrites = {},
    stencilTests = {},
    colorWrites = {},
    transforms = {},
    blendModes = {},
    shaders = {},
    sends = {},
  }
  function pass:push() end
  function pass:pop() end
  function pass:transform(t)
    table.insert(self.transforms, t)
  end
  function pass:draw()
    self.draws = self.draws + 1
  end
  function pass:setColor() end
  function pass:setBlendMode(mode, alphaMode)
    table.insert(self.blendModes, { mode, alphaMode })
  end
  function pass:setShader(shader)
    table.insert(self.shaders, shader)
  end
  function pass:send(name, value)
    table.insert(self.sends, { name, value })
  end
  function pass:polygon(mode, verts)
    self.polygons = self.polygons + 1
  end
  function pass:line() end
  function pass:points() end
  function pass:box() end
  function pass:text() end
  function pass:setStencilWrite(mode, value)
    if not M.passStencil then
      error("stencil not supported")
    end
    table.insert(self.stencilWrites, mode)
  end
  function pass:setStencilTest(mode, value)
    if not M.passStencil then
      error("stencil not supported")
    end
    table.insert(self.stencilTests, { mode, value })
  end
  function pass:setColorWrite(r, g, b, a)
    table.insert(self.colorWrites, { r, g, b, a })
  end
  return pass
end

M.passStencil = true

_G.lovr = M
return M
