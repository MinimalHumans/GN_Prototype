# =============================================================================
# ENHANCED TRAFFIC MANAGER - Integer ID System
# =============================================================================
extends Node2D
class_name TrafficManager

@export var spawn_distance: float = 4000.0
@export var debug_mode: bool = false

var current_npcs: Array = []
var spawn_timer: float = 0.0
var system_traffic_config: Dictionary = {}
var active: bool = false

# Dynamic archetype weights (loaded from JSON per system)
var current_archetype_weights: Dictionary = {}

# Default archetype weights (equal distribution) - used as fallback
var default_archetype_weights = {
	"trader": 0.33,
	"military": 0.33,
	"pirate": 0.34    # Slightly higher to account for rounding
}

# Default traffic configuration
var default_config = {
	"spawn_frequency": 15.0,
	"max_npcs": 5,
	"spawn_frequency_variance": 5.0,
	"archetype_weights": default_archetype_weights,
	"npc_config": {
		"thrust_power": 500.0,
		"rotation_speed": 3.0,
		"max_velocity": 400.0,
		"visit_duration_range": [3.0, 8.0]
	}
}

func _ready():
	add_to_group("traffic_manager")
	
	# Connect to system changes (now uses integer IDs)
	UniverseManager.system_changed.connect(_on_system_changed)
	
	# Initialize with current system (now integer ID)
	_on_system_changed(UniverseManager.current_system_id)

func _process(delta):
	if not active:
		return
	
	update_spawn_timer(delta)
	cleanup_distant_npcs()
	
	if debug_mode:
		queue_redraw()

func update_spawn_timer(delta):
	"""Handle NPC spawning timing"""
	spawn_timer -= delta
	
	if spawn_timer <= 0.0 and should_spawn_npc():
		spawn_npc()
		reset_spawn_timer()

func should_spawn_npc() -> bool:
	"""Check if we should spawn a new NPC"""
	var max_npcs = system_traffic_config.get("max_npcs", default_config.max_npcs)
	var current_count = get_active_npc_count()
	
	return current_count < max_npcs

func get_active_npc_count() -> int:
	"""Get count of active NPCs, cleaning up invalid ones"""
	current_npcs = current_npcs.filter(func(npc): return is_instance_valid(npc))
	return current_npcs.size()

func spawn_npc():
	"""Spawn a new NPC ship with assigned archetype"""
	var npc_ship = create_npc_ship()
	if not npc_ship:
		return
	
	# Calculate spawn position (simple version - just outside system center)
	var spawn_angle = randf() * TAU
	var spawn_pos = Vector2.from_angle(spawn_angle) * spawn_distance
	
	# Add to scene
	get_parent().add_child(npc_ship)
	current_npcs.append(npc_ship)
	
	# Position the NPC
	npc_ship.global_position = spawn_pos
	npc_ship.linear_velocity = Vector2.ZERO
	
	# Assign archetype using the current system's weights
	assign_archetype_to_npc(npc_ship)
	
	if debug_mode:
		print("TrafficManager: Spawned NPC at ", spawn_pos)

func create_npc_ship():
	"""Create a new NPC ship"""
	var npc_ship_scene = load("res://scenes/NPCShip.tscn")
	if not npc_ship_scene:
		push_error("Could not load NPCShip.tscn")
		return null
	
	var npc_ship = npc_ship_scene.instantiate()
	
	if debug_mode:
		print("Created NPC ship")
	
	return npc_ship

