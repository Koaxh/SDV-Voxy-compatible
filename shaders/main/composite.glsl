/*
================================ /// Super Duper Vanilla v1.3.8 /// ================================

    Developed by Eldeston, presented by FlameRender (C) Studios.

    Copyright (C) 2023 Eldeston | FlameRender (C) Studios License


    By downloading this content you have agreed to the license and its terms of use.

================================ /// Super Duper Vanilla v1.3.8 /// ================================
*/

/// Buffer features: Transparent complex shading and volumetric lighting

/// -------------------------------- /// Vertex Shader /// -------------------------------- ///

#ifdef VERTEX
    flat out vec3 skyCol;

    noperspective out vec2 texCoord;

    #ifdef WORLD_LIGHT
        flat out vec3 sRGBLightCol;
        flat out vec3 lightCol;

        #ifndef FORCE_DISABLE_DAY_CYCLE
            flat out vec3 sRGBSunCol;
            flat out vec3 sunCol;
            flat out vec3 sRGBMoonCol;
            flat out vec3 moonCol;
        #endif
    #endif

    #ifndef FORCE_DISABLE_WEATHER
        uniform float rainStrength;
    #endif

    #ifndef FORCE_DISABLE_DAY_CYCLE
        uniform float dayCycle;
        uniform float twilightPhase;
    #endif

    #ifdef WORLD_VANILLA_FOG_COLOR
        uniform vec3 fogColor;
    #endif

    void main(){
        // Get buffer texture coordinates
        texCoord = gl_MultiTexCoord0.xy;

        skyCol = toLinear(SKY_COLOR_DATA_BLOCK);

        #ifdef WORLD_LIGHT
            #ifdef FORCE_DISABLE_DAY_CYCLE
                sRGBLightCol = LIGHT_COLOR_DATA_BLOCK0;
                lightCol = toLinear(sRGBLightCol);
            #else
                sRGBSunCol = SUN_COL_DATA_BLOCK;
                sunCol = toLinear(sRGBSunCol);
                sRGBMoonCol = MOON_COL_DATA_BLOCK;
                moonCol = toLinear(sRGBMoonCol);

                sRGBLightCol = LIGHT_COLOR_DATA_BLOCK1(sRGBSunCol, sRGBMoonCol);
                lightCol = toLinear(sRGBLightCol);
            #endif
        #endif

        gl_Position = vec4(gl_Vertex.xy * 2.0 - 1.0, 0, 1);
    }
#endif

/// -------------------------------- /// Fragment Shader /// -------------------------------- ///

