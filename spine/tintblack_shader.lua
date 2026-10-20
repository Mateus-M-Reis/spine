-- Tint-black (two-color) shader for Spine slots with a dark color.
--
-- Returns a table: { shader = Shader, perVertex = bool } or nil.
--
-- The runtime supports several LÖVR shader dialects, so the module tries them
-- in order:
--   1. LÖVR 0.18: fragment shaders can read vertex attributes directly
--      (texture(ColorTexture, VertexUV), VertexColor, VertexDarkColor).
--      This allows fully batched tinted meshes (perVertex = true).
--   2. LÖVR 0.18 with a uniform dark color (perVertex = false).
--   3. LÖVR 0.11/0.19-style builtins (getPixel/Color/UV) with a uniform dark
--      color (perVertex = false).
--
-- Returning nil makes the renderer skip tint shading entirely.

local DARK_0_18_PERVERTEX = [[
  vec4 lovrmain() {
    vec4 texcolor = texture(ColorTexture, VertexUV);
    float a = texcolor.a;
    vec3 base = a > 0.0 ? texcolor.rgb / a : vec3(0.0);
    vec3 mixed = mix(VertexDarkColor.rgb, VertexColor.rgb, base);
    float outA = a * VertexColor.a;
    return vec4(mixed * outA, outA);
  }
]]

local DARK_0_18_UNIFORM = [[
  uniform vec4 darkColor;

  vec4 lovrmain() {
    vec4 texcolor = texture(ColorTexture, VertexUV);
    float a = texcolor.a;
    vec3 base = a > 0.0 ? texcolor.rgb / a : vec3(0.0);
    vec3 mixed = mix(darkColor.rgb, VertexColor.rgb, base);
    float outA = a * VertexColor.a;
    return vec4(mixed * outA, outA);
  }
]]

local DARK_NEW_UNIFORM = [[
  uniform vec4 darkColor;

  vec4 lovrmain() {
    vec4 texcolor = getPixel(ColorTexture, UV);
    float a = texcolor.a;
    vec3 base = a > 0.0 ? texcolor.rgb / a : vec3(0.0);
    vec3 mixed = mix(darkColor.rgb, Color.rgb, base);
    float outA = a * Color.a;
    return vec4(mixed * outA, outA);
  }
]]

local ok, shader = pcall(lovr.graphics.newShader, 'unlit', DARK_0_18_PERVERTEX)
if ok then
  return { shader = shader, perVertex = true }
end

local ok2, shader2 = pcall(lovr.graphics.newShader, 'unlit', DARK_0_18_UNIFORM)
if ok2 then
  return { shader = shader2, perVertex = false }
end

local ok3, shader3 = pcall(lovr.graphics.newShader, 'unlit', DARK_NEW_UNIFORM)
if ok3 then
  return { shader = shader3, perVertex = false }
end

return nil
