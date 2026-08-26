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

vec3 textureTAA(in ivec2 screenTexelCoord){
    // Current color
    vec3 currColor = texelFetch(colortex4, screenTexelCoord, 0).rgb;

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
    vec3 prevColor = currColor;
    if(all(greaterThanEqual(prevScreenCoord, vec2(0.0))) && all(lessThan(prevScreenCoord, vec2(1.0)))){
        prevColor = textureLod(colortex5, prevScreenCoord, 0).rgb;
    }

    // Apply clamping on the history color.
    vec3 nearCol0 = texelFetch(colortex4, ivec2(screenTexelCoord.x - 1, screenTexelCoord.y), 0).rgb;
    vec3 nearCol1 = texelFetch(colortex4, ivec2(screenTexelCoord.x, screenTexelCoord.y - 1), 0).rgb;
    vec3 nearCol2 = texelFetch(colortex4, ivec2(screenTexelCoord.x + 1, screenTexelCoord.y), 0).rgb;
    vec3 nearCol3 = texelFetch(colortex4, ivec2(screenTexelCoord.x, screenTexelCoord.y + 1), 0).rgb;
    
    vec3 boxMin = min(currColor, min(nearCol0, min(nearCol1, min(nearCol2, nearCol3))));
    vec3 boxMax = max(currColor, max(nearCol0, max(nearCol1, max(nearCol2, nearCol3))));;
    
    // Required to add the "sum color" of the remaining VL
    prevColor = clamp(prevColor, boxMin, boxMax);

    // Return temporal color
    return currColor * 0.1 + prevColor * 0.9;
}
