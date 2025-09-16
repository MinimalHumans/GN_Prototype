shader_type canvas_item;

// Shape Controls
uniform float asteroid_size : hint_range(0.1, 1.0) = 0.8;
uniform float edge_smoothness : hint_range(0.001, 0.1) = 0.02;
uniform float shape_distortion : hint_range(0.0, 0.5) = 0.15;
uniform float shape_distortion_scale : hint_range(1.0, 20.0) = 6.0;
uniform vec2 shape_distortion_offset = vec2(0.0);

// Overall Shape Warp (separate from edge distortion)
uniform float overall_warp_amount : hint_range(0.0, 1.0) = 0.0;
uniform float overall_warp_scale : hint_range(1.0, 20.0) = 3.0;
uniform vec2 overall_warp_offset = vec2(0.0);

// Base Color Controls
uniform vec3 base_color : source_color = vec3(0.4, 0.35, 0.3);
uniform float color_variation : hint_range(0.0, 1.0) = 0.3;
uniform vec3 dark_color : source_color = vec3(0.2, 0.15, 0.1);

// Surface Detail Controls
uniform float surface_roughness : hint_range(0.0, 2.0) = 1.0;
uniform float crater_depth : hint_range(0.0, 1.0) = 0.6;
uniform float detail_strength : hint_range(0.0, 1.0) = 0.4;

// Realistic Crater Controls
uniform float crater_density : hint_range(1.0, 20.0) = 8.0;
uniform float crater_size_min : hint_range(0.01, 0.2) = 0.03;
uniform float crater_size_max : hint_range(0.1, 0.5) = 0.15;
uniform float crater_depth_variation : hint_range(0.1, 2.0) = 0.8;
uniform float crater_rim_height : hint_range(0.0, 1.0) = 0.4;
uniform float crater_rim_width : hint_range(0.1, 0.5) = 0.15;
uniform float large_crater_probability : hint_range(0.0, 1.0) = 0.3;
uniform float crater_clustering : hint_range(0.0, 1.0) = 0.6;
uniform float crater_shape_noise : hint_range(0.0, 1.0) = 0.3;
uniform float crater_edge_blend : hint_range(0.1, 2.0) = 0.8;

// Noise Scale Controls
uniform float large_feature_scale : hint_range(1.0, 20.0) = 4.0;
uniform float medium_detail_scale : hint_range(5.0, 50.0) = 15.0;
uniform float fine_detail_scale : hint_range(10.0, 100.0) = 35.0;

// Noise offset controls
uniform vec2 large_feature_offset = vec2(0.0);
uniform vec2 medium_detail_offset = vec2(0.0);
uniform vec2 fine_detail_offset = vec2(0.0);

// Enhanced Lighting Controls
uniform float sun_angle : hint_range(0.0, 360.0) = 135.0;
uniform float sun_elevation : hint_range(-90.0, 90.0) = 30.0;
uniform float sun_intensity : hint_range(0.0, 3.0) = 1.2;
uniform float ambient_light : hint_range(0.0, 1.0) = 0.3;
uniform vec3 ambient_color : source_color = vec3(0.2, 0.25, 0.4);
uniform float shadow_opacity : hint_range(0.0, 1.0) = 0.7;

// Surface Normal Controls
uniform float normal_strength : hint_range(0.0, 3.0) = 1.0;
uniform float surface_contrast : hint_range(0.5, 2.0) = 1.2;
uniform float crater_shadow_strength : hint_range(0.0, 2.0) = 0.8;

// Hash functions
vec2 hash2(vec2 p) {
    p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
    return fract(sin(p) * 43758.5453);
}

vec3 hash3(vec2 p) {
    vec3 q = vec3(dot(p, vec2(127.1, 311.7)),
                  dot(p, vec2(269.5, 183.3)),
                  dot(p, vec2(419.2, 371.9)));
    return fract(sin(q) * 43758.5453);
}

