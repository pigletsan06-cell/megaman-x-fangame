shader_type canvas_item;
varying vec4 c0;
varying vec2 tuv;
void vertex() { c0 = CUSTOM0; tuv = UV; }
void fragment() { COLOR = vec4(c0.x / 255.0, tuv.x / 100.0, c0.w / 255.0, 1.0); }
