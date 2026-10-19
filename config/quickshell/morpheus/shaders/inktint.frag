// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// INK TINT — an icon redrawn in one ink, its detail kept: the ink at the
// opacity of each pixel's brightness. A light part is solid ink, a dark part
// shows a quarter of it, a color lands between — so a white logo with dark
// lines (steam's) keeps its lines, where a stencil filled them in and
// MultiEffect's colorization (hue only) changed nothing (user, 2026-10-19).
// Built with: /usr/lib/qt6/bin/qsb --glsl "100 es,120,150" --hlsl 50 --msl 12
//             -o inktint.frag.qsb inktint.frag
#version 440
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec4 ink;
    float floorAlpha;
};
layout(binding = 1) uniform sampler2D source;

void main() {
    vec4 c = texture(source, qt_TexCoord0);
    vec3 rgb = c.a > 0.0 ? c.rgb / c.a : vec3(0.0);      // the texture is premultiplied
    float lum = dot(rgb, vec3(0.299, 0.587, 0.114));
    float a = c.a * mix(floorAlpha, 1.0, lum);
    fragColor = vec4(ink.rgb * a, a) * qt_Opacity;       // premultiplied out
}
