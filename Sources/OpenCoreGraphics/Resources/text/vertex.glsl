#version 330 core
layout(location = 0) in vec2 aPosition;
layout(location = 1) in vec2 aTextureCoordinate;

uniform mat4 uProjection;

out vec2 vTextureCoordinate;

void main() {
    gl_Position = uProjection * vec4(aPosition, 0.0, 1.0);
    vTextureCoordinate = aTextureCoordinate;
}