#ifdef FRAGMENT
    /* RENDERTARGETS: 4 */
    layout(location = 0) out vec3 sceneColOut; // colortex4

    flat in vec3 skyCol;

    #ifdef WORLD_LIGHT
        flat in vec3 sRGBLightCol;
        flat in vec3 lightCol;

        #ifndef FORCE_DISABLE_DAY_CYCLE
            flat in vec3 sRGBSunCol;
            flat in vec3 sunCol;
            flat in vec3 sRGBMoonCol;
            flat in vec3 moonCol;
        #endif
    #endif

    noperspective in vec2 texCoord;

    uniform int isEyeInWater;

    uniform float borderFar;

    uniform float nightVision;
    uniform float effectFactor;
    uniform float lightningFlash;
    uniform float darknessLightFactor;

    uniform float fragmentFrameTime;

    uniform vec3 fogColor;

    uniform vec3 cameraPosition;

    uniform mat4 gbufferProjection;
    uniform mat4 gbufferProjectionInverse;

    uniform mat4 gbufferModelView;
    uniform mat4 gbufferModelViewInverse;

    #ifdef VOXY
        uniform int vxRenderDistance;
        uniform int frameMod;
        uniform float pixelWidth;
        uniform float pixelHeight;

        uniform mat4 vxProj;
        uniform mat4 vxProjInv;
        // Set per fragment from the convention marker emitted by both Voxy
        // draw passes. The integration does not bind a post-stage
        // vxDepthZeroToOne uniform.
        int vxDepthZeroToOne;

        uniform sampler2D vxDepthTexOpaque;
        uniform sampler2D vxDepthTexTrans;

        // Voxy translucents are rendered during the terrain injection, before
        // this pack's normal translucent stage. These attachments keep that
        // early draw isolated until this layer-composition pass.
        uniform sampler2D colortex16;
        uniform sampler2D colortex17;
        uniform sampler2D colortex19;
        uniform sampler2D colortex20;
        uniform sampler2D colortex15;
        uniform sampler2D colortex7;
    #endif

    uniform mat4 shadowModelView;

    // Main HDR buffer
    uniform sampler2D colortex4;
    uniform sampler2D colortex1;
    // For SSAO and material masks
    uniform sampler2D colortex2;
    uniform sampler2D colortex3;

    uniform sampler2D depthtex0;
    uniform sampler2D depthtex1;

    #if ANTI_ALIASING >= 2
        uniform float frameFract;
    #endif

    #ifndef FORCE_DISABLE_WEATHER
        uniform float rainStrength;
    #endif

    #ifndef FORCE_DISABLE_DAY_CYCLE
        uniform float dayCycle;
        uniform float dayCycleAdjust;
    #endif

    #if CLOUD_TYPE != 0 && !defined FORCE_DISABLE_CLOUDS
        uniform sampler2D colortex0;

        #if CLOUD_TYPE == 2
            uniform float volumetricCloudFar;

            #include "/lib/rayTracing/volumetricClouds.glsl"
        #endif
    #endif

    #ifdef DISTANT_HORIZONS
        uniform float near;
        uniform float dhNearPlane;

        uniform mat4 dhProjection;
        uniform mat4 dhProjectionInverse;

        uniform sampler2D dhDepthTex0;
    #endif

    #ifdef WORLD_CUSTOM_SKYLIGHT
        const float eyeBrightFact = WORLD_CUSTOM_SKYLIGHT;
    #else
        uniform float eyeSkylight;

        float eyeBrightFact = eyeSkylight;
    #endif

    #include "/lib/utility/projectionFunctions.glsl"

    #if (defined SSR || defined SSGI) && defined PREVIOUS_FRAME
        uniform vec3 camPosDelta;

        uniform mat4 gbufferPreviousModelView;
        uniform mat4 gbufferPreviousProjection;

        uniform sampler2D colortex5;

        #include "/lib/utility/prevProjectionFunctions.glsl"
    #endif

    #ifdef WORLD_LIGHT
        uniform float shdFade;

        #if defined VOLUMETRIC_LIGHTING && defined SHADOW_MAPPING
            uniform mat4 shadowProjection;

            #include "/lib/lighting/shdMapping.glsl"
        #endif

        #include "/lib/rayTracing/volumetricLight.glsl"
    #endif

    #include "/lib/utility/depthTex.glsl"

    #ifdef VOXY
        #include "/lib/utility/voxyProjectionFunctions.glsl"
    #endif

    #include "/lib/utility/noiseFunctions.glsl"

    #include "/lib/atmospherics/skyRender.glsl"
    #include "/lib/atmospherics/fogRender.glsl"

    // Only this transparent material pass needs the Voxy-domain screen-space
    // tracer. Keeping it opt-in preserves the original deferred/vanilla API.
    #ifdef VOXY
        #define SDV_VOXY_DEFERRED_RAYTRACE
    #endif
    #include "/lib/rayTracing/rayTracer.glsl"

    #include "/lib/lighting/complexShadingDeferred.glsl"

    #ifdef VOXY
        #if defined WATER_NORMAL || defined WATER_NOISE
            #include "/lib/surface/water.glsl"
        #endif
        #if defined WORLD_LIGHT && defined SPECULAR_HIGHLIGHTS
        #include "/lib/lighting/GGX.glsl"
        #endif
        #include "/lib/voxy/photonDistantWater.glsl"
    #endif

    void main(){
        // Screen texel coordinates
        ivec2 screenTexelCoord = ivec2(gl_FragCoord.xy);
        vec3 matRaw0 = texelFetch(colortex3, screenTexelCoord, 0).xyz;

        #if ANTI_ALIASING >= 2
            vec3 dither = fract(getRng3(screenTexelCoord & 255) + frameFract);
        #else
            vec3 dither = getRng3(screenTexelCoord & 255);
        #endif

        // Primary HDR scene color accumulator
        sceneColOut = texelFetch(colortex4, screenTexelCoord, 0).rgb;

        // Shared cross-scope geometric and shading variables
        float depth = texelFetch(depthtex0, screenTexelCoord, 0).x;
        bool realSky = false;
        vec3 screenPos;
        vec3 viewPos;
        vec3 eyePlayerPos;
        vec3 feetPlayerPos;
        vec3 nEyePlayerPos;
        vec3 nFeetPlayerPos;
        float viewDist;
        float viewDotInvSqrt;
        float feetPlayerDist = 0.0;
        float fogFactor;
        float borderFog = 0.0;
        bool isSky = false;

        #ifdef VOXY
            bool voxyLod = false;
            bool voxyTranslucentLayer = false;
            bool voxyWater = false;
            bool nativeWater = false;
            bool resolvedWater = false;
            vec4 voxyLayerColor = vec4(0.0);
            vec4 voxyLayerSurface = vec4(0.0);
            vec4 voxyLayerMaterial = vec4(0.0);
            vec4 voxyWaterLayer = vec4(0.0);
            vec3 voxyLayerAlbedo = vec3(0.0);
            float voxyLayerAlpha = 0.0;
        #endif

        // =========================================================================
        // Scope 1: Position & Depth Reconstruction
        // =========================================================================
        {
            #ifdef VOXY
                voxyLayerColor = texelFetch(colortex16, screenTexelCoord, 0);
                voxyLayerSurface = texelFetch(colortex17, screenTexelCoord, 0);
                voxyLayerMaterial = texelFetch(colortex19, screenTexelCoord, 0);
                voxyWaterLayer = texelFetch(colortex20, screenTexelCoord, 0);
                voxyLayerAlbedo = voxyLayerMaterial.rgb;
                bool voxyLayerZeroToOne = voxyLayerSurface.a >= 2.0;
                float voxyLayerSurfaceKind = voxyLayerSurface.a - (voxyLayerZeroToOne ? 2.0 : 0.0);
                vxDepthZeroToOne = int(getVoxyProjectionZeroToOne(vxProj, borderFar));
                voxyLayerAlpha = clamp(voxyLayerColor.a, 0.0, 1.0);

                nativeWater = depth < 1.0
                    && abs(matRaw0.z - 0.75) < 0.02
                    && voxyWaterLayer.a > 0.5
                    && voxyWaterLayer.z <= 0.0;
                resolvedWater = nativeWater;

                float voxyOpaqueDepth = texelFetch(vxDepthTexOpaque, screenTexelCoord, 0).x;
                float voxyTranslucentDepth = texelFetch(vxDepthTexTrans, screenTexelCoord, 0).x;

                voxyTranslucentLayer = depth == 1.0
                    && voxyLayerSurfaceKind > 0.1
                    && voxyTranslucentDepth < 1.0;
                voxyWater = voxyTranslucentLayer
                    && voxyLayerSurfaceKind > 0.75
                    && voxyWaterLayer.z > 0.0;
                resolvedWater = nativeWater || voxyWater;

                if(voxyTranslucentLayer){
                    depth = voxyTranslucentDepth;
                    voxyLod = true;
                } else if(depth == 1.0){
                    if(voxyOpaqueDepth < 1.0){
                        depth = voxyOpaqueDepth;
                        voxyLod = true;
                    }
                }
            #elif defined DISTANT_HORIZONS
                realSky = depth == 1.0;
                if(realSky) depth = texelFetch(dhDepthTex0, screenTexelCoord, 0).x;
            #endif

            screenPos = vec3(texCoord, depth);
            isSky = (depth == 1.0);

            #ifdef DISTANT_HORIZONS
                viewPos = getViewPos(realSky ? dhProjectionInverse : gbufferProjectionInverse, screenPos);
            #elif defined VOXY
                if(voxyLod){
                    viewPos = photonVoxyScreenToView(screenPos.xy, screenPos.z, vxDepthZeroToOne != 0, true);
                } else if(nativeWater){
                    viewPos = photonVanillaScreenToView(screenPos.xy, screenPos.z, true);
                } else {
                    viewPos = getViewPos(gbufferProjectionInverse, screenPos);
                }
            #else
                viewPos = getViewPos(gbufferProjectionInverse, screenPos);
            #endif

            eyePlayerPos = mat3(gbufferModelViewInverse) * viewPos;
            feetPlayerPos = eyePlayerPos + gbufferModelViewInverse[3].xyz;

            float viewDot = lengthSquared(viewPos);
            viewDotInvSqrt = inversesqrt(viewDot);
            viewDist = viewDot * viewDotInvSqrt;
            nEyePlayerPos = eyePlayerPos * viewDotInvSqrt;

            fogFactor = getFogFactor(viewDist, nEyePlayerPos.y, feetPlayerPos.y + cameraPosition.y);
            #ifdef BORDER_FOG
                borderFog = getBorderFog(viewDist, nEyePlayerPos.y);
            #endif

            #if defined WORLD_LIGHT || (!defined FORCE_DISABLE_CLOUDS && CLOUD_TYPE == 2)
                float feetPlayerDot = lengthSquared(feetPlayerPos);
                float feetPlayerDotInvSqrt = inversesqrt(feetPlayerDot);
                feetPlayerDist = feetPlayerDot * feetPlayerDotInvSqrt;
                nFeetPlayerPos = feetPlayerPos * feetPlayerDotInvSqrt;
            #endif

            #ifdef VOXY
                if(voxyTranslucentLayer && !voxyWater){
                    sceneColOut = sceneColOut * (1.0 - voxyLayerAlpha) + voxyLayerColor.rgb;
                }
            #endif
        }

        // =========================================================================
        // Scope 2: Water Refraction & Translucent / Deferred Forward Shading
        // =========================================================================
        {
            #ifdef VOXY
                if(resolvedWater){
                    bool waterZeroToOne = vxDepthZeroToOne != 0;
                    float reconstructedWaterLayerDistance = photonWaterLayerDistance(
                        texCoord,
                        viewPos,
                        voxyWater,
                        waterZeroToOne
                    );
                    float waterLayerDistance = reconstructedWaterLayerDistance;
                    if(voxyWater
                    && voxyLayerMaterial.a >= 0.0
                    && photonWaterFinitePosition(vec3(voxyLayerMaterial.a))){
                        waterLayerDistance = clamp(
                            voxyLayerMaterial.a,
                            0.0,
                            PHOTON_VOXY_MAX_WATER_DISTANCE
                        );
                    }
                    waterLayerDistance = clamp(
                        waterLayerDistance,
                        0.0,
                        PHOTON_VOXY_MAX_WATER_DISTANCE
                    );
                    vec3 waterDirectionWorld = normalize(eyePlayerPos);
                    vec3 waterWorldPosition = feetPlayerPos + cameraPosition;
                    vec3 waterTransmittance;
                    vec3 waterNormal;
                    vec4 waterBody = drawPhotonWater(
                        viewPos,
                        waterWorldPosition,
                        waterDirectionWorld,
                        voxyLayerSurface.rgb,
                        voxyLayerMaterial.rgb,
                        voxyWaterLayer.xy,
                        waterLayerDistance,
                        dither.z,
                        voxyWater,
                        waterZeroToOne,
                        waterTransmittance,
                        waterNormal
                    );

                    vec3 waveDelta = waterNormal - voxyLayerSurface.rgb;
                    vec3 viewWaveDelta = mat3(gbufferModelView) * waveDelta;
                    float refractScale = (isEyeInWater == 1) ? 0.035 : 0.015;
                    vec2 refractedCoord = clamp(texCoord + viewWaveDelta.xy * refractScale, vec2(0.001), vec2(0.999));

                    sceneColOut = textureLod(colortex4, refractedCoord, 0).rgb;

                    float thinSurfaceAlpha = nativeWater
                        ? clamp(abs(voxyWaterLayer.z), 0.0, 1.0)
                        : voxyLayerAlpha;

                    sceneColOut = sceneColOut * waterTransmittance + waterBody.rgb;
                    sceneColOut = sceneColOut * (1.0 - thinSurfaceAlpha) + voxyLayerColor.rgb;
                }
            #endif

            bool forwardMaterial = matRaw0.z > 0.0 && matRaw0.z < 1.0;
            #ifdef VOXY
                forwardMaterial = forwardMaterial || voxyTranslucentLayer;
            #endif
            if(forwardMaterial){
                vec3 albedo;
                vec3 normal;
                float materialMetallic;
                float materialSmoothness;

                #ifdef VOXY
                    if(voxyTranslucentLayer){
                        albedo = voxyLayerAlbedo;
                        normal = voxyLayerSurface.rgb;
                        materialMetallic = 0.02;
                        materialSmoothness = voxyWater ? 0.96 : 0.5;
                    } else {
                        albedo = texelFetch(colortex2, screenTexelCoord, 0).rgb;
                        normal = texelFetch(colortex1, screenTexelCoord, 0).xyz;
                        materialMetallic = matRaw0.x;
                        materialSmoothness = matRaw0.y;
                    }
                #else
                    albedo = texelFetch(colortex2, screenTexelCoord, 0).rgb;
                    normal = texelFetch(colortex1, screenTexelCoord, 0).xyz;
                    materialMetallic = matRaw0.x;
                    materialSmoothness = matRaw0.y;
                #endif

                vec3 viewNormal = mat3(gbufferModelView) * normal;
                #ifdef VOXY
                    if(!resolvedWater){
                        sceneColOut = complexShadingDeferred(sceneColOut, screenPos, viewPos, viewNormal, albedo, dither, viewDotInvSqrt, materialMetallic, materialSmoothness, realSky, voxyLod);
                    }
                #else
                    sceneColOut = complexShadingDeferred(sceneColOut, screenPos, viewPos, viewNormal, albedo, dither, viewDotInvSqrt, materialMetallic, materialSmoothness, realSky);
                #endif

                vec3 fogSkyCol = getSkyFogRender(nEyePlayerPos);
                #ifdef BORDER_FOG
                    fogFactor = (fogFactor - 1.0) * borderFog + 1.0;
                #endif

                sceneColOut = ((fogSkyCol - sceneColOut) * fogFactor + sceneColOut) * getFogEffectFactor(viewDist);
            }
        }

        // =========================================================================
        // Scope 3: Underwater Ambient Fog & Optical Absorption
        // =========================================================================
        {
            sceneColOut *= 1.0 - darknessLightFactor;

            if (isEyeInWater == 1) {
                float waterHaze = 1.0 - exp(-feetPlayerDist * 0.028);
                vec3 waterFogLinear = toLinear(clamp(fogColor, vec3(0.0), vec3(1.0))) * vec3(0.8, 1.25, 0.95);
                vec3 waterAmbient = (skyCol * vec3(0.7, 1.15, 0.9) + toLinear(AMBIENT_LIGHTING + nightVision * 0.5)) * eyeBrightFact + lightCol * vec3(0.15, 0.32, 0.25) * eyeBrightFact;
                vec3 waterBodyColor = waterFogLinear * waterAmbient * 2.5;
                sceneColOut = mix(sceneColOut, waterBodyColor, waterHaze);
            }
        }

        // =========================================================================
        // Scope 4: Volumetric Lighting & Dual-Layer Volumetric Clouds
        // =========================================================================
        {
            #ifdef WORLD_LIGHT
                if(VOLUMETRIC_LIGHTING_STRENGTH != 0 && isEyeInWater != 2 && max(lightCol.r, max(lightCol.g, lightCol.b)) > 0.0001){
                    sceneColOut += getVolumetricLight(nFeetPlayerPos, feetPlayerDist, fogFactor, borderFog, dither.x, isSky);
                }
            #endif

            #if !defined FORCE_DISABLE_CLOUDS && CLOUD_TYPE == 2
                bool isCloudSky = isSky;
                float cloudFeetPlayerDist = feetPlayerDist;

                #ifdef VOXY
                    float solidDepthVanilla = texelFetch(depthtex1, screenTexelCoord, 0).x;
                    float solidDepthVoxy = texelFetch(vxDepthTexOpaque, screenTexelCoord, 0).x;
                    bool solidSky = solidDepthVanilla >= 1.0 && solidDepthVoxy >= 1.0;
                    if(resolvedWater || isEyeInWater == 1){
                        if(solidSky){
                            isCloudSky = true;
                        } else if(solidDepthVanilla < 1.0){
                            vec3 solidViewPos = getViewPos(gbufferProjectionInverse, vec3(texCoord, solidDepthVanilla));
                            vec3 solidFeetPos = mat3(gbufferModelViewInverse) * solidViewPos + gbufferModelViewInverse[3].xyz;
                            cloudFeetPlayerDist = length(solidFeetPos);
                        }
                    }
                #else
                    float solidDepthVanilla = texelFetch(depthtex1, screenTexelCoord, 0).x;
                    if(isEyeInWater == 1 || depth < 1.0){
                        if(solidDepthVanilla >= 1.0){
                            isCloudSky = true;
                        } else {
                            vec3 solidViewPos = getViewPos(gbufferProjectionInverse, vec3(texCoord, solidDepthVanilla));
                            vec3 solidFeetPos = mat3(gbufferModelViewInverse) * solidViewPos + gbufferModelViewInverse[3].xyz;
                            cloudFeetPlayerDist = length(solidFeetPos);
                        }
                    }
                #endif

                #ifdef VOXY
                    float cloudRenderDistance = getSceneRenderDistance();
                    #ifndef FORCE_DISABLE_WEATHER
                        cloudRenderDistance *= 1.0 - rainStrength * 0.5;
                    #endif
                #else
                    float cloudRenderDistance = volumetricCloudFar;
                #endif

                vec3 cloudStartPos0 = vec3(cameraPosition.x + fragmentFrameTime, cameraPosition.y - volumetricCloudHeight, cameraPosition.z);
                vec3 cloudRayDir = nFeetPlayerPos;
                if(resolvedWater || isEyeInWater == 1){
                    #ifdef WATER_NORMAL
                        vec2 waveNorm = H2NWater((feetPlayerPos.xz + cameraPosition.xz) * waterTileSizeInv).xy;
                        cloudRayDir = normalize(nFeetPlayerPos + vec3(waveNorm.x, 0.0, waveNorm.y) * 0.2);
                    #endif
                }

                vec2 cloudData = volumetricClouds(cloudRayDir, cloudStartPos0, cloudFeetPlayerDist, cloudRenderDistance, dither.x, isCloudSky);

                #ifdef DOUBLE_LAYERED_CLOUDS
                    vec3 cloudStartPos1 = vec3(cloudStartPos0.x, cloudStartPos0.y - SECOND_CLOUD_HEIGHT, cloudStartPos0.z);
                    cloudData = max(volumetricClouds(cloudRayDir, cloudStartPos1, cloudFeetPlayerDist, cloudRenderDistance, dither.x, isCloudSky).yx, cloudData);
                #endif

                #ifdef DYNAMIC_CLOUDS
                    float fadeTime = saturate(sin(fragmentFrameTime * FADE_SPEED) * 0.8 + 0.5);
                    float cloudFinal = mix(mix(cloudData.x, cloudData.y, fadeTime), max(cloudData.x, cloudData.y), rainStrength) * 0.125;
                #else
                    float cloudFinal = mix(cloudData.x, max(cloudData.x, cloudData.y), rainStrength) * 0.125;
                #endif

                vec3 rawCloudCol;
                #ifdef FORCE_DISABLE_DAY_CYCLE
                    rawCloudCol = (toLinear(nightVision * 0.5 + AMBIENT_LIGHTING) + lightningFlash) + lightCol + skyCol;
                #else
                    rawCloudCol = (toLinear(nightVision * 0.5 + AMBIENT_LIGHTING) + lightningFlash) + mix(moonCol, sunCol, dayCycleAdjust) + skyCol;
                #endif

                if (isEyeInWater == 1) {
                    float snellFade = saturate(nFeetPlayerPos.y * 1.8 - 0.2);
                    float waterDepth = clamp(feetPlayerDist, 1.0, 45.0);
                    const vec3 waterExt = vec3(0.36, 0.085, 0.042);
                    vec3 waterTrans = exp(-waterExt * waterDepth);
                    vec3 waterFogCol = toLinear(clamp(fogColor, vec3(0.0), vec3(1.0))) * vec3(0.8, 1.25, 0.95);
                    vec3 waterTint = normalize(waterFogCol + vec3(0.02, 0.32, 0.26));
                    float cloudLum = max(rawCloudCol.r, max(rawCloudCol.g, rawCloudCol.b));
                    vec3 submergedCloudCol = mix(rawCloudCol * waterTrans, waterTint * cloudLum, clamp(waterDepth * 0.08, 0.3, 0.95));
                    
                    float depthCloudFade = exp(-waterDepth * 0.08);
                    sceneColOut = mix(sceneColOut, submergedCloudCol, cloudFinal * snellFade * depthCloudFade);
                } else {
                    sceneColOut = mix(sceneColOut, rawCloudCol, cloudFinal);
                }
            #endif
        }

        // Clamp scene color to prevent NaNs during post processing
        sceneColOut = max(sceneColOut, vec3(0.0));
    }
#endif
