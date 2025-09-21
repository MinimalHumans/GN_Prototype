# =============================================================================
# SYSTEM SCENE - Now with Starfield Configuration Loading and Empty System Support
# =============================================================================
# SystemScene.gd
extends Node2D
class_name SystemScene

@onready var celestial_bodies_container = $CelestialBodies
@onready var player_spawn = $PlayerSpawn
@onready var traffic_manager = $TrafficManager
@onready var parallax_starfield = $ParallaxStarfield

func _ready():
	add_to_group("system_scene")  # Add to group for easy finding
	
	# Initialize from save data
	if not UniverseManager.initialize_from_save():
		print("Failed to initialize UniverseManager from save")
		return
	
	PlayerData.initialize_from_save()
	
	UniverseManager.system_changed.connect(_on_system_changed)
	setup_system(UniverseManager.get_current_system())

func _on_system_changed(system_id: int):
	# Pause animations in old system before switching
	pause_all_planet_animations()
	setup_system(UniverseManager.get_current_system())

func setup_system(system_data: Dictionary):
	clear_system()
	spawn_celestial_bodies(system_data.get("celestial_bodies", []))
	
	# Load starfield configuration for this system
	load_system_starfield(system_data)
	
	# Only position player at spawn if it's not a hyperspace transition
	var player = UniverseManager.player_ship
	if player and player_spawn:
		# Check if player is in hyperspace sequence
		if player.hyperspace_state == player.HyperspaceState.NORMAL:
			# Normal spawn (e.g., game start)
			player.global_position = player_spawn.global_position
			player.linear_velocity = Vector2.ZERO
			player.angular_velocity = 0.0
			
			# Force camera update
			var camera = player.get_node("Camera2D")
			if camera:
				camera.global_position = player.global_position
				camera.force_update_scroll()
		# If in hyperspace, let the player ship handle its own positioning

func load_system_starfield(system_data: Dictionary):
	"""Load the starfield configuration for the current system"""
	print("SystemScene: Attempting to load starfield configuration")
	print("SystemScene: parallax_starfield exists: ", parallax_starfield != null)
	
	if parallax_starfield:
		print("SystemScene: parallax_starfield type: ", parallax_starfield.get_class())
		print("SystemScene: has load_system_starfield method: ", parallax_starfield.has_method("load_system_starfield"))
		
		if parallax_starfield.has_method("load_system_starfield"):
			# Defer the call to make sure the starfield is fully ready
			parallax_starfield.call_deferred("load_system_starfield", system_data)
			print("SystemScene: Deferred starfield loading for system: ", system_data.get("name", "Unknown"))
		else:
			print("SystemScene: ParallaxStarfield doesn't have load_system_starfield method")
	else:
		print("SystemScene: ParallaxStarfield node not found")
		# Try to find it manually
		var starfield_node = get_node_or_null("ParallaxStarfield")
		if starfield_node:
			print("SystemScene: Found ParallaxStarfield manually: ", starfield_node)
			starfield_node.call_deferred("load_system_starfield", system_data)
		else:
			print("SystemScene: Could not find ParallaxStarfield node at all")
			# Print all children to help debug
			print("SystemScene children: ")
			for child in get_children():
				print("  - ", child.name, " (", child.get_class(), ")")

func clear_system():
	for child in celestial_bodies_container.get_children():
		child.queue_free()

func spawn_celestial_bodies(bodies_data: Array):
	"""Spawn celestial bodies, with validation for empty/invalid entries"""
	print("SystemScene: Spawning celestial bodies. Count: ", bodies_data.size())
	
	var spawned_count = 0
	
	for i in range(bodies_data.size()):
		var body_data = bodies_data[i]
		
		# Validate celestial body data
		if not is_valid_celestial_body(body_data):
			print("SystemScene: Skipping invalid celestial body at index ", i, ": ", body_data)
			continue
		
		# Create and configure celestial body
		var celestial_body = preload("res://scenes/CelestialBody.tscn").instantiate()
		celestial_body.celestial_data = body_data
		
		# Set position safely
		var position_data = body_data.get("position", {"x": 0, "y": 0})
		celestial_body.position = Vector2(position_data.x, position_data.y)
		
		# Apply scale if specified for procedural planets
		if body_data.has("scale") and body_data.get("type") == "planet":
			celestial_body.scale = Vector2(body_data.scale, body_data.scale)
		
		# Use call_deferred to avoid physics timing issues
		celestial_bodies_container.call_deferred("add_child", celestial_body)
		spawned_count += 1
	
	if spawned_count == 0:
		print("SystemScene: No celestial bodies spawned - this is an empty system")
	else:
		print("SystemScene: Successfully spawned ", spawned_count, " celestial bodies")

func is_valid_celestial_body(body_data) -> bool:
	"""Check if celestial body data is valid and complete"""
	# Must be a dictionary
	if not body_data is Dictionary:
		return false
	
	# Must not be empty
	if body_data.is_empty():
		return false
	
	# Must have required fields - handle different data types
	var required_fields = ["id", "name", "type"]
	for field in required_fields:
		if not body_data.has(field):
			print("SystemScene: Celestial body missing required field: ", field)
			return false
		
		# Handle different data types appropriately
		var field_value = body_data[field]
		if field == "id":
			# ID can be integer or string, just make sure it exists and isn't null
			if field_value == null:
				print("SystemScene: Celestial body has null id field")
				return false
		else:
			# For name and type, check they're not empty strings
			if field_value == null or (field_value is String and field_value == ""):
				print("SystemScene: Celestial body has empty/null field: ", field)
				return false
	
	# Must have position data
	if not body_data.has("position"):
		print("SystemScene: Celestial body missing position data")
		return false
	
	var position_data = body_data["position"]
	if not position_data is Dictionary:
		print("SystemScene: Celestial body position is not a dictionary")
		return false
	
	if not position_data.has("x") or not position_data.has("y"):
		print("SystemScene: Celestial body position missing x or y coordinates")
		return false
	
	return true

func pause_all_planet_animations():
	"""Pause animations on all planets (performance optimization when leaving system)"""
	for child in celestial_bodies_container.get_children():
		if child.has_method("pause_animations"):
			child.pause_animations()

func resume_all_planet_animations():
	"""Resume animations on all planets (when entering system)"""
	for child in celestial_bodies_container.get_children():
		if child.has_method("resume_animations"):
			child.resume_animations()

# Called when the system becomes active (e.g., after hyperspace)
func _notification(what):
	if what == NOTIFICATION_VISIBILITY_CHANGED and visible:
		# Resume animations when system becomes visible
		call_deferred("resume_all_planet_animations")

# Debug methods for NPC traffic
func _input(event):
	if OS.is_debug_build():
		if event.is_action_pressed("debug_toggle"): 
			if traffic_manager:
				traffic_manager.set_debug_mode(!traffic_manager.debug_mode)
				print("Traffic debug mode: ", traffic_manager.debug_mode)
