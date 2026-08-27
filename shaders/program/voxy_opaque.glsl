// SDV Voxy opaque patch.
// Voxy owns a different projection/depth range, but not a different final view
// domain. Photon uses vxProj/vxProjInv only for projection and converts the
// result through the current vanilla model-view.

#define VOXY_PATCH

layout(location = 0) out vec4 sceneColOut; // colortex4
layout(location = 1) out vec3 normalDataOut; // colortex1
layout(location = 2) out vec3 albedoDataOut; // colortex2
layout(location = 3) out vec3 materialDataOut; // colortex3
layout(location = 4) out vec4 voxyDepthConventionOut; // colortex17

#if defined WORLD_LIGHT && defined SHADOW_MAPPING
    #include "/lib/lighting/voxyForwardShadow.glsl"
#endif

#if PBR_MODE == 1 && defined ENVIRONMENT_PBR && !defined FORCE_DISABLE_WEATHER \
        && defined WORLD_LIGHT && defined SPECULAR_HIGHLIGHTS
    #include "/lib/lighting/GGX.glsl"
#endif

// Voxy exposes the centre of a 16x16 lightmap texel. Reconstruct Minecraft's
// original 0,16,...,240 vertex-light coordinate and then run SDV's own decode;
// this preserves SDV's endpoint/precision correction exactly.
vec2 decodeVoxyLightMap(vec2 encodedLightMap) {
    return lightMapCoord(encodedLightMap * 256.0 - 8.0);
}

// Keep this classification identical to integratedPBR.glsl. customId is the
// Iris block.properties ID attached to the original block state by Voxy.
bool isVoxySubsurfaceMaterial(uint customId) {
    return (customId >= 10000u && customId <= 10800u)
        || (customId >= 11600u && customId <= 11799u)
        || customId == 10900u
        || customId == 11101u
        || customId == 12200u;
}

// The Voxy model atlas contains 256x256 models. Each model occupies a 3x2
// grid of projected 16x16 face textures.
const vec2 VOXY_MODEL_ATLAS_FACE_GRID = vec2(3.0 * 256.0, 2.0 * 256.0);

// Common ground surfaces whose Minecraft 26.2 blockstates contain four
// equally weighted y rotations (0, 90, 180 and 270 degrees). block.properties
// assigns this ID only to the affected states; snowy grass/podzol/mycelium use
// a single snow model and deliberately remain outside the group.
const uint VOXY_RANDOM_Y_SURFACE_ID = 13200u;

uint getVoxyRandomYVariant(ivec3 blockPosition) {
    // Deliberately cheap per-fragment approximation. Reproducing Java's
    // 64-bit Mth/Random sequence here caused severe register pressure and a
    // large throughput loss. This keeps a stable, well-distributed four-way
    // pattern, but it does not match vanilla's rotation at each coordinate.
    uvec3 positionBits = uvec3(blockPosition);
    uint hash = positionBits.x * 0x8DA6B343u
        ^ positionBits.y * 0xCB1AB31Fu
        ^ positionBits.z * 0xD8163841u;
    hash ^= hash >> 16u;
    return hash & 3u;
}

void rotateVoxyUvClockwise(
    uint quarterTurns,
    inout vec2 uv,
    inout vec2 uvDx,
    inout vec2 uvDy
) {
    if (quarterTurns == 1u) {
        uv = vec2(1.0 - uv.y, uv.x);
        uvDx = vec2(-uvDx.y, uvDx.x);
        uvDy = vec2(-uvDy.y, uvDy.x);
    } else if (quarterTurns == 2u) {
        uv = 1.0 - uv;
        uvDx = -uvDx;
        uvDy = -uvDy;
    } else if (quarterTurns == 3u) {
        uv = vec2(uv.y, 1.0 - uv.x);
        uvDx = vec2(uvDx.y, -uvDx.x);
        uvDy = vec2(uvDy.y, -uvDy.x);
    }
}

bool voxyModelFaceExists(uint faceData) {
    return faceData != 0xFFFFFFFFu;
}

