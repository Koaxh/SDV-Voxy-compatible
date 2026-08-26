#ifndef SDV_VOXY_PROJECTION_FUNCTIONS
#define SDV_VOXY_PROJECTION_FUNCTIONS

// Voxy follows the clip-depth convention selected by Minecraft's device.
// XY is always mapped between NDC and screen space; Z is already [0, 1]
// when ARB_clip_control is active and must not be remapped a second time.
float getVoxyNdcDepth(in float screenDepth) {
    return vxDepthZeroToOne != 0
        ? screenDepth
        : screenDepth * 2.0 - 1.0;
}

vec3 getVoxyNdcPos(in vec3 screenPos) {
    return vec3(
        screenPos.xy * 2.0 - 1.0,
        getVoxyNdcDepth(screenPos.z)
    );
}

vec3 getVoxyScreenPos(in vec4 clipPos) {
    vec3 ndcPos = clipPos.xyz / clipPos.w;
    return vec3(
        ndcPos.xy * 0.5 + 0.5,
        vxDepthZeroToOne != 0 ? ndcPos.z : ndcPos.z * 0.5 + 0.5
    );
}

vec3 getVoxyViewPos(in mat4 projectionInverse, in vec3 screenPos) {
    vec4 viewPos = projectionInverse * vec4(getVoxyNdcPos(screenPos), 1.0);
    return viewPos.xyz / viewPos.w;
}

#endif