func assign_archetype_to_npc(npc_ship):
	"""Assign a specific archetype to the NPC based on current system weights"""
	# Wait for NPC to be fully ready
	await get_tree().process_frame
	if npc_ship == null:
		print("⚠️ npc_ship is null")
		return
	
	var ai_component = npc_ship.get_node_or_null("Phase1CombatAI")
	if not ai_component:
		print("⚠️ NPC has no AI component")
		return
	
	# Choose archetype based on current system's weights
	var chosen_archetype = choose_archetype_for_system()
	
	# Load the AIArchetype class (use the enhanced version)
	const AIArchetypeClass = preload("res://scripts/ai/AIArchetype.gd")
	
	# Assign the archetype
	var archetype
	match chosen_archetype:
		"trader":
			archetype = AIArchetypeClass.create_trader()
		"pirate":
			archetype = AIArchetypeClass.create_pirate()
		"military":
			archetype = AIArchetypeClass.create_military()
		_:
			archetype = AIArchetypeClass.create_trader()
	
	# Set archetype directly on AI
	ai_component.archetype = archetype
	
	# Let AI recreate its behavior tree with the new archetype
	if ai_component.has_method("setup_behavior_tree"):
		ai_component.setup_behavior_tree()
	
	# Visual distinction (optional)
	apply_visual_archetype_hints(npc_ship, chosen_archetype)
	
	# Enable debug for testing (remove this later)
	if OS.is_debug_build():
		await get_tree().process_frame  # Wait for social system to be created
		if npc_ship.has_method("debug_enable_social_combat_debug"):
			npc_ship.debug_enable_social_combat_debug(true)
	
	if debug_mode:
		print("✅ Assigned ", chosen_archetype, " archetype to ", npc_ship.name, " with social combat")

func choose_archetype_for_system() -> String:
	"""Choose archetype based on current system's loaded weights"""
	# Use the current system's loaded archetype weights
	var weights_to_use = current_archetype_weights.duplicate()
	
	if debug_mode:
		print("Using archetype weights for current system: ", weights_to_use)
	
	# Choose based on weighted random
	return weighted_random_choice(weights_to_use)

func weighted_random_choice(weights: Dictionary) -> String:
	"""Choose a random key based on weights"""
	var total_weight = 0.0
	for weight in weights.values():
		total_weight += weight
	
	if total_weight <= 0:
		print("⚠️ Warning: Total archetype weight is 0, defaulting to trader")
		return "trader"
	
	var random_value = randf() * total_weight
	var current_weight = 0.0
	
	for key in weights:
		current_weight += weights[key]
		if random_value <= current_weight:
			return key
	
	# Fallback
	return weights.keys()[0] if not weights.is_empty() else "trader"

func apply_visual_archetype_hints(npc_ship, archetype: String):
	"""Apply subtle visual hints to distinguish archetypes"""
	var sprite = npc_ship.get_node_or_null("Sprite2D")
	if not sprite:
		return
	
	# Subtle color modifications to help distinguish ship types
	match archetype:
		"trader":
			sprite.modulate = Color(0.8, 1.0, 0.8)  # Slight green tint
		"military":
			sprite.modulate = Color(0.8, 0.8, 1.0)  # Slight blue tint
		"pirate":
			sprite.modulate = Color(1.0, 0.8, 0.8)  # Slight red tint

func spawn_initial_npcs():
	"""Spawn NPCs already in the system when player arrives"""
	var max_npcs = system_traffic_config.get("max_npcs", default_config.max_npcs)
	var initial_count = max(1, max_npcs / 2)
	
	if debug_mode:
		print("TrafficManager: Spawning ", initial_count, " initial NPCs")
	
	for i in range(initial_count):
		spawn_existing_npc()
		# Small delay between spawns
		await get_tree().create_timer(0.1).timeout

func spawn_existing_npc():
	"""Spawn an NPC that's already been in the system"""
	var current_system_at_start = UniverseManager.current_system_id

	var npc_ship = create_npc_ship()
	if not npc_ship:
		return

	get_parent().call_deferred("add_child", npc_ship)
	current_npcs.append(npc_ship)

	await get_tree().process_frame

	# Check if system changed during spawn
	if UniverseManager.current_system_id != current_system_at_start:
		return  # System changed, NPC was cleaned up

	if not is_instance_valid(npc_ship):
		return  # NPC was freed somehow
	
	# Use call_deferred to avoid the "busy setting up children" error
	get_parent().call_deferred("add_child", npc_ship)
	current_npcs.append(npc_ship)
	
	# Wait a frame for the NPC to be added to the scene
	await get_tree().process_frame
	
	# Position randomly in system (not too close to center)
	var min_radius = 800.0
	var max_radius = 2000.0
	var spawn_radius = randf_range(min_radius, max_radius)
	var spawn_angle = randf() * TAU
	var spawn_pos = Vector2.from_angle(spawn_angle) * spawn_radius
	
	npc_ship.global_position = spawn_pos
	
	# Give it some random velocity
	var velocity_angle = randf() * TAU
	var velocity_speed = randf_range(50, 150)
	npc_ship.linear_velocity = Vector2.from_angle(velocity_angle) * velocity_speed
	
	# Assign archetype using current system's weights
	assign_archetype_to_npc(npc_ship)
	
	if debug_mode:
		print("TrafficManager: Spawned existing NPC")

