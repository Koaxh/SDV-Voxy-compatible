#ifndef SDV_VOXY_PROJECTION_FUNCTIONS
#define SDV_VOXY_PROJECTION_FUNCTIONS

// Infer the clip-depth convention from the projection itself. The marker in
// colortex17 is shared by opaque, translucent and native-water draws and can
// be overwritten before a post pass consumes it. When that happens a 0..1
// Voxy depth is treated as -1..1, shortening every reconstructed LoD ray.
// Voxy chooses an 8-block near plane at a vanilla distance <= 2 chunks and a
// 16-block near plane otherwise; compare both matrix interpretations against
// that actual rule instead of trusting the shared attachment.
bool getVoxyProjectionZeroToOne(
    in mat4 projection,
    in float vanillaRenderDistance
) {
    float projectionA = projection[2][2];
    float projectionB = projection[3][2];
    float expectedNear = vanillaRenderDistance <= 32.0001 ? 8.0 : 16.0;

    float standardNear = abs(
        projectionB / min(projectionA - 1.0, -0.000001)
    );
    float zeroToOneNear = abs(
        projectionB / min(projectionA, -0.000001)
    );
    return abs(zeroToOneNear - expectedNear)
        < abs(standardNear - expectedNear);
}

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
    float ndcDepth = vxDepthZeroToOne != 0 ? screenPos.z : screenPos.z * 2.0 - 1.0;
    float invW = 1.0 / (ndcDepth * projectionInverse[2][3] + projectionInverse[3][3]);
    vec2 ndcXY = screenPos.xy * 2.0 - 1.0;
    return vec3(
        (ndcXY * vec2(projectionInverse[0][0], projectionInverse[1][1]) + projectionInverse[3].xy) * invW,
        -invW
    );
}

float getVoxyViewDepth(in mat4 projectionInverse, in float screenDepth) {
    float ndcDepth = vxDepthZeroToOne != 0 ? screenDepth : screenDepth * 2.0 - 1.0;
    return -1.0 / (ndcDepth * projectionInverse[2][3] + projectionInverse[3][3]);
}

#endif
