#version 330

in vec2 fragTexCoord;
in vec4 fragColor;

uniform sampler2D texture0;
uniform float time;

out vec4 finalColor;

float disp = 0.05;

void main() {
    vec2 diff = vec2(cos(time), sin(time))*disp;
    finalColor = texture(texture0, fragTexCoord+diff);
}
