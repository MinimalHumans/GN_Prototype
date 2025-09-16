shader_type canvas_item;

// === BASE 3D FORM ===
uniform float asteroid_radius : hint_range(0.1, 0.8) = 0.6;
uniform vec2 shape_scale = vec2(1.0, 0.8); // Non-uniform scaling
uniform float base_shape_seed : hint_range(0.0, 1000.0) = 42.0;

// === CELL NOISE WARP ===
uniform float warp_scale : hint_range(1.0, 15.0) = 4.0;
uniform float warp_amount : hint_range(0.0, 1.0) = 0.5;
uniform float warp_octaves : hint_range(1.0, 6.0) = 3.0;
uniform float warp_softening : hint_range(0.0, 1.0) = 0.6;
uniform float warp_smoothing : hint_range(0.0, 1.0) = 0.7;
uniform float warp_seed : hint_range(0.0, 1000.0) = 100.0;
uniform vec2 warp_offset = vec2(0.0);

// === SCULPTED FORM ===
uniform float sculpt_scale : hint_range(1.0, 8.0) = 3.0;
uniform float sculpt_strength : hint_range(0.0, 1.0) = 0.6;
uniform float sculpt_smoothing : hint_range(0.1, 1.0) = 0.7;

// === DETAIL NOISE LAYERS ===
uniform float detail_scale_1 : hint_range(5.0, 30.0) = 12.0;
uniform float detail_strength_1 : hint_range(0.0, 1.0) = 0.4;
uniform float detail_scale_2 : hint_range(10.0, 60.0) = 25.0;
uniform float detail_strength_2 : hint_range(0.0, 1.0) = 0.2;

// === DETAIL MASKING ===
uniform float mask_scale : hint_range(2.0, 15.0) = 6.0;
uniform float smooth_areas : hint_range(0.0, 1.0) = 0.6; // How much of surface is smooth
uniform float rough_areas : hint_range(0.0, 1.0) = 0.8; // How rough the rough areas are

// === MATERIAL ===
uniform vec3 base_color : source_color = vec3(0.3, 0.25, 0.2);
uniform vec3 highlight_color : source_color = vec3(0.5, 0.4, 0.3);
uniform float color_variation : hint_range(0.0, 1.0) = 0.3;

// === LIGHTING ===
uniform float sun_angle : hint_range(0.0, 360.0) = 135.0;
uniform float sun_elevation : hint_range(-45.0, 90.0) = 45.0;
uniform float sun_intensity : hint_range(0.0, 3.0) = 1.5;
uniform float ambient_light : hint_range(0.0, 1.0) = 0.25;
uniform vec3 ambient_color : source_color = vec3(0.2, 0.25, 0.35);

// === HASH FUNCTIONS ===
vec3 hash3_cell(vec2 p, float seed) {
    vec3 q = vec3(dot(p, vec2(127.1, 311.7)),
                  dot(p, vec2(269.5, 183.3)),
                  dot(p, vec2(419.2, 371.9)));
    q += seed;
    return fract(sin(q) * 43758.5453);
}

vec2 hash2_regular(vec2 p, float seed) {
    p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3))) + seed;
    return fract(sin(p) * 43758.5453);
}

// === CELL NOISE FUNCTIONS ===
float cell_noise(vec2 p, float seed) {
    vec2 grid_id = floor(p);
    vec2 grid_pos = fract(p);

    float min_dist = 10.0;

    for(int x = -1; x <= 1; x++) {
        for(int y = -1; y <= 1; y++) {
            vec2 neighbor = vec2(float(x), float(y));
            vec2 point_id = grid_id + neighbor;

            vec3 random_data = hash3_cell(point_id, seed);
            vec2 point_offset = random_data.xy;

            vec2 point_pos = neighbor + point_offset;
            vec2 diff = grid_pos - point_pos;
            float dist = length(diff);

            min_dist = min(min_dist, dist);
        }
    }

    return min_dist;
}

float cell_fbm(vec2 p, int octaves, float seed) {
    float value = 0.0;
    float amplitude = 1.0;
    float frequency = 1.0;
    float max_value = 0.0;

    for (int i = 0; i < octaves; i++) {
        value += amplitude * cell_noise(p * frequency, seed);
        max_value += amplitude;
        amplitude *= 0.5;
        frequency *= 2.0;
        seed += 100.0;
    }

    return value / max_value;
}

