-- Spine LÖVR Runtime - Utility functions module
-- Provides JSON parsing, string handling, table operations, and other utilities

local utils = {}

-- JSON解析器 (简化版)
local function parseJson(str)
  local pos = 1
  local len = #str

  local function skipWhitespace()
    while pos <= len and str:match("^%s", pos) do
      pos = pos + 1
    end
  end

  -- Forward declarations
  local parseValue, parseObject, parseArray, parseString, parseNumber, parseBoolean, parseNull

  parseValue = function()
    skipWhitespace()

    if pos > len then
      return nil
    end

    local char = str:sub(pos, pos)
    -- print("Parsing value at " .. pos .. ": " .. char)

    if char == '"' then
      return parseString()
    elseif char == '{' then
      return parseObject()
    elseif char == '[' then
      return parseArray()
    elseif char == 't' or char == 'f' then
      return parseBoolean()
    elseif char == 'n' then
      return parseNull()
    else
      return parseNumber()
    end
  end

  parseString = function()
    pos = pos + 1 -- 跳过开始引号
    local start = pos
    local result = {}

    while pos <= len do
      local char = str:sub(pos, pos)

      if char == '"' then
        table.insert(result, str:sub(start, pos - 1))
        pos = pos + 1
        return table.concat(result)
      elseif char == '\\' then
        table.insert(result, str:sub(start, pos - 1))
        pos = pos + 1

        if pos > len then
          return nil
        end

        local escape = str:sub(pos, pos)
        if escape == '"' then
          table.insert(result, '"')
        elseif escape == '\\' then
          table.insert(result, '\\')
        elseif escape == '/' then
          table.insert(result, '/')
        elseif escape == 'b' then
          table.insert(result, '\b')
        elseif escape == 'f' then
          table.insert(result, '\f')
        elseif escape == 'n' then
          table.insert(result, '\n')
        elseif escape == 'r' then
          table.insert(result, '\r')
        elseif escape == 't' then
          table.insert(result, '\t')
        else
          table.insert(result, escape)
        end

        pos = pos + 1
        start = pos
      else
        pos = pos + 1
      end
    end

    return nil -- 未闭合的字符串
  end

  parseObject = function()
    pos = pos + 1 -- 跳过 {
    local result = {}

    skipWhitespace()

    if pos <= len and str:sub(pos, pos) == '}' then
      pos = pos + 1
      return result
    end

    while pos <= len do
      local key = parseString()

      if not key then
        -- Check for trailing comma (key is missing, but we see })
        if str:sub(pos, pos) == '}' then
            pos = pos + 1
            return result
        end
        return nil
      end

      skipWhitespace()

      if pos > len or str:sub(pos, pos) ~= ':' then
        return nil
      end

      pos = pos + 1 -- 跳过 :

      local value = parseValue()
      result[key] = value

      skipWhitespace()

      if pos > len then
        return nil
      end

      local char = str:sub(pos, pos)

      if char == '}' then
        pos = pos + 1
        return result
      elseif char == ',' then
        pos = pos + 1
        skipWhitespace()
      else
        return nil
      end
    end

    return nil
  end

  parseArray = function()
    pos = pos + 1 -- 跳过 [
    local result = {}

    skipWhitespace()

    if pos <= len and str:sub(pos, pos) == ']' then
      pos = pos + 1
      return result
    end

    while pos <= len do
      local value = parseValue()

      if value ~= nil then
        table.insert(result, value)
      end

      skipWhitespace()

      if pos > len then
        return nil
      end

      local char = str:sub(pos, pos)

      if char == ']' then
        pos = pos + 1
        return result
      elseif char == ',' then
        pos = pos + 1
        skipWhitespace()
        -- Handle trailing comma
        if str:sub(pos, pos) == ']' then
            pos = pos + 1
            return result
        end
      else
        print("DEBUG: parseArray unexpected char " .. char .. " at " .. pos)
        return nil
      end
    end

    return nil
  end

  parseNumber = function()
    local start = pos

    -- 处理负号
    if pos <= len and str:sub(pos, pos) == '-' then
      pos = pos + 1
    end

    -- 处理整数部分
    if pos > len or not str:match("^%d", pos) then
      return nil
    end

    while pos <= len and str:match("^%d", pos) do
      pos = pos + 1
    end

    -- 处理小数部分
    if pos <= len and str:sub(pos, pos) == '.' then
      pos = pos + 1

      if pos > len or not str:match("^%d", pos) then
        return nil
      end

      while pos <= len and str:match("^%d", pos) do
        pos = pos + 1
      end
    end

    -- 处理指数部分
    if pos <= len and (str:sub(pos, pos) == 'e' or str:sub(pos, pos) == 'E') then
      pos = pos + 1

      if pos <= len and (str:sub(pos, pos) == '+' or str:sub(pos, pos) == '-') then
        pos = pos + 1
      end

      if pos > len or not str:match("^%d", pos) then
        return nil
      end

      while pos <= len and str:match("^%d", pos) do
        pos = pos + 1
      end
    end

    local numberStr = str:sub(start, pos - 1)
    return tonumber(numberStr)
  end

  parseBoolean = function()
    if str:sub(pos, pos + 3) == "true" then
      pos = pos + 4
      return true
    elseif str:sub(pos, pos + 4) == "false" then
      pos = pos + 5
      return false
    end
    return nil
  end

  parseNull = function()
    if str:sub(pos, pos + 3) == "null" then
      pos = pos + 4
      return nil
    end
    return nil
  end

  local result = parseValue()
  skipWhitespace()

  if pos <= len then
    print("JSON Parse Error: Unexpected character at position " .. pos .. ": " .. str:sub(pos, pos + 10))
    return nil, "Unexpected character at position " .. pos
  end

  if result == nil then
      print("JSON Parse Error: parseValue returned nil at position " .. pos)
  end

  return result
end

-- JSON解码
function utils.jsonDecode(str)
  if type(str) ~= "string" then
    return nil, "Input must be a string"
  end

  local success, result = pcall(parseJson, str)
  if not success then
    return nil, result
  end

  return result
end

-- JSON编码 (简化版)
function utils.jsonEncode(obj, pretty)
  pretty = pretty or false
  local indent = pretty and "  " or ""
  local newline = pretty and "\n" or ""

  local function encodeValue(value, level)
    level = level or 0
    local t = type(value)

    if t == "nil" then
      return "null"
    elseif t == "boolean" then
      return tostring(value)
    elseif t == "number" then
      -- 处理无穷大和NaN
      if value ~= value then
        return "null" -- NaN
      elseif value == math.huge then
        return "null" -- 正无穷
      elseif value == -math.huge then
        return "null" -- 负无穷
      else
        return tostring(value)
      end
    elseif t == "string" then
      -- 转义字符串
      return '"' .. value:gsub('(["\\%c])', function(c)
        if c == '"' then return '\\"'
        elseif c == '\\' then return '\\\\'
        elseif c == '\b' then return '\\b'
        elseif c == '\f' then return '\\f'
        elseif c == '\n' then return '\\n'
        elseif c == '\r' then return '\\r'
        elseif c == '\t' then return '\\t'
        else
          return string.format('\\u%04x', c:byte())
        end
      end) .. '"'
    elseif t == "table" then
      -- 检查是否为数组
      local isArray = true
      local count = 0
      for k, _ in pairs(value) do
        count = count + 1
        if type(k) ~= "number" or k < 1 or k ~= math.floor(k) then
          isArray = false
          break
        end
      end

      if isArray and count > 0 then
        -- 数组
        local parts = {}
        for i = 1, count do
          table.insert(parts, encodeValue(value[i], level + 1))
        end

        if pretty then
          local indentStr = string.rep(indent, level + 1)
          local closeIndent = string.rep(indent, level)
          return "[" .. newline ..
                 indentStr .. table.concat(parts, "," .. newline .. indentStr) .. newline ..
                 closeIndent .. "]"
        else
          return "[" .. table.concat(parts, ",") .. "]"
        end
      else
        -- 对象
        local parts = {}
        for k, v in pairs(value) do
          table.insert(parts, encodeValue(tostring(k), level + 1) .. ":" ..
                          (pretty and " " or "") .. encodeValue(v, level + 1))
        end

        if pretty then
          local indentStr = string.rep(indent, level + 1)
          local closeIndent = string.rep(indent, level)
          return "{" .. newline ..
                 indentStr .. table.concat(parts, "," .. newline .. indentStr) .. newline ..
                 closeIndent .. "}"
        else
          return "{" .. table.concat(parts, ",") .. "}"
        end
      end
    else
      return "null"
    end
  end

  return encodeValue(obj)
end

-- 颜色工具函数
function utils.hexToColor(hex)
  if not hex or #hex < 6 then return 1, 1, 1, 1 end

  local r = tonumber(hex:sub(1, 2), 16) / 255
  local g = tonumber(hex:sub(3, 4), 16) / 255
  local b = tonumber(hex:sub(5, 6), 16) / 255
  local a = 1

  if #hex >= 8 then
    a = tonumber(hex:sub(7, 8), 16) / 255
  end

  return r, g, b, a
end

-- 字符串工具函数
function utils.split(str, delimiter)
  local result = {}
  local pattern = "(.-)" .. delimiter
  local lastEnd = 1

  local start, endPos, capture = str:find(pattern, lastEnd)
  while start do
    table.insert(result, capture)
    lastEnd = endPos + 1
    start, endPos, capture = str:find(pattern, lastEnd)
  end

  table.insert(result, str:sub(lastEnd))
  return result
end

function utils.trim(str)
  return str:match("^%s*(.-)%s*$")
end

function utils.startsWith(str, prefix)
  return str:sub(1, #prefix) == prefix
end

function utils.endsWith(str, suffix)
  return str:sub(-#suffix) == suffix
end

function utils.contains(str, pattern)
  return str:find(pattern, 1, true) ~= nil
end

function utils.replace(str, old, new)
  return str:gsub(old, new)
end

-- 表操作工具函数
function utils.shallowCopy(t)
  local copy = {}
  for k, v in pairs(t) do
    copy[k] = v
  end
  return copy
end

function utils.deepCopy(t, seen)
  seen = seen or {}
  if type(t) ~= "table" then return t end
  if seen[t] then return seen[t] end

  local copy = {}
  seen[t] = copy

  for k, v in pairs(t) do
    copy[utils.deepCopy(k, seen)] = utils.deepCopy(v, seen)
  end

  return copy
end

function utils.merge(t1, t2)
  local result = utils.shallowCopy(t1)
  for k, v in pairs(t2) do
    result[k] = v
  end
  return result
end

function utils.filter(t, predicate)
  local result = {}
  for k, v in pairs(t) do
    if predicate(v, k) then
      table.insert(result, v)
    end
  end
  return result
end

function utils.map(t, transform)
  local result = {}
  for k, v in pairs(t) do
    result[k] = transform(v, k)
  end
  return result
end

function utils.reduce(t, reducer, initial)
  local result = initial
  for k, v in pairs(t) do
    result = reducer(result, v, k)
  end
  return result
end

function utils.keys(t)
  local result = {}
  for k in pairs(t) do
    table.insert(result, k)
  end
  return result
end

function utils.values(t)
  local result = {}
  for _, v in pairs(t) do
    table.insert(result, v)
  end
  return result
end

function utils.hasKey(t, key)
  return t[key] ~= nil
end

function utils.size(t)
  local count = 0
  for _ in pairs(t) do
    count = count + 1
  end
  return count
end

function utils.isEmpty(t)
  return next(t) == nil
end

function utils.clear(t)
  for k in pairs(t) do
    t[k] = nil
  end
end

-- 文件路径工具函数
function utils.getFileName(path)
  return path:match("([^/\\]+)$")
end

function utils.getFileExtension(path)
  local name = utils.getFileName(path)
  return name:match("%.([^%.]+)$")
end

function utils.getFileNameWithoutExtension(path)
  local name = utils.getFileName(path)
  return name:gsub("%.[^%.]+$", "")
end

function utils.joinPath(...)
  local parts = {...}
  local result = table.concat(parts, "/")
  -- 规范化路径
  result = result:gsub("/+", "/")
  result = result:gsub("/$", "")
  return result
end

-- 性能分析工具函数
utils.Profiler = {}
utils.Profiler.__index = utils.Profiler

function utils.Profiler.new(name)
  return setmetatable({
    name = name or "Profiler",
    startTime = 0,
    totalTime = 0,
    callCount = 0,
    isRunning = false
  }, utils.Profiler)
end

function utils.Profiler:start()
  if not self.isRunning then
    self.startTime = lovr.timer.getTime()
    self.isRunning = true
  end
end

function utils.Profiler:stop()
  if self.isRunning then
    local elapsed = lovr.timer.getTime() - self.startTime
    self.totalTime = self.totalTime + elapsed
    self.callCount = self.callCount + 1
    self.isRunning = false
    return elapsed
  end
  return 0
end

function utils.Profiler:getAverageTime()
  return self.callCount > 0 and self.totalTime / self.callCount or 0
end

function utils.Profiler:getStats()
  return {
    name = self.name,
    totalTime = self.totalTime,
    callCount = self.callCount,
    averageTime = self:getAverageTime(),
    isRunning = self.isRunning
  }
end

function utils.Profiler:reset()
  self.totalTime = 0
  self.callCount = 0
  self.isRunning = false
end

-- 缓存工具函数
utils.Cache = {}
utils.Cache.__index = utils.Cache

function utils.Cache.new(maxSize)
  return setmetatable({
    data = {},
    maxSize = maxSize or 100,
    accessOrder = {}
  }, utils.Cache)
end

function utils.Cache:get(key)
  local value = self.data[key]
  if value ~= nil then
    -- 更新访问顺序 (LRU)
    for i, k in ipairs(self.accessOrder) do
      if k == key then
        table.remove(self.accessOrder, i)
        break
      end
    end
    table.insert(self.accessOrder, key)
    return value
  end
  return nil
end

function utils.Cache:set(key, value)
  if self.data[key] == nil and #self.accessOrder >= self.maxSize then
    -- 移除最久未使用的项
    local oldestKey = table.remove(self.accessOrder, 1)
    self.data[oldestKey] = nil
  end

  self.data[key] = value

  if self.data[key] == nil then
    table.insert(self.accessOrder, key)
  end
end

function utils.Cache:clear()
  self.data = {}
  self.accessOrder = {}
end

function utils.Cache:getSize()
  return #self.accessOrder
end

-- Logging utilities
utils.log = function(level, message, ...)
  local levels = {DEBUG = 1, INFO = 2, WARN = 3, ERROR = 4}
  local currentLevel = levels[utils.logLevel] or levels.INFO
  local messageLevel = levels[level] or levels.INFO

  if messageLevel >= currentLevel then
    local timestamp = os.date("%Y-%m-%d %H:%M:%S")
    local formattedMessage = string.format(message, ...)
    print(string.format("[%s] [%s] %s", timestamp, level, formattedMessage))
  end
end

utils.logLevel = "INFO"

-- Simplified logging functions
utils.debug = function(...) utils.log("DEBUG", ...) end
utils.info = function(...) utils.log("INFO", ...) end
utils.warn = function(...) utils.log("WARN", ...) end
utils.error = function(...) utils.log("ERROR", ...) end

-- Polygon triangulation using ear clipping (replaces love.math.triangulate)
-- Input: flat array of 2D vertices {x1,y1, x2,y2, x3,y3, ...}
-- Output: flat array of triangle vertex indices {i1,i2,i3, i4,i5,i6, ...}
function utils.triangulate(vertices)
  local n = #vertices / 2
  if n < 3 then return {} end

  -- Convert to indexed point list
  local points = {}
  for i = 1, n do
    points[i] = {x = vertices[i*2-1], y = vertices[i*2], index = i - 1}
  end

  -- Determine winding order
  local area = 0
  for i = 1, n do
    local j = (i % n) + 1
    area = area + (points[i].x * points[j].y - points[j].x * points[i].y)
  end
  local clockwise = area > 0

  -- Build linked list of remaining vertices
  local prev, next = {}, {}
  for i = 1, n do
    prev[i] = i - 1
    next[i] = i + 1
  end
  prev[1] = n
  next[n] = 1

  local function sign(p1, p2, p3)
    return (p1.x - p3.x) * (p2.y - p3.y) - (p2.x - p3.x) * (p1.y - p3.y)
  end

  local function pointInTriangle(pt, p1, p2, p3)
    local d1 = sign(pt, p1, p2)
    local d2 = sign(pt, p2, p3)
    local d3 = sign(pt, p3, p1)
    local hasNeg = (d1 < 0) or (d2 < 0) or (d3 < 0)
    local hasPos = (d1 > 0) or (d2 > 0) or (d3 > 0)
    return not (hasNeg and hasPos)
  end

  local function isEar(i)
    local a = points[prev[i]]
    local b = points[i]
    local c = points[next[i]]

    local cross = sign(a, b, c)
    if clockwise and cross >= 0 then return false end
    if not clockwise and cross <= 0 then return false end

    -- Check if any other vertex is inside this triangle
    local k = next[next[i]]
    while k ~= prev[i] do
      if pointInTriangle(points[k], a, b, c) then
        return false
      end
      k = next[k]
    end
    return true
  end

  local result = {}
  local remaining = n
  local current = 1
  local safety = n * n -- prevent infinite loops

  while remaining > 2 and safety > 0 do
    safety = safety - 1
    if remaining == 3 then
      table.insert(result, points[prev[current]].index)
      table.insert(result, points[current].index)
      table.insert(result, points[next[current]].index)
      break
    end

    if isEar(current) then
      table.insert(result, points[prev[current]].index)
      table.insert(result, points[current].index)
      table.insert(result, points[next[current]].index)

      -- Remove current ear vertex
      next[prev[current]] = next[current]
      prev[next[current]] = prev[current]
      remaining = remaining - 1
      current = next[current]
    else
      current = next[current]
    end
  end

  return result
end

return utils