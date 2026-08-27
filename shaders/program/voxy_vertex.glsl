// SDV's vanilla water displacement is A*cos(-k*(x+z) + omega*t).
// A Voxy quad can cover many vanilla water quads, so its least-squares optimal
// constant displacement is the exact box average of that cosine over the
// represented x/z footprint. The sinc factors below are that analytic integral;
// no distance threshold or fitted attenuation is used.

const uint SDV_VERTEX_WATER_BLOCK_ID = 11102u;
const float SDV_WATER_WAVE_AMPLITUDE_BLOCKS = 0.05;

float sdvSinc(float value) {
    return abs(value) < 1e-4 ? 1.0 : sin(value) / value;
}

vec3 voxy_transformVertex(VoxyVertexParameters parameters) {
    if (parameters.customId != SDV_VERTEX_WATER_BLOCK_ID) {
        return parameters.position;
    }

    #ifdef WATER_ANIMATION
    if (CURRENT_SPEED > 0) {
        vec2 quadDelta = parameters.quadMax.xz - parameters.quadMin.xz;
        vec2 phaseHalfExtent = quadDelta * (CURRENT_FREQUENCY * 0.5);

        vec2 quadSum = parameters.quadMin.xz + parameters.quadMax.xz;
        float centerCoordSum = (quadSum.x + quadSum.y) * 0.5
            + float(baseSectionPos.x + baseSectionPos.z) * 32.0;

        float boxFilteredStrength = cos(
            -centerCoordSum * CURRENT_FREQUENCY
            + vertexFrameTime * CURRENT_SPEED
        ) * sdvSinc(phaseHalfExtent.x) * sdvSinc(phaseHalfExtent.y);

        parameters.position.y += boxFilteredStrength
            * SDV_WATER_WAVE_AMPLITUDE_BLOCKS;
    }
    #endif

    return parameters.position;
}
