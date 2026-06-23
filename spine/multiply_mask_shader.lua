local fragment_code = [[
  vec4 lovrmain() {
    vec4 t = texture(ColorTexture, VertexUV);
    float a = t.a;
    vec3 base = a > 0.0 ? t.rgb / a : vec3(1.0);
    vec3 factor = mix(vec3(1.0), base, a);
    return vec4(factor, a) * VertexColor;
  }
]]

local ok, shader = pcall(lovr.graphics.newShader, 'unlit', fragment_code)
if ok then
  return shader
else
  return nil
end
