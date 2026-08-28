#define VOLUMETRIC_LIGHT_STEPS 7u

const float volumetricStepsInverse = 1.0 / float(VOLUMETRIC_LIGHT_STEPS);

vec3 getVolumetricLight(in vec3 nFeetPlayerPos, in float feetPlayerDist, in float fogFactor, in float borderFog, in float dither, in bool isSky){
	// [Early exit 1]: Skip computation if light is completely dark or point is at hand range
	float maxLight = max(lightCol.r, max(lightCol.g, lightCol.b));
	if(maxLight <= 0.0001 || feetPlayerDist <= 0.2) return vec3(0.0);

	float totalFogDensity = FOG_TOTAL_DENSITY;

	#ifdef FORCE_DISABLE_WEATHER
		if(isEyeInWater != 0) totalFogDensity *= TAU;
    #else
		totalFogDensity *= isEyeInWater == 0 ? (rainStrength * PI + 1.0) : TAU;
    #endif

	float heightFade = 1.0;

	// Fade VL, but do not apply to underwater VL
	if(isEyeInWater == 0 && nFeetPlayerPos.y > 0.0){
		heightFade = squared(squared(1.0 - squared(nFeetPlayerPos.y)));
		if(isSky) heightFade *= heightFade;

		#ifndef WORLD_CUSTOM_SKYLIGHT
			#ifndef FORCE_DISABLE_WEATHER
				heightFade += (1.0 - heightFade) * max(1.0 - eyeBrightFact, rainStrength * 0.5);
			#else
				heightFade += (1.0 - heightFade) * (1.0 - eyeBrightFact);
			#endif
		#endif
	}

	float volumetricFogDensity = 1.0 - exp2(-feetPlayerDist * totalFogDensity);
	volumetricFogDensity = (volumetricFogDensity - fogFactor) * VOLUMETRIC_LIGHTING_STRENGTH + fogFactor;

	// Border fog
	#ifdef BORDER_FOG
		volumetricFogDensity = (volumetricFogDensity - 1.0) * borderFog + 1.0;
	#endif

	#if defined VOLUMETRIC_LIGHTING && defined SHADOW_MAPPING
		float vlMultiplier = min(1.0, VOLUMETRIC_LIGHTING_STRENGTH + VOLUMETRIC_LIGHTING_STRENGTH * float(isEyeInWater)) * squared(heightFade) * volumetricFogDensity;
		if(vlMultiplier <= 0.0001) return vec3(0.0);

		// Normalize then unormalize with feetPlayerDist and clamping it at minimum distance between far and current shadowDistance
		vec3 shadowScale = vec3(shadowProjection[0].x, shadowProjection[1].y, shadowProjection[2].z);
		float marchDist = min(min(borderFar, shadowDistance), feetPlayerDist) * volumetricStepsInverse;
		vec3 endPos = (shadowScale * (mat3(shadowModelView) * nFeetPlayerPos)) * marchDist;

		// Apply dithering added to the eyePlayerPos "camera" position converted to shadow clip space
		vec3 startPos = shadowScale * shadowModelView[3].xyz + endPos * dither;
		startPos.z += shadowProjection[3].z;

		if(isEyeInWater == 1){
			// Hoist uniform water fog linear conversion out of the 7-step loop
			vec3 hoistedWaterFog = toLinear(clamp(fogColor, vec3(0.0), vec3(1.0)));
			vec3 volumeData = vec3(0.0);
			for(uint i = 0u; i < VOLUMETRIC_LIGHT_STEPS; i++){
				float invDistort = 1.0 / (length(startPos.xy) * 2.0 + 0.2);
				vec3 volumeShadowPosition = vec3(startPos.xy * invDistort, startPos.z * 0.1) + 0.5;
				vec3 rawShd = getShdCol(volumeShadowPosition);
				float missingWaterCaster = smoothstep(0.98, 0.999, min(rawShd.r, min(rawShd.g, rawShd.b)));
				volumeData += mix(rawShd, hoistedWaterFog, missingWaterCaster);
				startPos += endPos;
			}
			
			// Preserve full godray luminance while shifting the hue to a natural cyan-green / teal aquatic tone
			vec3 waterTint = normalize(hoistedWaterFog * vec3(0.8, 1.25, 0.95) + vec3(0.02, 0.32, 0.26));
			vec3 effectiveLightCol = mix(lightCol, waterTint * maxLight * 1.6, 0.75);
			return volumeData * effectiveLightCol * (vlMultiplier * volumetricStepsInverse);
		} else {
			#ifdef SHADOW_COLOR
				vec3 volumeData = vec3(0.0);
				for(uint i = 0u; i < VOLUMETRIC_LIGHT_STEPS; i++){
					float invDistort = 1.0 / (length(startPos.xy) * 2.0 + 0.2);
					vec3 volumeShadowPosition = vec3(startPos.xy * invDistort, startPos.z * 0.1) + 0.5;
					volumeData += getShdCol(volumeShadowPosition);
					startPos += endPos;
				}
				return volumeData * lightCol * (vlMultiplier * volumetricStepsInverse);
			#else
				float volumeScalar = 0.0;
				for(uint i = 0u; i < VOLUMETRIC_LIGHT_STEPS; i++){
					float invDistort = 1.0 / (length(startPos.xy) * 2.0 + 0.2);
					vec3 volumeShadowPosition = vec3(startPos.xy * invDistort, startPos.z * 0.1) + 0.5;
					volumeScalar += textureLod(shadowtex0, volumeShadowPosition, 0).x;
					startPos += endPos;
				}
				return (volumeScalar * (vlMultiplier * volumetricStepsInverse)) * lightCol;
			#endif
		}
	#else
		if(isEyeInWater == 1) return lightCol * toLinear(fogColor) * (min(1.0, VOLUMETRIC_LIGHTING_STRENGTH * 2.0) * volumetricFogDensity);
		#ifdef WORLD_CUSTOM_SKYLIGHT
			else return lightCol * (volumetricFogDensity * VOLUMETRIC_LIGHTING_STRENGTH);
		#else
			else return lightCol * (squared(eyeBrightFact) * volumetricFogDensity * VOLUMETRIC_LIGHTING_STRENGTH);
		#endif
	#endif
}
