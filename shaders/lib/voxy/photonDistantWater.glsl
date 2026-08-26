#ifndef SDV_PHOTON_DISTANT_WATER_GLSL
#define SDV_PHOTON_DISTANT_WATER_GLSL

// Photon-style final-stage Voxy water resolver.
//
// Coordinate contract:
//   * vxProj/vxProjInv own only Voxy screen/depth projection.
//   * gbufferModelView/Inverse own view <-> scene/world conversion.
//   * front/back depth reconstruction removes the same TAA jitter used by
//     program/voxy.json.

const vec3 PHOTON_VOXY_WATER_BASE_ABSORPTION = vec3(0.39, 0.14, 0.07);
const vec3 PHOTON_VOXY_WATER_SCATTERING = vec3(0.01);
const float PHOTON_VOXY_ISOTROPIC_PHASE = 0.07957747154594767;
const float PHOTON_VOXY_WATER_F0 = 0.02;
const float PHOTON_VOXY_WATER_ROUGHNESS = 0.002;

vec2 photonVoxyTaaJitterNdc() {
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
        return offsets[frameMod] * vec2(pixelWidth, pixelHeight);
    #else
        return vec2(0.0);
    #endif
}

vec3 photonVoxyScreenToView(
    vec2 screenUv,
    float screenDepth,
    bool zeroToOneDepth,
    bool removeJitter
) {
    vec2 ndcXY = screenUv * 2.0 - 1.0;
    if (removeJitter) {
        ndcXY -= photonVoxyTaaJitterNdc();
    }
    float ndcDepth = zeroToOneDepth
        ? screenDepth
        : screenDepth * 2.0 - 1.0;
    vec4 homogeneousView = vxProjInv
        * vec4(ndcXY, ndcDepth, 1.0);
    return homogeneousView.xyz / homogeneousView.w;
}

vec3 photonVoxyViewToScreen(
    vec3 viewPosition,
    bool zeroToOneDepth,
    bool applyJitter
) {
    vec4 clipPosition = vxProj * vec4(viewPosition, 1.0);
    vec3 ndcPosition = clipPosition.xyz / clipPosition.w;
    if (applyJitter) {
        ndcPosition.xy += photonVoxyTaaJitterNdc();
    }
    return vec3(
        ndcPosition.xy * 0.5 + 0.5,
        zeroToOneDepth
            ? ndcPosition.z
            : ndcPosition.z * 0.5 + 0.5
    );
}

vec3 photonVanillaScreenToView(
    vec2 screenUv,
    float screenDepth,
    bool removeJitter
) {
    vec2 ndcXY = screenUv * 2.0 - 1.0;
    if (removeJitter) {
        ndcXY -= photonVoxyTaaJitterNdc();
    }
    vec4 homogeneousView = gbufferProjectionInverse * vec4(
        ndcXY,
        screenDepth * 2.0 - 1.0,
        1.0
    );
    return homogeneousView.xyz / homogeneousView.w;
}

mat4 photonCombinedProjection() {
    // Exact Voxy branch used by Photon's lod_mod_support.glsl: preserve the
    // vanilla FOV/near plane but extend the far plane to the LoD scene.  A
    // native-water SSR ray can therefore hit distant Voxy geometry instead of
    // being clipped at the vanilla render distance.
    float combinedNear = gbufferProjection[3][2]
        / (gbufferProjection[2][2] - 1.0);
    float combinedFar = max(float(16 * vxRenderDistance), combinedNear + 1.0);
    return mat4(
        vec4(gbufferProjection[0][0], 0.0, 0.0, 0.0),
        vec4(0.0, gbufferProjection[1][1], 0.0, 0.0),
        vec4(
            gbufferProjection[2][0],
            gbufferProjection[2][1],
            (combinedFar + combinedNear) / (combinedNear - combinedFar),
            -1.0
        ),
        vec4(
            0.0,
            0.0,
            (2.0 * combinedFar * combinedNear)
                / (combinedNear - combinedFar),
            0.0
        )
    );
}

