# =============================================================================
# SQLITE UNIVERSE MANAGER - Pure Integer ID System
# =============================================================================
# SQLiteUniverseManager.gd - Singleton (AutoLoad)
extends Node

signal system_changed(new_system_id: int)
signal celestial_body_approached(body_data)

# Core state - ALL integer IDs
var current_system_id: int = -1
var player_ship: Node = null

# Database connection
var db: SQLite
# db_path is set when game is created or loaded
var db_path: String = ""

# Caching system - integer keys
var universe_data: Dictionary = {"systems": {}, "governments": {}}
var system_cache: Dictionary = {}  # int -> system_data
var current_system_cache: Dictionary = {}
var connection_cache: Dictionary = {}  # int -> Array[int] (connected system IDs)
var system_name_cache: Dictionary = {}  # int -> String (for display only)

# Cache for pathfinding results
var distance_cache: Dictionary = {}  # "origin_id:destination_id" -> distance
var systems_by_distance_cache: Dictionary = {}  # "origin_id:min:max" -> Array[int]
var connection_graph: Dictionary = {}  # int -> Array[int] (bidirectional connections)


# Mission system
var current_system_missions: Dictionary = {}  # int (planet_id) -> Array[mission_data]

func _ready():
	print("SQLite UniverseManager; standing by")

func initialize_from_save():
	"""Initialize universe manager after save is loaded"""
	print("SQLite UniverseManager initializing from save.")
	if not initialize_database():
		return false

	load_governments()
	build_connection_graph()
	var player_data = SaveManager.load_player_data()
	var starting_system_id = player_data.get("current_system_id", 1)
	
	change_system(starting_system_id)
	return true

# =============================================================================
# DATABASE INITIALIZATION
# =============================================================================

func initialize_database() -> bool:
	"""Initialize SQLite database connection using current save"""
	db = SaveManager.get_current_save_database()
	
	if not db:
		push_error("No save database available from SaveManager")
		return false
	
	# Enable foreign keys and optimize for read performance  
	db.query("PRAGMA foreign_keys = ON;")
	db.query("PRAGMA journal_mode = WAL;")
	db.query("PRAGMA cache_size = -64000;")
	
	print("Universe database connected successfully from save")
	return true

func load_governments():
	"""Load government data for JSON compatibility"""
	universe_data.governments = {
		"confederation": {
			"name": "Terran Confederation",
			"description": "The unified government of human space",
			"color": "#0066CC",
			"starting_reputation": 0
		},
		"independent": {
			"name": "Independent Worlds", 
			"description": "Free traders and frontier settlements",
			"color": "#CC6600",
			"starting_reputation": 0
		}
	}

# =============================================================================
# PATHFINDING SYSTEM
# =============================================================================

func build_connection_graph():
	"""Build bidirectional connection graph for pathfinding"""
	print("Building connection graph for pathfinding...")
	connection_graph.clear()
	
	# Get all connections from database
	var connections_query = """
		SELECT DISTINCT source_system_id, target_system_id
		FROM system_connections;
	"""
	
	db.query(connections_query)
	var results = db.query_result
	
	# Build bidirectional graph
	for row in results:
		var source_id = row.source_system_id
		var target_id = row.target_system_id
		
		# Add forward connection
		if not connection_graph.has(source_id):
			connection_graph[source_id] = []
		if target_id not in connection_graph[source_id]:
			connection_graph[source_id].append(target_id)
		
		# Add reverse connection (bidirectional)
		if not connection_graph.has(target_id):
			connection_graph[target_id] = []
		if source_id not in connection_graph[target_id]:
			connection_graph[target_id].append(source_id)
	
	print("Connection graph built with ", connection_graph.size(), " systems")

