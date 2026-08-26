// Render distance in blocks for the geometry source that owns the scene edge.
// vxRenderDistance is supplied by Voxy in chunks; 16 is only the unit
// conversion. Without Voxy this remains SDV's original borderFar path.
float getSceneRenderDistance() {
    #ifdef VOXY
        return float(vxRenderDistance) * 16.0;
    #else
        return borderFar;
    #endif
}

// Original SDV/Complementary border-fog curve, evaluated against the actual
// scene render distance instead of an empirical borderFar multiplier.
float getBorderFog(in float playerPosLength){
    return exp2(-exp2(playerPosLength / getSceneRenderDistance() * 21.0 - 18.0));
}

// Ground fog calculation from this Stack Exchange post, variables has been renamed for their respective purpose
// https://www.bing.com/search?q=ground+fog+shader&qs=n&form=QBRE&sp=-1&lq=0&pq=&sc=0-0&sk=&cvid=CEF589A66F844D48A5D56923DDBF4540&ghsh=0&ghacc=0&ghpl=&ntref=1
float getAtmosphericFog(in float nPlayerPosY, in float worldPosY, in float playerPosLength, in float totalDensity, in float verticalFogDensity){
    // This is SDV's original signed height integral. The horizontal ray is a
    // removable 0/0 singularity, so evaluate its exact analytic limit there.
    float heightIntegral;
    if(nPlayerPosY == 0.0)
        heightIntegral = log(2.0) * playerPosLength * verticalFogDensity;
    else
        heightIntegral = (1.0 - exp2(-playerPosLength * nPlayerPosY * verticalFogDensity)) / nPlayerPosY;

    return (totalDensity / verticalFogDensity)
        * exp2(-worldPosY * verticalFogDensity)
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

    // Keep the exact SDV expression for both vanilla and Voxy receivers.
    return min(1.0, getAtmosphericFog(nEyePlayerPosY, max(0.0, worldPosY), viewDist, totalFogDensity, verticalFogDensity)) * min(1.0, GROUND_FOG_STRENGTH + GROUND_FOG_STRENGTH * isEyeInWater);
}

float getFogEffectFactor(in float viewDist){
    // Blindness fog
    return exp2(-viewDist * effectFactor);
}
