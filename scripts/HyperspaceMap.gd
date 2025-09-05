# =============================================================================
# ENHANCED HYPERSPACE MAP - SQLite + Zoom/Pan Integration
# =============================================================================
# HyperspaceMap.gd
extends Control

@onready var info_label: Label = $MainContainer/RightPanel/JumpPanel/InfoLabel
@onready var jump_button: Button = $MainContainer/RightPanel/InfoPanel/InfoContainer/JumpButton
@onready var cancel_button: Button = $MainContainer/RightPanel/InfoPanel/InfoContainer/CancelButton
@onready var flavor_panel = $MainContainer/RightPanel/FlavorPanel
@onready var flavor_label = $MainContainer/RightPanel/FlavorPanel/FlavorLabel
@onready var left_panel = $MainContainer/LeftPanel

# Database-loaded data (integer IDs)
var systems_data: Dictionary = {}  # int -> system_data
var system_connections: Dictionary = {}  # int -> Array[int]
var selected_system_id: int = -1
var current_system_id: int = -1

# Zoom/Pan system (adapted from test)
var zoom_level: float = 1.0
var pan_offset: Vector2 = Vector2.ZERO
var is_panning: bool = false
var last_pan_position: Vector2

# Visual settings
var system_base_size: float = 0.8
var connection_width: float = 2.0

# Map canvas and coordinates
var map_canvas: Control
var coord_bounds: Dictionary = {
	"min_x": 0.0, "max_x": 0.0,
	"min_y": 0.0, "max_y": 0.0,
	"width": 0.0, "height": 0.0
}

# Colors
var connection_color = Color(0.0, 0.8, 0.0, 0.7)
var current_system_color = Color(1.0, 1.0, 0.0, 1.0)
var selected_system_color = Color(1.0, 0.5, 0.0, 1.0)
var unavailable_color = Color(0.3, 0.3, 0.3, 1.0)

# Delivery visualization
var delivery_destinations: Dictionary = {}  # system_id -> delivery_count
var delivery_ring_color = Color(0.0, 1.0, 1.0, 0.8)  # Cyan ring
var delivery_icon_color = Color(0.0, 1.0, 1.0, 1.0)  # Cyan icon


func _ready():
	load_systems_from_database()
	current_system_id = UniverseManager.current_system_id
	
	await get_tree().process_frame
	
	if jump_button:
		jump_button.pressed.connect(_on_jump_pressed)
	if cancel_button:
		cancel_button.pressed.connect(_on_cancel_pressed)
	
	setup_map_canvas()
	setup_initial_view()
	update_ui()

func _process(_delta):
	"""Continuously update delivery ring animation when map is visible"""
	if visible and not delivery_destinations.is_empty() and map_canvas:
		map_canvas.queue_redraw()

func setup_map_canvas():
	"""Set up the zoomable/pannable map canvas in the left panel"""
	if not left_panel:
		push_error("Left panel not found!")
		return
	
	map_canvas = Control.new()
	map_canvas.name = "MapCanvas"
	map_canvas.mouse_filter = Control.MOUSE_FILTER_PASS
	
	left_panel.add_child(map_canvas)
	map_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	
	map_canvas.draw.connect(_draw_map)
	map_canvas.gui_input.connect(_on_map_input)
	
	print("Map canvas created")

func load_systems_from_database():
	"""Load all systems and connections from SQLite database"""
	print("Loading systems from SQLite database...")
	
	if not UniverseManager.db:
		push_error("Database not available!")
		return
	
	# Load all systems with their visual properties
	var systems_query = """
		SELECT 
			id, name, x, y, map_size, map_color, is_hub, 
			population, flavor_text
		FROM systems 
		ORDER BY name;
	"""
	
	UniverseManager.db.query(systems_query)
	var systems_results = UniverseManager.db.query_result
	
	systems_data.clear()
	system_connections.clear()
	
	# Process each system
	for system_row in systems_results:
		var system_id = system_row.id
		
		var system_data = {
			"id": system_id,
			"name": system_row.name,
			"x": float(system_row.x),
			"y": float(system_row.y),
			"map_size": float(system_row.map_size),
			"map_color": system_row.map_color,
			"is_hub": bool(system_row.is_hub),
			"population": system_row.population,
			"flavor_text": system_row.flavor_text if system_row.flavor_text else ""
		}
		
		systems_data[system_id] = system_data
		
		# Load connections for this system
		system_connections[system_id] = load_system_connections(system_id)
	
	print("Loaded ", systems_data.size(), " systems from database")
	calculate_coordinate_bounds()

