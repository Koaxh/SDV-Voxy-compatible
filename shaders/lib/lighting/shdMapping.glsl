// Enable filtering on shadows
const int shadowMapResolution = 1024; // Shadow map resolution. Increase for more resolution at the cost of performance. [512 1024 1536 2048 2560 3072 3584 4096 4608 5120 5632 6144 6656 7168 7680 8192]
const float shadowMapPixelSize = 1.0 / shadowMapResolution; // Shadow map pixel size. Calculated as the reciprocal of the shadow map resolution.
const bool shadowHardwareFiltering = true; // Free slightly better filtering

const float shadowDistance = 128.0; // Shadow distance. Increase to stretch the shadow map to farther distances in blocks. It's recommended to match this setting with your render distance and increase your shadow map resolution. [32.0 64.0 96.0 128.0 160.0 192.0 224.0 256.0 288.0 320.0 352.0 384.0 416.0 448.0 480.0 512.0 544.0 576.0 608.0 640.0 672.0 704.0 736.0 768.0 800.0 832.0 864.0 896.0 928.0 960.0 992.0 1024.0]
const float shadowDistanceRenderMul = 1.0; // Hardcoded to be always 1.0 for maximum optimization.
const float entityShadowDistanceMul = 0.5; // Renders the entity shadows at half shadowDistance. Iris only.

// Shadow opaque
#ifndef SDV_EXTERNAL_SHADOW_SAMPLERS
	uniform sampler2DShadow shadowtex0;

	#ifdef SHADOW_COLOR
		// Shadow w/o translucents
		uniform sampler2DShadow shadowtex1;

		// Shadow color
		uniform sampler2D shadowcolor0;
	#endif
#endif

vec3 getShdCol(in vec3 shdPos){
	#ifdef SHADOW_COLOR
		// Sample shadows
		float shd0 = textureLod(shadowtex0, shdPos, 0);
		// If not in shadow, return "white"
		if(shd0 == 1) return vec3(1);

		// Sample opaque only shadows
		float shd1 = textureLod(shadowtex1, shdPos, 0);
		// If in shadow, return "black"
		if(shd1 == 0) return vec3(0);
		// Otherwise, calculate the full shadow color
		return texelFetch(shadowcolor0, ivec2(shdPos.xy * shadowMapResolution), 0).rgb * (1.0 - shd0) * shd1 + shd0;
	#else
		// Sample shadows and return directly
		return vec3(textureLod(shadowtex0, shdPos, 0));
	#endif
}

vec3 getShdCol(in vec3 shdPos, in float dither){
	vec2 randVec = vec2(cos(dither), sin(dither)) * shadowMapPixelSize;

	#if ANTI_ALIASING >= 2
		return getShdCol(vec3(shdPos.xy + randVec, shdPos.z));
	#else
		return (getShdCol(vec3(shdPos.xy + randVec, shdPos.z)) + getShdCol(vec3(shdPos.xy - randVec, shdPos.z))) * 0.5;
	#endif
}

float getTranslucentShdCoverage(in vec3 shdPos){
	#ifdef SHADOW_COLOR
		// shadowtex0 contains opaque + translucent casters; shadowtex1 is
		// opaque-only. Their visibility difference is an independent water/glass
		// caster mask and does not depend on shadow RGB or caustic brightness.
		float allVisibility = textureLod(shadowtex0, shdPos, 0);
		float opaqueVisibility = textureLod(shadowtex1, shdPos, 0);
		return clamp(opaqueVisibility - allVisibility, 0.0, 1.0);
	#else
		return 0.0;
	#endif
}

float getTranslucentShdCoverage(in vec3 shdPos, in float dither){
	vec2 randVec = vec2(cos(dither), sin(dither)) * shadowMapPixelSize;

	#if ANTI_ALIASING >= 2
		return getTranslucentShdCoverage(
			vec3(shdPos.xy + randVec, shdPos.z)
		);
	#else
		return 0.5 * (
			getTranslucentShdCoverage(vec3(shdPos.xy + randVec, shdPos.z))
			+ getTranslucentShdCoverage(vec3(shdPos.xy - randVec, shdPos.z))
		);
	#endif
}

void getShdColAndTranslucentCoverage(
	in vec3 shdPos,
	out vec3 shadowColor,
	out float translucentCoverage
){
	#ifdef SHADOW_COLOR
		float s0 = textureLod(shadowtex0, shdPos, 0);
		float s1 = textureLod(shadowtex1, shdPos, 0);
		translucentCoverage = clamp(s1 - s0, 0.0, 1.0);
		if(s0 == 1.0){
			shadowColor = vec3(1.0);
		} else if(s1 == 0.0){
			shadowColor = vec3(0.0);
		} else {
			shadowColor = texelFetch(shadowcolor0, ivec2(shdPos.xy * shadowMapResolution), 0).rgb * (1.0 - s0) * s1 + s0;
		}
	#else
		shadowColor = vec3(textureLod(shadowtex0, shdPos, 0));
		translucentCoverage = 0.0;
	#endif
}

void getShdColAndTranslucentCoverage(
	in vec3 shdPos,
	in float dither,
	out vec3 shadowColor,
	out float translucentCoverage
){
	vec2 randVec = vec2(cos(dither), sin(dither)) * shadowMapPixelSize;

	#if ANTI_ALIASING >= 2
		getShdColAndTranslucentCoverage(
			vec3(shdPos.xy + randVec, shdPos.z),
			shadowColor,
			translucentCoverage
		);
	#else
		vec3 colA, colB;
		float covA, covB;
		getShdColAndTranslucentCoverage(
			vec3(shdPos.xy + randVec, shdPos.z),
			colA,
			covA
		);
		getShdColAndTranslucentCoverage(
			vec3(shdPos.xy - randVec, shdPos.z),
			colB,
			covB
		);
		shadowColor = (colA + colB) * 0.5;
		translucentCoverage = (covA + covB) * 0.5;
	#endif
}

vec3 getUnderwaterShdCol(in vec3 shadowColor, in vec3 waterFogColor){
    // A clear/absent coloured-shadow sample is white. Replace only that end of
    // the range with Minecraft's current underwater fog tint; real SDV coloured
    // water shadows and caustics remain untouched.
    float missingWaterCaster = smoothstep(0.98, 0.999, minOf(shadowColor));
    vec3 fallbackColor = toLinear(clamp(waterFogColor, vec3(0.0), vec3(1.0)));
    return mix(shadowColor, fallbackColor, missingWaterCaster);
}
