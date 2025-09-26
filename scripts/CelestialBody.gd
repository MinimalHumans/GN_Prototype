# =============================================================================
# CELESTIAL BODY - Updated to use library animation system and database IDs
# =============================================================================
# CelestialBody.gd
extends StaticBody2D
class_name CelestialBody

@export var celestial_data: Dictionary = {}
@onready var sprite = $Sprite2D
@onready var label = $Label

var procedural_planet: ColorRect = null
var planet_animator: PlanetAnimator = null

# In apply_system_variations()
var system_id = UniverseManager.current_system_id  # Now integer
var planet_id = celestial_data.get("id", -1)       # Now integer

# Generate seeds using integer IDs  
var base_seed = hash(str(planet_id) + str(system_id)) % 1000

# Visited tracking
var has_been_visited: bool = false
var interaction_area: Area2D = null

func _ready():
	if celestial_data.has("type") and celestial_data.type == "planet":
		create_procedural_planet()
	elif celestial_data.has("sprite"):
		load_sprite(celestial_data.sprite)
	
	if celestial_data.has("name"):
		label.text = celestial_data.name
	
	# Setup interaction area for visited tracking
	setup_interaction_area()
	
	# Check if already visited from database
	var body_id = celestial_data.get("id", -1)
	if body_id != -1:
		has_been_visited = UniverseManager.is_celestial_body_visited(body_id)

func create_procedural_planet():
	"""Create a procedural planet using the library system with integrated animations"""
	
	# Handle database IDs (integers) vs JSON IDs (strings)
	var raw_id = celestial_data.get("id", "default")
	var planet_id: String
	
	# Convert database integer ID to string for PlanetLibraryLoader
	if raw_id is int:
		planet_id = str(raw_id)
	elif raw_id is String:
		planet_id = raw_id
	else:
		planet_id = "default"
	
	print("Creating procedural planet with ID: ", planet_id, " (original: ", raw_id, ")")
	
	# Get both material and animation data from the library
	var planet_data = PlanetLibraryLoader.get_planet_data(planet_id)
	
	if not planet_data.material:
		print("No material found for planet ID: ", planet_id, " - using default")
		# Try with "default" as fallback
		planet_data = PlanetLibraryLoader.get_planet_data("default")
		
		if not planet_data.material:
			push_error("Failed to get material for planet: " + planet_id + " and default fallback failed")
			return
	
	# Create ColorRect for the procedural planet
	procedural_planet = ColorRect.new()
	procedural_planet.name = "ProceduralPlanet"
	
	# Set size to 512x512
	var planet_size = Vector2(512, 512)
	procedural_planet.size = planet_size
	procedural_planet.position = -planet_size / 2  # Center the planet
	procedural_planet.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	# Apply the material from the library
	procedural_planet.material = planet_data.material
	
	# Apply any system-specific modifications
	apply_system_variations(planet_data.material)
	
	# Setup parameter animations from library data
	setup_planet_animations_from_library(planet_data.material, planet_data.animation_data)
	
	# Hide the original sprite and add the procedural planet
	sprite.visible = false
	add_child(procedural_planet)
	
	# Update collision shape to match new planet size
	update_collision_shape(planet_size)
	
	print("Created procedural planet: ", planet_id)
	if planet_data.has_animations:
		print("  • Loaded animations for ", planet_data.animation_data.size(), " parameters")

func setup_planet_animations_from_library(material: ShaderMaterial, animation_data: Dictionary):
	"""Setup parameter animations from library animation data"""
	
	if animation_data.is_empty():
		print("No animations defined for planet: ", celestial_data.get("id", "unknown"))
		return  # No animations defined
	
	# Create and configure the animator
	planet_animator = PlanetAnimator.new()
	planet_animator.name = "PlanetAnimator"
	add_child(planet_animator)
	
	# Setup animations with the material and configuration from library
	planet_animator.setup_animations(material, animation_data)
	
	print("Setup animations for planet: ", celestial_data.get("id", "unknown"))
	print("  Animation parameters: ", animation_data.keys())

