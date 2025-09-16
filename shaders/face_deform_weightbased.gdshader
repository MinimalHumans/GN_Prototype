shader_type canvas_item;

// Control point positions (UV coordinates)
uniform vec2 left_eye_center = vec2(0.35, 0.35);
uniform vec2 right_eye_center = vec2(0.65, 0.35);
uniform vec2 mouth_center = vec2(0.50, 0.70);
uniform vec2 nose_tip = vec2(0.50, 0.55);
uniform vec2 left_ear = vec2(0.10, 0.50);
uniform vec2 right_ear = vec2(0.90, 0.50);

// Control point scales (driven by script)
uniform vec2 left_eye_scale = vec2(1.0, 1.0);
uniform vec2 right_eye_scale = vec2(1.0, 1.0);
uniform vec2 mouth_scale = vec2(1.0, 1.0);
uniform vec2 nose_scale = vec2(1.0, 1.0);
uniform vec2 left_ear_scale = vec2(1.0, 1.0);
uniform vec2 right_ear_scale = vec2(1.0, 1.0);

// Control point translations (driven by script)
uniform vec2 left_eye_translation = vec2(0.0, 0.0);
uniform vec2 right_eye_translation = vec2(0.0, 0.0);
uniform vec2 mouth_translation = vec2(0.0, 0.0);
uniform vec2 nose_translation = vec2(0.0, 0.0);
uniform vec2 left_ear_translation = vec2(0.0, 0.0);
uniform vec2 right_ear_translation = vec2(0.0, 0.0);

// Inner radius - area that gets 100% deformation (protected area)
uniform float eye_inner_radius: hint_range(0.0, 0.2) = 0.04;
uniform float mouth_inner_radius: hint_range(0.0, 0.2) = 0.06;
uniform float nose_inner_radius: hint_range(0.0, 0.2) = 0.02;
uniform float ear_inner_radius: hint_range(0.0, 0.2) = 0.02;

// Outer radius - edge of deformation influence
uniform float eye_outer_radius: hint_range(0.01, 0.3) = 0.12;
uniform float mouth_outer_radius: hint_range(0.01, 0.3) = 0.16;
uniform float nose_outer_radius: hint_range(0.01, 0.3) = 0.08;
uniform float ear_outer_radius: hint_range(0.01, 0.3) = 0.07;

// Falloff curve for the transition zone
uniform float eye_falloff: hint_range(0.5, 5.0) = 2.0;
uniform float mouth_falloff: hint_range(0.5, 5.0) = 2.0;
uniform float nose_falloff: hint_range(0.5, 5.0) = 2.0;
uniform float ear_falloff: hint_range(0.5, 5.0) = 2.0;

// Debug and utility
uniform bool show_control_points = true;
uniform float point_size: hint_range(0.005, 0.05) = 0.015;
uniform bool show_inner_areas = true;
uniform bool show_outer_areas = true;
uniform bool show_blend_weights = false;

// Helper function to calculate influence weight for a control point
float calculate_influence_weight(vec2 uv, vec2 control_pos, float inner_radius, float outer_radius, float falloff) {
    if (outer_radius <= 0.0) return 0.0;

    float dist = distance(uv, control_pos);

    // No influence beyond outer radius
    if (dist > outer_radius) return 0.0;

    // Full influence within inner radius
    if (dist <= inner_radius) return 1.0;

    // Gradual falloff between inner and outer radius
    float transition_zone = outer_radius - inner_radius;
    if (transition_zone > 0.0) {
        float transition_progress = (dist - inner_radius) / transition_zone;
        return 1.0 - pow(transition_progress, falloff);
    }

    return 1.0; // If inner == outer, full influence
}

// Helper function to calculate what a single control point wants to do to a UV coordinate
vec2 calculate_control_point_target(vec2 uv, vec2 control_pos, vec2 scale, vec2 translation) {
    // Calculate what this control point wants the final position to be
    vec2 offset_from_control = uv - control_pos;
    vec2 scaled_offset = offset_from_control * scale;
    vec2 translated_offset = scaled_offset + translation;
    return control_pos + translated_offset;
}

