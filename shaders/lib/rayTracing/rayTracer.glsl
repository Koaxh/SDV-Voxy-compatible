const uint rayTraceSteps = uint(RAYTRACER_STEPS);
const uint rayTraceBiSteps = uint(RAYTRACER_BISTEPS);

// This raytracer is so fast I swear...
// Based from Belmu's raytracer https://github.com/BelmuTM/NobleRT
// Basically an upgrade to Shadax's raytracer https://github.com/Shadax-stack/MinecraftSSR
vec3 rayTraceScene(in vec3 screenPos, in vec3 viewPos, in vec3 rayDir, in float dither){
	// Fix for the blob when player is near a surface. From Bálint#1673
	if(rayDir.z > -viewPos.z) return vec3(0);

	// Get screenspace rayDir
	vec3 screenPosRayDir = fastNormalize(getScreenPos(gbufferProjection, viewPos + rayDir) - screenPos) * rayTracerStepsInv;

	// Apply dithering
	vec3 startPos = screenPos + screenPosRayDir * dither;

	for(uint i = 0u; i < rayTraceSteps; i++){
		// We raytrace here
		startPos += screenPosRayDir;

		// If current pos is out of bounds, exit immediately
		if(startPos.x < 0 || startPos.y < 0 || startPos.x > 1 || startPos.y > 1) return vec3(0);

		// Get current texture depth
		float currDepth = textureLod(depthtex0, startPos.xy, 0).x;

		// If hand return immediately
		if(currDepth <= 0.56) return vec3(0);

		// Check intersection
		bool intersection = currDepth < startPos.z;

		// If intersection
		if(intersection){
			// Integrated binary refinement
			#if RAYTRACER_BISTEPS != 0
				for(uint i = 0u; i < rayTraceBiSteps; i++){
					// If sky return immediately
					if(getDepthTex(startPos.xy) == 1) return vec3(0);

					// Continue refinement
					screenPosRayDir *= 0.5;
					startPos += intersection ? -screenPosRayDir : screenPosRayDir;

					// Get current texture depth
					currDepth = textureLod(depthtex0, startPos.xy, 0).x;
					// Check intersection
					intersection = currDepth < startPos.z;
				}
			#else
				// If sky return immediately
				if(getDepthTex(startPos.xy) == 1) return vec3(0);
			#endif

			// Return final results
			return vec3(startPos.xy, 1);
		}
	}

	return vec3(0);
}