func reset_spawn_timer():
	"""Reset the spawn timer with variance"""
	var base_frequency = system_traffic_config.get("spawn_frequency", default_config.spawn_frequency)
	var variance = system_traffic_config.get("spawn_frequency_variance", default_config.spawn_frequency_variance)
	
	var random_offset = randf_range(-variance, variance)
	spawn_timer = max(1.0, base_frequency + random_offset)
	
	if debug_mode:
		print("TrafficManager: Next spawn in ", spawn_timer, " seconds")

func cleanup_distant_npcs():
	"""Remove NPCs that have traveled too far from the system"""
	var system_center = Vector2.ZERO
	var cleanup_distance = spawn_distance * 1.5
	
	for i in range(current_npcs.size() - 1, -1, -1):
		var npc = current_npcs[i]
		if not is_instance_valid(npc):
			current_npcs.remove_at(i)
			continue
		
		var distance_from_center = npc.global_position.distance_to(system_center)
		if distance_from_center > cleanup_distance:
			if debug_mode:
				print("TrafficManager: Cleaning up distant NPC at distance ", distance_from_center)
			npc.queue_free()
			current_npcs.remove_at(i)

func _on_system_changed(system_id: int):
	"""Handle system changes - now uses integer system ID"""
	# Clear existing NPCs
	cleanup_all_npcs()
	
	# Load new system configuration (including archetype weights)
	load_system_traffic_config(system_id)
	
	# Spawn initial NPCs using the new configuration
	spawn_initial_npcs()
	
	# Activate traffic for new system
	active = true
	
	# Reset spawn timer
	reset_spawn_timer()
	
	if debug_mode:
		var system_name = UniverseManager.get_system_name(system_id)
		print("TrafficManager: System changed to ", system_name, " (ID: ", system_id, ")")
		print("TrafficManager: Loaded archetype weights: ", current_archetype_weights)

func load_system_traffic_config(system_id: int):
	"""Load traffic configuration for the specified system ID"""
	var system_data = UniverseManager.get_current_system()
	system_traffic_config = system_data.get("traffic", {})
	
	# Merge with defaults for missing keys
	for key in default_config:
		if not system_traffic_config.has(key):
			system_traffic_config[key] = default_config[key]
	
	# Load archetype weights specifically
	load_archetype_weights(system_data)
	
	if debug_mode:
		var system_name = UniverseManager.get_system_name(system_id)
		print("TrafficManager: Loaded traffic config for ", system_name, " (ID: ", system_id, ")")
		print("  Max NPCs: ", system_traffic_config.get("max_npcs", "default"))
		print("  Spawn frequency: ", system_traffic_config.get("spawn_frequency", "default"))
		print("  Archetype weights: ", current_archetype_weights)

func load_archetype_weights(system_data: Dictionary):
	"""Load archetype weights from system data with validation and fallbacks"""
	var traffic_data = system_data.get("traffic", {})
	var json_weights = traffic_data.get("archetype_weights", {})
	
	# Start with defaults
	current_archetype_weights = default_archetype_weights.duplicate()
	
	if json_weights.is_empty():
		if debug_mode:
			print("TrafficManager: No archetype weights defined for system, using defaults")
		return
	
	# Validate and load weights from JSON
	var valid_archetypes = ["trader", "military", "pirate"]
	var total_weight = 0.0
	var loaded_weights = {}
	
	# Load and validate each weight
	for archetype in valid_archetypes:
		if json_weights.has(archetype):
			var weight = json_weights[archetype]
			if weight is float or weight is int:
				if weight >= 0:
					loaded_weights[archetype] = float(weight)
					total_weight += weight
				else:
					print("⚠️ Warning: Negative weight for ", archetype, ", using default")
			else:
				print("⚠️ Warning: Invalid weight type for ", archetype, ", using default")
	
	# Check if we have valid weights
	if total_weight <= 0:
		print("⚠️ Warning: Total archetype weights is 0 or negative, using defaults")
		return
	
	# Normalize weights to ensure they sum to 1.0
	for archetype in loaded_weights:
		current_archetype_weights[archetype] = loaded_weights[archetype] / total_weight
	
	if debug_mode:
		print("TrafficManager: Loaded and normalized archetype weights: ", current_archetype_weights)
		var weight_sum = 0.0
		for weight in current_archetype_weights.values():
			weight_sum += weight
		print("TrafficManager: Weight sum verification: ", weight_sum, " (should be ~1.0)")