mat4 photonCombinedProjectionInverse() {
    // Exact inverse paired with Photon's Voxy combined projection.
    float combinedNear = gbufferProjection[3][2]
        / (gbufferProjection[2][2] - 1.0);
    float combinedFar = max(float(16 * vxRenderDistance), combinedNear + 1.0);
    return mat4(
        vec4(gbufferProjectionInverse[0][0], 0.0, 0.0, 0.0),
        vec4(0.0, gbufferProjectionInverse[1][1], 0.0, 0.0),
        vec4(
            0.0,
            0.0,
            0.0,
            -(combinedFar - combinedNear)
                / (2.0 * combinedFar * combinedNear)
        ),
        vec4(
            gbufferProjectionInverse[3][0],
            gbufferProjectionInverse[3][1],
            -1.0,
            (combinedFar + combinedNear)
                / (2.0 * combinedFar * combinedNear)
        )
    );
}

vec3 photonCombinedViewToScreen(vec3 viewPosition, bool applyJitter) {
    vec4 clipPosition = photonCombinedProjection()
        * vec4(viewPosition, 1.0);
    vec3 ndcPosition = clipPosition.xyz / clipPosition.w;
    if (applyJitter) {
        ndcPosition.xy += photonVoxyTaaJitterNdc();
    }
    return ndcPosition * 0.5 + 0.5;
}

vec3 photonCombinedScreenToView(
    vec2 screenUv,
    float screenDepth,
    bool removeJitter
) {
    vec2 ndcXY = screenUv * 2.0 - 1.0;
    if (removeJitter) {
        ndcXY -= photonVoxyTaaJitterNdc();
    }
    vec4 homogeneousView = photonCombinedProjectionInverse() * vec4(
        ndcXY,
        screenDepth * 2.0 - 1.0,
        1.0
    );
    return homogeneousView.xyz / homogeneousView.w;
}

vec3 photonWaterViewToScreen(
    vec3 viewPosition,
    bool frontIsVoxy,
    bool zeroToOneDepth,
    bool applyJitter
) {
    return frontIsVoxy
        ? photonVoxyViewToScreen(
            viewPosition,
            zeroToOneDepth,
            applyJitter
        )
        : photonCombinedViewToScreen(viewPosition, applyJitter);
}

bool photonWaterFinitePosition(vec3 position) {
    return !any(isnan(position)) && !any(isinf(position));
}

bool photonCombinedOpaqueViewPosition(
    vec2 screenUv,
    bool frontIsVoxy,
    bool zeroToOneDepth,
    out vec3 backViewPosition
) {
    ivec2 vanillaSize = textureSize(depthtex1, 0);
    ivec2 voxySize = textureSize(vxDepthTexOpaque, 0);
    ivec2 vanillaTexel = clamp(
        ivec2(screenUv * vec2(vanillaSize)),
        ivec2(0),
        vanillaSize - ivec2(1)
    );
    ivec2 voxyTexel = clamp(
        ivec2(screenUv * vec2(voxySize)),
        ivec2(0),
        voxySize - ivec2(1)
    );

    float vanillaDepth = texelFetch(depthtex1, vanillaTexel, 0).x;
    float voxyDepth = texelFetch(vxDepthTexOpaque, voxyTexel, 0).x;
    // SDV reserves <= 0.56 for the hand. Photon excludes hand depth from SSR.
    bool hasVanilla = vanillaDepth > 0.56 && vanillaDepth < 1.0;
    bool hasVoxy = voxyDepth < 1.0;

    vec3 vanillaViewPosition = vec3(0.0);
    vec3 voxyViewPosition = vec3(0.0);
    if (hasVanilla) {
        vanillaViewPosition = photonVanillaScreenToView(
            screenUv,
            vanillaDepth,
            true
        );
        hasVanilla = photonWaterFinitePosition(vanillaViewPosition)
            && vanillaViewPosition.z < 0.0;
    }
    if (hasVoxy) {
        voxyViewPosition = photonVoxyScreenToView(
            screenUv,
            voxyDepth,
            zeroToOneDepth,
            true
        );
        hasVoxy = photonWaterFinitePosition(voxyViewPosition)
            && voxyViewPosition.z < 0.0;
    }

    if (!hasVanilla && !hasVoxy) {
        backViewPosition = vec3(0.0);
        return false;
    }

    // Photon does not let a coarser LoD bottom compete with an existing
    // vanilla solid back layer. Native water owns native back depth and falls
    // through to LoD only when that layer is clear; distant water owns its LoD
    // solid back unconditionally.
    if (frontIsVoxy) {
        if (!hasVoxy) {
            backViewPosition = vec3(0.0);
            return false;
        }
        backViewPosition = voxyViewPosition;
    } else if (hasVanilla) {
        backViewPosition = vanillaViewPosition;
    } else if (hasVoxy) {
        backViewPosition = voxyViewPosition;
    } else {
        backViewPosition = vanillaViewPosition;
    }
    return true;
}

