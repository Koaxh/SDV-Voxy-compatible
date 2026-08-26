/*
================================ /// Super Duper Vanilla v1.3.8 /// ================================

    Developed by Eldeston, presented by FlameRender (C) Studios.

    Copyright (C) 2023 Eldeston | FlameRender (C) Studios License


    By downloading this content you have agreed to the license and its terms of use.

================================ /// Super Duper Vanilla v1.3.8 /// ================================
*/

/// Buffer features: TAA jittering, complex shading, animation, water noise, PBR, and world curvature

/// -------------------------------- /// Vertex Shader /// -------------------------------- ///

#ifdef VERTEX
    flat out int blockId;

    out vec2 lmCoord;
    out vec2 texCoord;
    out vec2 waterNoiseUv;

    out vec3 vertexColor;
    out vec3 vertexFeetPlayerPos;
    out vec3 vertexWorldPos;

    out mat3 TBN;

    #if defined NORMAL_GENERATION || defined PARALLAX_OCCLUSION
        flat out vec2 vTexCoordScale;
        flat out vec2 vTexCoordPos;

        out vec2 vTexCoord;
    #endif

    uniform vec3 cameraPosition;

    uniform mat4 gbufferModelViewInverse;

    #if defined WATER_ANIMATION || defined WORLD_CURVATURE
        uniform mat4 gbufferModelView;
    #endif
    
    #if ANTI_ALIASING == 2
        uniform int frameMod;

        uniform float pixelWidth;
        uniform float pixelHeight;

        #include "/lib/utility/taaJitter.glsl"
    #endif

    #ifdef WATER_ANIMATION
        uniform float vertexFrameTime;

        #include "/lib/vertex/waveWater.glsl"
    #endif

    attribute vec3 mc_Entity;

    attribute vec4 at_tangent;

    #if defined NORMAL_GENERATION || defined PARALLAX_OCCLUSION
        attribute vec2 mc_midTexCoord;
    #endif

    void main(){
        // Get block id
        blockId = int(mc_Entity.x);
        // Get buffer texture coordinates
        texCoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
        // Get vertex color
        vertexColor = gl_Color.rgb;

        // Lightmap fix for mods
        #ifdef WORLD_CUSTOM_SKYLIGHT
            lmCoord = vec2(lightMapCoord(gl_MultiTexCoord1.x), WORLD_CUSTOM_SKYLIGHT);
        #else
            lmCoord = lightMapCoord(gl_MultiTexCoord1.xy);
        #endif

        // Get vertex normal
        vec3 vertexNormal = fastNormalize(gl_Normal);
        // Get vertex tangent
        vec3 vertexTangent = fastNormalize(at_tangent.xyz);

        // Get vertex view position
        vec3 vertexViewPos = mat3(gl_ModelViewMatrix) * gl_Vertex.xyz + gl_ModelViewMatrix[3].xyz;
        // Get vertex feet player position
        vertexFeetPlayerPos = mat3(gbufferModelViewInverse) * vertexViewPos + gbufferModelViewInverse[3].xyz;

        // Get world position
        vertexWorldPos = vertexFeetPlayerPos + cameraPosition;

        // Get water noise uv position
        waterNoiseUv = vertexWorldPos.xz * waterTileSizeInv;

        // Calculate TBN matrix
	    TBN = mat3(gbufferModelViewInverse) * (gl_NormalMatrix * mat3(vertexTangent, cross(vertexTangent, vertexNormal) * sign(at_tangent.w), vertexNormal));

        #if defined NORMAL_GENERATION || defined PARALLAX_OCCLUSION
            vec2 midCoord = (gl_TextureMatrix[0] * vec4(mc_midTexCoord, 0, 0)).xy;
            vec2 texMinMidCoord = texCoord - midCoord;

            vTexCoordScale = abs(texMinMidCoord) * 2.0;
            vTexCoordPos = min(texCoord, midCoord - texMinMidCoord);
            vTexCoord = sign(texMinMidCoord) * 0.5 + 0.5;
        #endif

        #ifdef WATER_ANIMATION
            vertexFeetPlayerPos = getWaterWave(vertexFeetPlayerPos, vertexWorldPos.xz, mc_Entity.x, vertexFrameTime);
        #endif

        #ifdef WORLD_CURVATURE
            // Apply curvature distortion
            vertexFeetPlayerPos.y -= dot(vertexFeetPlayerPos.xz, vertexFeetPlayerPos.xz) * worldCurvatureInv;
        #endif

        #if defined WATER_ANIMATION || defined WORLD_CURVATURE
            // Convert back to vertex view position
            vertexViewPos = mat3(gbufferModelView) * vertexFeetPlayerPos + gbufferModelView[3].xyz;
        #endif

        // Convert to clip position and output as final position
        // gl_Position = gl_ProjectionMatrix * vertexViewPos;
        gl_Position.xyz = getMatScale(mat3(gl_ProjectionMatrix)) * vertexViewPos;
        gl_Position.z += gl_ProjectionMatrix[3].z;

        gl_Position.w = -vertexViewPos.z;

        #if ANTI_ALIASING == 2
            gl_Position.xy += jitterPos(gl_Position.w);
        #endif
    }
