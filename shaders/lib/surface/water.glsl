float getCellNoise(in vec2 uv, in float animateTime){
    return textureLod(noisetex, uv + animateTime, 0).z + textureLod(noisetex, animateTime - uv, 0).z;
}

float getCellNoise(in vec2 uv){
    const float currentSpeed = CURRENT_SPEED * 0.0625;
    float animateTime = fragmentFrameTime * currentSpeed;
    return getCellNoise(uv, animateTime);
}

// Convert height map of water to a normal map with footprint-aware filtering
vec4 H2NWater(in vec2 uv){
    const float currentSpeed = CURRENT_SPEED * 0.0625;
    const float baseWaterPixel = WATER_BLUR_SIZE * 0.00390625;
    const float waterDepth = WATER_BLUR_SIZE * WATER_DEPTH_SIZE;

    float animateTime = fragmentFrameTime * currentSpeed;

    // Estimate screen footprint in UV space to eliminate grazing angle aliasing
    vec2 dUVdx = dFdx(uv);
    vec2 dUVdy = dFdy(uv);
    float footprint = max(length(dUVdx), length(dUVdy));
    float filterStep = max(baseWaterPixel, footprint * 0.75);

    vec2 offsetU = vec2(filterStep, 0.0);
    vec2 offsetV = vec2(0.0, filterStep);

    float hCenter = getCellNoise(uv, animateTime);
    float hU = getCellNoise(uv + offsetU, animateTime);
    float hV = getCellNoise(uv + offsetV, animateTime);

    // Gradient calculation
    float dU = (hCenter - hU) * (baseWaterPixel / filterStep);
    float dV = (hCenter - hV) * (baseWaterPixel / filterStep);

    // Grazing angle normal dampening to prevent reflection blowups
    float grazingAttenuation = clamp(1.0 - footprint * 8.0, 0.15, 1.0);
    dU *= grazingAttenuation;
    dV *= grazingAttenuation;

    return vec4(dU, dV, waterDepth, hCenter);
}