float photonWaterLayerDistance(
    vec2 screenUv,
    vec3 frontViewPosition,
    bool frontIsVoxy,
    bool zeroToOneDepth
) {
    vec3 backViewPosition;
    if (!photonCombinedOpaqueViewPosition(
        screenUv,
        frontIsVoxy,
        zeroToOneDepth,
        backViewPosition
    )) {
        return 48000.0;
    }
    float layerDistance = distance(frontViewPosition, backViewPosition);
    return photonWaterFinitePosition(vec3(layerDistance))
        ? max(layerDistance, 0.0)
        : 48000.0;
}

vec3 photonVoxyWaterNormal(vec3 worldPosition, vec3 flatNormal) {
    vec3 normal = normalize(flatNormal);

    // Photon recomputes waves at layer-composition time.  Use SDV's H2N wave
    // field here so the near and LOD surfaces retain the same moving detail,
    // while preserving Photon's final-stage ownership of the normal.
    #ifdef WATER_NORMAL
        vec4 waterData = H2NWater(worldPosition.xz * waterTileSizeInv).xzyw;
        normal = normalize(
            waterData.yxz * flatNormal.x
            + waterData.xyz * flatNormal.y
            + waterData.xzy * flatNormal.z
        );
    #endif

    return normal;
}

vec3 photonVoxyBiomeWaterAbsorption(vec3 tintSrgb) {
    const float densityScale = 0.15;
    const float biomeContribution = 0.33;
    const vec3 forestAbsorption = -densityScale
        * log(vec3(0.1245, 0.1797, 0.7108));

    vec3 tintLinear = toLinear(clamp(tintSrgb, 0.0, 1.0));
    vec3 biomeAbsorption = -densityScale
        * log(max(tintLinear, vec3(0.00001)))
        - forestAbsorption;
    return max(
        PHOTON_VOXY_WATER_BASE_ABSORPTION
            + biomeAbsorption * biomeContribution,
        vec3(0.0)
    );
}

float photonVoxyHenyeyGreenstein(float cosTheta, float anisotropy) {
    float denominator = max(
        1.0 + anisotropy * anisotropy
            - 2.0 * anisotropy * cosTheta,
        0.00001
    );
    return PHOTON_VOXY_ISOTROPIC_PHASE
        * (1.0 - anisotropy * anisotropy)
        / (denominator * sqrt(denominator));
}

