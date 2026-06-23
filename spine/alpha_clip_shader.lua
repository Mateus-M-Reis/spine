local fragment_code = [[
  vec4 lovrmain() {
    vec4 t = texture(ColorTexture, VertexUV);
    if (t.a <= 0.0039) discard;
    return t * VertexColor;
  }
]]

local ok, shader = pcall(lovr.graphics.newShader, 'unlit', fragment_code)
if ok then
  return shader
else
  return nil
end
