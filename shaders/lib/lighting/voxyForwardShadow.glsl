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
    in vec3 normal
) {
    vec3 shdPos = vec3(
        shadowProjection[0].x,
        shadowProjection[1].y,
        shadowProjection[2].z
    ) * (mat3(shadowModelView) * feetPlayerPos + shadowModelView[3].xyz);
    shdPos.z += shadowProjection[3].z;

    shdPos = vec3(
        shdPos.xy / (length(shdPos.xy) * 2.0 + 0.2),
        shdPos.z * 0.1
    ) + 0.5;

    const vec3 biasAdjustFactor = vec3(
        shadowMapPixelSize * 2.0,
        shadowMapPixelSize * 2.0,
        -0.00006103515625
    );
    vec3 shadowNormal = vec3(
        dot(normal, vec3(shadowModelView[0].x, shadowModelView[1].x, shadowModelView[2].x)),
        dot(normal, vec3(shadowModelView[0].y, shadowModelView[1].y, shadowModelView[2].y)),
        dot(normal, vec3(shadowModelView[0].z, shadowModelView[1].z, shadowModelView[2].z))
    );
    shdPos += shadowNormal * biasAdjustFactor;

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
        return getShdCol(shdPos, dither * TAU);
    #else
        return getShdCol(shdPos);
    #endif
}