void photonVoxyWaterFog(
    vec3 tint,
    vec2 lightLevels,
    float layerDistance,
    vec3 directionWorld,
    out vec3 scattering,
    out vec3 transmittance
) {
    vec3 absorption = photonVoxyBiomeWaterAbsorption(tint);
    vec3 extinction = absorption + PHOTON_VOXY_WATER_SCATTERING;
    vec3 scatteringAlbedo = PHOTON_VOXY_WATER_SCATTERING / extinction;
    vec3 multipleFactor = 0.84 * scatteringAlbedo;
    vec3 multipleEnergy = multipleFactor / (1.0 - multipleFactor);

    float skyLightFactor = lightLevels.y * lightLevels.y * lightLevels.y;
    float opticalDistance = max(layerDistance, 2.0 - skyLightFactor);
    transmittance = exp(-extinction * opticalDistance);

    vec3 ambientLight = (
        skyCol + toLinear(AMBIENT_LIGHTING + nightVision * 0.5)
    ) * lightLevels.y;
    ambientLight += 1.41 * toLinear(1.25 * blockLightColor)
        * squared(lightLevels.x);

    #ifdef WORLD_LIGHT
        vec3 lightDirectionWorld = normalize(vec3(
            shadowModelView[0].z,
            shadowModelView[1].z,
            shadowModelView[2].z
        ));
        vec3 directLight = lightCol;
        float lightVisibility = smoothstep(0.0, 0.25, lightLevels.y);
        float phase = 0.7 * photonVoxyHenyeyGreenstein(
            dot(lightDirectionWorld, directionWorld),
            0.4
        ) + 0.3 * PHOTON_VOXY_ISOTROPIC_PHASE;
        scattering = directLight * lightVisibility * phase;
    #else
        scattering = vec3(0.0);
    #endif

    scattering += ambientLight * PHOTON_VOXY_ISOTROPIC_PHASE;
    scattering *= (1.0 - transmittance)
        * PHOTON_VOXY_WATER_SCATTERING / extinction;
    scattering *= 1.0 + multipleEnergy;
}

float photonVoxyF0ToIor(float f0) {
    float sqrtF0 = sqrt(f0) * 0.99999;
    return (1.0 + sqrtF0) / (1.0 - sqrtF0);
}

vec3 photonVoxyDielectricFresnel(float cosTheta, float f0) {
    float ior = photonVoxyF0ToIor(f0);
    float gSquared = ior * ior + cosTheta * cosTheta - 1.0;
    if (gSquared < 0.0) {
        return vec3(1.0);
    }
    float g = sqrt(gSquared);
    float a = g - cosTheta;
    float b = g + cosTheta;
    float fresnel = 0.5 * squared(a / b)
        * (1.0 + squared(
            (b * cosTheta - 1.0) / (a * cosTheta + 1.0)
        ));
    return vec3(fresnel);
}

#if defined WORLD_LIGHT && defined SPECULAR_HIGHLIGHTS
vec3 photonVoxyWaterHighlight(
    vec3 normal,
    vec3 directionWorld
) {
    vec3 lightDirectionWorld = normalize(vec3(
        shadowModelView[0].z,
        shadowModelView[1].z,
        shadowModelView[2].z
    ));
    vec3 viewerDirection = -directionWorld;
    float noL = dot(normal, lightDirectionWorld);
    float noV = clamp(dot(normal, viewerDirection), 0.0, 1.0);
    float loV = dot(lightDirectionWorld, viewerDirection);
    float halfwayNorm = inversesqrt(max(2.0 * loV + 2.0, 0.00001));
    float loH = clamp(loV * halfwayNorm + halfwayNorm, 0.0, 1.0);
    if (noL <= 0.00001) {
        return vec3(0.0);
    }

    float noHSquared = getNoHSquared(noL, noV, loV);
    float alphaSquared = PHOTON_VOXY_WATER_ROUGHNESS
        * PHOTON_VOXY_WATER_ROUGHNESS;
    float distributionDenominator = squared(
        1.0 - noHSquared + noHSquared * alphaSquared
    );
    float distribution = alphaSquared
        / (PI * max(distributionDenominator, 0.0000001));
    float ggxL = noV * sqrt(
        (-noL * alphaSquared + noL) * noL + alphaSquared
    );
    float ggxV = noL * sqrt(
        (-noV * alphaSquared + noV) * noV + alphaSquared
    );
    float visibility = 0.5 / max(ggxL + ggxV, 0.00001);
    vec3 fresnel = photonVoxyDielectricFresnel(
        loH,
        PHOTON_VOXY_WATER_F0
    );
    return min(
        vec3(noL * distribution * visibility) * fresnel,
        vec3(4.0)
    ) * lightCol;
}
#endif