#endif

/// -------------------------------- /// Fragment Shader /// -------------------------------- ///

#ifdef FRAGMENT
    #ifdef VOXY
        /* RENDERTARGETS: 4,1,2,3,16,17,19,20 */
    #else
        /* RENDERTARGETS: 4,1,2,3 */
    #endif
    layout(location = 0) out vec4 sceneColOut; // colortex4
    layout(location = 1) out vec3 normalDataOut; // colortex1
    layout(location = 2) out vec3 albedoDataOut; // colortex2
    layout(location = 3) out vec3 materialDataOut; // colortex3
    #ifdef VOXY
        // Photon-style raw water packet.  Alpha on these outputs is an MRT
        // overwrite mask; the real thin-surface alpha is stored in .z of the
        // final packet so it cannot be confused with blend coverage.
        layout(location = 4) out vec4 photonWaterSurfaceColorOut; // colortex16
        layout(location = 5) out vec4 photonWaterNormalOut;       // colortex17
        layout(location = 6) out vec4 photonWaterTintOut;         // colortex19
        layout(location = 7) out vec4 photonWaterMetaOut;         // colortex20
    #endif

    flat in int blockId;

    in vec2 lmCoord;
    in vec2 texCoord;
    in vec2 waterNoiseUv;

    in vec3 vertexColor;
    in vec3 vertexFeetPlayerPos;
    in vec3 vertexWorldPos;

    in mat3 TBN;

    #if defined NORMAL_GENERATION || defined PARALLAX_OCCLUSION
        flat in vec2 vTexCoordScale;
        flat in vec2 vTexCoordPos;

        in vec2 vTexCoord;
    #endif

    uniform int isEyeInWater;

    uniform float nightVision;
    uniform float lightningFlash;

    uniform float near;

    uniform sampler2D depthtex1;
    uniform sampler2D gtexture;

    #ifdef VOXY
        #if ANTI_ALIASING == 2
            uniform int frameMod;
            uniform float pixelWidth;
            uniform float pixelHeight;
        #endif

        uniform mat4 gbufferProjectionInverse;
        uniform mat4 gbufferModelViewInverse;

        vec2 photonNativeTaaJitterNdc(){
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

        vec3 photonNativeScreenToView(float depth){
            vec2 screenSize = vec2(textureSize(depthtex1, 0));
            vec2 ndc = gl_FragCoord.xy / screenSize * 2.0 - 1.0;
            ndc -= photonNativeTaaJitterNdc();
            vec4 viewPosition = gbufferProjectionInverse
                * vec4(ndc, depth * 2.0 - 1.0, 1.0);
            return viewPosition.xyz / viewPosition.w;
        }

        void getPhotonNativeThinWaterSurface(
            vec4 sampledWater,
            vec3 flatNormal,
            out vec3 surfaceAlbedo,
            out float surfaceAlpha
        ){
            const vec3 photonWaterAbsorption = vec3(0.39, 0.14, 0.07);

            float highlightSignal = clamp(
                0.5 * squared(clamp(
                    (sampledWater.r - 0.63) / 0.37,
                    0.0,
                    1.0
                )) + 0.03 * sampledWater.r,
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
                0.5 * exp(-2.0 * photonWaterAbsorption) * textureHighlight,
                0.0,
                1.0
            );
            surfaceAlpha = 0.01 + textureHighlight;

            vec3 frontViewPosition = photonNativeScreenToView(gl_FragCoord.z);
            float backDepth = texelFetch(
                depthtex1,
                ivec2(gl_FragCoord.xy),
                0
            ).x;
            vec3 backViewPosition = photonNativeScreenToView(backDepth);
            float layerDistance = distance(frontViewPosition, backViewPosition);
            if(isnan(layerDistance) || isinf(layerDistance)) layerDistance = 48000.0;

            vec3 directionWorld = fastNormalize(
                mat3(gbufferModelViewInverse) * frontViewPosition
            );
            float normalLayerDistance = layerDistance
                * max(abs(directionWorld.y), 0.00001);
            float edgeHighlight = max(1.0 - 2.0 * normalLayerDistance, 0.0);
            edgeHighlight = edgeHighlight * edgeHighlight * edgeHighlight
                * (1.0 + 8.0 * textureHighlight);
            edgeHighlight *= max(flatNormal.y, 0.0)
                * (1.0 - 0.5 * squared(lmCoord.y));

            // Only the luminance normalization for Photon's thin edge term is
            // needed here.  Dimension sky macros require uniforms that are not
            // part of every gbuffers_water variant, while the shared final
            // resolver applies the actual dimension sky lighting.
            vec3 ambientColor = vec3(toLinear(
                AMBIENT_LIGHTING + nightVision * 0.5
            ));
            float ambientLuminance = dot(
                ambientColor,
                vec3(0.2126, 0.7152, 0.0722)
            );
            surfaceAlbedo += 0.1 * edgeHighlight
                / mix(1.0, max(ambientLuminance, 0.5), lmCoord.y);
            surfaceAlbedo = clamp(surfaceAlbedo, 0.0, 1.0);
            surfaceAlpha = clamp(surfaceAlpha + edgeHighlight, 0.0, 1.0);
        }
    #endif

    #ifndef FORCE_DISABLE_WEATHER
        uniform float rainStrength;
    #endif

    #if defined SHADOW_FILTER && ANTI_ALIASING >= 2
        uniform float frameFract;
    #endif

    #ifndef FORCE_DISABLE_DAY_CYCLE
        uniform float dayCycle;
        uniform float twilightPhase;
    #endif

    #ifdef WORLD_VANILLA_FOG_COLOR
        uniform vec3 fogColor;
    #endif

    #ifdef WORLD_CUSTOM_SKYLIGHT
        const float eyeBrightFact = WORLD_CUSTOM_SKYLIGHT;
    #else
        uniform float eyeSkylight;
        
        float eyeBrightFact = eyeSkylight;
    #endif

    #ifdef WORLD_LIGHT
        uniform float shdFade;

        uniform mat4 shadowModelView;

        #ifdef SHADOW_MAPPING
            uniform mat4 shadowProjection;

            #include "/lib/lighting/shdMapping.glsl"
        #endif

        #include "/lib/lighting/GGX.glsl"
    #endif

    #include "/lib/PBR/dataStructs.glsl"

    #if PBR_MODE <= 1
        #include "/lib/PBR/integratedPBR.glsl"
    #else
        #include "/lib/PBR/labPBR.glsl"
    #endif

    #include "/lib/utility/noiseFunctions.glsl"

    #if defined WATER_NORMAL || defined WATER_NOISE
        uniform float fragmentFrameTime;

        #include "/lib/surface/water.glsl"
    #endif

    #if defined ENVIRONMENT_PBR && !defined FORCE_DISABLE_WEATHER
        uniform float isPrecipitationRain;

        #include "/lib/PBR/enviroPBR.glsl"
    #endif

    #include "/lib/lighting/complexShadingForward.glsl"

    void main(){
	    #ifdef VOXY
            // Non-water translucents must preserve any earlier Voxy packet.
            // The per-target SRC_ALPHA blend rules make alpha=0 a no-op.
            photonWaterSurfaceColorOut = vec4(0.0);
            photonWaterNormalOut = vec4(0.0);
            photonWaterTintOut = vec4(0.0);
            photonWaterMetaOut = vec4(0.0);
        #endif

	    // Declare materials
	    dataPBR material;
        getPBR(material, blockId);

        #ifdef VOXY
            if(blockId == 11102){
                // Match Photon's split pipeline: this pass owns only the raw
                // packet and the very thin texture/edge layer.  RGB extinction,
                // waves, direct highlight, SSR and Fresnel are all resolved once
                // in composite for both native and Voxy water.
                vec4 sampledWater = textureGrad(
                    gtexture,
                    texCoord,
                    dcdx,
                    dcdy
                );
                vec3 flatNormal = fastNormalize(TBN[2]);
                vec3 surfaceAlbedo;
                float surfaceAlpha;
                getPhotonNativeThinWaterSurface(
                    sampledWater,
                    flatNormal,
                    surfaceAlbedo,
                    surfaceAlpha
                );

                dataPBR surfaceMaterial = material;
                surfaceMaterial.albedo = vec4(surfaceAlbedo, 1.0);
                surfaceMaterial.normal = flatNormal;
                surfaceMaterial.metallic = 0.0;
                surfaceMaterial.emissive = 0.0;
                surfaceMaterial.smoothness = 0.0;
                surfaceMaterial.ambient = 1.0;
                surfaceMaterial.porosity = 0.0;
                surfaceMaterial.ss = 0.0;
                surfaceMaterial.parallaxShd = 1.0;

                vec3 premultipliedSurface = max(
                    complexShadingForward(surfaceMaterial) * surfaceAlpha,
                    vec3(0.0)
                );
                float effectiveSurfaceAlpha = max(
                    premultipliedSurface.r,
                    max(premultipliedSurface.g, premultipliedSurface.b)
                ) > 0.000001 ? surfaceAlpha : 0.0;

                // Source alpha zero preserves the opaque HDR destination while
                // this draw still writes native front depth to depthtex0.
                sceneColOut = vec4(0.0);
                normalDataOut = flatNormal;
                albedoDataOut = vertexColor;
                materialDataOut = vec3(0.02, 0.998, 0.75);

                // Alpha=1 is solely an overwrite mask for the earlier Voxy MRT
                // packet.  The negative sign on meta.z identifies native water;
                // abs(meta.z) is its actual thin-surface alpha.
                photonWaterSurfaceColorOut = vec4(premultipliedSurface, 1.0);
                photonWaterNormalOut = vec4(flatNormal, 1.0);
                photonWaterTintOut = vec4(vertexColor, 1.0);
                photonWaterMetaOut = vec4(
                    lmCoord,
                    -effectiveSurfaceAlpha,
                    1.0
                );
                return;
            }
        #endif

        if(blockId == 11102 || blockId == 12100){
            // Fast depth linearization by DrDesten
            // Not great, but plausible for most scenarios
            float blockDepth = near / (1.0 - gl_FragCoord.z) - near / (1.0 - texelFetch(depthtex1, ivec2(gl_FragCoord.xy), 0).x);
            // Get the depth outline for the end portal
            float edgeBrightness = exp2((blockDepth + 0.0625) * 8.0);

            // Water
            if(blockId == 11102){
                float waterNoise = WATER_BRIGHTNESS;

                #if defined WATER_NORMAL
                    vec4 waterData = H2NWater(waterNoiseUv).xzyw;
                    material.normal = fastNormalize(waterData.yxz * TBN[2].x + waterData.xyz * TBN[2].y + waterData.xzy * TBN[2].z);

                    #ifdef WATER_NOISE
                        waterNoise *= squared(0.128 + waterData.w * 0.5);
                    #endif
                #elif defined WATER_NOISE
                    float waterData = getCellNoise(waterNoiseUv);

                    waterNoise *= squared(0.128 + waterData * 0.5);
                #endif

                #ifdef WATER_STYLIZE_ABSORPTION
                    if(isEyeInWater == 0){
                        float depthBrightness = exp2(blockDepth * 0.25);
                        material.albedo.rgb = material.albedo.rgb * (waterNoise * (1.0 - depthBrightness) + depthBrightness);
                        material.albedo.a = fastSqrt(material.albedo.a) * (1.0 - depthBrightness);
                    }
                    else material.albedo.rgb *= waterNoise;
                #else
                    material.albedo.rgb *= waterNoise;
                #endif

                #ifdef WATER_FOAM
                    material.albedo = min(vec4(1), material.albedo + edgeBrightness);
                #endif
            }

            // Nether portal
            else material.albedo.rgb = min(vec3(1), material.albedo.rgb * (0.5 + edgeBrightness * 2.0));
        }

        material.albedo.rgb = toLinear(material.albedo.rgb);

        #if defined ENVIRONMENT_PBR && !defined FORCE_DISABLE_WEATHER
            if(blockId != 11102) enviroPBR(material, TBN[2]);
        #endif

        // Write to HDR scene color
        sceneColOut = vec4(complexShadingForward(material), material.albedo.a);

        // Write buffer datas
        normalDataOut = material.normal;
        albedoDataOut = material.albedo.rgb;
        // Reserve a stable translucent material marker for composite's
        // Photon-style water reflection resolver.  Other translucents retain
        // 0.5 and continue through SDV's generic deferred path.
        materialDataOut = vec3(
            material.metallic,
            material.smoothness,
            blockId == 11102 ? 0.75 : 0.5
        );
    }
#endif