func apply_system_variations(material: ShaderMaterial):
	"""Apply minor system-specific variations (lighting, seeds)"""
	var system_id = UniverseManager.current_system_id
	var planet_id_raw = celestial_data.get("id", "")
	var planet_id = str(planet_id_raw) if planet_id_raw != null else ""
	
	# Generate system-consistent but planet-unique seeds
	var base_seed = hash(str(planet_id) + str(system_id)) % 1000
	var system_rng = RandomNumberGenerator.new()
	system_rng.seed = hash(system_id)
	
	# Update terrain seeds for variety while keeping the library's base appearance
	var current_continent_seed = material.get_shader_parameter("continent_seed")
	if current_continent_seed == null or current_continent_seed == 0.0:
		material.set_shader_parameter("continent_seed", float(base_seed))
	
	# Add slight seed variations for other terrain features
	material.set_shader_parameter("terrain_seed", float(base_seed + system_rng.randi() % 200))
	material.set_shader_parameter("detail_seed", float(base_seed + system_rng.randi() % 200))
	material.set_shader_parameter("river_seed", float(base_seed + system_rng.randi() % 200))
	
	# Apply system-based lighting variations (different star types)
	apply_star_lighting(material, system_id)

func apply_star_lighting(material: ShaderMaterial, system_id: int):
	"""Apply star-type-specific lighting"""
	# Get system name for matching if needed
	var system_name = UniverseManager.get_system_name(system_id)
	
	match system_name:
		"Helios":
			# Yellow star - warm light (your starting system)
			material.set_shader_parameter("light_color", Color(0.921, 0.594, 0.674))
			material.set_shader_parameter("ambient_color", Color(0.4, 0.6, 1.0))
			material.set_shader_parameter("light_intensity", 1.4)
			
		"sol_system":
			# Yellow star - warm light
			material.set_shader_parameter("light_color", Color(0.921, 0.594, 0.674))
			material.set_shader_parameter("ambient_color", Color(0.4, 0.6, 1.0))
			material.set_shader_parameter("light_intensity", 1.4)
			
		#"sirius_system":
			# Blue-white star - cool bright light
			#material.set_shader_parameter("light_color", Color(0.9, 0.95, 1.0))
			#material.set_shader_parameter("light_intensity", 1.2)
			#material.set_shader_parameter("ambient_color", Color(0.6, 0.7, 1.0))
			
		#"antares_system":
			# Red supergiant - warm red light
			#material.set_shader_parameter("light_color", Color(1.0, 0.7, 0.5))
			#material.set_shader_parameter("ambient_color", Color(0.8, 0.4, 0.3))
			
		#"rigel_system":
			# Blue supergiant - intense blue-white light
			#material.set_shader_parameter("light_color", Color(0.8, 0.9, 1.0))
			#material.set_shader_parameter("light_intensity", 1.4)
			#material.set_shader_parameter("ambient_color", Color(0.5, 0.6, 1.0))
			
		#"arcturus_system":
			# Red giant - warm orange light
			#material.set_shader_parameter("light_color", Color(1.0, 0.8, 0.6))
			#material.set_shader_parameter("ambient_color", Color(0.7, 0.5, 0.4))
			
		#"vega_system":
			# Blue-white star - bright cool light
			#material.set_shader_parameter("light_color", Color(0.9, 0.9, 1.0))
			#material.set_shader_parameter("light_intensity", 1.1)
			
		_:
			# Default: slight variation but don't override library settings too much
			pass

func update_collision_shape(planet_size: Vector2):
	"""Update collision shapes to match the new planet size"""
	var collision_shape = $CollisionShape2D
	if collision_shape and collision_shape.shape is CircleShape2D:
		var circle_shape = collision_shape.shape as CircleShape2D
		circle_shape.radius = planet_size.x / 8  # Reasonable collision size
	
	# Update interaction area for visited tracking
	if interaction_area:
		var interaction_collision = interaction_area.get_node("CollisionShape2D")
		if interaction_collision and interaction_collision.shape is CircleShape2D:
			var interaction_circle = interaction_collision.shape as CircleShape2D
			interaction_circle.radius = planet_size.x / 2  # Larger interaction range

