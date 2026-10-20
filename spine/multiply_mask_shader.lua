-- Multiply blend mode shader. Returns a Shader or nil.
-- Tries the LÖVR 0.18 dialect first, then the 0.11/0.19 builtins dialect.

local MUL_0_18 = [[
  vec4 lovrmain() {
    vec4 t = texture(ColorTexture, VertexUV);
    float a = t.a;
    vec3 base = a > 0.0 ? t.rgb / a : vec3(1.0);
    vec3 factor = mix(vec3(1.0), base, a);
    return vec4(factor, a) * VertexColor;
  }
]]

local MUL_NEW = [[
  vec4 lovrmain() {
    vec4 t = getPixel(ColorTexture, UV);
    float a = t.a;
    vec3 base = a > 0.0 ? t.rgb / a : vec3(1.0);
    vec3 factor = mix(vec3(1.0), base, a);
    return vec4(factor, a) * Color;
  }
]]

local ok, shader = pcall(lovr.graphics.newShader, 'unlit', MUL_0_18)
if ok then
  return shader
end

local ok2, shader2 = pcall(lovr.graphics.newShader, 'unlit', MUL_NEW)
if ok2 then
  return shader2
end

return nil