#ifdef SSR
float photonWaterSsrtDepth(
    vec2 screenUv,
    bool frontIsVoxy
) {
    ivec2 samplerSize = frontIsVoxy
        ? textureSize(vxDepthTexTrans, 0)
        : textureSize(colortex15, 0);
    ivec2 texel = clamp(
        ivec2(screenUv * vec2(samplerSize)),
        ivec2(0),
        samplerSize - ivec2(1)
    );
    return frontIsVoxy
        ? texelFetch(vxDepthTexTrans, texel, 0).x
        : texelFetch(colortex15, texel, 0).x;
}

vec3 photonWaterSsrtScreenToView(
    vec3 screenPosition,
    bool frontIsVoxy,
    bool zeroToOneDepth,
    bool removeJitter
) {
    return frontIsVoxy
        ? photonVoxyScreenToView(
            screenPosition.xy,
            screenPosition.z,
            zeroToOneDepth,
            removeJitter
        )
        : photonCombinedScreenToView(
            screenPosition.xy,
            screenPosition.z,
            removeJitter
        );
}

bool photonRaymarchWater(
    vec3 screenPosition,
    vec3 viewPosition,
    vec3 viewDirection,
    float dither,
    bool frontIsVoxy,
    bool zeroToOneDepth,
    out vec3 hitPosition,
    out vec3 hitViewPosition
) {
    if (viewDirection.z > 0.0
    && viewDirection.z >= -viewPosition.z) {
        return false;
    }

    vec3 projectedDirection = photonWaterViewToScreen(
        viewPosition + viewDirection,
        frontIsVoxy,
        zeroToOneDepth,
        true
    ) - screenPosition;
    float projectedLength = length(projectedDirection);
    if (projectedLength <= 0.000001) {
        return false;
    }

    vec3 screenDirection = projectedDirection / projectedLength;
    vec3 boundaryDistance = abs(sign(screenDirection) - screenPosition)
        / max(abs(screenDirection), vec3(0.00001));
    float rayLength = min(
        boundaryDistance.x,
        min(boundaryDistance.y, boundaryDistance.z)
    );
    vec3 rayStep = screenDirection
        * (rayLength / max(float(rayTraceSteps), 1.0));
    hitPosition = screenPosition
        + dither * rayStep
        + length(vec2(pixelWidth, pixelHeight)) * screenDirection;

    float depthTolerance = max(
        abs(rayStep.z) * 3.0,
        0.02 / max(squared(viewPosition.z), 0.00001)
    );
    bool hit = false;

    for (uint i = 0u; i < rayTraceSteps; ++i, hitPosition += rayStep) {
        // Photon deliberately continues while an LoD-domain ray is in front
        // of the near plane instead of turning that moment into a hard miss.
        if (hitPosition.z < 0.0) {
            continue;
        }
        if (any(lessThan(hitPosition.xy, vec2(0.0)))
        || any(greaterThan(hitPosition.xy, vec2(1.0)))
        || hitPosition.z > 1.0) {
            return false;
        }

        float sampledDepth = photonWaterSsrtDepth(
            hitPosition.xy,
            frontIsVoxy
        );
        float depthDelta = hitPosition.z - sampledDepth;
        if (sampledDepth < hitPosition.z
        && abs(depthTolerance - depthDelta) < depthTolerance) {
            hit = true;
            break;
        }
    }

    if (!hit) {
        return false;
    }

    float finalDepth = photonWaterSsrtDepth(
        hitPosition.xy,
        frontIsVoxy
    );
    for (uint i = 0u; i < rayTraceBiSteps; ++i) {
        rayStep *= 0.5;

        float sampledDepth = photonWaterSsrtDepth(
            hitPosition.xy,
            frontIsVoxy
        );
        float depthDelta = hitPosition.z - sampledDepth;
        bool intersection = sampledDepth < hitPosition.z
            && abs(depthTolerance - depthDelta) < depthTolerance;
        hitPosition += intersection ? -rayStep : rayStep;
        finalDepth = sampledDepth;
    }

    // Photon reconstructs the refined ray position itself with jitter handling
    // disabled. Re-sampling/reprojecting a different surface here caused the
    // grazing-angle discontinuity at the native/LoD ownership boundary.
    hitViewPosition = photonWaterSsrtScreenToView(
        hitPosition,
        frontIsVoxy,
        zeroToOneDepth,
        false
    );
    return finalDepth > 0.56
        && finalDepth < 1.0
        && photonWaterFinitePosition(hitViewPosition);
}
#endif