func find_shortest_path(origin_system_id: int, destination_system_id: int) -> Array[int]:
	"""Find shortest path between systems using BFS. Returns array of system IDs."""
	if origin_system_id == destination_system_id:
		var result: Array[int] = [origin_system_id]
		return result
	
	if not connection_graph.has(origin_system_id) or not connection_graph.has(destination_system_id):
		var empty_result: Array[int] = []
		return empty_result  # One or both systems not in graph
	
	# BFS to find shortest path
	var queue: Array = [[origin_system_id]]  # Array of paths
	var visited: Dictionary = {origin_system_id: true}
	
	while not queue.is_empty():
		var current_path: Array = queue.pop_front()
		var current_system: int = current_path[-1]
		
		# Check all connected systems
		var connections = connection_graph.get(current_system, [])
		for next_system in connections:
			if next_system == destination_system_id:
				# Found destination - create properly typed result
				var final_path: Array[int] = []
				for system_id in current_path:
					final_path.append(system_id)
				final_path.append(next_system)
				return final_path
			
			if not visited.has(next_system):
				visited[next_system] = true
				var new_path: Array = current_path.duplicate()
				new_path.append(next_system)
				queue.append(new_path)
	
	var no_path_result: Array[int] = []
	return no_path_result  # No path found

func get_jump_distance(origin_system_id: int, destination_system_id: int) -> int:
	"""Get jump distance between systems using cached pathfinding"""
	if origin_system_id == destination_system_id:
		return 0
	
	# Check cache first
	var cache_key = str(origin_system_id) + ":" + str(destination_system_id)
	if distance_cache.has(cache_key):
		return distance_cache[cache_key]
	
	# Calculate using pathfinding
	var path = find_shortest_path(origin_system_id, destination_system_id)
	var distance = path.size() - 1 if path.size() > 0 else -1  # -1 means unreachable
	
	# Cache the result (and reverse direction)
	distance_cache[cache_key] = distance
	var reverse_key = str(destination_system_id) + ":" + str(origin_system_id)
	distance_cache[reverse_key] = distance
	
	return distance

func get_systems_within_jump_range(origin_system_id: int, min_jumps: int, max_jumps: int) -> Array[int]:
	"""Get all systems within a specific jump range from origin"""
	var cache_key = str(origin_system_id) + ":" + str(min_jumps) + ":" + str(max_jumps)
	
	# Check cache first
	if systems_by_distance_cache.has(cache_key):
		return systems_by_distance_cache[cache_key].duplicate()
	
	var systems_in_range: Array[int] = []
	
	# Get all systems and check their distance
	var all_systems_query = "SELECT id FROM systems;"
	db.query(all_systems_query)
	var all_systems = db.query_result
	
	for system_row in all_systems:
		var system_id = system_row.id
		if system_id == origin_system_id:
			continue  # Skip origin
		
		var distance = get_jump_distance(origin_system_id, system_id)
		if distance >= min_jumps and distance <= max_jumps:
			systems_in_range.append(system_id)
	
	# Cache result
	systems_by_distance_cache[cache_key] = systems_in_range.duplicate()
	
	print("Found ", systems_in_range.size(), " systems within ", min_jumps, "-", max_jumps, " jumps of system ", origin_system_id)
	return systems_in_range

func get_landable_destinations_by_distance(origin_system_id: int, min_jumps: int, max_jumps: int) -> Array[Dictionary]:
	"""Get landable destinations within specific jump range"""
	var systems_in_range = get_systems_within_jump_range(origin_system_id, min_jumps, max_jumps)
	var destinations: Array[Dictionary] = []
	
	for system_id in systems_in_range:
		# Load system data if not cached
		var system_data = load_system_data(system_id)
		var system_name = get_system_name(system_id)
		var celestial_bodies = system_data.get("celestial_bodies", [])
		
		for body in celestial_bodies:
			if body.get("can_land", false):
				var destination = {
					"system_id": system_id,
					"system_name": system_name,
					"planet_id": body.get("id", -1),
					"planet_name": body.get("name", "Unknown"),
					"planet_type": body.get("type", "unknown"),
					"jump_distance": get_jump_distance(origin_system_id, system_id)
				}
				destinations.append(destination)
	
	return destinations