vec2 create_cell_warp(vec2 uv) {
    vec2 warp_uv = uv + warp_offset;

    float warp_x = cell_fbm(warp_uv * warp_scale, int(warp_octaves), warp_seed);
    float warp_y = cell_fbm(warp_uv * warp_scale + vec2(123.4, 567.8), int(warp_octaves), warp_seed + 50.0);

    warp_x = mix(0.5, warp_x, warp_softening);
    warp_y = mix(0.5, warp_y, warp_softening);

    warp_x = smoothstep(0.0, 1.0, warp_x);
    warp_y = smoothstep(0.0, 1.0, warp_y);

    vec2 displacement = vec2(warp_x - 0.5, warp_y - 0.5) * warp_amount;

    return uv + displacement;
}

// === REGULAR NOISE FUNCTIONS ===
float perlin_noise(vec2 p, float seed) {
    vec2 i = floor(p);
    vec2 f = fract(p);

    vec2 u = f * f * (3.0 - 2.0 * f);

    vec2 ga = hash2_regular(i + vec2(0.0, 0.0), seed) * 2.0 - 1.0;
    vec2 gb = hash2_regular(i + vec2(1.0, 0.0), seed) * 2.0 - 1.0;
    vec2 gc = hash2_regular(i + vec2(0.0, 1.0), seed) * 2.0 - 1.0;
    vec2 gd = hash2_regular(i + vec2(1.0, 1.0), seed) * 2.0 - 1.0;

    float va = dot(ga, f - vec2(0.0, 0.0));
    float vb = dot(gb, f - vec2(1.0, 0.0));
    float vc = dot(gc, f - vec2(0.0, 1.0));
    float vd = dot(gd, f - vec2(1.0, 1.0));

    return mix(mix(va, vb, u.x), mix(vc, vd, u.x), u.y) * 0.5 + 0.5;
}

float fbm(vec2 p, int octaves, float seed) {
    float value = 0.0;
    float amplitude = 1.0;
    float frequency = 1.0;
    float max_value = 0.0;

    for (int i = 0; i < octaves; i++) {
        value += amplitude * perlin_noise(p * frequency, seed);
        max_value += amplitude;
        amplitude *= 0.5;
        frequency *= 2.0;
        seed += 100.0;
    }

    return value / max_value;
}

// === STEP 1: BASE SPHERE WITH NON-UNIFORM SCALING ===
float create_base_sphere(vec2 uv) {
    vec2 centered = (uv - 0.5) * 2.0;

    centered.x /= shape_scale.x;
    centered.y /= shape_scale.y;

    float dist = length(centered);
    return 1.0 - smoothstep(asteroid_radius - 0.05, asteroid_radius, dist);
}

// === STEP 2: APPLY CELL NOISE WARP ===
float apply_cell_warp(vec2 uv, float base_mask) {
    if (base_mask < 0.01) return 0.0;

    vec2 warped_uv = create_cell_warp(uv);

    vec2 centered = (warped_uv - 0.5) * 2.0;
    centered.x /= shape_scale.x;
    centered.y /= shape_scale.y;

    float dist = length(centered);
    float warped_mask = 1.0 - smoothstep(asteroid_radius - 0.02, asteroid_radius, dist);

    // Create sharp transition instead of soft blend
    return step(0.5, mix(base_mask, warped_mask, 0.8));
}

// === STEP 3: SCULPTED FORM ===
float create_sculpted_form(vec2 uv, float warped_mask) {
    if (warped_mask < 0.01) return 0.0;

    vec2 warped_uv = create_cell_warp(uv);

    float sculpt_noise = fbm(warped_uv * sculpt_scale, 4, base_shape_seed + 100.0);

    float sculpt_variation = (sculpt_noise - 0.5) * sculpt_strength;
    sculpt_variation = mix(sculpt_variation, 0.0, 1.0 - sculpt_smoothing);

    float sculpted_result = warped_mask + sculpt_variation * warped_mask;

    // Create sharp edges by using step function instead of smooth gradient
    return step(0.1, sculpted_result);
}

// === STEP 4: CALCULATE 3D HEIGHT FROM SCULPTED FORM ===
float calculate_3d_height(vec2 uv, float sculpted_mask) {
    if (sculpted_mask < 0.01) return 0.0;

    vec2 centered = (uv - 0.5) * 2.0;
    centered.x /= shape_scale.x;
    centered.y /= shape_scale.y;

    float dist = length(centered);

    // Only use sphere calculation within the actual sculpted shape
    // No circular falloff beyond the irregular boundary
    float sphere_z = sqrt(max(0.0, asteroid_radius * asteroid_radius - dist * dist));
    float normalized_height = sphere_z / asteroid_radius;

    // Height is only where the sculpted mask exists, no circular gradient
    return normalized_height * step(0.01, sculpted_mask);
}