func load_system_connections(system_id: int) -> Array[int]:
	"""Load bidirectional connections for a specific system"""
	# Get connections where this system is the source
	var outbound_query = """
		SELECT target_system_id
		FROM system_connections
		WHERE source_system_id = ?;
	"""
	
	UniverseManager.db.query_with_bindings(outbound_query, [system_id])
	var outbound_results = UniverseManager.db.query_result
	
	# Get connections where this system is the target (reverse direction)
	var inbound_query = """
		SELECT source_system_id
		FROM system_connections
		WHERE target_system_id = ?;
	"""
	
	UniverseManager.db.query_with_bindings(inbound_query, [system_id])
	var inbound_results = UniverseManager.db.query_result
	
	# Combine both directions and remove duplicates
	var connections: Array[int] = []
	var connection_set = {}
	
	# Add outbound connections
	for row in outbound_results:
		var target_id = row.target_system_id
		if not connection_set.has(target_id):
			connections.append(target_id)
			connection_set[target_id] = true
	
	# Add inbound connections (reverse direction)
	for row in inbound_results:
		var source_id = row.source_system_id
		if not connection_set.has(source_id):
			connections.append(source_id)
			connection_set[source_id] = true
	
	return connections

func calculate_coordinate_bounds():
	"""Calculate bounds of all system coordinates"""
	if systems_data.is_empty():
		return
	
	var min_x = INF
	var max_x = -INF
	var min_y = INF
	var max_y = -INF
	
	for system_data in systems_data.values():
		var x = system_data.x
		var y = system_data.y
		
		min_x = min(min_x, x)
		max_x = max(max_x, x)
		min_y = min(min_y, y)
		max_y = max(max_y, y)
	
	coord_bounds = {
		"min_x": min_x,
		"max_x": max_x,
		"min_y": min_y,
		"max_y": max_y,
		"width": max_x - min_x,
		"height": max_y - min_y
	}
	
	print("Coordinate bounds: X(", min_x, " to ", max_x, ") Y(", min_y, " to ", max_y, ")")

# Add this method to load delivery information
func load_delivery_destinations():
	"""Load systems that have active delivery missions"""
	delivery_destinations.clear()
	
	var active_missions = PlayerData.get_active_missions()
	
	for mission in active_missions:
		var destination_system_id = mission.get("destination_system", -1)
		if destination_system_id != -1:
			if delivery_destinations.has(destination_system_id):
				delivery_destinations[destination_system_id] += 1
			else:
				delivery_destinations[destination_system_id] = 1
	
	print("Loaded delivery destinations: ", delivery_destinations)


func setup_initial_view():
	"""Set up initial view to show all systems"""
	if systems_data.is_empty():
		return
	
	await get_tree().process_frame  # Wait for canvas to be ready
	
	if not map_canvas:
		return
	
	var canvas_size = map_canvas.size
	if canvas_size.x <= 0 or canvas_size.y <= 0:
		return
	
	# Calculate zoom to fit all systems with padding
	var padding = 100.0
	var zoom_x = (canvas_size.x - padding * 2) / coord_bounds.width
	var zoom_y = (canvas_size.y - padding * 2) / coord_bounds.height
	zoom_level = min(zoom_x, zoom_y) * 0.8  # 80% to leave some margin
	
	# Center the map
	var viewport_center = canvas_size / 2
	var map_center = Vector2(
		coord_bounds.min_x + coord_bounds.width / 2,
		-(coord_bounds.min_y + coord_bounds.height / 2)  # Flip Y
	)
	
	pan_offset = viewport_center - map_center * zoom_level
	
	print("Initial view - Zoom: ", zoom_level, " Pan: ", pan_offset)
	queue_redraw()

func _draw_map():
	"""Draw the hyperspace map with zoom/pan support"""
	if not map_canvas or systems_data.is_empty():
		return
	
	var canvas_size = map_canvas.size
	if canvas_size.x <= 0 or canvas_size.y <= 0:
		return
	
	# Draw connections first (behind systems)
	draw_connections()
	
	# Draw systems
	draw_systems()
	
	# Draw instructions
	draw_instructions(canvas_size)