# =============================================================================
# DEBUG METHODS FOR PATHFINDING
# =============================================================================

func debug_pathfinding_test(origin_id: int, destination_id: int):
	"""Test pathfinding between two systems"""
	print("=== PATHFINDING TEST ===")
	print("Origin: ", get_system_name(origin_id), " (ID: ", origin_id, ")")
	print("Destination: ", get_system_name(destination_id), " (ID: ", destination_id, ")")
	
	var path = find_shortest_path(origin_id, destination_id)
	var distance = get_jump_distance(origin_id, destination_id)
	
	print("Distance: ", distance, " jumps")
	print("Path: ")
	for i in range(path.size()):
		var system_id = path[i]
		var system_name = get_system_name(system_id)
		print("  ", i, ": ", system_name, " (ID: ", system_id, ")")
	print("========================")

func debug_distance_distribution(origin_id: int):
	"""Analyze distance distribution from origin system"""
	print("=== DISTANCE DISTRIBUTION FROM ", get_system_name(origin_id), " ===")
	
	var distance_counts = {}
	var max_distance = 0
	
	# Count systems at each distance
	var all_systems_query = "SELECT id FROM systems WHERE id != ?;"
	db.query_with_bindings(all_systems_query, [origin_id])
	var all_systems = db.query_result
	
	for system_row in all_systems:
		var system_id = system_row.id
		var distance = get_jump_distance(origin_id, system_id)
		
		if distance >= 0:  # -1 means unreachable
			if not distance_counts.has(distance):
				distance_counts[distance] = 0
			distance_counts[distance] += 1
			max_distance = max(max_distance, distance)
	
	# Print distribution
	for d in range(1, max_distance + 1):
		var count = distance_counts.get(d, 0)
		print("Distance ", d, ": ", count, " systems")
	
	# Show ranges for mission generation
	var range_1_5 = get_systems_within_jump_range(origin_id, 1, 5).size()
	var range_6_10 = get_systems_within_jump_range(origin_id, 6, 10).size()
	var range_11_20 = get_systems_within_jump_range(origin_id, 11, 20).size()
	
	print("Mission ranges:")
	print("  1-5 jumps: ", range_1_5, " systems")
	print("  6-10 jumps: ", range_6_10, " systems")
	print("  11-20 jumps: ", range_11_20, " systems")
	print("=======================================")

func clear_pathfinding_cache():
	"""Clear pathfinding caches (useful for testing)"""
	distance_cache.clear()
	systems_by_distance_cache.clear()
	print("Pathfinding caches cleared")

# =============================================================================
# MAIN API - Integer ID Based
# =============================================================================

func change_system(system_id: int):
	"""Change to new system by ID"""
	print("Changing to system ID: ", system_id)
	
	var system_data = load_system_data(system_id)
	if system_data.is_empty():
		push_error("System not found: " + str(system_id))
		return
	
	current_system_id = system_id
	current_system_cache = system_data
	
	# Update universe_data for HyperspaceMap compatibility (use int keys)
	universe_data.systems[system_id] = system_data
	
	# Mark system as visited
	mark_system_visited(system_id)
	
	# Save current system to player data
	PlayerData.set_current_system(system_id)
	
	generate_system_missions()
	system_changed.emit(system_id)
	
	var system_name = get_system_name(system_id)
	print("Entered system: ", system_name, " (ID: ", system_id, ")")

func get_current_system() -> Dictionary:
	"""Get current system data"""
	return current_system_cache

func get_celestial_body(body_id: int) -> Dictionary:
	"""Get celestial body by integer ID"""
	var system = get_current_system()
	for body in system.get("celestial_bodies", []):
		if body.id == body_id:
			return body
	return {}

func can_travel_to_system(system_id: int) -> bool:
	"""Check if travel is possible to system by ID"""
	var connections = get_system_connections(current_system_id)
	return system_id in connections
	
