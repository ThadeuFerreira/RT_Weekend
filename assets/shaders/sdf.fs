#version 330

// Input vertex attributes (from vertex shader)
in vec2 fragTexCoord;
in vec4 fragColor;

// Input uniform values
uniform sampler2D texture0;
uniform vec4 colDiffuse;

// Output fragment color
out vec4 finalColor;

// NOTE: Add your custom variables here

void main()
{
    // Texel color fetching from texture sampler
    // NOTE: Calculate alpha using signed distance field (SDF)
    // Use .r (red channel) — raylib loads SDF atlases as GL_R8 (grayscale).
    // Reading .a from a GL_R8 texture returns 1.0 on OpenGL (no swizzle),
    // which makes dFdx/dFdy = 0 and collapses smoothstep → invisible text on Mesa/Intel.
    float distanceFromOutline = texture(texture0, fragTexCoord).r - 0.5;
    float distanceChangePerFragment = length(vec2(dFdx(distanceFromOutline), dFdy(distanceFromOutline)));
    float alpha = smoothstep(-distanceChangePerFragment, distanceChangePerFragment, distanceFromOutline);

    // Calculate final fragment color
    finalColor = vec4(fragColor.rgb, fragColor.a*alpha);
}
