#version 330 core

const int MAX_COLOR_STOPS = 128;

in vec2 vPosition;
out vec4 FragColor;
uniform int uKind;
uniform vec2 uStart;
uniform vec2 uEnd;
uniform float uStartRadius;
uniform float uEndRadius;
uniform int uDrawsBeforeStart;
uniform int uDrawsAfterEnd;
uniform int uStopCount;
uniform vec4 uColors[MAX_COLOR_STOPS];
uniform float uLocations[MAX_COLOR_STOPS];

float linearPosition() {
    vec2 axis = uEnd - uStart;
    float lengthSquared = dot(axis, axis);
    return lengthSquared > 0.0 ? dot(vPosition - uStart, axis) / lengthSquared : 0.0;
}

float radialPosition() {
    vec2 axis = uEnd - uStart;
    vec2 point = vPosition - uStart;
    float radiusDelta = uEndRadius - uStartRadius;
    float a = dot(axis, axis) - radiusDelta * radiusDelta;
    float b = -2.0 * (dot(point, axis) + uStartRadius * radiusDelta);
    float c = dot(point, point) - uStartRadius * uStartRadius;

    if (abs(a) < 0.000001) {
        if (abs(b) < 0.000001) {
            return abs(c) < 0.000001 ? 0.0 : -1.0e30;
        }
        return -c / b;
    }

    float discriminant = b * b - 4.0 * a * c;
    if (discriminant < 0.0) {
        return -1.0e30;
    }
    float root = sqrt(discriminant);
    return max((-b - root) / (2.0 * a), (-b + root) / (2.0 * a));
}

vec4 colorAt(float position) {
    if (position < uLocations[0]) {
        return uDrawsBeforeStart == 1 ? uColors[0] : vec4(0.0);
    }
    if (position > uLocations[uStopCount - 1]) {
        return uDrawsAfterEnd == 1 ? uColors[uStopCount - 1] : vec4(0.0);
    }

    for (int index = 1; index < MAX_COLOR_STOPS; ++index) {
        if (index >= uStopCount) {
            break;
        }
        float upperLocation = uLocations[index];
        if (position <= upperLocation) {
            float lowerLocation = uLocations[index - 1];
            float stopSpan = upperLocation - lowerLocation;
            float fraction = stopSpan > 0.0 ? (position - lowerLocation) / stopSpan : 1.0;
            return mix(uColors[index - 1], uColors[index], fraction);
        }
    }
    return uColors[uStopCount - 1];
}

void main() {
    float position = uKind == 0 ? linearPosition() : radialPosition();
    if (position < -1.0e20
        || (position < uLocations[0] && uDrawsBeforeStart == 0)
        || (position > uLocations[uStopCount - 1] && uDrawsAfterEnd == 0)) {
        discard;
    }
    FragColor = colorAt(position);
}
