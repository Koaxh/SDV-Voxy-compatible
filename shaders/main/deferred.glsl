/*
================================ /// Super Duper Vanilla v1.3.8 /// ================================

    Developed by Eldeston, presented by FlameRender (C) Studios.

    Copyright (C) 2023 Eldeston | FlameRender (C) Studios License


    By downloading this content you have agreed to the license and its terms of use.

================================ /// Super Duper Vanilla v1.3.8 /// ================================
*/

/// Buffer features: Solid screen space ambient occlusion

/// -------------------------------- /// Vertex Shader /// -------------------------------- ///

#ifdef VERTEX
    #ifdef SSAO
        noperspective out vec2 texCoord;
    #endif

    void main(){
        #ifdef SSAO
            // Get buffer texture coordinates
            texCoord = gl_MultiTexCoord0.xy;
        #endif

        gl_Position = vec4(gl_Vertex.xy * 2.0 - 1.0, 0, 1);
    }
#endif

/// -------------------------------- /// Fragment Shader /// -------------------------------- ///

#ifdef FRAGMENT
    /* RENDERTARGETS: 2 */
    #ifdef SSAO
        layout(location = 0) out vec4 albedoDataOut; // colortex2
    #else
        layout(location = 0) out vec3 albedoDataOut; // colortex2
    #endif

    // SSAO without normals fix for beacon
    const vec4 colortex1ClearColor = vec4(0, 0, 0, 1);

    #ifdef SSAO
        noperspective in vec2 texCoord;
    #endif

    uniform sampler2D colortex2;

    #ifdef SSAO
        uniform float near;

        uniform mat4 gbufferModelView;

        uniform mat4 gbufferProjection;
        uniform mat4 gbufferProjectionInverse;

        uniform sampler2D colortex1;

        uniform sampler2D depthtex0;

        #ifdef VOXY
            uniform mat4 vxProj;
            uniform mat4 vxProjInv;
            int vxDepthZeroToOne;

            // This program runs in the opaque deferred stage. Sampling the
            // combined depth here would make LOD water participate as opaque.
            uniform sampler2D vxDepthTexOpaque;
            uniform sampler2D colortex17;
        #endif

        #if ANTI_ALIASING >= 2
            uniform float frameFract;
        #endif

        #include "/lib/utility/projectionFunctions.glsl"
        #ifdef VOXY
            #include "/lib/utility/voxyProjectionFunctions.glsl"
        #endif
        #include "/lib/utility/noiseFunctions.glsl"

        #include "/lib/lighting/SSAO.glsl"
    #endif

    void main(){
        // Screen texel coordinates
        ivec2 screenTexelCoord = ivec2(gl_FragCoord.xy);

        #ifdef SSAO
            float depth = texelFetch(depthtex0, screenTexelCoord, 0).x;
            vec3 albedo = texelFetch(colortex2, screenTexelCoord, 0).rgb;
            albedoDataOut = vec4(albedo, 0.25);

            // Sky (1.0), player hand (<= 0.56) and distant Voxy LODs (which maintain neutral 0.25 AO) return immediately
            // Completely skips colortex1 (normal) fetch and 4-tap SSAO raymarch
            if(depth == 1.0 || depth <= 0.56) return;

            // Check if normal has a valid non-zero direction
            vec3 normal = texelFetch(colortex1, screenTexelCoord, 0).xyz;
            if(dot(normal, normal) < 0.0001) return;

            // Do SSAO for near vanilla geometry
            albedoDataOut.w = getSSAO(vec3(texCoord, depth), mat3(gbufferModelView) * normal);
        #else
            albedoDataOut = texelFetch(colortex2, screenTexelCoord, 0).rgb;
        #endif
    }
#endif
