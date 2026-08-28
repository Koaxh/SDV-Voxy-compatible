// https://sugulee.wordpress.com/2021/06/21/temporal-anti-aliasingtaa-tutorial/
#ifdef VOXY
vec2 getVoxyPrevScreenCoord(in vec2 currScreenPos, in float screenDepth){
    vec3 currViewPos = getVoxyViewPos(
        vxProjInv,
        vec3(currScreenPos, screenDepth)
    );

    // Voxy renders with the current vanilla model-view matrix, but uses its own depth projection.
    vec3 currFeetPlayerPos = mat3(gbufferModelViewInverse) * currViewPos + gbufferModelViewInverse[3].xyz;
    currFeetPlayerPos += camPosDelta;

    vec3 prevViewPos = mat3(gbufferPreviousModelView) * currFeetPlayerPos + gbufferPreviousModelView[3].xyz;
    return getScreenCoord(gbufferPreviousProjection, prevViewPos);
}
#endif

// Fast RGB <-> YCoCg color space conversion
vec3 RGB2YCoCg(vec3 c) {
    return vec3(
         0.25 * c.r + 0.50 * c.g + 0.25 * c.b,
         0.50 * c.r             - 0.50 * c.b,
        -0.25 * c.r + 0.50 * c.g - 0.25 * c.b
    );
}

vec3 YCoCg2RGB(vec3 c) {
    return clamp(vec3(
        c.x + c.y - c.z,
        c.x + c.z,
        c.x - c.y - c.z
    ), 0.0, 65504.0);
}

vec3 textureTAA(in ivec2 screenTexelCoord){
    // Current color
    vec3 currColorRGB = texelFetch(colortex4, screenTexelCoord, 0).rgb;

    float vanillaDepth = texelFetch(depthtex0, screenTexelCoord, 0).x;
    vec2 prevScreenCoord;

    #ifdef VOXY
        float voxyDepth = texelFetch(vxDepthTexTrans, screenTexelCoord, 0).x;
        bool voxyLod = vanillaDepth == 1.0 && voxyDepth < 1.0;
        prevScreenCoord = voxyLod
            ? getVoxyPrevScreenCoord(texCoord, voxyDepth)
            : getPrevScreenCoord(texCoord, vanillaDepth);
    #else
        prevScreenCoord = getPrevScreenCoord(texCoord, vanillaDepth);
    #endif

    // Previous color
    vec3 prevColorRGB = currColorRGB;
    if(all(greaterThanEqual(prevScreenCoord, vec2(0.0))) && all(lessThan(prevScreenCoord, vec2(1.0)))){
        prevColorRGB = textureLod(colortex5, prevScreenCoord, 0).rgb;
    }

    // Convert to YCoCg space for chrominance-decoupled clamping
    vec3 currY = RGB2YCoCg(currColorRGB);
    vec3 prevY = RGB2YCoCg(prevColorRGB);

    // Guard 5-tap neighbourhood against screen-edge clearcolor (black) bleed.
    // Clamping the texel coordinates prevents out-of-bounds taps from sampling
    // the gcolorClearColor = (0,0,0,1) border and pulling boxMin.x (luma) to
    // zero, which was the root cause of the "black filter chasing the camera"
    // artifact when panning the view.
    ivec2 texSize = textureSize(colortex4, 0) - 1;
    vec3 c0 = RGB2YCoCg(texelFetch(colortex4, clamp(screenTexelCoord + ivec2(-1,  0), ivec2(0), texSize), 0).rgb);
    vec3 c1 = RGB2YCoCg(texelFetch(colortex4, clamp(screenTexelCoord + ivec2( 1,  0), ivec2(0), texSize), 0).rgb);
    vec3 c2 = RGB2YCoCg(texelFetch(colortex4, clamp(screenTexelCoord + ivec2( 0, -1), ivec2(0), texSize), 0).rgb);
    vec3 c3 = RGB2YCoCg(texelFetch(colortex4, clamp(screenTexelCoord + ivec2( 0,  1), ivec2(0), texSize), 0).rgb);

    vec3 boxMin = min(currY, min(min(c0, c1), min(c2, c3)));
    vec3 boxMax = max(currY, max(max(c0, c1), max(c2, c3)));

    // Luminance-chrominance decoupled AABB clamping:
    // - Luma (Y)  : tight clamp, prevents ghosting on sharp luminance edges.
    // - Chroma (CoCg): relaxed by 25% to avoid crushing colour on fast camera
    //   motion, which contributed to the desaturated / dark world appearance.
    vec3 chromaSlack = (boxMax - boxMin) * 0.25;
    prevY.x  = clamp(prevY.x,  boxMin.x,              boxMax.x             );
    prevY.yz = clamp(prevY.yz, boxMin.yz - chromaSlack.yz, boxMax.yz + chromaSlack.yz);

    // Blend 15% current / 85% history. The original 10/90 split was too
    // conservative: during fast panning the stale (dark) history needed many
    // frames to converge, making the black fringe linger visibly longer.
    return YCoCg2RGB(currY * 0.15 + prevY * 0.85);
}