func setup_interaction_area():
	"""Setup interaction area for detecting when player comes within range"""
	interaction_area = Area2D.new()
	interaction_area.name = "InteractionArea"
	
	var collision_shape = CollisionShape2D.new()
	var circle_shape = CircleShape2D.new()
	circle_shape.radius = 200.0  # Default interaction range
	collision_shape.shape = circle_shape
	
	interaction_area.add_child(collision_shape)
	add_child(interaction_area)
	
	# Connect signals for player detection
	interaction_area.body_entered.connect(_on_player_entered_range)
	
	# Set collision layers/masks to detect player
	interaction_area.collision_layer = 0  # Don't collide with anything
	interaction_area.collision_mask = 1   # Detect player (assuming player is on layer 1)

func _on_player_entered_range(body: Node2D):
	"""Called when player enters interaction range"""
	# Check if it's the player ship
	if body.has_method("get_ship_id") or body.name.contains("Player"):
		mark_as_visited()

func mark_as_visited():
	"""Mark this celestial body as visited"""
	if has_been_visited:
		return  # Already marked as visited
	
	var body_id = celestial_data.get("id", -1)
	if body_id != -1:
		UniverseManager.mark_celestial_body_visited(body_id)
		has_been_visited = true
		print("Player discovered: ", celestial_data.get("name", "Unknown Body"))

func load_sprite(sprite_path: String):
	"""Load static sprite for non-planet celestial bodies"""
	var texture = load(sprite_path)
	if texture:
		sprite.texture = texture

func can_interact() -> bool:
	return celestial_data.get("can_land", false)

func interact():
	print("Landing on: ", celestial_data.name)
	
	# Ensure it's marked as visited (in case interaction happens before range detection)
	mark_as_visited()
	
	UniverseManager.celestial_body_approached.emit(celestial_data)
	# Here you would transition to planet surface or show services menu

func pause_animations():
	"""Pause planet animations (called when leaving system)"""
	if planet_animator:
		planet_animator.stop_animations()

func resume_animations():
	"""Resume planet animations (called when entering system)"""
	if planet_animator:
		planet_animator.start_animations()

# Development helper function
func reload_planet_from_library():
	"""Reload this planet's appearance from the library (useful during development)"""
	if procedural_planet and celestial_data.get("type") == "planet":
		var raw_id = celestial_data.get("id", "default")
		var planet_id = str(raw_id) if raw_id is int else raw_id
		
		PlanetLibraryLoader.reload_library()
		
		# Get fresh data from library
		var planet_data = PlanetLibraryLoader.get_planet_data(planet_id)
		
		if planet_data.material:
			# Stop current animations
			if planet_animator:
				planet_animator.stop_animations()
				planet_animator.queue_free()
				planet_animator = null
			
			# Apply new material and restart animations
			procedural_planet.material = planet_data.material
			apply_system_variations(planet_data.material)
			setup_planet_animations_from_library(planet_data.material, planet_data.animation_data)
			
			print("Reloaded planet from library: ", planet_id)
			if planet_data.has_animations:
				print("  • Reloaded animations for ", planet_data.animation_data.size(), " parameters")

# Debug function to print current animation status
func debug_print_animation_status():
	"""Print debug information about this planet's animations"""
	print("=== Animation Status for ", celestial_data.get("name", "Unknown"), " ===")
	
	if not planet_animator:
		print("❌ No planet animator attached")
		return
	
	if planet_animator.animations.is_empty():
		print("⚪ No animations defined")
		return
	
	print("✅ Active animations: ", planet_animator.animations.size())
	for anim in planet_animator.animations:
		var status = "▶️ RUNNING" if planet_animator.is_active else "⏸️ PAUSED"
		print("  • %s (%s, rate: %.3f) %s" % [
			anim.parameter_name, 
			anim.animation_type, 
			anim.rate,
			status
		])
	
	print("Animator active: ", planet_animator.is_active)
	print("================================================")

# LEGACY COMPATIBILITY - Remove these when all systems are updated
func setup_planet_animations(material: ShaderMaterial, animation_data: Dictionary):
	"""Legacy function for backward compatibility - now redirects to new system"""
	push_warning("CelestialBody.setup_planet_animations(): This function is deprecated. Use setup_planet_animations_from_library() instead.")
	setup_planet_animations_from_library(material, animation_data)