// Main noise function
float perlin_noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);

    // Quintic interpolation for smoother results
    vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);

    // Get gradient vectors for each corner
    vec2 ga = hash2(i + vec2(0.0, 0.0)) * 2.0 - 1.0;
    vec2 gb = hash2(i + vec2(1.0, 0.0)) * 2.0 - 1.0;
    vec2 gc = hash2(i + vec2(0.0, 1.0)) * 2.0 - 1.0;
    vec2 gd = hash2(i + vec2(1.0, 1.0)) * 2.0 - 1.0;

    // Calculate dot products
    float va = dot(ga, f - vec2(0.0, 0.0));
    float vb = dot(gb, f - vec2(1.0, 0.0));
    float vc = dot(gc, f - vec2(0.0, 1.0));
    float vd = dot(gd, f - vec2(1.0, 1.0));

    // Interpolate
    return mix(mix(va, vb, u.x), mix(vc, vd, u.x), u.y) * 0.5 + 0.5;
}

// Fractional Brownian Motion
float fbm(vec2 p, int octaves, float lacunarity, float gain) {
    float value = 0.0;
    float amplitude = 1.0;
    float frequency = 1.0;
    float max_value = 0.0;

    for (int i = 0; i < octaves; i++) {
        value += amplitude * perlin_noise(p * frequency);
        max_value += amplitude;
        amplitude *= gain;
        frequency *= lacunarity;
    }

    return value / max_value;
}

// Convert UV to sphere coordinates
vec3 uv_to_sphere(vec2 uv) {
    vec2 centered = (uv - 0.5) * 2.0;
    float dist = length(centered);

    if (dist > 1.0) {
        return vec3(0.0, 0.0, -1.0);
    }

    float x = centered.x;
    float y = centered.y;
    float z = sqrt(1.0 - dist * dist);

    return vec3(x, y, z);
}

// Sphere to texture mapping
vec2 sphere_to_texture(vec3 sphere_pos) {
    vec3 abs_pos = abs(sphere_pos);
    float max_axis = max(abs_pos.x, max(abs_pos.y, abs_pos.z));

    vec2 uv;
    if (max_axis == abs_pos.z) {
        uv = vec2(sphere_pos.x, sphere_pos.y) / max_axis;
    } else if (max_axis == abs_pos.x) {
        uv = vec2(sphere_pos.z * sign(sphere_pos.x), sphere_pos.y) / max_axis;
    } else {
        uv = vec2(sphere_pos.x, sphere_pos.z * sign(sphere_pos.y)) / max_axis;
    }

    uv = uv * 0.5 + 0.5;
    return uv;
}

// Generate realistic craters
float generate_craters(vec2 uv, float density, vec2 offset) {
    vec2 grid_uv = (uv + offset) * density;
    vec2 grid_id = floor(grid_uv);
    vec2 grid_pos = fract(grid_uv);

    float crater_effect = 0.0;

    // Check 3x3 grid for overlapping craters
    for(int x = -1; x <= 1; x++) {
        for(int y = -1; y <= 1; y++) {
            vec2 neighbor_id = grid_id + vec2(float(x), float(y));
            vec3 crater_data = hash3(neighbor_id);

            float has_crater = step(0.5, crater_data.x);

            if (has_crater > 0.5) {
                vec2 cluster_offset = (crater_data.yz - 0.5) * crater_clustering;
                vec2 crater_center = vec2(float(x), float(y)) + 0.5 + cluster_offset;

                vec2 to_crater = grid_pos - crater_center;
                float base_dist = length(to_crater);

                // Add shape noise for irregular craters
                float noise_angle = atan(to_crater.y, to_crater.x);
                vec2 noise_coord = crater_center + vec2(cos(noise_angle), sin(noise_angle)) * base_dist * 5.0;
                float shape_noise = fbm(noise_coord * 15.0, 3, 2.0, 0.5);
                float dist = base_dist * (1.0 + (shape_noise - 0.5) * crater_shape_noise);

                // Crater size
                float size_rand = hash3(neighbor_id + vec2(123.4, 567.8)).x;
                float is_large = step(1.0 - large_crater_probability, size_rand);
                float crater_size = mix(crater_size_min, crater_size_max, crater_data.z);
                crater_size *= mix(1.0, 2.5, is_large);

                float crater_depth_local = crater_depth_variation * crater_size * (0.5 + crater_data.y * 0.5);

                float rim_start = crater_size * (1.0 - crater_rim_width);
                float rim_end = crater_size * 1.2;

                if (dist < rim_end) {
                    if (dist < rim_start) {
                        // Inside crater
                        float crater_falloff = 1.0 - smoothstep(0.0, rim_start, dist);
                        crater_falloff = pow(crater_falloff, crater_edge_blend);
                        crater_effect -= crater_falloff * crater_depth_local;
                    } else {
                        // Crater rim
                        float rim_falloff = 1.0 - smoothstep(rim_start, rim_end, dist);
                        rim_falloff = smoothstep(0.0, 1.0, rim_falloff);
                        rim_falloff = pow(rim_falloff, crater_edge_blend * 0.5);
                        float rim_height_local = crater_rim_height * crater_size * 0.5;
                        crater_effect += rim_falloff * rim_height_local;
                    }
                }
            }
        }
    }

    return crater_effect;
}

