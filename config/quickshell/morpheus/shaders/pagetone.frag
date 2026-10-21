// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// PAGE TONE — a printed page laid between two inks: what was black becomes
// `lo`, what was white becomes `hi`, the greys between them in step. A
// colour keeps `chroma` of its own colourfulness on top, so a chart's lines
// and a photograph are still told apart on a sepia or a night page
// (minerva's page themes, 2026-10-21). Night is lo light, hi dark: the
// page's lightness turned over, its hues kept.
// Built with: /usr/lib/qt6/bin/qsb --glsl "100 es,120,150" --hlsl 50 --msl 12
//             -o pagetone.frag.qsb pagetone.frag
#version 440
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec4 lo;
    vec4 hi;
    float chroma;
};
layout(binding = 1) uniform sampler2D source;

void main() {
    vec4 c = texture(source, qt_TexCoord0);
    vec3 rgb = c.a > 0.0 ? c.rgb / c.a : vec3(0.0);      // the texture is premultiplied
    float lum = dot(rgb, vec3(0.299, 0.587, 0.114));
    vec3 tone = mix(lo.rgb, hi.rgb, lum);
    vec3 outc = clamp(tone + (rgb - vec3(lum)) * chroma, 0.0, 1.0);
    fragColor = vec4(outc * c.a, c.a) * qt_Opacity;       // premultiplied out
}