// Identify SDV cutout vegetation whose baked Voxy model still has the
// topology of Minecraft's crossed planes. Requiring both horizontal
// projections while rejecting up/down projections keeps this away from
// leaves, lily pads, wall vines and ordinary alpha-tested block models.
bool isVoxyPrincipledCrossPlant(VoxyFragmentParameters parameters) {
    if (!isVoxySubsurfaceMaterial(parameters.customId) || !useDiscard()) {
        return false;
    }

    BlockModel model = modelData[parameters.modelId];
    bool hasHorizontalFace = voxyModelFaceExists(model.faceData[0])
        || voxyModelFaceExists(model.faceData[1]);
    bool hasZProjection = voxyModelFaceExists(model.faceData[2])
        || voxyModelFaceExists(model.faceData[3]);
    bool hasXProjection = voxyModelFaceExists(model.faceData[4])
        || voxyModelFaceExists(model.faceData[5]);

    return !hasHorizontalFace && hasXProjection && hasZProjection;
}

uint hashVoxyCrossPlantFragment(VoxyFragmentParameters parameters) {
    // Anchor the stochastic coverage to the baked 16x16 model texel and the
    // merged-quad tile. It therefore stays fixed while the camera moves and
    // needs neither frame time nor a screen-space noise lookup.
    vec2 faceUv = fract(parameters.uv * VOXY_MODEL_ATLAS_FACE_GRID);
    uvec2 modelTexel = uvec2(clamp(
        floor(faceUv * 16.0),
        vec2(0.0),
        vec2(15.0)
    ));
    uvec2 quadTile = uvec2(max(floor(parameters.tile), vec2(0.0)));

    uint hash = (parameters.modelId + 1u) * 0x9E3779B9u;
    hash ^= (getFace() + 1u) * 0x85EBCA6Bu;
    hash ^= (quadTile.x + quadTile.y * 17u + 1u) * 0xC2B2AE35u;
    hash ^= (modelTexel.x + modelTexel.y * 16u + 1u) * 0x27D4EB2Fu;
    hash ^= hash >> 16u;
    hash *= 0x7FEB352Du;
    hash ^= hash >> 15u;
    hash *= 0x846CA68Bu;
    hash ^= hash >> 16u;
    return hash;
}

float getVoxyCrossPlantCoverage(vec3 feetPlayerPosition) {
    vec2 projectedView = abs(feetPlayerPosition.xz);
    float proxyProjectedArea = projectedView.x + projectedView.y;
    if (proxyProjectedArea <= 1e-6) return 1.0;

    // For the two original +/-45 degree planes:
    // (abs(Vx+Vz) + abs(Vx-Vz)) / sqrt(2)
    //     = sqrt(2) * max(abs(Vx), abs(Vz)).
    // Each orthographic Voxy face already contains the complete axis-view
    // silhouette, so its normalized target is max(abs(Vx),abs(Vz)). Voxy's
    // two visible proxy faces instead sum to abs(Vx)+abs(Vz). Their ratio is
    // the exact stochastic retention probability required to conserve the
    // crossed model's projected area.
    return max(projectedView.x, projectedView.y) / proxyProjectedArea;
}

void getVoxyCrossPlantGeometry(
    vec3 feetPlayerPosition,
    vec3 proxyNormal,
    out vec3 planeNormalA,
    out vec3 planeNormalB,
    out vec2 planeWeights,
    out vec3 effectiveNormal
) {
    const float inverseSqrtTwo = 0.7071067811865476;
    planeNormalA = vec3(inverseSqrtTwo, 0.0, inverseSqrtTwo);
    planeNormalB = vec3(inverseSqrtTwo, 0.0, -inverseSqrtTwo);

    float viewLengthSquared = dot(feetPlayerPosition, feetPlayerPosition);
    if (viewLengthSquared <= 1e-8) {
        planeWeights = vec2(0.0);
        effectiveNormal = proxyNormal;
        return;
    }

    vec3 viewDirection = -feetPlayerPosition * inversesqrt(viewLengthSquared);
    vec2 facing = vec2(
        dot(planeNormalA, viewDirection),
        dot(planeNormalB, viewDirection)
    );

    // Minecraft's crossed cutouts are visible from both sides. Orient each
    // analytical plane toward the current view, then weight it by projected
    // area. This is the first normal moment of the visible crossed geometry.
    planeNormalA *= facing.x < 0.0 ? -1.0 : 1.0;
    planeNormalB *= facing.y < 0.0 ? -1.0 : 1.0;
    planeWeights = abs(facing);

    vec3 normalMoment = planeNormalA * planeWeights.x
        + planeNormalB * planeWeights.y;
    float momentLengthSquared = dot(normalMoment, normalMoment);
    effectiveNormal = momentLengthSquared > 1e-8
        ? normalMoment * inversesqrt(momentLengthSquared)
        : proxyNormal;
}

