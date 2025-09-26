# =============================================================================
# MINIMAP - Simple geometric minimap for system navigation (Hyperspace-Safe)
# =============================================================================
# Minimap.gd
extends Control
class_name Minimap

@export var minimap_radius: float = 128.0
@export var zoom_scale: float = 0.1  # Adjust this to fine-tune zoom level
@export var player_size: float = 4.0
@export var base_celestial_body_size: float = 6.0
@export var scale_multiplier: float = 3.0  # How much to amplify scale differences
@export var min_body_size: float = 5.0      # Minimum size for tiny bodies
@export var max_body_size: float = 72.0     # Maximum size for huge bodies
@export var center_arrow_distance: float = 2000.0  # Distance from (0,0) before showing center arrow

# Colors - matching your game's retro theme
var background_color = Color(0.0, 0.2, 0.0, 0.8)  # Dark green with transparency
var border_color = Color(0.0, 1.0, 0.0, 1.0)      # Bright green
var player_color = Color(1.0, 1.0, 0.0, 1.0)      # Yellow
var planet_color = Color(0.0, 0.8, 0.0, 1.0)      # Medium green
var station_color = Color(0.0, 1.0, 1.0, 1.0)     # Cyan
var npc_color = Color(1.0, 0.5, 0.0, 1.0)         # Orange for NPCs
var center_arrow_color = Color(1.0, 0.5, 0.0, 1.0) # Orange

var player_ship: Node2D
var celestial_bodies: Array[Node2D] = []
var system_center: Vector2 = Vector2.ZERO
var is_active: bool = true  # Track if minimap should be active

func _ready():
	# Set up the minimap
	custom_minimum_size = Vector2(minimap_radius * 2 + 20, minimap_radius * 2 + 20)
	
	# Find player ship
	find_player_ship()
	
	# Find celestial bodies
	find_celestial_bodies()
	
	# Connect to system changes
	UniverseManager.system_changed.connect(_on_system_changed)

func _draw():
	var center = Vector2(minimap_radius + 10, minimap_radius + 10)
	
	# Always draw background circle
	draw_circle(center, minimap_radius, background_color)
	draw_arc(center, minimap_radius, 0, TAU, 64, border_color, 2.0)
	
	# If inactive (during hyperspace), show "HYPERSPACE" text
	if not is_active:
		var font = ThemeDB.fallback_font
		var font_size = 14
		var text = "HYPERSPACE"
		var text_size = font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
		var text_pos = center - text_size / 2
		draw_string(font, text_pos, text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, player_color)
		return
	
	if not player_ship:
		return
	
	var player_pos = player_ship.global_position
	
	# Draw celestial bodies (only if active)
	for body in celestial_bodies:
		# Safety check: make sure body is still valid
		if is_instance_valid(body):
			draw_celestial_body(body, player_pos, center)
	
	# Draw NPC ships
	draw_npc_ships(player_pos, center)
	
	# Draw player
	draw_player(player_pos, center)
	
	# Draw center arrow if player is far from system center
	draw_center_arrow(player_pos, center)

func draw_celestial_body(body: Node2D, player_pos: Vector2, minimap_center: Vector2):
	# Additional safety check
	if not is_instance_valid(body):
		return
	
	var relative_pos = (body.global_position - player_pos) * zoom_scale
	var minimap_pos = minimap_center + relative_pos
	
	# Only draw if within minimap radius
	var distance_from_center = minimap_pos.distance_to(minimap_center)
	if distance_from_center > minimap_radius:
		return
	
	# Determine color based on celestial body type
	var color = planet_color
	if body.has_method("get") and body.celestial_data.has("type"):
		match body.celestial_data.type:
			"station":
				color = station_color
			"planet":
				color = planet_color
			_:
				color = planet_color
	
	# Calculate size based on celestial body scale from database
	var body_size = base_celestial_body_size
	if body.has_method("get") and body.celestial_data.has("scale"):
		var scale_factor = body.celestial_data.get("scale", 1.0)
		# Use exponential scaling to make differences more dramatic
		# This maps 0.035->min_size, 1.0->base_size, 5.0->max_size
		if scale_factor < 1.0:
			# Scale down dramatically for small bodies
			var normalized = scale_factor / 1.0  # 0.035 becomes 0.035
			body_size = lerp(min_body_size, base_celestial_body_size, pow(normalized, 1.0/scale_multiplier))
		else:
			# Scale up dramatically for large bodies  
			var normalized = (scale_factor - 1.0) / 4.0  # 5.0 becomes 1.0, 1.0 becomes 0.0
			body_size = lerp(base_celestial_body_size, max_body_size, pow(normalized, 1.0/scale_multiplier))
		
		# Final clamp for safety
		body_size = clamp(body_size, min_body_size, max_body_size)
	
	# Draw the celestial body
	draw_circle(minimap_pos, body_size, color)
	
	# Draw a small border
	draw_arc(minimap_pos, body_size, 0, TAU, 16, border_color, 1.0)

func draw_npc_ships(player_pos: Vector2, minimap_center: Vector2):
	"""Draw NPC ships as small dots on the minimap"""
	# Find all NPC ships in the scene
	var npc_ships = get_tree().get_nodes_in_group("npc_ships")
	
	for npc in npc_ships:
		# Safety check
		if not is_instance_valid(npc):
			continue
			
		var relative_pos = (npc.global_position - player_pos) * zoom_scale
		var minimap_pos = minimap_center + relative_pos
		
		# Only draw if within minimap radius
		var distance_from_center = minimap_pos.distance_to(minimap_center)
		if distance_from_center > minimap_radius:
			continue
		
		# Draw NPC as a small dot
		var npc_size = 2.5  # Smaller than celestial bodies
		draw_circle(minimap_pos, npc_size, npc_color)
		
		# Optional: Draw a subtle outline
		draw_arc(minimap_pos, npc_size, 0, TAU, 8, border_color, 0.5)

