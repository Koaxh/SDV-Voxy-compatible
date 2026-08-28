const uint volumetricCloudSteps = uint(VOLUMETRIC_CLOUD_STEPS);

const float volumetricCenterDepth = VOLUMETRIC_CLOUD_DEPTH * 0.5;
const float volumetricCloudHeight = 195.0 + volumetricCenterDepth;

// Optimized volumetric clouds raymarching
vec2 volumetricClouds(in vec3 nFeetPlayerPos, in vec3 cameraPos, in float feetPlayerDist, in float cloudRenderDistance, in float dither, in bool isSky){
    // [Early Bailout 1]: Ray is nearly horizontal (parallel to cloud slab) -> instant return
    if(abs(nFeetPlayerPos.y) < 1e-5) return vec2(0.0);

    // [Early Bailout 2]: Ray points completely away from cloud layer
    // (e.g. looking down when below clouds, or looking up when above clouds)
    if((cameraPos.y < -VOLUMETRIC_CLOUD_DEPTH && nFeetPlayerPos.y <= 0.0) ||
       (cameraPos.y > 0.0 && nFeetPlayerPos.y >= 0.0)) {
        return vec2(0.0);
    }

    // Precompute reciprocal of Y direction (1 division replaces 2 divisions)
    float invY = 1.0 / nFeetPlayerPos.y;
    float higherBoundDist = -cameraPos.y * invY;
    float lowerBoundDist  = higherBoundDist - VOLUMETRIC_CLOUD_DEPTH * invY;

    // Finds the nearest and furthest plane
    float nearestPlane = max(min(lowerBoundDist, higherBoundDist), 0.0);
    if(!isSky && feetPlayerDist <= nearestPlane) return vec2(0.0);

    // Minimum cloud distance, if terrain, caps distance to the minimum cloud distance
    float cloudFar = isSky ? cloudRenderDistance : min(cloudRenderDistance, feetPlayerDist);
	float furthestPlane = min(cloudFar, max(lowerBoundDist, higherBoundDist));

    // If the clouds are outside the bounding box, return nothing
    if(furthestPlane < 0.0) return vec2(0.0);

    // Get distance inside the cloud
    float distInsideCloud = furthestPlane - nearestPlane;
    if(distInsideCloud <= 0.001) return vec2(0.0);

    // Calculate cloud steps that dynamically increase with distance
    uint dynamicSteps = max(min(uint(distInsideCloud), volumetricCloudSteps), 1u);
    float stepDist = distInsideCloud / float(dynamicSteps);

    // Multiply by stepDist to get the step size and scale with distance
    vec3 endPos = nFeetPlayerPos * stepDist;

    // Camera position as its start position
    vec3 startPos = cameraPos + nFeetPlayerPos * nearestPlane + endPos * dither;

    // Vectorized 2D texture coordinates (pre-scaled by 0.0625 = 1/16)
    vec2 uvPos  = startPos.xz * 0.0625;
    vec2 uvStep = endPos.xz * 0.0625;

    float negPosY     = -startPos.y;
    float stepNegPosY = -endPos.y;

    float currentRayDist = nearestPlane + dither * stepDist;
    float invCloudFarSqrd = 1.0 / squared(cloudRenderDistance);

    // To store the cloud data for 2 cloud layers
    vec2 clouds = vec2(0.0);

    // Streamlined Raymarching Loop
    for(uint i = 0u; i < dynamicSteps; i++){
        float cloudFog = max(0.0, 1.0 - (currentRayDist * currentRayDist) * invCloudFarSqrd);
        vec2 cloudData = texelFetch(colortex0, ivec2(uvPos) & 255, 0).xy;

        float sampleVal = negPosY * cloudFog;
        if(cloudData.x > 0.5) clouds.x = max(clouds.x, sampleVal);
        if(cloudData.y > 0.5) clouds.y = max(clouds.y, sampleVal);

        uvPos += uvStep;
        negPosY += stepNegPosY;
        currentRayDist += stepDist;
    }

    return clouds;
}
