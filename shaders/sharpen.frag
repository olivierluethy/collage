#version 460 core

// Sharpen filter for slot photos: an unsharp mask using the four direct
// neighbours. Used through ImageFilter.shader, so the engine sets u_size to
// the texture size and binds the filter input to the first sampler.

#include <flutter/runtime_effect.glsl>

uniform vec2 u_size;
uniform float u_amount; // 0 (off) .. ~1.5 (strong)

uniform sampler2D u_texture;

out vec4 frag_color;

void main() {
  vec2 uv = FlutterFragCoord().xy / u_size;
#ifdef IMPELLER_TARGET_OPENGLES
  uv.y = 1.0 - uv.y;
#endif
  vec2 px = 1.0 / u_size;
  vec4 c = texture(u_texture, uv);
  vec4 n = texture(u_texture, uv + vec2(px.x, 0.0)) +
           texture(u_texture, uv - vec2(px.x, 0.0)) +
           texture(u_texture, uv + vec2(0.0, px.y)) +
           texture(u_texture, uv - vec2(0.0, px.y));
  vec4 sharp = c + u_amount * (4.0 * c - n);
  // Colours are premultiplied: keep each channel within the pixel's alpha.
  frag_color = vec4(clamp(sharp.rgb, vec3(0.0), vec3(c.a)), c.a);
}
