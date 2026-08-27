// SDV Voxy translucent patch.
//
// This pass follows Photon's distant-water split.  It does not resolve the
// water volume, waves, highlights or reflections.  It only writes the raw
// inputs needed by composite.glsl and, separately, the very thin premultiplied
// surface layer used by Photon.  Resolving all angle/depth-dependent terms in
// one later pass is essential: doing part of the water shading here and a
// second, unrelated alpha calculation in composite caused the visible seam.

#define VOXY_PATCH
#define WATER
// Voxy has an independent projection, but it renders with the current vanilla
// model-view.  Never alias gbufferModelView to vxModelView here: Voxy's vx
// model-view uniforms may be one frame late and Photon only uses vxProj/vxProjInv
// for the independent depth domain.

// Note: do NOT add `uniform float near;` here. Iris already exposes the
// camera near plane as the nameless-UBO member `near` (see ShaderUniformBindings
// in the post-processed shader). A global `uniform float near;` would shadow
// it and bind to a zero default, which would make blockDepth collapse to 0.

// Match BSL/Photon's integration rule: Voxy translucents render before the
// vanilla translucent pass, so they must not enter SDV's opaque scene/G-buffer
// attachments here. composite.glsl consumes these dedicated attachments after
// the opaque deferred stages have finished.
layout(location = 0) out vec4 voxyTranslucentColorOut; // colortex16
layout(location = 1) out vec4 voxyTranslucentSurfaceOut; // colortex17
layout(location = 2) out vec4 voxyTranslucentAlbedoOut; // colortex19
layout(location = 3) out vec4 voxyWaterLayerOut; // colortex20

// Iris model IDs from shaders/block.properties and SDV material constants from
// lib/PBR/integratedPBR.glsl. These are source constants, not fitted values.
const uint SDV_WATER_BLOCK_ID = 11102u;
const float SDV_ALPHA_THRESHOLD = 0.1;
const float SDV_VOXY_GENERIC_SURFACE = 0.25;
const float SDV_VOXY_WATER_SURFACE = 1.0;
const float SDV_VOXY_ZERO_TO_ONE_SURFACE_OFFSET = 2.0;

// Photon's default water constants.  These describe only the optional thin
// surface/edge layer; the actual RGB extinction is evaluated in composite.
const vec3 PHOTON_WATER_ABSORPTION = vec3(0.39, 0.14, 0.07);

// The stable water-forward path and generic translucent path share these
// fragment-scoped inputs. They are populated from Voxy data below.
vec2 lmCoord;
vec3 vertexFeetPlayerPos;

#ifdef WORLD_CUSTOM_SKYLIGHT
    const float eyeBrightFact = WORLD_CUSTOM_SKYLIGHT;
#else
    float eyeBrightFact;
#endif

#if defined WORLD_LIGHT && defined SHADOW_MAPPING
    #include "/lib/lighting/voxyForwardShadow.glsl"
#endif

vec2 decodeVoxyLightMap(vec2 encodedLightMap) {
    return lightMapCoord(encodedLightMap * 256.0 - 8.0);
}

vec3 getVoxyFaceNormal(uint face) {
    vec3 axis = vec3(
        uint((face >> 1u) == 2u),
        uint((face >> 1u) == 0u),
        uint((face >> 1u) == 1u)
    );
    float direction = float(int(face) & 1) * 2.0 - 1.0;
    return axis * direction;
}

vec2 getVoxyTaaJitterNdc() {
    #if ANTI_ALIASING == 2
        const vec2 offsets[8] = vec2[8](
            vec2( 0.125, -0.375),
            vec2(-0.125,  0.375),
            vec2( 0.625,  0.125),
            vec2( 0.375, -0.625),
            vec2(-0.625,  0.625),
            vec2(-0.875, -0.125),
            vec2( 0.375, -0.875),
            vec2( 0.875,  0.875)
        );
        return offsets[frameMod] / vec2(viewWidth, viewHeight);
    #else
        return vec2(0.0);
    #endif
}