// Calculate surface normal from height map
vec3 calculate_surface_normal(vec2 tex_uv, float current_height) {
    float offset = 0.01;

    // Sample neighboring heights for normal calculation
    float height_right = current_height;
    float height_up = current_height;

    // Get height samples (simplified for performance)
    vec2 right_uv = tex_uv + vec2(offset, 0.0);
    vec2 up_uv = tex_uv + vec2(0.0, offset);

    // Calculate basic surface features for neighbors
    float large_r = fbm(right_uv * large_feature_scale + large_feature_offset, 4, 2.0, 0.5);
    float medium_r = fbm(right_uv * medium_detail_scale + medium_detail_offset, 5, 2.0, 0.4);
    height_right = large_r * 0.4 + (medium_r - 0.5) * surface_roughness * 0.25;

    float large_u = fbm(up_uv * large_feature_scale + large_feature_offset, 4, 2.0, 0.5);
    float medium_u = fbm(up_uv * medium_detail_scale + medium_detail_offset, 5, 2.0, 0.4);
    height_up = large_u * 0.4 + (medium_u - 0.5) * surface_roughness * 0.25;

    // Calculate gradient
    vec2 gradient = vec2(
        (height_right - current_height) / offset,
        (height_up - current_height) / offset
    ) * normal_strength;

    // Convert gradient to normal (in tangent space)
    vec3 tangent_normal = normalize(vec3(-gradient.x, -gradient.y, 1.0));

    return tangent_normal;
}

// Enhanced lighting calculation
vec3 calculate_lighting(vec3 surface_normal, vec3 view_normal, vec3 surface_color, float surface_height, float crater_shadow) {
    // Convert sun angle to 3D direction
    float sun_rad = radians(sun_angle);
    float elev_rad = radians(sun_elevation);
    vec3 sun_direction = normalize(vec3(
        cos(elev_rad) * cos(sun_rad),
        cos(elev_rad) * sin(sun_rad),
        sin(elev_rad)
    ));

    // Calculate diffuse lighting (Lambertian)
    float diffuse_dot = max(dot(surface_normal, sun_direction), 0.0);

    // Apply crater shadows to diffuse lighting
    diffuse_dot *= (1.0 - crater_shadow * crater_shadow_strength);

    // Calculate shadow factor (how much surface faces away from light)
    float shadow_factor = 1.0 - diffuse_dot;
    shadow_factor = smoothstep(0.2, 0.8, shadow_factor); // Smooth shadow transition

    // Calculate lighting contributions separately
    vec3 diffuse_contribution = surface_color * sun_intensity * diffuse_dot;
    vec3 ambient_contribution = surface_color * ambient_color * ambient_light;

    // Combine diffuse and ambient
    vec3 lit_color = diffuse_contribution + ambient_contribution;

    // Apply shadow tinting (only affects shadowed areas, not highlights)
    lit_color = mix(lit_color, lit_color * ambient_color, shadow_factor * shadow_opacity);

    // Apply contrast enhancement
    lit_color = pow(lit_color, vec3(1.0 / surface_contrast));

    return lit_color;
}

