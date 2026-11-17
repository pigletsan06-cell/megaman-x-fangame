shader_type canvas_item;
// tela de seleção: retratos dos chefes vencidos em cinza (donos = qual retrato cobre cada pixel)
uniform sampler2D donos : filter_nearest;
uniform int vencidos = 0;
void fragment() {
	vec4 c = texture(TEXTURE, UV);
	int o = int(texture(donos, UV).r * 255.0 + 0.5);
	if (o < 8 && ((vencidos >> o) & 1) == 1) {
		float l = dot(c.rgb, vec3(0.3, 0.59, 0.11));
		c.rgb = vec3(l * 0.62);
	}
	COLOR = c;
}