# Add this method to SQLiteUniverseManager.gd
func get_system_display_position(system_id: int) -> Vector2:
	"""Get system position with Y-axis flipped to match hyperspace map display"""
	var systems_query = """
		SELECT x, y FROM systems WHERE id = ?;
	"""
	
	db.query_with_bindings(systems_query, [system_id])
	var results = db.query_result
	
	if results.is_empty():
		return Vector2.ZERO
	
	var system_row = results[0]
	# Return position with Y-flipped to match hyperspace map orientation
	return Vector2(float(system_row.x), -float(system_row.y))

func get_current_system_display_position() -> Vector2:
	"""Get current system position with display correction"""
	return get_system_display_position(current_system_id)

# =============================================================================
# NAME LOOKUP HELPERS - For display only
# =============================================================================

func get_system_name(system_id: int) -> String:
	"""Get system name for display purposes"""
	if system_name_cache.has(system_id):
		return system_name_cache[system_id]
	
	db.query_with_bindings("SELECT name FROM systems WHERE id = ?;", [system_id])
	var results = db.query_result
	
	if results.is_empty():
		return "Unknown System"
	
	var name = results[0].name
	system_name_cache[system_id] = name
	return name

func get_system_id_by_name(system_name: String) -> int:
	"""Get system ID by name (for legacy compatibility/startup)"""
	db.query_with_bindings("SELECT id FROM systems WHERE name = ?;", [system_name])
	var results = db.query_result
	
	if results.is_empty():
		return -1
	
	return results[0].id

func get_body_name(body_id: int) -> String:
	"""Get celestial body name for display purposes"""
	db.query_with_bindings("SELECT name FROM celestial_bodies WHERE id = ?;", [body_id])
	var results = db.query_result
	
	if results.is_empty():
		return "Unknown Body"
	
	return results[0].name

# =============================================================================
# DATABASE LOADING - Pure integer ID operations
# =============================================================================

func load_system_data(system_id: int) -> Dictionary:
	"""Load complete system data by integer ID"""
	
	# Check cache first
	if system_cache.has(system_id):
		return system_cache[system_id]
	
	#print("Loading system from database - ID: ", system_id)
	
	var system_query = """
		SELECT 
			id, name, type, x, y, population, security_level, tech_level,
			crime_level, corruption_level, risk_rating, is_hub, is_exceptional,
			asteroid_field, radiation, murk_level, nebula_type,
			bg_color_r, bg_color_g, bg_color_b,
			light_direction, light_color_r, light_color_g, light_color_b, light_intensity,
			map_size, map_color, note, flavor_text
		FROM systems 
		WHERE id = ?;
	"""
	
	db.query_with_bindings(system_query, [system_id])
	var system_results = db.query_result
	
	if system_results.is_empty():
		return {}
	
	var system_row = system_results[0]
	
	# Cache the name for quick lookup
	system_name_cache[system_id] = system_row.name
	
	# Build system data with integer IDs
	var system_data = {
		"id": system_row.id,
		"name": system_row.name,
		"description": system_row.note if system_row.note else "A star system",
		"flavor_text": system_row.flavor_text if system_row.flavor_text else "",
		"connections": get_system_connections(system_id),
		"map_position": {
			"x": system_row.x / 1000.0,
			"y": system_row.y / 1000.0
		},
		"celestial_bodies": load_system_bodies(system_id),
		"starfield": build_starfield_config(system_row),
		"traffic": build_traffic_config(system_row)
	}
	
	# Cache by integer ID
	system_cache[system_id] = system_data
	return system_data

