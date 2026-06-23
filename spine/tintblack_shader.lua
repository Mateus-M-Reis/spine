local fragment_code = [[
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

return lovr.graphics.newShader('unlit', fragment_code)