vec3 reconstructVoxyFeetPlayerPosition() {
    vec3 screenPosition = vec3(
        gl_FragCoord.xy / vec2(viewWidth, viewHeight),
        gl_FragCoord.z
    );

    vec4 viewPosition = vxProjInv * vec4(
        screenPosition.xy * 2.0 - 1.0,
        SCREEN2NDC_DEPTH(screenPosition.z),
        1.0
    );
    viewPosition /= viewPosition.w;
    return (gbufferModelViewInverse * viewPosition).xyz;
}

// Integrated PBR starts ordinary terrain at porosity=0, metallic=0.04 and
// smoothness=0. This is enviroPBR.glsl's rainMatFact with those exact defaults.
// The early exits are algebraically neutral and avoid the noise lookup for dry,
// covered, vertical and downward-facing fragments.
#if PBR_MODE == 1 && defined ENVIRONMENT_PBR && !defined FORCE_DISABLE_WEATHER
float getVoxyIntegratedRainMaterialFactor(
    vec2 lightMap,
    vec3 geometricNormal,
    vec3 feetPlayerPosition
) {
    if (isPrecipitationRain <= 0.0 || geometricNormal.y < 0.005 || dot(feetPlayerPosition.xz, feetPlayerPosition.xz) > 65536.0) {
        return 0.0;
    }

    float skyLightDelta = lightMap.y - 0.8;
    if (skyLightDelta <= 0.0) return 0.0;

    float rainMaterialFactor = skyLightDelta
        * isPrecipitationRain * geometricNormal.y * 5.0;

    vec3 worldPosition = feetPlayerPosition + cameraPosition;
    vec2 rainNoise = textureLod(
        noisetex,
        worldPosition.xz * 0.001953125,
        0.0
    ).xy;
    rainMaterialFactor *= clamp(rainNoise.x + rainNoise.y - 0.5, 0.0, 1.0);

    return rainMaterialFactor;
}

bool excludesVoxyIntegratedEnvironmentPbr(uint customId) {
    // Match gbuffers_terrain's lava/fire exclusions. Water is handled by the
    // translucent pipeline and is also excluded by gbuffers_water.
    return customId == 11100u || customId == 12101u || customId == 11102u;
}
#endif

vec2 getVoxyWorldFaceUv(uint face, vec3 worldPosition) {
    uint axis = face >> 1u;

    if (axis == 0u) return worldPosition.xz; // Down / up
    if (axis == 1u) return worldPosition.xy; // North / south
    return worldPosition.yz;                 // West / east
}

bool canWorldLockVoxyFace(uint modelId, uint sourceFace) {
    uint faceData = modelData[modelId].faceData[sourceFace];
    vec4 faceBounds = extractFaceSizes(faceData);

    // Voxy classifies the whole grass model as cutout because its side overlay
    // contains alpha. Its up face is nevertheless a complete opaque texture,
    // so changing that face's UV cannot invalidate Voxy's earlier alpha test.
    bool safeRandomSurfaceTop = sourceFace == 1u
        && modelData[modelId].customId == VOXY_RANDOM_Y_SURFACE_ID;

    // Voxy performs its alpha test before entering this patch. Changing a
    // cutout face's UV here would make that old mask disagree with the new
    // sample, so only complete opaque 1x1 faces are safe to reproject.
    return (!useDiscard() || safeRandomSurfaceTop)
        && all(equal(faceBounds, vec4(0.0, 1.0, 0.0, 1.0)));
}

