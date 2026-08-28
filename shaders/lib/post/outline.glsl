float getVanillaOutline(
    in float depthOrigin,
    in float depth0,
    in float depth1,
    in float depth2,
    in float depth3
){
    float sumInv =
        1.0 / (1.0 - depth0) +
        1.0 / (1.0 - depth1) +
        1.0 / (1.0 - depth2) +
        1.0 / (1.0 - depth3);

    float diff = sumInv - 4.0 / (1.0 - depthOrigin);

    #if OUTLINES == 1
        // Preserve SDV's standard outline exactly for vanilla-only pixels.
        return saturate(near * diff);
    #else
        // Preserve SDV's dungeons outline exactly for vanilla-only pixels.
        return saturate((64.0 * (1.0 - depthOrigin)) * diff);
    #endif
}

#if defined VOXY && !defined DISTANT_HORIZONS
    float getOutlineViewDepth(in float depth, in bool isVoxyDepth){
        float ndcDepth = isVoxyDepth
            ? getVoxyNdcDepth(depth)
            : depth * 2.0 - 1.0;

        // Since homogeneousZ is algebraically -1.0 for perspective inverse matrices,
        // -viewZ simplifies to 1.0 / homogeneousW directly.
        float homogeneousW = isVoxyDepth
            ? vxProjInv[2][3] * ndcDepth + vxProjInv[3][3]
            : gbufferProjectionInverse[2][3] * ndcDepth + gbufferProjectionInverse[3][3];

        return max(1.0 / homogeneousW, 0.0001);
    }

    float getOutline(in ivec2 iUv, in float depthOrigin, in bool originIsVoxy){
        ivec2 topRightCorner = iUv - OUTLINE_PIXEL_SIZE;
        ivec2 bottomLeftCorner = iUv + OUTLINE_PIXEL_SIZE;
        ivec2 topLeftCorner = ivec2(topRightCorner.x, bottomLeftCorner.y);
        ivec2 bottomRightCorner = ivec2(bottomLeftCorner.x, topRightCorner.y);

        float depth0 = texelFetch(depthtex0, topRightCorner, 0).x;
        float depth1 = texelFetch(depthtex0, bottomLeftCorner, 0).x;
        float depth2 = texelFetch(depthtex0, topLeftCorner, 0).x;
        float depth3 = texelFetch(depthtex0, bottomRightCorner, 0).x;

        // The overwhelmingly common vanilla interior path retains SDV's four
        // texture reads and its original outline equations.
        if(!originIsVoxy && depth0 < 1.0 && depth1 < 1.0 && depth2 < 1.0 && depth3 < 1.0){
            return getVanillaOutline(depthOrigin, depth0, depth1, depth2, depth3);
        }

        float voxyDepth0 = 1.0;
        float voxyDepth1 = 1.0;
        float voxyDepth2 = 1.0;
        float voxyDepth3 = 1.0;

        bool depth0IsVoxy = false;
        bool depth1IsVoxy = false;
        bool depth2IsVoxy = false;
        bool depth3IsVoxy = false;

        // Match deferred1's ownership rule: vanilla wins wherever it exists;
        // Voxy supplies a sample only where vanilla depth is clear.
        if(depth0 == 1.0){
            voxyDepth0 = texelFetch(vxDepthTexOpaque, topRightCorner, 0).x;
            depth0IsVoxy = voxyDepth0 < 1.0;
        }
        if(depth1 == 1.0){
            voxyDepth1 = texelFetch(vxDepthTexOpaque, bottomLeftCorner, 0).x;
            depth1IsVoxy = voxyDepth1 < 1.0;
        }
        if(depth2 == 1.0){
            voxyDepth2 = texelFetch(vxDepthTexOpaque, topLeftCorner, 0).x;
            depth2IsVoxy = voxyDepth2 < 1.0;
        }
        if(depth3 == 1.0){
            voxyDepth3 = texelFetch(vxDepthTexOpaque, bottomRightCorner, 0).x;
            depth3IsVoxy = voxyDepth3 < 1.0;
        }

        bool hasVoxyNeighbor = depth0IsVoxy || depth1IsVoxy || depth2IsVoxy || depth3IsVoxy;

        // A vanilla silhouette with no Voxy behind it must remain bit-for-bit
        // on SDV's original path, including the original sky-edge behavior.
        if(!originIsVoxy && !hasVoxyNeighbor){
            return getVanillaOutline(depthOrigin, depth0, depth1, depth2, depth3);
        }

        // A genuinely empty neighbor is a scene silhouette. Avoid attempting
        // to linearize the depth clear value, which represents infinity.
        if(
            (depth0 == 1.0 && !depth0IsVoxy) ||
            (depth1 == 1.0 && !depth1IsVoxy) ||
            (depth2 == 1.0 && !depth2IsVoxy) ||
            (depth3 == 1.0 && !depth3IsVoxy)
        ){
            return 1.0;
        }

        float viewDepthOrigin = getOutlineViewDepth(depthOrigin, originIsVoxy);
        float viewDepth0 = getOutlineViewDepth(depth0IsVoxy ? voxyDepth0 : depth0, depth0IsVoxy);
        float viewDepth1 = getOutlineViewDepth(depth1IsVoxy ? voxyDepth1 : depth1, depth1IsVoxy);
        float viewDepth2 = getOutlineViewDepth(depth2IsVoxy ? voxyDepth2 : depth2, depth2IsVoxy);
        float viewDepth3 = getOutlineViewDepth(depth3IsVoxy ? voxyDepth3 : depth3, depth3IsVoxy);
        float diffView = (viewDepth0 + viewDepth1 + viewDepth2 + viewDepth3) - viewDepthOrigin * 4.0;

        #if OUTLINES == 1
            return saturate(diffView);
        #else
            return saturate((64.0 / viewDepthOrigin) * diffView);
        #endif
    }
#else
    float getOutline(in ivec2 iUv, in float depthOrigin){
        ivec2 topRightCorner = iUv - OUTLINE_PIXEL_SIZE;
        ivec2 bottomLeftCorner = iUv + OUTLINE_PIXEL_SIZE;

        float depth0 = texelFetch(depthtex0, topRightCorner, 0).x;
        float depth1 = texelFetch(depthtex0, bottomLeftCorner, 0).x;
        float depth2 = texelFetch(depthtex0, ivec2(topRightCorner.x, bottomLeftCorner.y), 0).x;
        float depth3 = texelFetch(depthtex0, ivec2(bottomLeftCorner.x, topRightCorner.y), 0).x;

        return getVanillaOutline(depthOrigin, depth0, depth1, depth2, depth3);
    }
#endif