vec3 unprojectVoxyViewPosition(float screenDepth) {
    vec2 framebufferSize = vec2(textureSize(vxDepthTexOpaque, 0));
    vec2 screenUv = gl_FragCoord.xy / framebufferSize;
    vec3 ndcPosition = vec3(
        screenUv * 2.0 - 1.0 - getVoxyTaaJitterNdc(),
        SCREEN2NDC_DEPTH(screenDepth)
    );
    vec4 homogeneousViewPosition = vxProjInv
        * vec4(ndcPosition, 1.0);
    return homogeneousViewPosition.xyz / homogeneousViewPosition.w;
}

float encodeVoxySurfaceKind(float surfaceKind) {
    // The Voxy base fragment selects one of two SCREEN2NDC_DEPTH functions at
    // compile time. 0 maps to 0 only for a zero-to-one clip-depth projection;
    // preserve that fact in the material attachment because Voxy 0.2.18 does
    // not expose the convention as a post-processing uniform.
    float zeroToOneDepth = float(SCREEN2NDC_DEPTH(0.0) == 0.0);
    return surfaceKind
        + zeroToOneDepth * SDV_VOXY_ZERO_TO_ONE_SURFACE_OFFSET;
}

float getVoxyWaterLayerDistance(vec3 waterSurfaceViewPosition) {
    float opaqueDepth = texelFetch(
        vxDepthTexOpaque,
        ivec2(gl_FragCoord.xy),
        0
    ).x;
    if (opaqueDepth >= 1.0) {
        return -1.0;
    }
    vec3 opaqueViewPosition = unprojectVoxyViewPosition(opaqueDepth);
    float layerDistance = distance(opaqueViewPosition, waterSurfaceViewPosition);
    return (isnan(layerDistance) || isinf(layerDistance))
        ? -1.0
        : clamp(layerDistance, 0.0, 50.0);
}
vec3 shadeVoxyThinSurface(vec3 albedo, vec3 normal) {
    float blockLightSquared = squared(lmCoord.x);
    float skyLightSquared = squared(lmCoord.y);
    vec3 totalIllumination = (
        toLinear(SKY_COLOR_DATA_BLOCK) + lightningFlash
    ) * skyLightSquared;
    totalIllumination += toLinear(AMBIENT_LIGHTING + nightVision * 0.5);
    totalIllumination += toLinear(1.25 * blockLightSquared * blockLightColor);
    #ifdef WORLD_LIGHT
        vec3 sRGBLightCol = LIGHT_COLOR_DATA_BLOCK0;
        float NLZ = dot(normal, voxyLightDir);
        bool isShadow = NLZ > 0.0;
        vec3 shdCol = vec3(0.0);
        float waterCasterCoverage = 0.0;

        if (isShadow) {
            #ifdef SHADOW_MAPPING
                shdCol = getVoxyVanillaCastShadow(
                    vertexFeetPlayerPos,
                    normal,
                    waterCasterCoverage
                );
            #else
                shdCol = vec3(1.0);
            #endif

            float shadowFactor = shdFade;
            if (isEyeInWater == 0) {
                shadowFactor *= min(1.0, (lmCoord.y + eyeBrightFact) * 4.0);
            } else if (isEyeInWater == 1) {
                shadowFactor *= mix(
                    skyLightSquared,
                    1.0,
                    waterCasterCoverage
                );
            }
            shdCol *= shadowFactor * NLZ;
        }

        #ifndef FORCE_DISABLE_WEATHER
            float rainDiffuseAmount = rainStrength * 0.5;
            shdCol *= 1.0 - rainDiffuseAmount;
            shdCol += rainDiffuseAmount * skyLightSquared * (1.0 - shdFade);
        #endif

        totalIllumination += toLinear(sRGBLightCol) * shdCol;
    #endif

    return albedo * totalIllumination;
}