vec4 sampleVoxySurfaceColour(
    VoxyFragmentParameters parameters,
    vec3 feetPlayerPosition
) {
    // Beyond 256m, a block quad occupies only ~1 pixel or less on screen.
    // Skip expensive manual derivatives (dFdx/dFdy), random rotation hashing,
    // and textureGrad sampling by directly returning Voxy's pre-baked colour.
    if (dot(feetPlayerPosition.xz, feetPlayerPosition.xz) > 65536.0) {
        return parameters.sampledColour;
    }

    // Accepted limitation: once a coarse LOD voxel has collapsed several
    // block materials into one modelId, their original distribution is gone.
    // This path only restores the surviving face texture's world-space scale.
    // getFace() is the source atlas face. parameters.face may subsequently be
    // flipped for the geometric normal, while the texture cell stays here.
    uint sourceFace = getFace();
    if (!canWorldLockVoxyFace(parameters.modelId, sourceFace)) {
        return parameters.sampledColour;
    }

    // Voxy keeps the camera's integer section and section-local position
    // separate. Using cameraSubPos preserves block precision at the world
    // border, unlike adding the large float cameraPosition directly.
    vec3 sectionWorldPosition = feetPlayerPosition + cameraSubPos;
    vec2 worldFaceUv = getVoxyWorldFaceUv(
        sourceFace,
        sectionWorldPosition
    );

    vec2 localFaceUv = fract(worldFaceUv);
    vec2 localFaceUvDx = dFdx(worldFaceUv);
    vec2 localFaceUvDy = dFdy(worldFaceUv);

    if (parameters.customId == VOXY_RANDOM_Y_SURFACE_ID && sourceFace == 1u) {
        // Move just inside the owning block before flooring: an up face lies
        // on the next block's integer Y boundary, while dirt paths already lie
        // slightly below it. baseSectionPos is measured in 32-block sections.
        ivec3 blockPosition = (baseSectionPos << 5) + ivec3(floor(
            sectionWorldPosition - vec3(0.0, 0.001, 0.0)
        ));
        uint surfaceVariant = getVoxyRandomYVariant(blockPosition);

        // SoftwareModelTextureBakery always uses seed 42. For an equal-weight
        // four-entry list that selects entry 2 (the 180-degree model), so sample
        // the baked image at bakedRotation - requestedRotation.
        uint relativeQuarterTurns = (2u - surfaceVariant) & 3u;
        rotateVoxyUvClockwise(
            relativeQuarterTurns,
            localFaceUv,
            localFaceUvDx,
            localFaceUvDy
        );
    }

    uvec2 modelCell = uvec2(
        parameters.modelId & 255u,
        (parameters.modelId >> 8u) & 255u
    );
    uvec2 atlasFaceCell = modelCell * uvec2(3u, 2u)
        + uvec2(sourceFace >> 1u, sourceFace & 1u);

    vec2 atlasUv = (vec2(atlasFaceCell) + localFaceUv)
        / VOXY_MODEL_ATLAS_FACE_GRID;

    // Differentiate the unwrapped world coordinate. Hardware therefore sees
    // the vanilla virtual mip0 density: 16 source texels per world-space block.
    vec2 atlasUvDx = localFaceUvDx / VOXY_MODEL_ATLAS_FACE_GRID;
    vec2 atlasUvDy = localFaceUvDy / VOXY_MODEL_ATLAS_FACE_GRID;

    return textureGrad(blockModelAtlas, atlasUv, atlasUvDx, atlasUvDy);
}

