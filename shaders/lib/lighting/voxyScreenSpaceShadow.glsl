// Photon-style projected screen-space shadows cast by Voxy LOD geometry.
// deferred1 writes the current result to colortex18; vanilla and Voxy
// receivers consume the reprojected result on the following frame.

// Keep Photon's default sample budget internal. The geometric distribution
// covers the visible ray without exposing a world-space step/range setting.
const int VOXY_SSRT_SAMPLE_COUNT = 10;
const float VOXY_SSRT_SAMPLE_RATIO = 2.0;
const float VOXY_SSRT_DEPTH_TOLERANCE = 10.0;
const float VOXY_SSRT_DIRECTION_JITTER = 0.03;

float getVoxyLinearDepth(in float depth) {
    depth = getVoxyNdcDepth(depth);
    vec2 zw = depth * vxProjInv[2].zw + vxProjInv[3].zw;
    return -zw.x / zw.y;
}

bool isVoxySsrtScreenPositionValid(in vec3 screenPosition) {
    return all(greaterThanEqual(screenPosition, vec3(0.0)))
        && all(lessThanEqual(screenPosition, vec3(1.0)));
}

float getVoxySsrtViewportRayLength(
    in vec3 rayOriginScreen,
    in vec3 rayDirectionScreen
) {
    // Distance to x/y/z viewport boundaries in the direction of travel.
    // This is the robust [0,1] equivalent of Photon's sign-based bound.
    vec3 distanceToEdge = mix(
        rayOriginScreen,
        vec3(1.0) - rayOriginScreen,
        step(vec3(0.0), rayDirectionScreen)
    ) / max(abs(rayDirectionScreen), vec3(1e-6));
    return min(distanceToEdge.x, min(distanceToEdge.y, distanceToEdge.z));
}

bool isVoxySsrtOccluder(in vec3 rayPositionScreen) {
    ivec2 depthSize = textureSize(vxDepthTexOpaque, 0);
    ivec2 depthTexel = clamp(
        ivec2(rayPositionScreen.xy * vec2(depthSize)),
        ivec2(0),
        depthSize - 1
    );
    float casterDepth = texelFetch(vxDepthTexOpaque, depthTexel, 0).r;
    if (casterDepth >= 1.0 || casterDepth >= rayPositionScreen.z) return false;

    float rayDepthLinear = getVoxyLinearDepth(rayPositionScreen.z);
    float casterDepthLinear = getVoxyLinearDepth(casterDepth);
    float depthDelta = rayDepthLinear - casterDepthLinear;

    // Match Photon's SSRT slab test. A sampled surface must be in front of
    // the ray and within the 20-block interval centred on the tolerance.
    return abs(VOXY_SSRT_DEPTH_TOLERANCE - depthDelta)
        < VOXY_SSRT_DEPTH_TOLERANCE;
}

float getVoxySsrtShadow(
    in vec3 receiverViewPosition,
    in vec3 lightDirectionView,
    in vec3 dither
) {
    // Photon perturbs the celestial ray slightly and lets temporal filtering
    // turn the binary SSRT result into a stable soft edge.
    vec3 rayDirectionView = normalize(
        lightDirectionView
        + VOXY_SSRT_DIRECTION_JITTER * generateUnitVector(dither.xy)
    );

    vec4 rayOriginClip = vxProj * vec4(receiverViewPosition, 1.0);
    vec4 rayTargetClip = vxProj
        * vec4(receiverViewPosition + rayDirectionView, 1.0);
    if (rayOriginClip.w <= 0.0 || rayTargetClip.w <= 0.0) return 1.0;

    vec3 rayOriginScreen = getVoxyScreenPos(rayOriginClip);
    if (!isVoxySsrtScreenPositionValid(rayOriginScreen)) return 1.0;

    vec3 projectedDirection = getVoxyScreenPos(rayTargetClip)
        - rayOriginScreen;
    float projectedLengthSquared = dot(projectedDirection, projectedDirection);
    if (projectedLengthSquared <= 1e-10) return 1.0;
    vec3 rayDirectionScreen = projectedDirection
        * inversesqrt(projectedLengthSquared);

    float rayLength = getVoxySsrtViewportRayLength(
        rayOriginScreen,
        rayDirectionScreen
    );
    rayLength = min(
        rayLength,
        max(
            0.1,
            exp(-max(length(receiverViewPosition) * 0.025 - 1.0, 0.0))
        )
    );
    if (rayLength <= 0.0) return 1.0;

    const float initialStepScale = (VOXY_SSRT_SAMPLE_RATIO - 1.0)
        / (pow(
            VOXY_SSRT_SAMPLE_RATIO,
            float(VOXY_SSRT_SAMPLE_COUNT)
        ) - 1.0);
    float stepLength = rayLength * initialStepScale;

    vec2 pixelSize = 1.0 / vec2(textureSize(vxDepthTexOpaque, 0));
    vec3 rayPosition = rayOriginScreen
        + length(pixelSize) * rayDirectionScreen;

    #if ANTI_ALIASING >= 2
        float sampleDither = fract(
            dither.z + float(frameCounter) * 0.61803398875
        );
    #else
        float sampleDither = dither.z;
    #endif

    for (int i = 0; i < VOXY_SSRT_SAMPLE_COUNT; ++i) {
        // This ordering intentionally follows Photon: each interval is twice
        // the previous one, concentrating work around the receiver while the
        // final samples cover the rest of the visible projected ray.
        stepLength *= VOXY_SSRT_SAMPLE_RATIO;
        vec3 rayStep = rayDirectionScreen * stepLength;
        vec3 samplePosition = rayPosition + sampleDither * rayStep;
        rayPosition += rayStep;

        if (!isVoxySsrtScreenPositionValid(samplePosition)) break;
        if (isVoxySsrtOccluder(samplePosition)) return 0.0;
    }

    return 1.0;
}