func draw_player(player_pos: Vector2, minimap_center: Vector2):
	# Player is always at the center of the minimap
	var player_minimap_pos = minimap_center
	
	# Draw player as a triangle pointing in the direction they're facing
	var player_rotation = player_ship.rotation
	
	# Create triangle points
	var triangle_points = PackedVector2Array()
	var forward = Vector2(0, -player_size).rotated(player_rotation)
	var back_left = Vector2(-player_size * 0.6, player_size * 0.8).rotated(player_rotation)
	var back_right = Vector2(player_size * 0.6, player_size * 0.8).rotated(player_rotation)
	
	triangle_points.append(player_minimap_pos + forward)
	triangle_points.append(player_minimap_pos + back_left)
	triangle_points.append(player_minimap_pos + back_right)
	
	# Draw filled triangle
	draw_colored_polygon(triangle_points, player_color)
	
	# Draw triangle outline
	draw_polyline(triangle_points + PackedVector2Array([triangle_points[0]]), border_color, 1.0)

func draw_center_arrow(player_pos: Vector2, minimap_center: Vector2):
	var distance_from_center = player_pos.distance_to(system_center)
	
	if distance_from_center < center_arrow_distance:
		return
	
	# Calculate direction to system center
	var direction_to_center = (system_center - player_pos).normalized()
	
	# Draw line from center toward edge
	var line_start = minimap_center
	var line_end = minimap_center + direction_to_center * (minimap_radius - 20)
	draw_line(line_start, line_end, center_arrow_color, 2.0)
	
	# Position arrow head on the edge of minimap
	var arrow_pos = minimap_center + direction_to_center * (minimap_radius - 15)
	
	# Create arrow pointing toward center - FIXED ROTATION
	var arrow_size = 8.0
	var arrow_points = PackedVector2Array()
	var rotation = direction_to_center.angle() + PI/2  # Fixed: added PI/2 to correct rotation
	
	var tip = Vector2(0, -arrow_size).rotated(rotation)
	var left_wing = Vector2(-arrow_size * 0.6, arrow_size * 0.4).rotated(rotation)
	var right_wing = Vector2(arrow_size * 0.6, arrow_size * 0.4).rotated(rotation)
	
	arrow_points.append(arrow_pos + tip)
	arrow_points.append(arrow_pos + left_wing)
	arrow_points.append(arrow_pos + right_wing)
	
	# Draw filled arrow
	draw_colored_polygon(arrow_points, center_arrow_color)
	
	# Draw arrow outline
	draw_polyline(arrow_points + PackedVector2Array([arrow_points[0]]), border_color, 1.0)

func _process(_delta):
	# Check player ship hyperspace status
	check_hyperspace_status()
	
	# Only redraw if active
	if is_active:
		queue_redraw()

func check_hyperspace_status():
	"""Monitor player ship hyperspace state and disable/enable minimap accordingly"""
	if not player_ship:
		return
	
	# Check if player ship has hyperspace_state property
	if player_ship.has_method("get") and "hyperspace_state" in player_ship:
		var in_hyperspace = (player_ship.hyperspace_state != player_ship.HyperspaceState.NORMAL)
		
		if in_hyperspace and is_active:
			# Player entered hyperspace - disable minimap
			print("Minimap: Player entered hyperspace, disabling")
			disable_minimap()
		elif not in_hyperspace and not is_active:
			# Player exited hyperspace - re-enable minimap
			print("Minimap: Player exited hyperspace, enabling")
			enable_minimap()

func disable_minimap():
	"""Disable the minimap during hyperspace jumps"""
	is_active = false
	celestial_bodies.clear()  # Clear references to prevent errors
	queue_redraw()

func enable_minimap():
	"""Re-enable the minimap after hyperspace jumps"""
	is_active = true
	# Refresh celestial bodies for new system
	call_deferred("find_celestial_bodies")
	queue_redraw()

func find_player_ship():
	player_ship = UniverseManager.player_ship
	if not player_ship:
		print("Minimap: Could not find player ship")

func find_celestial_bodies():
	celestial_bodies.clear()
	
	# Only find bodies if minimap is active
	if not is_active:
		return
	
	# Find the SystemScene
	var system_scene = get_tree().get_first_node_in_group("system_scene")
	if not system_scene:
		# Try alternative method
		system_scene = get_tree().current_scene.get_node_or_null("SystemScene")
	
	if system_scene:
		var celestial_container = system_scene.get_node_or_null("CelestialBodies")
		if celestial_container:
			for child in celestial_container.get_children():
				if child is Node2D and is_instance_valid(child):
					celestial_bodies.append(child)
		print("Minimap: Found ", celestial_bodies.size(), " celestial bodies")
	else:
		print("Minimap: Could not find SystemScene")

func _on_system_changed(system_id: int):
	# System changed - re-enable minimap and refresh celestial bodies
	if not is_active:
		enable_minimap()
	else:
		call_deferred("find_celestial_bodies")

# Public methods for runtime adjustment
func set_zoom_scale(new_zoom: float):
	zoom_scale = new_zoom

func set_center_arrow_threshold(new_distance: float):
	center_arrow_distance = new_distance