void voxy_emitFragment(VoxyFragmentParameters parameters) {
    vec2 lmCoord = decodeVoxyLightMap(parameters.lightMap);
    #ifdef WORLD_CUSTOM_SKYLIGHT
        lmCoord.y = WORLD_CUSTOM_SKYLIGHT;
    #endif

    bool isPrincipledCrossPlant = isVoxyPrincipledCrossPlant(parameters);

    #if COLOR_MODE == 0 || defined WORLD_LIGHT \
            || (PBR_MODE == 1 && defined ENVIRONMENT_PBR && !defined FORCE_DISABLE_WEATHER)
        vec3 currentFeetPlayerPos = reconstructVoxyFeetPlayerPosition();
    #else
        vec3 currentFeetPlayerPos = vec3(0.0);
        if (isPrincipledCrossPlant) {
            currentFeetPlayerPos = reconstructVoxyFeetPlayerPosition();
        }
    #endif

    if (isPrincipledCrossPlant) {
        float retainedCoverage = getVoxyCrossPlantCoverage(currentFeetPlayerPos);
        float coverageSample = float(
            hashVoxyCrossPlantFragment(parameters) & 0x00FFFFFFu
        ) * (1.0 / 16777216.0);
        if (coverageSample >= retainedCoverage) {
            discard;
            return;
        }
    }

    vec3 srgbAlbedo;
    #if COLOR_MODE == 1
        srgbAlbedo = vec3(1.0);
    #elif COLOR_MODE == 2
        srgbAlbedo = vec3(0.0);
    #elif COLOR_MODE == 3
        srgbAlbedo = parameters.tinting.rgb;
    #else
        srgbAlbedo = sampleVoxySurfaceColour(
            parameters,
            currentFeetPlayerPos
        ).rgb * parameters.tinting.rgb;
    #endif
    vec3 baseColor = toLinear(srgbAlbedo);

    // Decode the cuboid face normal from Voxy's face byte.
    vec3 normal = vec3(
        uint((parameters.face >> 1u) == 2u),
        uint((parameters.face >> 1u) == 0u),
        uint((parameters.face >> 1u) == 1u)
    ) * (float(int(parameters.face) & 1) * 2.0 - 1.0);

    vec3 crossPlaneNormalA = normal;
    vec3 crossPlaneNormalB = normal;
    vec2 crossPlaneWeights = vec2(0.0);
    if (isPrincipledCrossPlant) {
        getVoxyCrossPlantGeometry(
            currentFeetPlayerPos,
            normal,
            crossPlaneNormalA,
            crossPlaneNormalB,
            crossPlaneWeights,
            normal
        );
    }

    const float voxyMaterialAmbient = 1.0;
    float voxyMaterialMetallic = 0.0;
    float voxyMaterialSmoothness = 0.0;
    float rainMaterialFactor = 0.0;

    #if PBR_MODE == 1 && defined ENVIRONMENT_PBR && !defined FORCE_DISABLE_WEATHER
        if (!excludesVoxyIntegratedEnvironmentPbr(parameters.customId)) {
            rainMaterialFactor = getVoxyIntegratedRainMaterialFactor(
                lmCoord,
                normal,
                currentFeetPlayerPos
            );

            if (rainMaterialFactor > 0.0) {
                // enviroPBR.glsl for Integrated PBR defaults:
                // metallic=max(0.02*f, 0.04), smoothness=mix(0, 0.96, f).
                voxyMaterialMetallic = 0.04;
                voxyMaterialSmoothness = 0.96 * rainMaterialFactor;
                baseColor *= 1.0 - rainMaterialFactor * 0.5;
            }
        }
    #endif

    float blockLightSquared = squared(lmCoord.x);
    float skyLightSquared = squared(lmCoord.y);

    vec3 wetSpecularDelta = vec3(0.0);

    vec3 totalIllumination =
        (toLinear(SKY_COLOR_DATA_BLOCK) + lightningFlash) * skyLightSquared;
    totalIllumination += toLinear(blockLightSquared * blockLightColor * 1.25);
    totalIllumination += toLinear(vec3(nightVision * 0.5 + AMBIENT_LIGHTING));

    #ifdef WORLD_LIGHT
        float NdotL = dot(normal, voxyLightDir);
        float crossPlaneWeightSum = crossPlaneWeights.x + crossPlaneWeights.y;
        float directionalDiffuse;
        if (isPrincipledCrossPlant && crossPlaneWeightSum > 1e-6) {
            // SDV's original diffuse term is max(0,N.L). Apply that exact
            // function to both analytical crossed planes, then integrate them
            // using their visible projected areas instead of evaluating the
            // non-linear Lambert term on Voxy's cuboid proxy normal.
            vec2 crossedLambert = max(vec2(0.0), vec2(
                dot(crossPlaneNormalA, voxyLightDir),
                dot(crossPlaneNormalB, voxyLightDir)
            ));
            directionalDiffuse = dot(crossedLambert, crossPlaneWeights)
                / crossPlaneWeightSum;
        } else {
            directionalDiffuse = max(0.0, NdotL);
        }

        // Vanilla SDV does not shade foliage as pure Lambert. Its terrain
        // material path assigns ss=0.75 and fills in the back/edge-lit part of
        // the direct term. Voxy cannot reproduce per-vertex AO, so use the
        // neutral ambient value (1.0) that open cutout plants normally carry.
        #ifdef SUBSURFACE_SCATTERING
            if (isVoxySubsurfaceMaterial(parameters.customId)) {
                const float voxySubsurface = 0.75;
                directionalDiffuse += (1.0 - directionalDiffuse)
                    * voxyMaterialAmbient * voxySubsurface * 0.5;
            }
        #endif

        float sunCaveGate = isEyeInWater == 1
            ? skyLightSquared
            : smoothstep(0.0, 0.25, lmCoord.y);

        float lodCastShadow = 1.0;
        vec3 vanillaCastShadow = vec3(1.0);
        float vanillaWaterCasterCoverage = 0.0;
        #ifdef SHADOW_MAPPING
            lodCastShadow = getVoxyTemporalCastShadow(currentFeetPlayerPos);
            vanillaCastShadow = getVoxyVanillaCastShadow(
                currentFeetPlayerPos,
                normal,
                vanillaWaterCasterCoverage
            );
        #endif
        if (isEyeInWater == 1) {
            sunCaveGate = mix(
                skyLightSquared,
                1.0,
                vanillaWaterCasterCoverage
            );
        }

        // The regular CSM and Voxy-only caster mask are independent factors.
        // Only direct celestial light is shadowed; ambient terms stay intact.
        vec3 shdCol = vanillaCastShadow
            * (directionalDiffuse * shdFade * sunCaveGate * lodCastShadow);

        #ifndef FORCE_DISABLE_WEATHER
            // Keep the rain-diffused direct term mathematically identical to
            // complexShadingForward.glsl. Voxy has no per-vertex AO, so its
            // existing neutral material ambient is the only substituted input.
            float rainDiffuseAmount = rainStrength * 0.5;
            shdCol *= 1.0 - rainDiffuseAmount;
            shdCol += rainDiffuseAmount * voxyMaterialAmbient
                * skyLightSquared * (1.0 - shdFade);
        #endif

        #if PBR_MODE == 1 && defined ENVIRONMENT_PBR \
                && !defined FORCE_DISABLE_WEATHER && defined SPECULAR_HIGHLIGHTS
            if (rainMaterialFactor > 0.0 && NdotL > 0.0 && rainStrength < 1.0) {
                vec3 viewDirection = -fastNormalize(currentFeetPlayerPos);
                float viewNormalDot = dot(normal, viewDirection);

                // Voxy's accepted dry path predates Integrated-PBR GGX. Add
                // only the wet-minus-dry GGX delta so clear weather remains
                // bit-identical while the weather response matches Vanilla.
                vec3 drySpecular = getSpecularBRDF(
                    viewDirection,
                    normal,
                    baseColor,
                    NdotL,
                    viewNormalDot,
                    0.04,
                    0.0
                );
                vec3 wetSpecular = getSpecularBRDF(
                    viewDirection,
                    normal,
                    baseColor,
                    NdotL,
                    viewNormalDot,
                    voxyMaterialMetallic,
                    voxyMaterialSmoothness
                );
                wetSpecularDelta = (wetSpecular - drySpecular)
                    * shdCol * LIGHT_COLOR_DATA_BLOCK0;
            }
        #endif

        totalIllumination += shdCol * toLinear(LIGHT_COLOR_DATA_BLOCK0);
    #endif

    #if PBR_MODE == 1 && defined ENVIRONMENT_PBR && !defined FORCE_DISABLE_WEATHER
        if (rainMaterialFactor > 0.0) {
            // Same dielectric Fresnel energy removal as complexShadingForward.
            vec3 viewDirection = -fastNormalize(currentFeetPlayerPos);
            float viewNormalDot = dot(normal, viewDirection);
            float smoothCosTheta = viewNormalDot > 0.0
                ? exp2(-9.28 * viewNormalDot) * voxyMaterialSmoothness
                : voxyMaterialSmoothness;
            float oneMinusCosTheta = voxyMaterialSmoothness - smoothCosTheta;
            totalIllumination *= 1.0 - (
                smoothCosTheta + voxyMaterialMetallic * oneMinusCosTheta
            );
        }
    #endif

    vec3 sceneColor = baseColor * totalIllumination + wetSpecularDelta;

    sceneColOut = vec4(sceneColor, 1.0);
    normalDataOut = normal;
    albedoDataOut = baseColor;
    materialDataOut = vec3(
        voxyMaterialMetallic,
        voxyMaterialSmoothness,
        0.0
    );
    // Carry the Voxy clip-depth convention wherever an opaque LoD back layer
    // exists.  0.01 is below composite's translucent-kind threshold; adding 2
    // preserves the existing zero-to-one convention encoding. Native water
    // overwrites only this target's RGB and deliberately keeps destination A.
    voxyDepthConventionOut = vec4(
        0.0,
        0.0,
        0.0,
        0.01 + 2.0 * float(SCREEN2NDC_DEPTH(0.0) == 0.0)
    );
}