vec3 photonRefogWaterReflection(
    vec3 foggedRadiance,
    vec2 fogUv,
    vec3 frontWorldPosition,
    vec3 hitWorldPosition,
    vec3 reflectedWorldDirection
) {
    // Photon stores fog scattering separately, subtracts it from reflected
    // history, then applies fog over only the water-to-hit segment. This avoids
    // trying to invert a temporally reprojected, already-fogged HDR value.
    vec3 clearRadiance = max(
        foggedRadiance - textureLod(colortex7, fogUv, 0).rgb,
        vec3(0.0)
    );

    vec3 reflectedSegment = hitWorldPosition - frontWorldPosition;
    float segmentDistance = length(reflectedSegment);
    if (segmentDistance <= 0.0001) {
        return clearRadiance;
    }
    vec3 segmentDirection = reflectedSegment / segmentDistance;
    float segmentFog = getFogFactor(
        segmentDistance,
        segmentDirection.y,
        hitWorldPosition.y
    );
    vec3 segmentFogColor = getSkyFogRender(reflectedWorldDirection);
    return mix(clearRadiance, segmentFogColor, segmentFog)
        * getFogEffectFactor(segmentDistance);
}

vec3 photonTraceWaterReflection(
    vec3 frontViewPosition,
    vec3 frontWorldPosition,
    vec3 directionWorld,
    vec3 waterNormal,
    float dither,
    bool frontIsVoxy,
    bool zeroToOneDepth
) {
    vec3 reflectedWorldDirection = reflect(directionWorld, waterNormal);
    // Match Photon's mirror branch exactly: a reflected ray below the
    // geometric water hemisphere contributes neither SSR nor sky radiance.
    // Letting that invalid ray reach the sky fallback produces a sudden bright
    // band precisely at low grazing angles.
    if (dot(waterNormal, reflectedWorldDirection) < 0.000001) {
        return vec3(0.0);
    }
    vec3 reflectedViewDirection = mat3(gbufferModelView)
        * reflectedWorldDirection;
    vec3 skyReflection = getSkyReflection(reflectedViewDirection);
    vec3 radiance = skyReflection;

    #ifdef SSR
        vec3 frontScreenPosition = photonWaterViewToScreen(
            frontViewPosition,
            frontIsVoxy,
            zeroToOneDepth,
            true
        );
        vec3 hitPosition;
        vec3 hitViewPosition;
        bool hit = photonRaymarchWater(
            frontScreenPosition,
            frontViewPosition,
            reflectedViewDirection,
            dither,
            frontIsVoxy,
            zeroToOneDepth,
            hitPosition,
            hitViewPosition
        );
        if (hit) {
            vec3 hitScenePosition = (
                gbufferModelViewInverse * vec4(hitViewPosition, 1.0)
            ).xyz;

            vec2 fogUv = hitPosition.xy;
            bool validReflectionSample = true;
            #ifdef PREVIOUS_FRAME
                vec3 previousViewPosition = (
                    gbufferPreviousModelView
                        * vec4(hitScenePosition + camPosDelta, 1.0)
                ).xyz;
                vec2 reflectionUv = getScreenCoord(
                    gbufferPreviousProjection,
                    previousViewPosition
                );
                bool validHistory = all(greaterThanEqual(
                    reflectionUv,
                    vec2(0.0)
                )) && all(lessThanEqual(reflectionUv, vec2(1.0)));
                if (validHistory) {
                    radiance = textureLod(colortex5, reflectionUv, 0).rgb;
                    fogUv = reflectionUv;
                } else {
                    // Photon returns the sky fallback when the reprojected hit
                    // leaves history; never run that fallback through hit fog.
                    radiance = skyReflection;
                    validReflectionSample = false;
                }
            #else
                radiance = textureLod(colortex4, hitPosition.xy, 0).rgb;
            #endif

            if (validReflectionSample) {
                vec3 hitWorldPosition = hitScenePosition + cameraPosition;
                radiance = photonRefogWaterReflection(
                    radiance,
                    fogUv,
                    frontWorldPosition,
                    hitWorldPosition,
                    reflectedWorldDirection
                );
            }

            // Photon's border attenuation makes the SSR-to-sky transition
            // continuous instead of exposing the chunk/LoD screen rectangle.
            float viewUp = clamp(
                1.0 - gbufferModelViewInverse[2].y,
                0.0,
                1.0
            );
            float viewUp4 = squared(squared(viewUp));
            float borderScale = mix(0.01, 0.000001, viewUp4);
            float borderSignal = (hitPosition.x * hitPosition.y - hitPosition.x)
                * (hitPosition.x * hitPosition.y - hitPosition.y);
            float borderAttenuation = clamp(
                borderSignal / borderScale,
                0.0,
                1.0
            );
            borderAttenuation *= 2.0 - borderAttenuation;
            radiance = mix(skyReflection, radiance, borderAttenuation);
        }
    #endif

    float noV = clamp(dot(waterNormal, -directionWorld), 0.0, 1.0);
    return radiance * photonVoxyDielectricFresnel(
        noV,
        PHOTON_VOXY_WATER_F0
    );
}

