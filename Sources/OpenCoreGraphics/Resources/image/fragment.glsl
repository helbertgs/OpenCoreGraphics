#version 330 core

in vec2 vTextureCoordinate;
out vec4 FragColor;
uniform sampler2D uImage;

void main() {
    FragColor = texture(uImage, vTextureCoordinate);
}