func load_system_bodies(system_id: int) -> Array:
	"""Load celestial bodies for a system by integer ID"""
	var bodies_query = """
		SELECT 
			id, name, type, pos_x, pos_y, scale, can_land,
			shipyard_package, description, flavor_text,
			service_refuel, service_missions, service_shipyard
		FROM celestial_bodies
		WHERE system_id = ?
		ORDER BY name;
	"""
	
	db.query_with_bindings(bodies_query, [system_id])
	var bodies_results = db.query_result
	
	#print("Loading celestial bodies for system ID ", system_id, " - Found: ", bodies_results.size())
	
	var celestial_bodies = []
	
	for body_row in bodies_results:
		# Build services array from database boolean columns
		var services = build_services_array(body_row)
		
		# Use integer IDs throughout
		var body_data = {
			"id": body_row.id,  # Integer database ID
			"name": body_row.name,
			"type": body_row.type,
			"description": body_row.description if body_row.description else "",
			"flavor_text": body_row.flavor_text if body_row.flavor_text else "",
			"position": {"x": body_row.pos_x, "y": body_row.pos_y},
			"scale": body_row.scale,
			"can_land": bool(body_row.can_land),
			"services": services,  # ← Now loaded from database
			"government": "confederation",
			"tech_level": 4,
			"population": 1000000
		}
		
		if body_row.shipyard_package:
			body_data["shipyard"] = {"available_ships": [body_row.shipyard_package]}
		
		celestial_bodies.append(body_data)
		# print("  Loaded body: ", body_data.name, " (ID: ", body_data.id, ") with services: ", services)
	
	return celestial_bodies

func build_services_array(body_row: Dictionary) -> Array:
	"""Convert database service columns to services array"""
	var services = []
	
	# Add services based on database boolean columns
	if body_row.get("service_missions", 0):
		services.append("mission_computer")  # This enables shipping missions
	
	if body_row.get("service_refuel", 0):
		services.append("hyperspace_recharge")
	
	if body_row.get("service_shipyard", 0):
		services.append("shipyard")
	
	# Add standard services for landable planets
	if body_row.get("can_land", 0):
		services.append("outfitter")
		services.append("commodity_exchange")
	
	# Always ensure mission_computer is available if no services specified but can_land is true
	if services.is_empty() and body_row.get("can_land", 0):
		services.append("mission_computer")
	
	return services

func get_system_connections(system_id: int) -> Array[int]:
	"""Get array of connected system IDs"""
	
	# Check cache first
	if connection_cache.has(system_id):
		return connection_cache[system_id]
	
	var connections_query = """
		SELECT target_system_id
		FROM system_connections
		WHERE source_system_id = ?;
	"""
	
	db.query_with_bindings(connections_query, [system_id])
	var results = db.query_result
	
	var connections: Array[int] = []
	for row in results:
		connections.append(row.target_system_id)
	
	# Cache the result
	connection_cache[system_id] = connections
	
	#print("Loaded connections for system ID ", system_id, ": ", connections)
	return connections

func build_starfield_config(system_row: Dictionary) -> Dictionary:
	"""Build starfield configuration from system data"""
	return {
		"BaseColor": [system_row.bg_color_r, system_row.bg_color_g, system_row.bg_color_b],
		"StarLayers_Star_Density": 1.0,
		"StarLayers_Star_Brightness": system_row.light_intensity,
		"StarLayers_Twinkle_Speed": 0.3
	}

func build_traffic_config(system_row: Dictionary) -> Dictionary:
	"""Build traffic configuration based on system properties"""
	var base_frequency = 15.0
	var max_npcs = 3
	
	if system_row.is_hub:
		base_frequency = 5.0
		max_npcs = 8
	elif system_row.population > 1000000:
		base_frequency = 8.0  
		max_npcs = 5
	
	return {
		"spawn_frequency": base_frequency,
		"max_npcs": max_npcs,
		"spawn_frequency_variance": 3.0,
		"npc_config": {
			"thrust_power": 450.0,
			"rotation_speed": 2.8,
			"max_velocity": 380.0,
			"visit_duration_range": [3.0, 8.0]
		}
	}

# =============================================================================
# HYPERSPACE MAP SUPPORT - Integer ID based
# =============================================================================