#ifdef SDV_VOXY_DEFERRED_RAYTRACE
    // Project a Voxy-view-space position into the same [0, 1] depth convention
    // used by its depth textures. Voxy can use either OpenGL NDC convention.
    vec3 getVoxyRayTraceScreenPos(in vec3 viewPos){
        vec4 clipPos = vxProj * vec4(viewPos, 1.0);
        vec3 ndcPos = clipPos.xyz / clipPos.w;

        return vec3(
            ndcPos.xy * 0.5 + 0.5,
            vxDepthZeroToOne != 0 ? ndcPos.z : ndcPos.z * 0.5 + 0.5
        );
    }

    // Return the closest opaque scene depth expressed in Voxy screen space.
    // Vanilla-owned pixels can carry a separate hidden Voxy caster depth for
    // cross-domain shadows. That layer is not visible scene geometry here.
    // Convert the authoritative Vanilla depth into the Voxy domain in those
    // pixels; elsewhere use Voxy's opaque depth to avoid hitting the water.
    bool getVoxyRayTraceSceneDepth(in vec2 screenCoord, out float sceneDepth){
        float vanillaDepth = textureLod(depthtex0, screenCoord, 0).x;

        if(vanillaDepth < 1.0){
            // Preserve the original tracer's hand exclusion.
            if(vanillaDepth <= 0.56) return false;

            // Fast 1D scalar depth remapping: eliminates 4x4 matrix-vector multiplication in loop
            float ndcVanilla = vanillaDepth * 2.0 - 1.0;
            float denom = ndcVanilla * gbufferProjectionInverse[2][3] + gbufferProjectionInverse[3][3];
            float viewZ = gbufferProjectionInverse[3][2] / denom;
            float voxyNdcDepth = -vxProj[2][2] - vxProj[3][2] / viewZ;

            sceneDepth = vxDepthZeroToOne != 0
                ? voxyNdcDepth
                : voxyNdcDepth * 0.5 + 0.5;
            return true;
        }

        sceneDepth = textureLod(vxDepthTexOpaque, screenCoord, 0).x;
        return sceneDepth < 1.0;
    }

    #if (defined SSR || defined SSGI) && defined PREVIOUS_FRAME
        // Reproject a Voxy-depth hit through the same vanilla scene/history
        // matrices as Photon. vxProjInv only reconstructs the current view
        // position; vxModelView* must not be applied a second time.
        bool getPrevVoxyRayTraceScreenCoord(
            in vec2 currScreenCoord,
            out vec2 prevScreenCoord
        ){
            float currDepth;
            if(!getVoxyRayTraceSceneDepth(currScreenCoord, currDepth)){
                return false;
            }

            vec3 currNdcPos = vec3(
                currScreenCoord * 2.0 - 1.0,
                vxDepthZeroToOne != 0
                    ? currDepth
                    : currDepth * 2.0 - 1.0
            );
            vec4 currViewPos = vxProjInv * vec4(currNdcPos, 1.0);
            if(abs(currViewPos.w) < 0.000001) return false;
            currViewPos /= currViewPos.w;

            vec4 currScenePos = gbufferModelViewInverse * currViewPos;
            currScenePos.xyz += camPosDelta;

            vec4 prevClipPos = gbufferPreviousProjection
                * gbufferPreviousModelView * currScenePos;
            if(prevClipPos.w <= 0.000001) return false;

            prevScreenCoord = prevClipPos.xy / prevClipPos.w * 0.5 + 0.5;
            return prevScreenCoord.x >= 0.0
                && prevScreenCoord.y >= 0.0
                && prevScreenCoord.x <= 1.0
                && prevScreenCoord.y <= 1.0;
        }
    #endif

    vec3 rayTraceSceneVoxy(
        in vec3 screenPos,
        in vec3 viewPos,
        in vec3 rayDir,
        in float dither
    ){
        // Fix for the blob when the camera is near a surface.
        if(rayDir.z > -viewPos.z) return vec3(0);

        vec3 projectedRayEnd = getVoxyRayTraceScreenPos(viewPos + rayDir);
        vec3 screenPosRayDir = fastNormalize(projectedRayEnd - screenPos)
            * rayTracerStepsInv;
        vec3 startPos = screenPos + screenPosRayDir * dither;

        for(uint i = 0u; i < rayTraceSteps; i++){
            startPos += screenPosRayDir;

            if(startPos.x < 0.0 || startPos.y < 0.0
            || startPos.x > 1.0 || startPos.y > 1.0){
                return vec3(0);
            }

            float currDepth;
            bool hasSceneDepth = getVoxyRayTraceSceneDepth(
                startPos.xy,
                currDepth
            );
            bool intersection = hasSceneDepth && currDepth < startPos.z;

            if(intersection){
                #if RAYTRACER_BISTEPS != 0
                    for(uint j = 0u; j < rayTraceBiSteps; j++){
                        screenPosRayDir *= 0.5;
                        startPos += intersection
                            ? -screenPosRayDir
                            : screenPosRayDir;

                        hasSceneDepth = getVoxyRayTraceSceneDepth(
                            startPos.xy,
                            currDepth
                        );
                        if(!hasSceneDepth) return vec3(0);
                        intersection = currDepth < startPos.z;
                    }
                #else
                    if(!hasSceneDepth) return vec3(0);
                #endif

                return vec3(startPos.xy, 1.0);
            }
        }

        return vec3(0);
    }
#endif