void getPhotonVoxyThinWaterSurface(
    VoxyFragmentParameters parameters,
    vec3 geometricNormal,
    vec3 surfaceViewPosition,
    float layerDistance,
    out vec3 surfaceAlbedo,
    out float surfaceAlpha
) {
    surfaceAlbedo = vec3(0.0);
    surfaceAlpha = 0.01;

    // Photon WATER_TEXTURE_HIGHLIGHT_UNDERGROUND.  In open skylight this fades
    // away, leaving the final-stage volume/reflection as the water appearance.
    float highlightSignal = clamp(
        0.5 * squared(clamp(
            (parameters.sampledColour.r - 0.63) / 0.37,
            0.0,
            1.0
        )) + 0.03 * parameters.sampledColour.r,
        0.0,
        1.0
    );
    float textureHighlight = highlightSignal * (2.0 - highlightSignal);
    float undergroundFade = clamp(lmCoord.y / 0.5, 0.0, 1.0);
    undergroundFade = undergroundFade * undergroundFade
        * (3.0 - 2.0 * undergroundFade);
    textureHighlight *= 1.0
        - undergroundFade * undergroundFade * undergroundFade;

    surfaceAlbedo = clamp(
        vec3(0.22920315, 0.37789222, 0.43467882) * textureHighlight,
        0.0,
        1.0
    );
    surfaceAlpha += textureHighlight;

    // Photon water edge highlight.  This is a surface-only term; the distance
    // is deliberately not reused for absorption in this pass.
    vec3 eyePlayerPosition = mat3(gbufferModelViewInverse)
        * surfaceViewPosition;
    vec3 directionWorld = fastNormalize(eyePlayerPosition);
    float normalLayerDistance = layerDistance
        * max(abs(directionWorld.y), 0.00001);
    float edgeHighlight = max(1.0 - 2.0 * normalLayerDistance, 0.0);
    edgeHighlight = edgeHighlight * edgeHighlight * edgeHighlight
        * (1.0 + 8.0 * textureHighlight);
    edgeHighlight *= max(geometricNormal.y, 0.0)
        * (1.0 - 0.5 * squared(lmCoord.y));

    vec3 ambientColor = toLinear(SKY_COLOR_DATA_BLOCK)
        + toLinear(AMBIENT_LIGHTING + nightVision * 0.5);
    float ambientLuminance = dot(
        ambientColor,
        vec3(0.2126, 0.7152, 0.0722)
    );
    surfaceAlbedo += 0.1 * edgeHighlight
        / mix(1.0, max(ambientLuminance, 0.5), lmCoord.y);
    surfaceAlbedo = clamp(surfaceAlbedo, 0.0, 1.0);
    surfaceAlpha = clamp(surfaceAlpha + edgeHighlight, 0.0, 1.0);
}

void emitSdvWater(VoxyFragmentParameters parameters) {
    if (parameters.sampledColour.a < SDV_ALPHA_THRESHOLD) {
        discard;
    }

    // lmCoord was decoded by voxy_emitFragment with the same SDV function
    // used by native gbuffers_water. Do not replace it with Voxy's centred
    // lightmap-texel domain here.

    vec3 waterSurfaceViewPosition = unprojectVoxyViewPosition(gl_FragCoord.z);
    vertexFeetPlayerPos = (
        gbufferModelViewInverse * vec4(waterSurfaceViewPosition, 1.0)
    ).xyz;
    // Water also has vertical faces (waterfalls and exposed fluid sides).
    // Pinning every fragment to +Y made those faces use the wrong Fresnel,
    // GGX and reflected ray. The corrected Voxy face value already accounts
    // for winding at the quads.frag boundary and maps to SDV's TBN[2] axis.
    vec3 geometricNormal = getVoxyFaceNormal(parameters.face);
    // This pass has the authoritative Voxy front and opaque-back depths under
    // the same compile-time clip convention. Preserve that ray length for the
    // later Photon-style volume integral instead of reconstructing it again
    // after the Voxy projection state has left the draw.
    float waterLayerDistance = getVoxyWaterLayerDistance(
        waterSurfaceViewPosition
    );

    vec3 surfaceAlbedo;
    float surfaceAlpha;
    getPhotonVoxyThinWaterSurface(
        parameters,
        geometricNormal,
        waterSurfaceViewPosition,
        waterLayerDistance,
        surfaceAlbedo,
        surfaceAlpha
    );
    vec3 surfaceLighting = shadeVoxyThinSurface(
        surfaceAlbedo,
        geometricNormal
    );

    // Attachment 0 is the independent premultiplied thin surface. Attachments
    // 1/2/3 are unblended raw metadata consumed by the distant-water resolver.
    vec3 premultipliedSurface = max(
        surfaceLighting * surfaceAlpha,
        vec3(0.0)
    );
    voxyTranslucentColorOut = max(
        premultipliedSurface.r,
        max(premultipliedSurface.g, premultipliedSurface.b)
    ) <= 0.000001
        ? vec4(0.0)
        : vec4(premultipliedSurface, surfaceAlpha);
    voxyTranslucentSurfaceOut = vec4(
        geometricNormal,
        encodeVoxySurfaceKind(SDV_VOXY_WATER_SURFACE)
    );
    voxyTranslucentAlbedoOut = vec4(
        parameters.tinting.rgb,
        waterLayerDistance
    );
    voxyWaterLayerOut = vec4(lmCoord, surfaceAlpha, 1.0);
}

