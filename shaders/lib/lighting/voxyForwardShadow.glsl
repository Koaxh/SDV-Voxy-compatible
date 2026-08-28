// Shared direct-shadow terms for Voxy opaque/translucent receivers.
// Samplers are declared by voxy.json, while the sampling implementation stays
// exactly the same as SDV's vanilla terrain path.
#define SDV_EXTERNAL_SHADOW_SAMPLERS
#include "/lib/lighting/shdMapping.glsl"
#undef SDV_EXTERNAL_SHADOW_SAMPLERS

vec3 getVoxyCurrentFeetPlayerPos() {
    vec3 screenPos = SCREEN2NDC(vec3(
        gl_FragCoord.xy / vec2(viewWidth, viewHeight),
        gl_FragCoord.z
    ));
    vec4 viewPos = gbufferProjectionInverse
        * vec4(screenPos, 1.0);
    viewPos /= viewPos.w;
    return (gbufferModelViewInverse * viewPos).xyz;
}

float getVoxyTemporalCastShadow(in vec3 currentFeetPlayerPos) {
    // Static world position expressed relative to the previous camera.
    vec3 previousFeetPlayerPos = currentFeetPlayerPos
        + cameraPosition - previousCameraPosition;
    vec4 previousClipPos = gbufferPreviousProjection
        * gbufferPreviousModelView * vec4(previousFeetPlayerPos, 1.0);

    if (previousClipPos.w <= 0.0) return 1.0;

    vec2 historyUv = previousClipPos.xy / previousClipPos.w * 0.5 + 0.5;
    if (any(lessThan(historyUv, vec2(0.0))) ||
        any(greaterThan(historyUv, vec2(1.0)))) return 1.0;

    return decodeVoxyShadowHistory(textureLod(colortex18, historyUv, 0.0).r);
}

vec3 getVoxyVanillaCastShadow(
    in vec3 feetPlayerPos,
    in vec3 normal,
    out float translucentCasterCoverage
) {
    if (dot(feetPlayerPos.xz, feetPlayerPos.xz) > squared(shadowDistance)) {
        translucentCasterCoverage = 0.0;
        return vec3(1.0);
    }

    // [MOD-8]: Fused Shadow MVP transformation (eliminates separate scale/offset stages)
    mat4 shadowMVP = shadowProjection * shadowModelView;
    vec3 shdPos = mat3(shadowMVP) * feetPlayerPos + shadowMVP[3].xyz;

    shdPos = vec3(
        shdPos.xy / (length(shdPos.xy) * 2.0 + 0.2),
        shdPos.z * 0.1
    ) + 0.5;

    // [MOD-8]: Slope-Scaled Depth Bias (eliminates acne at grazing angles)
    vec3 shadowNormal = mat3(shadowModelView) * normal;
    float slope = length(shadowNormal.xy) / max(abs(shadowNormal.z), 1e-4);
    float slopeBiasZ = -0.00006103515625 * (1.0 + 1.5 * clamp(slope, 0.0, 4.0));

    shdPos.xy += shadowNormal.xy * (shadowMapPixelSize * 2.0);
    shdPos.z  += shadowNormal.z  * slopeBiasZ;

    vec3 shadowColor;
    #ifdef SHADOW_FILTER
        #if ANTI_ALIASING >= 2
            float dither = fract(
                texelFetch(noisetex, ivec2(gl_FragCoord.xy) & 255, 0).x
                + frameFract
            );
        #else
            float dither = texelFetch(
                noisetex,
                ivec2(gl_FragCoord.xy) & 255,
                0
            ).x;
        #endif
        getShdColAndTranslucentCoverage(
            shdPos,
            dither * TAU,
            shadowColor,
            translucentCasterCoverage
        );
    #else
        getShdColAndTranslucentCoverage(
            shdPos,
            shadowColor,
            translucentCasterCoverage
        );
    #endif

    return isEyeInWater == 1
        ? getUnderwaterShdCol(shadowColor, fogColor)
        : shadowColor;
}