func load_all_systems_for_map() -> Dictionary:
	"""Load all systems for hyperspace map with integer keys"""
	print("Loading all systems for hyperspace map...")
	
	universe_data.systems.clear()
	
	var systems_query = """
		SELECT id, name, x, y, flavor_text
		FROM systems 
		ORDER BY name;
	"""
	
	db.query(systems_query)
	var systems_results = db.query_result
	
	for system_row in systems_results:
		var system_id = system_row.id
		
		# Cache name for quick lookup
		system_name_cache[system_id] = system_row.name
		
		var system_data = {
			"id": system_id,
			"name": system_row.name,
			"map_position": {
				"x": system_row.x / 1000.0,
				"y": system_row.y / 1000.0
			},
			"flavor_text": system_row.flavor_text if system_row.flavor_text else "",
			"connections": get_system_connections(system_id),
			"celestial_bodies": load_system_bodies(system_id)
		}
		
		universe_data.systems[system_id] = system_data
	
	print("Loaded ", universe_data.systems.size(), " systems for hyperspace map")
	return universe_data.systems

func ensure_all_systems_loaded():
	"""Ensure all systems are loaded for hyperspace map"""
	if universe_data.systems.size() < 10:  # Adjust threshold as needed
		load_all_systems_for_map()

# =============================================================================
# MISSION SYSTEM - Integer ID based
# =============================================================================

func generate_system_missions():
	"""Generate missions for current system using integer IDs"""
	current_system_missions.clear()
	
	var system_data = get_current_system()
	if system_data.is_empty():
		return
	
	var celestial_bodies = system_data.get("celestial_bodies", [])
	var mission_count = 0
	
	print("=== Generating missions for system ID ", current_system_id, " ===")
	
	for body in celestial_bodies:
		if body.get("can_land", false):
			var planet_id = body.get("id", -1)  # Integer ID
			var missions = MissionGenerator.generate_missions_for_planet(body, current_system_id)
			
			if not missions.is_empty():
				current_system_missions[planet_id] = missions
				mission_count += missions.size()
				print("Generated ", missions.size(), " missions for ", body.get("name", str(planet_id)))
	
	print("=== Total missions generated: ", mission_count, " ===")

func get_missions_for_planet(planet_id: int) -> Array[Dictionary]:
	"""Get missions for planet by integer ID"""
	if current_system_missions.has(planet_id):
		return current_system_missions[planet_id].duplicate()
	return []

func remove_mission_from_system(planet_id: int, mission_data: Dictionary):
	"""Remove mission from system using integer planet ID"""
	if current_system_missions.has(planet_id):
		var planet_missions = current_system_missions[planet_id]
		
		for i in range(planet_missions.size() - 1, -1, -1):
			var mission = planet_missions[i]
			if (mission.get("cargo_type") == mission_data.get("cargo_type") and
				mission.get("cargo_weight") == mission_data.get("cargo_weight") and
				mission.get("destination_planet") == mission_data.get("destination_planet") and
				mission.get("destination_system") == mission_data.get("destination_system")):
				
				planet_missions.remove_at(i)
				print("Removed mission from available list")
				break
		
		current_system_missions[planet_id] = planet_missions

# =============================================================================
# PLAYER VISITED TRACKING
# =============================================================================

func mark_system_visited(system_id: int):
	"""Mark a system as visited by the player"""
	if not db:
		return
	
	var update_sql = "UPDATE systems SET player_visited = 1 WHERE id = ?;"
	db.query_with_bindings(update_sql, [system_id])
	
	var system_name = get_system_name(system_id)
	print("Marked system as visited: ", system_name, " (ID: ", system_id, ")")

func mark_celestial_body_visited(body_id: int):
	"""Mark a celestial body as visited by the player"""
	if not db:
		return
	
	var update_sql = "UPDATE celestial_bodies SET player_visited = 1 WHERE id = ?;"
	db.query_with_bindings(update_sql, [body_id])
	
	var body_name = get_body_name(body_id)
	print("Marked celestial body as visited: ", body_name, " (ID: ", body_id, ")")

func is_system_visited(system_id: int) -> bool:
	"""Check if a system has been visited by the player"""
	if not db:
		return false
	
	var query_sql = "SELECT player_visited FROM systems WHERE id = ?;"
	db.query_with_bindings(query_sql, [system_id])
	var results = db.query_result
	
	if results.is_empty():
		return false
	
	return bool(results[0].player_visited)