// === STEP 5: ADD DETAIL NOISE WITH MASKING ===
float add_surface_details(vec2 uv, float base_height, float sculpted_mask) {
    if (sculpted_mask < 0.01) return base_height;

    vec2 warped_uv = create_cell_warp(uv);

    float detail_mask = fbm(warped_uv * mask_scale, 3, base_shape_seed + 200.0);
    float smooth_mask = smoothstep(smooth_areas - 0.1, smooth_areas + 0.1, detail_mask);

    float detail1 = fbm(warped_uv * detail_scale_1, 4, base_shape_seed + 300.0);
    detail1 = (detail1 - 0.5) * detail_strength_1;

    float detail2 = fbm(warped_uv * detail_scale_2, 3, base_shape_seed + 400.0);
    detail2 = (detail2 - 0.5) * detail_strength_2;

    float combined_detail = detail1 + detail2 * 0.5;

    float masked_detail = combined_detail * mix(0.2, rough_areas, smooth_mask);

    masked_detail *= base_height;

    return base_height + masked_detail;
}

// === SURFACE NORMAL CALCULATION ===
vec3 calculate_surface_normal(vec2 uv, float sculpted_mask) {
    if (sculpted_mask < 0.01) return vec3(0.0, 0.0, 1.0);

    float offset = 0.008;

    float base_height = calculate_3d_height(uv, sculpted_mask);
    float center_height = add_surface_details(uv, base_height, sculpted_mask);

    float warped_right = apply_cell_warp(uv + vec2(offset, 0.0),
                                        create_base_sphere(uv + vec2(offset, 0.0)));
    float sculpted_right = create_sculpted_form(uv + vec2(offset, 0.0), warped_right);
    float base_height_right = calculate_3d_height(uv + vec2(offset, 0.0), sculpted_right);
    float right_height = add_surface_details(uv + vec2(offset, 0.0), base_height_right, sculpted_right);

    float warped_up = apply_cell_warp(uv + vec2(0.0, offset),
                                     create_base_sphere(uv + vec2(0.0, offset)));
    float sculpted_up = create_sculpted_form(uv + vec2(0.0, offset), warped_up);
    float base_height_up = calculate_3d_height(uv + vec2(0.0, offset), sculpted_up);
    float up_height = add_surface_details(uv + vec2(0.0, offset), base_height_up, sculpted_up);

    vec2 gradient = vec2(
        (right_height - center_height) / offset,
        (up_height - center_height) / offset
    );

    vec3 normal = normalize(vec3(-gradient.x, -gradient.y, 1.0));
    return normal;
}

// === LIGHTING ===
vec3 calculate_lighting(vec3 surface_normal, vec3 surface_color) {
    float sun_rad = radians(sun_angle);
    float elev_rad = radians(sun_elevation);
    vec3 sun_direction = normalize(vec3(
        cos(elev_rad) * cos(sun_rad),
        cos(elev_rad) * sin(sun_rad),
        sin(elev_rad)
    ));

    float diffuse = max(dot(surface_normal, sun_direction), 0.0);

    vec3 diffuse_contribution = surface_color * diffuse * sun_intensity;
    vec3 ambient_contribution = surface_color * ambient_color * ambient_light;

    return diffuse_contribution + ambient_contribution;
}

void fragment() {
    vec2 uv = UV;

    float base_sphere = create_base_sphere(uv);
    float warped_shape = apply_cell_warp(uv, base_sphere);
    float sculpted_form = create_sculpted_form(uv, warped_shape);

    vec3 final_color = vec3(0.0);
    float final_alpha = sculpted_form;

    if (sculpted_form > 0.01) {
        float base_3d_height = calculate_3d_height(uv, sculpted_form);
        float final_height = add_surface_details(uv, base_3d_height, sculpted_form);

        vec3 surface_normal = calculate_surface_normal(uv, sculpted_form);

        // Create surface color variation - no height-based darkening
        float color_noise = fbm(uv * 15.0, 3, base_shape_seed + 500.0);
        vec3 surface_color = mix(base_color, highlight_color, final_height * 0.4);

        // Add subtle color variation
        surface_color = mix(surface_color, base_color * 1.1, color_noise * color_variation);

        final_color = calculate_lighting(surface_normal, surface_color);
    }

    COLOR = vec4(final_color, final_alpha);
}