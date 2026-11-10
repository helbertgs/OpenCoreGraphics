#version 330 core

layout(location = 0) in vec2 aPosition;
uniform mat4 uProjection;
out vec2 vPosition;

void main() {
    gl_Position = uProjection * vec4(aPosition, 0.0, 1.0);
    vPosition = aPosition;
}