func is_celestial_body_visited(body_id: int) -> bool:
	"""Check if a celestial body has been visited by the player"""
	if not db:
		return false
	
	var query_sql = "SELECT player_visited FROM celestial_bodies WHERE id = ?;"
	db.query_with_bindings(query_sql, [body_id])
	var results = db.query_result
	
	if results.is_empty():
		return false
	
	return bool(results[0].player_visited)

func get_visited_systems() -> Array[int]:
	"""Get array of all visited system IDs"""
	if not db:
		return []
	
	var query_sql = "SELECT id FROM systems WHERE player_visited = 1;"
	db.query(query_sql)
	var results = db.query_result
	
	var visited_systems: Array[int] = []
	for row in results:
		visited_systems.append(row.id)
	
	return visited_systems

func get_adjacent_systems(system_id: int) -> Array[int]:
	"""Get systems that are one jump away from the given system"""
	if not connection_graph.has(system_id):
		var empty_result: Array[int] = []
		return empty_result
	
	var connections = connection_graph[system_id]
	var result: Array[int] = []
	for system_id_conn in connections:
		result.append(system_id_conn)
	return result

func get_visible_systems_for_map() -> Array[int]:
	"""Get systems that should be visible on hyperspace map (visited + adjacent to current + systems with missions)"""
	var visible_systems: Array[int] = []
	var visited_systems = get_visited_systems()
	
	# Add all visited systems
	for system_id in visited_systems:
		if system_id not in visible_systems:
			visible_systems.append(system_id)
	
	# Add systems adjacent to current system (even if not visited)
	if current_system_id != -1:
		var adjacent_systems = get_adjacent_systems(current_system_id)
		for system_id in adjacent_systems:
			if system_id not in visible_systems:
				visible_systems.append(system_id)
	
	# Add systems that have active delivery missions (even if not visited or adjacent)
	var mission_systems = get_systems_with_active_missions()
	for system_id in mission_systems:
		if system_id not in visible_systems:
			visible_systems.append(system_id)
	
	return visible_systems

func get_systems_with_active_missions() -> Array[int]:
	"""Get systems that have active delivery missions"""
	var mission_systems: Array[int] = []
	var active_missions = PlayerData.get_active_missions()
	
	for mission in active_missions:
		var destination_system_id = mission.get("destination_system", -1)
		if destination_system_id != -1 and destination_system_id not in mission_systems:
			mission_systems.append(destination_system_id)
	
	return mission_systems

func get_visited_celestial_bodies() -> Array[int]:
	"""Get array of all visited celestial body IDs"""
	if not db:
		return []
	
	var query_sql = "SELECT id FROM celestial_bodies WHERE player_visited = 1;"
	db.query(query_sql)
	var results = db.query_result
	
	var visited_bodies: Array[int] = []
	for row in results:
		visited_bodies.append(row.id)
	
	return visited_bodies

# =============================================================================
# DEBUG METHODS
# =============================================================================

func debug_print_current_system():
	"""Debug method to print current system info"""
	print("=== CURRENT SYSTEM DEBUG ===")
	print("System ID: ", current_system_id)
	print("System Name: ", get_system_name(current_system_id))
	print("Cached systems: ", system_cache.size())
	print("Cached connections: ", connection_cache.size())
	
	var system_data = get_current_system()
	var bodies = system_data.get("celestial_bodies", [])
	print("Celestial bodies: ", bodies.size())
	for body in bodies:
		var visited_status = "✓" if is_celestial_body_visited(body.id) else "○"
		print("  - ", body.name, " (ID: ", body.id, ") ", visited_status)
	
	var system_visited = "✓" if is_system_visited(current_system_id) else "○"
	print("System visited: ", system_visited)
	print("===========================")

# =============================================================================
# CLEANUP
# =============================================================================

func _exit_tree():
	# Don't close database here - SaveManager handles it
	print("Universe manager shutting down")