func draw_connections():
	"""Draw hyperspace connections between systems"""
	for system_id in system_connections:
		if not systems_data.has(system_id):
			continue
			
		var system_data = systems_data[system_id]
		var system_screen_pos = world_to_screen(Vector2(system_data.x, system_data.y))
		
		# Skip if system is far off screen
		if not is_point_on_screen(system_screen_pos, 200):
			continue
		
		var connections = system_connections[system_id]
		for connected_id in connections:
			if not systems_data.has(connected_id):
				continue
				
			var connected_data = systems_data[connected_id]
			var connected_screen_pos = world_to_screen(Vector2(connected_data.x, connected_data.y))
			
			# Skip if connection is completely off screen
			if not is_line_on_screen(system_screen_pos, connected_screen_pos):
				continue
			
			# Draw connection line
			var width = connection_width * max(0.5, zoom_level)
			map_canvas.draw_line(system_screen_pos, connected_screen_pos, connection_color, width)

func draw_systems():
	"""Draw all star systems"""
	for system_id in systems_data:
		var system_data = systems_data[system_id]
		var world_pos = Vector2(system_data.x, system_data.y)
		var screen_pos = world_to_screen(world_pos)
		
		# Cull off-screen systems
		var base_radius = system_base_size * system_data.map_size * max(0.3, zoom_level)
		if not is_point_on_screen(screen_pos, base_radius + 50):
			continue
		
		# Calculate visual properties
		var final_radius = base_radius
		var final_color = get_system_color(system_data)
		
		# Apply selection highlighting
		if system_id == current_system_id:
			final_color = current_system_color
			final_radius *= 1.2
		elif system_id == selected_system_id:
			final_color = selected_system_color
			final_radius *= 1.1
		elif not can_travel_to(system_id):
			final_color = unavailable_color
		
		# Draw system circle
		map_canvas.draw_circle(screen_pos, final_radius, final_color)
		
		# Draw border for hubs
		if system_data.is_hub:
			map_canvas.draw_arc(screen_pos, final_radius + 2, 0, TAU, 32, Color.WHITE, 2.0)
		
		# NEW: Draw delivery indicators
		draw_delivery_indicators(screen_pos, final_radius, system_id)
		
		
		# Draw system name if zoomed in enough
		if zoom_level > 0.5:
			draw_system_label(screen_pos, system_data.name, final_radius)

# Add this new method for drawing delivery indicators:
func draw_delivery_indicators(screen_pos: Vector2, system_radius: float, system_id: int):
	"""Draw delivery indicators for systems with active missions"""
	if not delivery_destinations.has(system_id):
		return
	
	var delivery_count = delivery_destinations[system_id]
	var indicator_radius = system_radius + 6
	
	# Draw pulsing delivery ring
	var pulse_factor = 1.0 + 0.3 * sin(Time.get_ticks_msec() / 1000.0 * 3.0)
	var ring_radius = indicator_radius * pulse_factor
	var ring_width = max(2.0, 3.0 * zoom_level)
	
	# Draw the delivery ring
	map_canvas.draw_arc(screen_pos, ring_radius, 0, TAU, 32, delivery_ring_color, ring_width)
	
	# Draw cargo icon if zoomed in enough
	if zoom_level > 0.3:
		draw_delivery_icon(screen_pos, system_radius, delivery_count)

func draw_delivery_icon(screen_pos: Vector2, system_radius: float, delivery_count: int):
	"""Draw a small cargo/delivery icon"""
	var icon_size = max(8.0, 12.0 * zoom_level)
	var icon_offset = Vector2(system_radius + 15, -system_radius - 5)
	var icon_pos = screen_pos + icon_offset
	
	# Draw a simple cargo box icon
	var box_size = Vector2(icon_size, icon_size * 0.7)
	var box_rect = Rect2(icon_pos - box_size/2, box_size)
	
	# Box outline
	map_canvas.draw_rect(box_rect, delivery_icon_color, false, 2.0)
	
	# Box fill (semi-transparent)
	var fill_color = delivery_icon_color
	fill_color.a = 0.3
	map_canvas.draw_rect(box_rect, fill_color, true)
	
	# Draw delivery count if multiple
	if delivery_count > 1:
		draw_delivery_count_badge(icon_pos, delivery_count, icon_size)

