// Render distance in blocks for the geometry source that owns the scene edge.
// vxRenderDistance is supplied by Voxy in chunks; 16 is only the unit
// conversion. Without Voxy this remains SDV's original borderFar path.
float getSceneRenderDistance() {
    #ifdef VOXY
        float vxDist = float(vxRenderDistance) * 16.0;
        return vxDist > 32.0 ? vxDist : max(borderFar, 64.0);
    #else
        return max(borderFar, 64.0);
    #endif
}

// Border fog evaluated against horizontal distance so altitude does not consume render distance budget
float getBorderFog(in float playerPosLength, in float nPlayerPosY){
    float horizDist = playerPosLength * sqrt(max(0.0, 1.0 - nPlayerPosY * nPlayerPosY));
    float sceneDist = getSceneRenderDistance();
    return exp2(-exp2(clamp(horizDist / sceneDist * 21.0 - 18.0, -20.0, 20.0)));
}

float getBorderFog(in float playerPosLength){
    float sceneDist = getSceneRenderDistance();
    return exp2(-exp2(clamp(playerPosLength / sceneDist * 21.0 - 18.0, -20.0, 20.0)));
}

// Ground fog calculation: exact analytic optical depth integral through exponential atmosphere
// Numerically symmetric and bounded; never overflows at high altitudes or grazing angles
float getAtmosphericFog(in float nPlayerPosY, in float worldPosY, in float playerPosLength, in float totalDensity, in float verticalFogDensity){
    float yCam = worldPosY - playerPosLength * nPlayerPosY;
    float yMin = max(0.0, min(yCam, worldPosY));
    float yMax = max(0.0, max(yCam, worldPosY));
    float deltaY = yMax - yMin;
    float absNDirY = max(abs(nPlayerPosY), 1e-4);

    float heightIntegral;
    if (abs(nPlayerPosY) < 1e-4) {
        heightIntegral = playerPosLength * verticalFogDensity * 0.69314718;
    } else {
        heightIntegral = (1.0 - exp2(-deltaY * verticalFogDensity)) / (absNDirY * 0.69314718);
    }

    return (totalDensity / verticalFogDensity)
        * exp2(-yMin * verticalFogDensity)
        * heightIntegral;
}

float getFogFactor(in float viewDist, in float nEyePlayerPosY, in float worldPosY){
    #ifdef FORCE_DISABLE_WEATHER
        float verticalFogDensity = isEyeInWater == 0 ? FOG_VERTICAL_DENSITY : FOG_VERTICAL_DENSITY * 0.2;
        float totalFogDensity = isEyeInWater == 0 ? FOG_TOTAL_DENSITY : FOG_TOTAL_DENSITY * TAU;
    #else
        float verticalFogDensity = isEyeInWater == 0 ? FOG_VERTICAL_DENSITY - FOG_VERTICAL_DENSITY * rainStrength * 0.8 : FOG_VERTICAL_DENSITY * 0.2;
        float totalFogDensity = isEyeInWater == 0 ? FOG_TOTAL_DENSITY * (rainStrength * eyeBrightFact * PI + 1.0) : FOG_TOTAL_DENSITY * TAU;
    #endif

    return min(1.0, getAtmosphericFog(nEyePlayerPosY, max(0.0, worldPosY), viewDist, totalFogDensity, verticalFogDensity)) * min(1.0, GROUND_FOG_STRENGTH + GROUND_FOG_STRENGTH * isEyeInWater);
}

float getFogEffectFactor(in float viewDist){
    // Blindness fog
    return exp2(-viewDist * effectFactor);
}

