#version 330 core
in vec2 vTextureCoordinate;

uniform sampler2D uGlyphAtlas;
uniform vec4 uGlyphColor;

out vec4 FragColor;

void main() {
    float coverage = texture(uGlyphAtlas, vTextureCoordinate).r;
    FragColor = uGlyphColor * coverage;
}