vec4 drawPhotonWater(
    vec3 frontViewPosition,
    vec3 frontWorldPosition,
    vec3 directionWorld,
    vec3 flatNormal,
    vec3 tint,
    vec2 lightLevels,
    float layerDistance,
    float dither,
    bool frontIsVoxy,
    bool zeroToOneDepth
) {
    float volumeLayerDistance = layerDistance;
    if (frontIsVoxy) {
        // Voxy's reduced fluid/solid surfaces can collapse the outermost water
        // cell when both layers are simplified.  The depth subtraction then
        // starts one full-water block too late, which removes the blue volume
        // scattering and leaves the LoD bottom too visible.  Restore that
        // missing 7/8-block column along the actual viewing ray; native depth
        // already contains it and therefore receives no correction.
        float surfaceRayCos = max(
            abs(dot(normalize(flatNormal), directionWorld)),
            0.125
        );
        volumeLayerDistance += 0.875 / surfaceRayCos;
    }

    vec3 scattering;
    vec3 transmittance;
    photonVoxyWaterFog(
        tint,
        lightLevels,
        volumeLayerDistance,
        directionWorld,
        scattering,
        transmittance
    );

    float brightnessControl = (1.0 - lightLevels.y)
        + (1.0 - exp(-0.33 * volumeLayerDistance)) * lightLevels.y;
    vec3 waterColor = scattering
        * (1.0 + 6.0 * transmittance * transmittance)
        * brightnessControl;

    vec3 waterNormal = photonVoxyWaterNormal(
        frontWorldPosition - vec3(0.0, 0.125, 0.0),
        flatNormal
    );

    #if defined WORLD_LIGHT && defined SPECULAR_HIGHLIGHTS
        waterColor += photonVoxyWaterHighlight(
            waterNormal,
            directionWorld
        );
    #endif

    waterColor += photonTraceWaterReflection(
        frontViewPosition,
        frontWorldPosition,
        directionWorld,
        waterNormal,
        dither,
        frontIsVoxy,
        zeroToOneDepth
    );

    return vec4(max(waterColor, vec3(0.0)), 1.0 - transmittance.r);
}

#endif
