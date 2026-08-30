// Adapted from Hei's MIT-licensed 2D Perspective shader:
// https://godotshaders.com/shader/2d-perspective/
shader_type canvas_item;

uniform float fov : hint_range(1.0, 179.0) = 70.0;
uniform float y_rot : hint_range(-20.0, 20.0) = 0.0;
uniform float x_rot : hint_range(-20.0, 20.0) = 0.0;
uniform float inset : hint_range(0.0, 1.0) = 0.12;
uniform vec2 rect_size = vec2(100.0, 140.0);

varying flat vec2 perspective_offset;
varying vec3 perspective_position;

const float CARD_PI = 3.14159265;

void vertex() {
	float sin_y = sin(y_rot / 180.0 * CARD_PI);
	float cos_y = cos(y_rot / 180.0 * CARD_PI);
	float sin_x = sin(x_rot / 180.0 * CARD_PI);
	float cos_x = cos(x_rot / 180.0 * CARD_PI);
	mat3 inverse_rotation;
	inverse_rotation[0] = vec3(cos_y, 0.0, -sin_y);
	inverse_rotation[1] = vec3(sin_y * sin_x, cos_x, cos_y * sin_x);
	inverse_rotation[2] = vec3(sin_y * cos_x, -sin_x, cos_y * cos_x);

	float tangent = tan(fov / 360.0 * CARD_PI);
	perspective_position = inverse_rotation * vec3(UV - 0.5, 0.5 / tangent);
	float view_scale = (0.5 / tangent) + 0.5;
	perspective_position.xy *= view_scale * inverse_rotation[2].z;
	perspective_offset = view_scale * inverse_rotation[2].xy;
	VERTEX += (UV - 0.5) * rect_size * tangent * (1.0 - inset);
}

void fragment() {
	if (perspective_position.z <= 0.0) {
		discard;
	}
	vec2 perspective_uv = perspective_position.xy / perspective_position.z - perspective_offset;
	COLOR = texture(TEXTURE, perspective_uv + 0.5);
	COLOR.a *= step(max(abs(perspective_uv.x), abs(perspective_uv.y)), 0.5);
}
