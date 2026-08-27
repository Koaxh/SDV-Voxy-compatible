float getSSAO(in vec3 screenPos, in vec3 viewNormal){
    #if ANTI_ALIASING >= 2
        vec3 dither = fract(getRng3(ivec2(gl_FragCoord.xy) & 255) + frameFract);
    #else
        vec3 dither = getRng3(ivec2(gl_FragCoord.xy) & 255);
    #endif

    float occlusion = 0.25;

    // Instead of iterating by adding stepSize and using fract every time, we swizzle + one fract instead for pleasant and optimized results
    vec3 baseDither = dither.xyz * 0.5 - 0.25;
	vec3 ditherSwizzle[4] = vec3[4](
		baseDither.xyz,
		baseDither.zxy,
		baseDither.yzx,
		fract(dither.zyx + GOLDEN_RATIO) * 0.5 - 0.25
	);

    float depthOrigin = near / (1.0 - screenPos.z);

    // Pre calculate base position
    vec3 basePos = getViewPos(gbufferProjectionInverse, screenPos) + viewNormal * 0.5;

    for(uint i = 0u; i < 4u; i++){
        // Add new offsets to origin
        vec3 samplePos = getScreenPos(gbufferProjection, basePos + ditherSwizzle[i]);
        // Sample new depth and linearize
        float sampleDepth = textureLod(depthtex0, samplePos.xy, 0).x;

        // Check if the offset points are inside geometry or if the point is occluded
        if(samplePos.z > sampleDepth) occlusion -= 0.0625 / max(depthOrigin - near / (1.0 - sampleDepth), 1.0);
    }

    // Remap results and return
    return occlusion;
}

#ifdef VOXY
float getVoxySSAO(in vec3 screenPos, in vec3 viewNormal){
    #if ANTI_ALIASING >= 2
        vec3 dither = fract(getRng3(ivec2(gl_FragCoord.xy) & 255) + frameFract);
    #else
        vec3 dither = getRng3(ivec2(gl_FragCoord.xy) & 255);
    #endif

    float occlusion = 0.25;

    vec3 baseDither = dither.xyz * 0.5 - 0.25;
    vec3 ditherSwizzle[4] = vec3[4](
        baseDither.xyz,
        baseDither.zxy,
        baseDither.yzx,
        fract(dither.zyx + GOLDEN_RATIO) * 0.5 - 0.25
    );

    vec3 originViewPos = getVoxyViewPos(vxProjInv, screenPos);
    float depthOrigin = -originViewPos.z;
    vec3 basePos = originViewPos + viewNormal * 0.5;

    for(uint i = 0u; i < 4u; i++){
        vec3 samplePos = getVoxyScreenPos(
            vxProj * vec4(basePos + ditherSwizzle[i], 1.0)
        );
        float sampleDepth = textureLod(vxDepthTexOpaque, samplePos.xy, 0).x;
        float vanillaSampleDepth = textureLod(
            depthtex0,
            samplePos.xy,
            0
        ).x;

        // SSAO runs before translucent composition, so only opaque LOD depth
        // is a valid sample surface here.
        if(vanillaSampleDepth >= 1.0 &&
            sampleDepth < 1.0 && samplePos.z > sampleDepth){
            float sampleViewDepth = -getVoxyViewPos(
                vxProjInv,
                vec3(samplePos.xy, sampleDepth)
            ).z;
            occlusion -= 0.0625 / max(depthOrigin - sampleViewDepth, 1.0);
        }
    }

    return occlusion;
}
#endif
