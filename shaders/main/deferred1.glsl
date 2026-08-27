/*
================================ /// Super Duper Vanilla v1.3.8 /// ================================

    Developed by Eldeston, presented by FlameRender (C) Studios.

    Copyright (C) 2023 Eldeston | FlameRender (C) Studios License


    By downloading this content you have agreed to the license and its terms of use.

================================ /// Super Duper Vanilla v1.3.8 /// ================================
*/

/// Buffer features: Solid complex shading

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
    #ifdef VOXY
        /* RENDERTARGETS: 4,18,15,7 */
        layout(location = 0) out vec3 sceneColOut; // colortex4
        layout(location = 1) out float voxyShadowOut; // colortex18
        layout(location = 2) out float combinedDepthOut; // colortex15
        layout(location = 3) out vec3 fogScatteringOut; // colortex7
    #else
        /* RENDERTARGETS: 4 */
        layout(location = 0) out vec3 sceneColOut; // colortex4
    #endif

    // Sky silhoutte fix
    const vec4 gcolorClearColor = vec4(0, 0, 0, 1);

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

        uniform mat4 vxProj;
        uniform mat4 vxProjInv;
        // Voxy 0.2.18 does not expose this value to post programs. It is
        // decoded per pixel from the marker written by the Voxy draw passes.
        int vxDepthZeroToOne;

        // BSL/Photon keep the combined translucent depth out of opaque
        // deferred work and consume it later during layer composition.
        uniform sampler2D vxDepthTexOpaque;
        uniform sampler2D vxDepthTexTrans;
        uniform sampler2D colortex17;
        uniform int frameCounter;
    #endif

    uniform mat4 shadowModelView;

    // Main HDR buffer
    uniform sampler2D colortex4;
    uniform sampler2D colortex1;
    // For SSAO and material masks
    uniform sampler2D colortex2;
    uniform sampler2D colortex3;
    
    uniform sampler2D depthtex0;
    #ifdef VOXY
        uniform sampler2D depthtex1;
    #endif

    #ifdef WORLD_LIGHT
        uniform float shdFade;
    #endif

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
    #endif

    #ifdef DISTANT_HORIZONS
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

    #ifdef SSAO
        float getSSAOBoxBlur(in ivec2 screenTexelCoord){
            ivec2 topRightCorner = screenTexelCoord + 1;
            ivec2 bottomLeftCorner = screenTexelCoord - 1;

            float sample0 = texelFetch(colortex2, topRightCorner, 0).a;
            float sample1 = texelFetch(colortex2, bottomLeftCorner, 0).a;
            float sample2 = texelFetch(colortex2, ivec2(topRightCorner.x, bottomLeftCorner.y), 0).a;
            float sample3 = texelFetch(colortex2, ivec2(bottomLeftCorner.x, topRightCorner.y), 0).a;

            return sample0 + sample1 + sample2 + sample3;
        }
    #endif

    #if ANTI_ALIASING == 2
        uniform int frameMod;

        uniform float pixelWidth;
        uniform float pixelHeight;

        #include "/lib/utility/taaJitter.glsl"
    #endif

    #include "/lib/utility/depthTex.glsl"
    #ifdef VOXY
        #include "/lib/utility/voxyProjectionFunctions.glsl"
    #endif

    #if OUTLINES != 0
        #if OUTLINES == 1
            uniform float near;
        #endif

        #include "/lib/post/outline.glsl"
    #endif

    #include "/lib/utility/noiseFunctions.glsl"

    #include "/lib/atmospherics/skyRender.glsl"
    #include "/lib/atmospherics/fogRender.glsl"
    
    #include "/lib/rayTracing/rayTracer.glsl"

    #include "/lib/lighting/complexShadingDeferred.glsl"
    #ifdef VOXY
        #include "/lib/lighting/voxyScreenSpaceShadow.glsl"

        // Photon's native-water SSRT does not rebuild a mixed scene for every
        // ray step. A full-screen pass first converts vanilla solid depth and
        // Voxy combined depth into one stable projection (colortex15).
        float photonCombinedNear() {
            return gbufferProjection[3][2]
                / (gbufferProjection[2][2] - 1.0);
        }

        mat4 photonCombinedProjection() {
            float combinedNear = photonCombinedNear();
            float combinedFar = max(
                float(16 * vxRenderDistance),
                combinedNear + 1.0
            );
            return mat4(
                vec4(gbufferProjection[0][0], 0.0, 0.0, 0.0),
                vec4(0.0, gbufferProjection[1][1], 0.0, 0.0),
                vec4(
                    gbufferProjection[2][0],
                    gbufferProjection[2][1],
                    (combinedFar + combinedNear)
                        / (combinedNear - combinedFar),
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

        float photonDepthToViewDistance(
            mat4 projectionInverse,
            float screenDepth,
            bool zeroToOneDepth
        ) {
            float ndcDepth = zeroToOneDepth
                ? screenDepth
                : screenDepth * 2.0 - 1.0;
            vec2 zw = ndcDepth * projectionInverse[2].zw
                + projectionInverse[3].zw;
            return -zw.x / zw.y;
        }

        float photonViewDistanceToCombinedDepth(float viewDistance) {
            mat4 projection = photonCombinedProjection();
            vec2 zw = -viewDistance * projection[2].zw
                + projection[3].zw;
            return (zw.x / zw.y) * 0.5 + 0.5;
        }

        float getPhotonCombinedDepth(ivec2 texel) {
            float vanillaDepth = texelFetch(depthtex1, texel, 0).x;
            float voxyDepth = texelFetch(vxDepthTexTrans, texel, 0).x;
            bool hand = vanillaDepth <= 0.56;
            bool useVoxy = vanillaDepth >= 1.0 && voxyDepth < 1.0;

            if (hand) return 0.0;
            if (vanillaDepth >= 1.0 && !useVoxy) return 1.0;

            float viewDistance = useVoxy
                ? photonDepthToViewDistance(
                    vxProjInv,
                    voxyDepth,
                    vxDepthZeroToOne != 0
                )
                : photonDepthToViewDistance(
                    gbufferProjectionInverse,
                    vanillaDepth,
                    false
                );
            return photonViewDistanceToCombinedDepth(viewDistance);
        }
    #endif

    void main(){
        // Screen texel coordinates
        ivec2 screenTexelCoord = ivec2(gl_FragCoord.xy);

        #ifdef VOXY
            vec4 voxyConvention = texelFetch(
                colortex17,
                screenTexelCoord,
                0
            );
            // Derive this from vxProj. The shared attachment marker can be
            // overwritten by another owner before deferred runs, which made
            // LoD view distance—and therefore underwater fog—far too short.
            vxDepthZeroToOne = int(getVoxyProjectionZeroToOne(
                vxProj,
                borderFar
            ));
            combinedDepthOut = getPhotonCombinedDepth(screenTexelCoord);
            fogScatteringOut = vec3(0.0);

            // Sky/unowned pixels are valid unshadowed history. Zero remains
            // reserved for an attachment that has not been written yet.
            voxyShadowOut = encodeVoxyShadowHistory(1.0);
            bool voxyLod = false;
        #endif

        bool realSky = false;

        float depth = texelFetch(depthtex0, screenTexelCoord, 0).x;

        // Distant Horizons apparently uses a different depth texture
        #ifdef DISTANT_HORIZONS
            realSky = depth == 1;
            if(realSky) depth = texelFetch(dhDepthTex0, screenTexelCoord, 0).x;
        #elif defined VOXY
            // Voxy LOD is deliberately absent from vanilla depthtex0. Its
            // combined opaque/translucent depth identifies LOD pixels here.
            if(depth == 1.0){
                float voxyDepth = texelFetch(vxDepthTexOpaque, screenTexelCoord, 0).x;
                if(voxyDepth < 1.0){
                    depth = voxyDepth;
                    voxyLod = true;
                }
            }
        #endif

        // Get screen pos
        vec3 screenPos = vec3(texCoord, depth);

        // Get sky mask
        bool skyMask = screenPos.z == 1;

        // Jitter the sky only
        #if ANTI_ALIASING == 2
            if(skyMask) screenPos.xy += jitterPos(-0.5);
        #endif

        // Distant Horizons apparently uses a different projection matrix
        #ifdef DISTANT_HORIZONS
            vec3 viewPos = getViewPos(realSky ? dhProjectionInverse : gbufferProjectionInverse, screenPos);
        #elif defined VOXY
            vec3 viewPos;
            if(voxyLod){
                viewPos = getVoxyViewPos(vxProjInv, screenPos);
            } else {
                viewPos = getViewPos(gbufferProjectionInverse, screenPos);
            }
        #else
            vec3 viewPos = getViewPos(gbufferProjectionInverse, screenPos);
        #endif

        // Get eye player pos
        // vxProj owns only the Voxy depth projection. Photon converts every
        // reconstructed position through the current vanilla model-view.
        vec3 eyePlayerPos = mat3(gbufferModelViewInverse) * viewPos;

        // Get view distance
        float viewDot = lengthSquared(viewPos);
	    float viewDotInvSqrt = inversesqrt(viewDot);

        // Get normalized eyePlayerPos
        vec3 nEyePlayerPos = eyePlayerPos * viewDotInvSqrt;

        // Get scene color
        sceneColOut = texelFetch(colortex4, screenTexelCoord, 0).rgb;

        // Get sky pos by shadow model view
        vec3 skyPos = mat3(shadowModelView) * nEyePlayerPos;

        #if defined WORLD_LIGHT && !defined FORCE_DISABLE_DAY_CYCLE
            // Flip if the sun has gone below the horizon
            if(dayCycle < 1) skyPos.xz = -skyPos.xz;
        #endif

        // Get basic sky simple color
        vec3 currSkyCol = getSkyBasic(nEyePlayerPos.y, skyPos.z);        // If sky, do full sky render and return immediately
        if(skyMask){
            // Calculate and output sky render
            sceneColOut = getFullSkyRender(nEyePlayerPos, skyPos, currSkyCol + sceneColOut) * exp2(-borderFar * effectFactor);
            // Exit function immediately
            return;
        }

        #if ANTI_ALIASING >= 2
            vec3 dither = fract(getRng3(screenTexelCoord & 255) + frameFract);
        #else
            vec3 dither = getRng3(screenTexelCoord & 255);
        #endif

        // Declare and get materials
        vec2 matRaw0 = texelFetch(colortex3, screenTexelCoord, 0).xy;
        vec3 albedo = texelFetch(colortex2, screenTexelCoord, 0).rgb;
        vec3 normal = texelFetch(colortex1, screenTexelCoord, 0).xyz;

        #if defined VOXY && !defined DISTANT_HORIZONS && defined WORLD_LIGHT && defined SHADOW_MAPPING
            vec3 voxyLightDirWorld = normalize(vec3(
                shadowModelView[0].z,
                shadowModelView[1].z,
                shadowModelView[2].z
            ));
            vec3 voxyLightDirView = mat3(gbufferModelView)
                * voxyLightDirWorld;

            // Backface early-out: backfacing fragments (N.L <= 0) receive zero direct diffuse,
            // so skip the 10-step SSRT depth raymarching completely.
            float nDotL = dot(normal, voxyLightDirWorld);
            if (nDotL > 0.0) {
                vec3 voxyTraceViewPos = viewPos;
                float lodShadow = getVoxySsrtShadow(
                    voxyTraceViewPos,
                    voxyLightDirView,
                    dither
                );
                voxyShadowOut = encodeVoxyShadowHistory(lodShadow);
            } else {
                voxyShadowOut = encodeVoxyShadowHistory(0.0);
            }
        #endif

        // Apply deffered shading
        sceneColOut = complexShadingDeferred(sceneColOut, screenPos, viewPos, mat3(gbufferModelView) * normal, albedo, dither, viewDotInvSqrt, matRaw0.x, matRaw0.y, realSky);

        #if OUTLINES != 0
            // Outline calculation
            #if defined VOXY && !defined DISTANT_HORIZONS
                sceneColOut *= 1.0 + getOutline(screenTexelCoord, screenPos.z, voxyLod) * OUTLINE_BRIGHTNESS;
            #else
                sceneColOut *= 1.0 + getOutline(screenTexelCoord, screenPos.z) * OUTLINE_BRIGHTNESS;
            #endif
        #endif

        #ifdef SSAO
            // Apply ambient occlusion with simple blur
            sceneColOut *= getSSAOBoxBlur(screenTexelCoord);
        #endif

        float viewDist = viewDot * viewDotInvSqrt;

        // Get basic sky fog color
        vec3 fogSkyCol = getSkyFogRender(nEyePlayerPos, skyPos, currSkyCol);
        // Get fog factor
        float fogWorldPosY = eyePlayerPos.y + gbufferModelViewInverse[3].y + cameraPosition.y;
        float fogFactor = getFogFactor(viewDist, nEyePlayerPos.y, fogWorldPosY);

        // Border fog
        #ifdef BORDER_FOG
            fogFactor = (fogFactor - 1.0) * getBorderFog(viewDist) + 1.0;
        #endif

        // Apply fog and darkness fog
        float fogEffect = getFogEffectFactor(viewDist);
        #ifdef VOXY
            // Exact additive component of SDV's own fog equation. Photon
            // subtracts this buffer from reflected history before applying fog
            // over the water-to-hit segment.
            fogScatteringOut = fogSkyCol * fogFactor * fogEffect;
        #endif
        sceneColOut = ((fogSkyCol - sceneColOut) * fogFactor
            + sceneColOut) * fogEffect;
        // Clamp scene color to prevent NaNs during post processing
        sceneColOut = max(sceneColOut, vec3(0));
    }
#endif