void emitGenericVoxyTranslucent(VoxyFragmentParameters parameters) {
    vec4 baseColor = vec4(
        toLinear(parameters.sampledColour.rgb * parameters.tinting.rgb),
        parameters.sampledColour.a * parameters.tinting.a
    );
    vec3 normal = getVoxyFaceNormal(parameters.face);

    float blockLightSquared = squared(lmCoord.x);
    float skyLightSquared = squared(lmCoord.y);
    vec3 totalIllumination = (toLinear(SKY_COLOR_DATA_BLOCK) + lightningFlash)
        * skyLightSquared;
    totalIllumination += toLinear(AMBIENT_LIGHTING + nightVision * 0.5);
    totalIllumination += toLinear(blockLightSquared * blockLightColor * 1.25);

    #ifdef WORLD_LIGHT
        float normalDotLight = max(0.0, dot(normal, voxyLightDir));
        float caveVisibility = 1.0;
        if (isEyeInWater == 0) {
            caveVisibility = min(1.0, (lmCoord.y + eyeBrightFact) * 4.0);
        } else if (isEyeInWater == 1) {
            caveVisibility = skyLightSquared;
        }

        float lodCastShadow = 1.0;
        vec3 vanillaCastShadow = vec3(1.0);
        float vanillaWaterCasterCoverage = 0.0;
        #ifdef SHADOW_MAPPING
            vec3 feetPlayerPosition = (
                gbufferModelViewInverse * vec4(
                    unprojectVoxyViewPosition(gl_FragCoord.z),
                    1.0
                )
            ).xyz;
            lodCastShadow = getVoxyTemporalCastShadow(feetPlayerPosition);
            vanillaCastShadow = getVoxyVanillaCastShadow(
                feetPlayerPosition,
                normal,
                vanillaWaterCasterCoverage
            );
        #endif
        if (isEyeInWater == 1) {
            caveVisibility = mix(
                skyLightSquared,
                1.0,
                vanillaWaterCasterCoverage
            );
        }

        vec3 shadowColor = vanillaCastShadow
            * (normalDotLight * shdFade * caveVisibility * lodCastShadow);

        #ifndef FORCE_DISABLE_WEATHER
            float rainDiffuseAmount = rainStrength * 0.5;
            shadowColor *= 1.0 - rainDiffuseAmount;
            shadowColor += rainDiffuseAmount * skyLightSquared
                * (1.0 - shdFade);
        #endif

        totalIllumination += toLinear(LIGHT_COLOR_DATA_BLOCK0) * shadowColor;
    #endif

    voxyTranslucentColorOut = vec4(
        baseColor.rgb * totalIllumination * baseColor.a,
        baseColor.a
    );
    voxyTranslucentSurfaceOut = vec4(
        normal,
        encodeVoxySurfaceKind(SDV_VOXY_GENERIC_SURFACE)
    );
    voxyTranslucentAlbedoOut = baseColor;
    voxyWaterLayerOut = vec4(0.0);
}

void voxy_emitFragment(VoxyFragmentParameters parameters) {
    lmCoord = decodeVoxyLightMap(parameters.lightMap);
    #ifdef WORLD_CUSTOM_SKYLIGHT
        lmCoord.y = WORLD_CUSTOM_SKYLIGHT;
    #else
        eyeBrightFact = eyeSkylight;
    #endif

    if (parameters.customId == SDV_WATER_BLOCK_ID) {
        emitSdvWater(parameters);
        return;
    }

    emitGenericVoxyTranslucent(parameters);
}

#undef WATER