func draw_delivery_count_badge(icon_pos: Vector2, count: int, icon_size: float):
	"""Draw a small badge showing number of deliveries"""
	var badge_radius = icon_size * 0.4
	var badge_pos = icon_pos + Vector2(icon_size * 0.4, -icon_size * 0.4)
	
	# Badge background circle
	map_canvas.draw_circle(badge_pos, badge_radius, Color(1.0, 0.5, 0.0, 0.9))  # Orange background
	map_canvas.draw_arc(badge_pos, badge_radius, 0, TAU, 16, Color.WHITE, 1.0)    # White border
	
	# Badge number text
	var font = ThemeDB.fallback_font
	var font_size = max(8, int(icon_size * 0.6))
	var count_text = str(count)
	var text_size = font.get_string_size(count_text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	var text_pos = badge_pos - text_size / 2
	
	# Draw number
	map_canvas.draw_string(font, text_pos, count_text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, Color.WHITE)



func draw_system_label(screen_pos: Vector2, system_name: String, radius: float):
	"""Draw system name label"""
	var font = ThemeDB.fallback_font
	var font_size = int(12 * max(0.8, zoom_level))
	var text_size = font.get_string_size(system_name, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	var text_pos = screen_pos + Vector2(-text_size.x / 2, radius + 20)
	
	# Keep text on screen
	var canvas_size = map_canvas.size
	text_pos.x = clamp(text_pos.x, 0, canvas_size.x - text_size.x)
	text_pos.y = clamp(text_pos.y, font_size, canvas_size.y)
	
	# Draw text with shadow
	map_canvas.draw_string(font, text_pos + Vector2(1, 1), system_name, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, Color.BLACK)
	map_canvas.draw_string(font, text_pos, system_name, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, Color.WHITE)

func draw_instructions(canvas_size: Vector2):
	"""Draw control instructions with delivery legend"""
	var font = ThemeDB.fallback_font
	var instruction_text = "Mouse Wheel: Zoom  |  Middle Click + Drag: Pan  |  Left Click: Select System"
	var instruction_size = font.get_string_size(instruction_text, HORIZONTAL_ALIGNMENT_CENTER, -1, 12)
	var instruction_pos = Vector2((canvas_size.x - instruction_size.x) / 2, canvas_size.y - 30)
	
	# Draw main instructions
	map_canvas.draw_string(font, instruction_pos + Vector2(1, 1), instruction_text, HORIZONTAL_ALIGNMENT_CENTER, -1, 12, Color.BLACK)
	map_canvas.draw_string(font, instruction_pos, instruction_text, HORIZONTAL_ALIGNMENT_CENTER, -1, 12, Color.YELLOW)
	
	# Draw delivery legend
	var legend_text = "Cyan Ring = Active Deliveries"
	var legend_size = font.get_string_size(legend_text, HORIZONTAL_ALIGNMENT_CENTER, -1, 10)
	var legend_pos = Vector2((canvas_size.x - legend_size.x) / 2, canvas_size.y - 15)
	
	map_canvas.draw_string(font, legend_pos + Vector2(1, 1), legend_text, HORIZONTAL_ALIGNMENT_CENTER, -1, 10, Color.BLACK)
	map_canvas.draw_string(font, legend_pos, legend_text, HORIZONTAL_ALIGNMENT_CENTER, -1, 10, delivery_ring_color)

# Add method to refresh delivery data when missions change
func refresh_delivery_indicators():
	"""Call this method when missions are completed or accepted"""
	load_delivery_destinations()
	if map_canvas:
		map_canvas.queue_redraw()
		
func get_system_color(system_data: Dictionary) -> Color:
	"""Get system color from map_color property or default based on system type"""
	var color_str = system_data.get("map_color", "#FFFFFF")
	
	# Parse hex color
	if color_str.begins_with("#") and color_str.length() >= 7:
		return Color.html(color_str)
	
	# Fallback colors based on system properties
	if system_data.is_hub:
		return Color.CYAN
	elif system_data.population > 1000000:
		return Color.GREEN
	else:
		return Color.WHITE

# =============================================================================
# COORDINATE CONVERSION (from test)
# =============================================================================

func screen_to_world(screen_pos: Vector2) -> Vector2:
	"""Convert screen coordinates to world coordinates"""
	var world_pos = (screen_pos - pan_offset) / zoom_level
	# Flip Y coordinate back when converting to world space
	return Vector2(world_pos.x, -world_pos.y)

func world_to_screen(world_pos: Vector2) -> Vector2:
	"""Convert world coordinates to screen coordinates"""
	# Flip Y coordinate to match display system
	var flipped_world_pos = Vector2(world_pos.x, -world_pos.y)
	return flipped_world_pos * zoom_level + pan_offset

# =============================================================================
# MOUSE INTERACTION (adapted from test)
# =============================================================================

func _on_map_input(event):
	"""Handle mouse input on the map canvas"""
	if event is InputEventMouseButton:
		handle_mouse_button(event)
	elif event is InputEventMouseMotion:
		handle_mouse_motion(event)

func handle_mouse_button(event: InputEventMouseButton):
	"""Handle mouse button events"""
	if event.button_index == MOUSE_BUTTON_WHEEL_UP:
		zoom_at_point(event.position, 1.2)
	elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		zoom_at_point(event.position, 0.8)
	elif event.button_index == MOUSE_BUTTON_MIDDLE:
		is_panning = event.pressed
		last_pan_position = event.position
	elif event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		handle_system_click(event.position)

func handle_mouse_motion(event: InputEventMouseMotion):
	"""Handle mouse motion for panning"""
	if is_panning:
		pan_offset += event.position - last_pan_position
		last_pan_position = event.position
		map_canvas.queue_redraw()

func zoom_at_point(screen_point: Vector2, zoom_factor: float):
	"""Zoom in/out at specific screen point"""
	var world_point = screen_to_world(screen_point)
	
	zoom_level *= zoom_factor
	zoom_level = clamp(zoom_level, 0.05, 5.0)
	
	# Adjust pan to keep world point under screen point
	var new_screen_point = world_to_screen(world_point)
	pan_offset += screen_point - new_screen_point
	
	map_canvas.queue_redraw()

func handle_system_click(click_position: Vector2):
	"""Handle clicking on systems"""
	var clicked_system_id = get_system_at_position(click_position)
	
	if clicked_system_id != -1:
		select_system(clicked_system_id)

func get_system_at_position(screen_pos: Vector2) -> int:
	"""Find system at screen position"""
	var world_pos = screen_to_world(screen_pos)
	var min_distance = INF
	var closest_system_id = -1
	
	for system_id in systems_data:
		var system_data = systems_data[system_id]
		var system_world_pos = Vector2(system_data.x, system_data.y)
		var distance = world_pos.distance_to(system_world_pos)
		
		if distance < min_distance:
			min_distance = distance
			closest_system_id = system_id
	
	# Check if click is within reasonable distance
	if closest_system_id != -1:
		var system_data = systems_data[closest_system_id]
		var threshold = (system_base_size * system_data.map_size + 10) / zoom_level
		
		if min_distance <= threshold:
			return closest_system_id
	
	return -1

# =============================================================================
# UTILITY FUNCTIONS (from test)
# =============================================================================

func is_point_on_screen(point: Vector2, margin: float = 0) -> bool:
	"""Check if point is visible on screen"""
	var canvas_size = map_canvas.size
	return point.x >= -margin and point.x <= canvas_size.x + margin and \
		   point.y >= -margin and point.y <= canvas_size.y + margin

func is_line_on_screen(p1: Vector2, p2: Vector2, margin: float = 100) -> bool:
	"""Check if line segment intersects with screen"""
	var canvas_size = map_canvas.size
	var screen_rect = Rect2(-margin, -margin, canvas_size.x + margin * 2, canvas_size.y + margin * 2)
	
	return screen_rect.has_point(p1) or screen_rect.has_point(p2) or \
		   (p1.x < 0 and p2.x > canvas_size.x) or (p1.y < 0 and p2.y > canvas_size.y)

# =============================================================================
# SYSTEM SELECTION & UI (existing functionality)
# =============================================================================

func select_system(system_id: int):
	"""Select system and update UI"""
	selected_system_id = system_id
	update_ui()
	map_canvas.queue_redraw()
	
	var system_name = get_system_name(system_id)
	print("Selected system: ", system_name, " (ID: ", system_id, ")")

func update_ui():
	"""Update right panel with system information"""
	var flavor_text = ""
	
	if selected_system_id == -1:
		info_label.text = "Select a destination system"
		jump_button.disabled = true
		flavor_text = "Navigate the galaxy using the hyperspace network.\n\nSystems with cyan rings have active delivery missions.\n\nUse mouse wheel to zoom and middle-click + drag to pan around the map."
	elif selected_system_id == current_system_id:
		var system_name = get_system_name(selected_system_id)
		info_label.text = "Current location: " + system_name
		jump_button.disabled = true
		flavor_text = get_system_flavor(selected_system_id)
	elif can_travel_to(selected_system_id):
		var system_name = get_system_name(selected_system_id)
		info_label.text = "Jump to: " + system_name
		jump_button.disabled = false
		flavor_text = get_system_flavor(selected_system_id)
		
		# Add delivery information if applicable
		if delivery_destinations.has(selected_system_id):
			var delivery_count = delivery_destinations[selected_system_id]
			var delivery_text = "\n\n📦 DELIVERIES AVAILABLE\n"
			delivery_text += "You have %d active delivery mission%s to this system." % [delivery_count, "s" if delivery_count > 1 else ""]
			flavor_text += delivery_text
	else:
		var system_name = get_system_name(selected_system_id)
		info_label.text = system_name + " - Not accessible"
		jump_button.disabled = true
		flavor_text = get_system_flavor(selected_system_id)
		
		# Show delivery info even if not accessible
		if delivery_destinations.has(selected_system_id):
			var delivery_count = delivery_destinations[selected_system_id]
			var delivery_text = "\n\n📦 DELIVERIES WAITING\n"
			delivery_text += "You have %d delivery mission%s to this system, but it's not directly accessible. Find a route through connected systems." % [delivery_count, "s" if delivery_count > 1 else ""]
			flavor_text += delivery_text
	
	if flavor_label:
		flavor_label.text = flavor_text

func get_system_name(system_id: int) -> String:
	"""Get system name by ID"""
	if systems_data.has(system_id):
		return systems_data[system_id].name
	return "Unknown System"

func get_system_flavor(system_id: int) -> String:
	"""Get system flavor text"""
	if systems_data.has(system_id):
		var flavor = systems_data[system_id].flavor_text
		return flavor if flavor != "" else "No information available about this system."
	return "No information available about this system."

func can_travel_to(system_id: int) -> bool:
	"""Check if travel is possible to system"""
	if current_system_id == -1:
		return false
	var connections = system_connections.get(current_system_id, [])
	return system_id in connections

# =============================================================================
# MAIN INTERFACE (existing)
# =============================================================================

func show_map():
	"""Show the hyperspace map"""
	load_systems_from_database()
	load_delivery_destinations()  
	current_system_id = UniverseManager.current_system_id
	selected_system_id = -1
	
	update_ui()
	visible = true
	get_tree().paused = true
	
	await get_tree().process_frame
	
	if map_canvas:
		map_canvas.queue_redraw()

func hide_map():
	"""Hide the hyperspace map"""
	visible = false
	get_tree().paused = false
	selected_system_id = -1

func _on_jump_pressed():
	"""Handle jump button press"""
	if selected_system_id != -1 and can_travel_to(selected_system_id):
		var player_ship = UniverseManager.player_ship
		if player_ship and player_ship.has_method("start_hyperspace_sequence"):
			player_ship.start_hyperspace_sequence(selected_system_id)
			hide_map()
		else:
			UniverseManager.change_system(selected_system_id)
			hide_map()

func _on_cancel_pressed():
	"""Handle cancel button press"""
	hide_map()

func _input(event):
	"""Handle global input when map is visible"""
	if not visible:
		return
	
	if event.is_action_pressed("ui_cancel"):
		hide_map()
		get_viewport().set_input_as_handled()

# =============================================================================
# DEBUG METHODS
# =============================================================================

func debug_print_map_info():
	"""Print debug information about the map"""
	print("=== HYPERSPACE MAP DEBUG ===")
	print("Systems loaded: ", systems_data.size())
	print("Current system: ", current_system_id)
	print("Selected system: ", selected_system_id)
	print("Coordinate bounds: ", coord_bounds)
	print("Zoom level: ", zoom_level)
	print("Pan offset: ", pan_offset)
	print("===========================")