void fragment() {
    vec2 uv = UV;

    vec3 sphere_pos = uv_to_sphere(uv);

    vec3 surface_color = vec3(0.0);
    float alpha = 0.0;

    if (sphere_pos.z >= 0.0) {
        vec2 tex_uv = sphere_to_texture(sphere_pos);

        // Apply overall shape warp
        if (overall_warp_amount > 0.0) {
            vec2 warp_noise_vec = vec2(
                fbm(tex_uv * overall_warp_scale + overall_warp_offset, 4, 2.0, 0.5),
                fbm(tex_uv * overall_warp_scale + overall_warp_offset + vec2(123.4, 567.8), 4, 2.0, 0.5)
            );
            tex_uv += (warp_noise_vec - 0.5) * overall_warp_amount * 0.2;
        }

        float center_dist = length((uv - 0.5) * 2.0);

        // Shape distortion for edges
        float shape_noise = fbm(tex_uv * shape_distortion_scale + shape_distortion_offset, 4, 2.0, 0.5);
        float distorted_radius = asteroid_size + (shape_noise - 0.5) * shape_distortion;

        alpha = 1.0 - smoothstep(distorted_radius - edge_smoothness, distorted_radius + edge_smoothness, center_dist);

        if (alpha > 0.01) {
            // Generate craters with shadow information
            float crater_heights = generate_craters(tex_uv, crater_density, vec2(0.0));
            float small_craters = generate_craters(tex_uv, crater_density * 2.5, vec2(123.45, 678.90)) * 0.4;

            // Calculate crater shadows (areas inside craters get more shadow)
            float crater_shadow = 0.0;
            crater_shadow += max(0.0, -crater_heights) * 2.0; // Main craters cast shadows
            crater_shadow += max(0.0, -small_craters) * 1.5; // Small craters too
            crater_shadow = clamp(crater_shadow, 0.0, 1.0);

            // Generate surface detail
            float large_features = fbm(tex_uv * large_feature_scale + large_feature_offset, 4, 2.0, 0.5);
            float medium_details = fbm(tex_uv * medium_detail_scale + medium_detail_offset, 5, 2.0, 0.4);
            float fine_details = fbm(tex_uv * fine_detail_scale + fine_detail_offset, 6, 2.0, 0.3);

            // Combine surface features
            float surface_height = large_features * 0.4;
            surface_height += (medium_details - 0.5) * surface_roughness * 0.25;
            surface_height += (fine_details - 0.5) * detail_strength * 0.15;

            // Add craters
            surface_height += crater_heights;
            surface_height += small_craters;

            // Legacy crater effect (reduced)
            float legacy_crater_mask = 1.0 - smoothstep(0.3, 0.7, large_features);
            legacy_crater_mask = pow(legacy_crater_mask, 2.0);
            surface_height -= legacy_crater_mask * crater_depth * 0.1;

            surface_height = clamp(surface_height, 0.0, 1.0);

            // Calculate enhanced surface normal
            vec3 surface_normal = calculate_surface_normal(tex_uv, surface_height);

            // Get sphere normal for view calculations
            vec3 sphere_normal = normalize(sphere_pos);

            // Create base color variation
            surface_color = mix(dark_color, base_color, surface_height);

            float color_noise = fbm(tex_uv * 12.0, 3, 2.0, 0.6);
            surface_color = mix(surface_color, base_color, color_noise * color_variation);

            // Apply enhanced lighting with crater shadows
            surface_color = calculate_lighting(surface_normal, sphere_normal, surface_color, surface_height, crater_shadow);
        }
    }

    COLOR = vec4(surface_color, alpha);
}