vec2 apply_blended_deformations(vec2 uv) {
    // Step 1: Calculate all influence weights
    float weights[6];
    weights[0] = calculate_influence_weight(uv, left_eye_center, eye_inner_radius, eye_outer_radius, eye_falloff);
    weights[1] = calculate_influence_weight(uv, right_eye_center, eye_inner_radius, eye_outer_radius, eye_falloff);
    weights[2] = calculate_influence_weight(uv, mouth_center, mouth_inner_radius, mouth_outer_radius, mouth_falloff);
    weights[3] = calculate_influence_weight(uv, nose_tip, nose_inner_radius, nose_outer_radius, nose_falloff);
    weights[4] = calculate_influence_weight(uv, left_ear, ear_inner_radius, ear_outer_radius, ear_falloff);
    weights[5] = calculate_influence_weight(uv, right_ear, ear_inner_radius, ear_outer_radius, ear_falloff);

    // Step 2: Calculate total weight
    float total_weight = weights[0] + weights[1] + weights[2] + weights[3] + weights[4] + weights[5];

    // Step 3: If no influences, return original UV
    if (total_weight <= 0.0) return uv;

    // Step 4: Calculate what each control point wants to do
    vec2 targets[6];
    targets[0] = calculate_control_point_target(uv, left_eye_center, left_eye_scale, left_eye_translation);
    targets[1] = calculate_control_point_target(uv, right_eye_center, right_eye_scale, right_eye_translation);
    targets[2] = calculate_control_point_target(uv, mouth_center, mouth_scale, mouth_translation);
    targets[3] = calculate_control_point_target(uv, nose_tip, nose_scale, nose_translation);
    targets[4] = calculate_control_point_target(uv, left_ear, left_ear_scale, left_ear_translation);
    targets[5] = calculate_control_point_target(uv, right_ear, right_ear_scale, right_ear_translation);

    // Step 5: Blend all influences based on normalized weights
    vec2 final_uv = vec2(0.0);
    vec2 uninfluenced_contribution = uv * (1.0 - min(total_weight, 1.0));

    for (int i = 0; i < 6; i++) {
        if (weights[i] > 0.0) {
            float normalized_weight = weights[i] / max(total_weight, 1.0);
            final_uv += targets[i] * normalized_weight;
        }
    }

    // Combine influenced and uninfluenced parts
    return final_uv + uninfluenced_contribution;
}

void fragment() {
    vec2 deformed_uv = apply_blended_deformations(UV);

    // Sample the texture at deformed coordinates
    vec4 tex_color = texture(TEXTURE, deformed_uv);

    // Debug visualization
    if (show_control_points || show_inner_areas || show_outer_areas || show_blend_weights) {
        // Define control points and their properties for debug rendering
        vec2 points[6] = vec2[](left_eye_center, right_eye_center, mouth_center, nose_tip, left_ear, right_ear);
        float inner_radii[6] = float[](eye_inner_radius, eye_inner_radius, mouth_inner_radius, nose_inner_radius, ear_inner_radius, ear_inner_radius);
        float outer_radii[6] = float[](eye_outer_radius, eye_outer_radius, mouth_outer_radius, nose_outer_radius, ear_outer_radius, ear_outer_radius);
        float falloffs[6] = float[](eye_falloff, eye_falloff, mouth_falloff, nose_falloff, ear_falloff, ear_falloff);
        vec3 colors[6] = vec3[](vec3(1.0, 0.3, 0.3), vec3(1.0, 0.3, 0.3), vec3(0.3, 1.0, 0.3), vec3(0.3, 0.3, 1.0), vec3(1.0, 1.0, 0.3), vec3(1.0, 1.0, 0.3));

        // Show blend weights as color intensity
        if (show_blend_weights) {
            float total_influence = 0.0;
            vec3 blend_color = vec3(0.0);

            for (int i = 0; i < 6; i++) {
                float weight = calculate_influence_weight(UV, points[i], inner_radii[i], outer_radii[i], falloffs[i]);
                if (weight > 0.0) {
                    total_influence += weight;
                    blend_color += colors[i] * weight;
                }
            }

            if (total_influence > 0.0) {
                blend_color /= max(total_influence, 1.0);
                tex_color = mix(tex_color, vec4(blend_color, 0.3), 0.4);
            }
        }

        for (int i = 0; i < 6; i++) {
            float dist_to_point = distance(UV, points[i]);

            // Draw control point dots
            if (show_control_points && dist_to_point < point_size) {
                tex_color = mix(tex_color, vec4(colors[i], 1.0), 0.9);
            }

            // Draw inner radius circles (solid protected area)
            if (show_inner_areas && inner_radii[i] > 0.0) {
                float inner_edge = abs(dist_to_point - inner_radii[i]);
                if (inner_edge < 0.003) {
                    tex_color = mix(tex_color, vec4(colors[i], 1.0), 0.8);
                }
            }

            // Draw outer radius circles (falloff boundary)
            if (show_outer_areas && outer_radii[i] > 0.0) {
                float outer_edge = abs(dist_to_point - outer_radii[i]);
                if (outer_edge < 0.002) {
                    tex_color = mix(tex_color, vec4(colors[i], 0.6), 0.5);
                }
            }
        }
    }

    COLOR = tex_color;
}