func cleanup_all_npcs():
	"""Remove all current NPCs (used when changing systems)"""
	for npc in current_npcs:
		if is_instance_valid(npc):
			npc.call_deferred("queue_free")
	current_npcs.clear()

func _on_npc_removed(npc):
	"""Called by NPCs when they remove themselves"""
	current_npcs.erase(npc)
	if debug_mode:
		print("TrafficManager: NPC removed, ", current_npcs.size(), " remaining")

func set_debug_mode(enabled: bool):
	"""Enable/disable debug mode"""
	debug_mode = enabled
	queue_redraw()

func _draw():
	"""Debug visualization"""
	if not debug_mode:
		return
	
	var system_center = Vector2.ZERO
	
	# Draw spawn circle
	draw_arc(system_center, spawn_distance, 0, TAU, 64, Color.GREEN, 3.0)
	
	# Draw cleanup circle
	var cleanup_distance = spawn_distance * 1.5
	draw_arc(system_center, cleanup_distance, 0, TAU, 64, Color.RED, 2.0)
	
	# Draw NPC info with archetype
	var font = ThemeDB.fallback_font
	for i in range(current_npcs.size()):
		var npc = current_npcs[i]
		if not is_instance_valid(npc):
			continue
		
		var local_pos = to_local(npc.global_position)
		draw_circle(local_pos, 8.0, Color.YELLOW)
		
		# Get archetype info
		var ai_component = npc.get_node_or_null("Phase1CombatAI")
		var archetype_name = "Unknown"
		if ai_component and ai_component.archetype:
			archetype_name = ai_component.archetype.archetype_name.get_slice(" ", 0)  # First word
		
		var npc_info = "NPC " + str(i) + "\n" + archetype_name
		draw_string(font, local_pos + Vector2(10, 0), npc_info, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)
	
	# Draw spawn timer and current archetype distribution
	var current_system_name = UniverseManager.get_system_name(UniverseManager.current_system_id)
	var timer_info = "System: " + current_system_name + " (ID: " + str(UniverseManager.current_system_id) + ")"
	timer_info += "\nSpawn in: " + str(round(spawn_timer * 10) / 10.0) + "s\nNPCs: " + str(current_npcs.size()) + "/" + str(system_traffic_config.get("max_npcs", 0))
	timer_info += "\nCurrent Weights:"
	for archetype in current_archetype_weights:
		var percentage = int(current_archetype_weights[archetype] * 100)
		timer_info += "\n  " + archetype.capitalize() + ": " + str(percentage) + "%"
	
	draw_string(font, Vector2(-200, -250), timer_info, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.CYAN)

# =============================================================================
# DEBUG METHODS - For testing different configurations
# =============================================================================

func debug_print_current_weights():
	"""Debug method to print current archetype weights"""
	print("=== CURRENT ARCHETYPE WEIGHTS ===")
	var system_name = UniverseManager.get_system_name(UniverseManager.current_system_id)
	print("System: ", system_name, " (ID: ", UniverseManager.current_system_id, ")")
	for archetype in current_archetype_weights:
		var percentage = int(current_archetype_weights[archetype] * 100)
		print("  ", archetype.capitalize(), ": ", percentage, "%")
	print("==================================")

func debug_set_weights(trader: float, military: float, pirate: float):
	"""Debug method to manually set archetype weights"""
	var total = trader + military + pirate
	if total <= 0:
		print("Invalid weights - total must be positive")
		return
	
	current_archetype_weights = {
		"trader": trader / total,
		"military": military / total,
		"pirate": pirate / total
	}
	
	print("Debug: Set archetype weights to - Trader: ", int(current_archetype_weights.trader * 100), "%, Military: ", int(current_archetype_weights.military * 100), "%, Pirate: ", int(current_archetype_weights.pirate * 100), "%")
