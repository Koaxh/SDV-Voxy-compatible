/*
================================ /// Super Duper Vanilla v1.3.8 /// ================================

    Developed by Eldeston, presented by FlameRender (C) Studios.

    Copyright (C) 2023 Eldeston | FlameRender (C) Studios License


    By downloading this content you have agreed to the license and its terms of use.

================================ /// Super Duper Vanilla v1.3.8 /// ================================
*/

/// Buffer features: Buffer settings, retro filter, chromatic aberration, and sharpen filter

/// -------------------------------- /// Vertex Shader /// -------------------------------- ///

#ifdef VERTEX
    noperspective out vec2 texCoord;

    void main(){
        // Get buffer texture coordinates
        texCoord = gl_MultiTexCoord0.xy;

        gl_Position = vec4(gl_Vertex.xy * 2.0 - 1.0, 0, 1);
    }
#endif

/// -------------------------------- /// Fragment Shader /// -------------------------------- ///

#ifdef FRAGMENT
    // Final scene color out
    layout(location = 0) out vec3 finalColOut;

    /*
    Buffer settings, the compiler will attempt to read the commented lines:

    const int colortex0Format = R11F_G11F_B10F;
    const int colortex1Format = RGB16_SNORM;
    const int colortex2Format = RGBA8;
    const int colortex3Format = RGB8;
    const int colortex4Format = R11F_G11F_B10F;
    const int colortex5Format = RGBA16F;
    const int colortex7Format = R11F_G11F_B10F;
    const int colortex15Format = R32F;
    const int colortex16Format = RGBA16F;
    const int colortex17Format = RGBA16F;
    const int colortex18Format = R8;
    const int colortex19Format = RGBA16F;
    const int colortex20Format = RGBA16F;
    */

    // Voxy is injected before Minecraft's translucent terrain pass. Keep its
    // translucent colour and material data out of SDV's opaque G-buffer, then
    // consume them once in composite alongside regular water.
    const bool colortex16Clear = true;
    const bool colortex17Clear = true;
    const bool colortex19Clear = true;
    const bool colortex20Clear = true;
    const vec4 colortex16ClearColor = vec4(0.0, 0.0, 0.0, 0.0);
    const vec4 colortex17ClearColor = vec4(0.0, 0.0, 0.0, 0.0);
    const vec4 colortex19ClearColor = vec4(0.0, 0.0, 0.0, 0.0);
    const vec4 colortex20ClearColor = vec4(0.0, 0.0, 0.0, 0.0);

    // Photon-compatible combined solid depth and the additive part of SDV fog.
    // deferred1 writes both over the full screen before water composition.
    const bool colortex15Clear = false;
    const bool colortex7Clear = true;
    // Iris parses shaderpack vec4 directives component by component; use the
    // explicit four-argument form instead of GLSL's scalar-splat constructor.
    const vec4 colortex7ClearColor = vec4(0.0, 0.0, 0.0, 0.0);

    // Voxy opaque reads the value written by deferred1 in the previous frame.
    const bool colortex18Clear = false;

    #if ((defined SSR || defined SSGI) && defined PREVIOUS_FRAME) || ANTI_ALIASING >= 2 || defined AUTO_EXPOSURE
        // Disable buffer clear if TAA, previous frame reflections, or auto exposure is on
        const bool colortex5Clear = false;
    #endif

    noperspective in vec2 texCoord;

    uniform sampler2D colortex3;

    #if (ANTI_ALIASING != 0 && defined SHARPEN_FILTER) || defined CHROMATIC_ABERRATION || defined RETRO_FILTER
        uniform float viewWidth;
        uniform float viewHeight;
    #endif

    #if ANTI_ALIASING != 0 && defined SHARPEN_FILTER
        // https://www.shadertoy.com/view/lslGRr
        vec3 sharpenFilter(in vec3 color, in vec2 uv, in vec2 pixelSize){
            vec2 topRightCorner = uv + pixelSize;
            vec2 bottomLeftCorner = uv - pixelSize;

            vec3 blur = textureLod(colortex3, bottomLeftCorner, 0).rgb + textureLod(colortex3, topRightCorner, 0).rgb +
                textureLod(colortex3, vec2(bottomLeftCorner.x, topRightCorner.y), 0).rgb + textureLod(colortex3, vec2(topRightCorner.x, bottomLeftCorner.y), 0).rgb;
            
            return color * 2.0 - blur * 0.25;
        }
    #endif

    void main(){
        #if defined CHROMATIC_ABERRATION || (ANTI_ALIASING != 0 && defined SHARPEN_FILTER)
            vec2 pixelSize = 1.0 / vec2(viewWidth, viewHeight);
        #endif

        #ifdef RETRO_FILTER
            const float texCoordScale = 0.5 / MC_RENDER_QUALITY;
            vec2 retroResolution = vec2(viewWidth, viewHeight) * texCoordScale;
            vec2 retroCoord = floor(texCoord * retroResolution) / retroResolution;

            #define texCoord retroCoord
        #endif

        #ifdef CHROMATIC_ABERRATION
            vec2 chromaStrength = ((texCoord - 0.5) * ABERRATION_PIXEL_SIZE) * pixelSize;

            finalColOut = vec3(
                textureLod(colortex3, texCoord - chromaStrength, 0).r,
                textureLod(colortex3, texCoord, 0).g,
                textureLod(colortex3, texCoord + chromaStrength, 0).b
            );
        #else
            finalColOut = textureLod(colortex3, texCoord, 0).rgb;
        #endif

        #if ANTI_ALIASING != 0 && defined SHARPEN_FILTER
            finalColOut = sharpenFilter(finalColOut, texCoord, pixelSize);
        #endif
    }
#endif
