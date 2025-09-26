# =============================================================================
# PLAYER SHIP - Main player controller with hyperspace sequence (Integer ID System)
# =============================================================================
# PlayerShip.gd
extends RigidBody2D
class_name PlayerShip

# Ship stats - now loaded from ShipManager instead of hardcoded
var thrust_power: float = 500.0
var rotation_speed: float = 3.0
var max_velocity: float = 400.0
var hyperspace_thrust_power: float = 1500.0
var hyperspace_entry_speed: float = 800.0

var hull: float = 1000.0        # Player has more health
var max_hull: float = 500.0
var shields: float = 1000.0
var max_shields: float = 1000.0
var shield_recharge_timer: float = 0.0
var shield_recharge_delay: float = 2.0 

@onready var sprite = $Sprite2D
@onready var engine_particles = $EngineParticles
@onready var interaction_area = $InteractionArea
@onready var camera = $Camera2D

var current_target: Node = null
var flash_overlay: ColorRect

# Hyperspace sequence states
enum HyperspaceState {
	NORMAL,
	HYPERSPACE_SEQUENCE
}

enum HyperspacePhase {
	DECELERATION,
	ROTATION,
	ACCELERATION,
	FLASH,
	ENTRY
}

var hyperspace_state: HyperspaceState = HyperspaceState.NORMAL
var hyperspace_phase: HyperspacePhase = HyperspacePhase.DECELERATION
var hyperspace_destination: int = -1  # FIXED: Now integer ID
var hyperspace_timer: float = 0.0
var target_rotation: float = 0.0
var acceleration_timer: float = 0.0
var flash_timer: float = 0.0
var rotation_timer: float = 0.0
var deceleration_timer: float = 0.0
var entry_position: Vector2 = Vector2.ZERO
var entry_target: Vector2 = Vector2.ZERO
var jump_direction: Vector2 = Vector2.ZERO
var map_direction: Vector2 = Vector2.ZERO  # Store the direction from the map
var position_update_timer: float = 0.0
var position_update_interval: float = 1.0  # Update position every 1 second

func _ready():
	UniverseManager.player_ship = self
	interaction_area.body_entered.connect(_on_interaction_area_entered)
	interaction_area.body_exited.connect(_on_interaction_area_exited)
	
	# Create flash overlay for hyperspace effect
	create_flash_overlay()
	
	# Remove this line - we'll let the combat system handle weapons
	# setup_test_weapon()
	
	# Add combat system
	var combat_system = ShipCombatSystem.new()
	combat_system.name = "ShipCombatSystem"
	add_child(combat_system)
	
	# Connect combat signals for UI updates
	combat_system.hull_damaged.connect(_on_hull_damaged)
	combat_system.shields_damaged.connect(_on_shields_damaged)
	combat_system.ship_destroyed.connect(_on_player_ship_destroyed)
	
	# FIX: Manually set ship owner for hardpoints
	await get_tree().process_frame  # Wait for everything to initialize
	
	setup_player_combat()
	
	var hardpoint = get_node_or_null("WeaponHardpoint")
	if hardpoint:
		print("Setting ship owner manually...")
		hardpoint.ship_owner = self  # Directly assign the ship
		print("Ship owner set to: ", hardpoint.ship_owner.name)
	
	# Debug check
	var combat_check = get_node_or_null("ShipCombatSystem")
	if combat_check:
		print("✅ Combat system created successfully")
		print("Weapon hardpoints found: ", combat_check.weapon_hardpoints.size())
	else:
		print("❌ Combat system not found!")
		
func _process(delta: float) -> void:
	update_shield_recharge(delta)
		
func setup_player_combat():
	"""Initialize player combat stats"""
	hull = max_hull
	shields = max_shields
	print("Player combat initialized - Hull: ", hull, " Shields: ", shields)

func take_damage(amount: float, attacker: Node2D = null):
	"""Player takes damage"""
	print("*** PLAYER TAKING DAMAGE *** Amount: ", amount, " From: ", attacker.name if attacker else "unknown")
	
	var original_amount = amount
	
	# Shields absorb damage first
	if shields > 0:
		var shield_absorbed = min(amount, shields)
		shields -= shield_absorbed
		amount -= shield_absorbed
		shield_recharge_timer = shield_recharge_delay
		print("Player shields: ", shield_absorbed, " absorbed, ", shields, " remaining")
	
	# Remaining damage to hull
	if amount > 0:
		hull -= amount
		print("Player hull: ", amount, " damage, ", hull, " remaining")
		
		# Screen shake effect
		if camera:
			add_screen_shake()
		
		# Check for player death
		if hull <= 0:
			player_destroyed()

func player_destroyed():
	"""Handle player death"""
	print("*** PLAYER DESTROYED ***")
	hull = 0
	shields = 0
	
	# Simple game over for now
	get_tree().paused = true
	
	# Create simple game over popup
	var popup = AcceptDialog.new()
	popup.title = "SHIP DESTROYED"
	popup.dialog_text = "Your ship has been destroyed!\n\nPress OK to restart."
	popup.process_mode = Node.PROCESS_MODE_ALWAYS
	
	get_tree().current_scene.add_child(popup)
	popup.popup_centered()
	
	popup.confirmed.connect(func(): 
		get_tree().paused = false
		get_tree().reload_current_scene()
	)

func add_screen_shake():
	"""Simple screen shake when taking damage"""
	if not camera:
		return
	
	var shake_strength = 10.0
	var shake_duration = 0.3
	
	var original_pos = camera.offset
	var tween = create_tween()
	
	# Shake for duration
	for i in range(5):
		var shake_offset = Vector2(
			randf_range(-shake_strength, shake_strength),
			randf_range(-shake_strength, shake_strength)
		)
		tween.parallel().tween_property(camera, "offset", original_pos + shake_offset, shake_duration / 10)
	
	# Return to normal
	tween.tween_property(camera, "offset", original_pos, 0.1)

func update_shield_recharge(delta: float):
	"""Handle shield recharging"""
	if shields >= max_shields:
		return
	
	if shield_recharge_timer > 0:
		shield_recharge_timer -= delta
		return
	
	# Recharge shields
	var recharge_rate = 10.0  # shields per second
	shields = min(shields + recharge_rate * delta, max_shields)

func handle_combat_input(event):
	"""Handle combat input"""
	if event.is_action_pressed("shoot"):  # Space bar or A button
		fire_player_weapon()

func fire_player_weapon():
	"""Fire the player's weapon"""
	var weapon_hardpoint = get_node_or_null("WeaponHardpoint")
	if weapon_hardpoint and weapon_hardpoint.has_method("try_fire"):
		if weapon_hardpoint.try_fire():
			print("Player fired weapon")
		else:
			print("Player weapon not ready")

func setup_test_weapon():
	var hardpoint = get_node_or_null("WeaponHardpoint")
	if hardpoint:
		var weapon = Weapon.create_basic_laser()
		hardpoint.mount_weapon(weapon)
		print("Test weapon mounted to player ship")
		
func _on_hull_damaged(current_hull: float, max_hull: float):
	# Update UI health bars here
	pass

func _on_shields_damaged(current_shields: float, max_shields: float):
	# Update UI shield bars here
	pass

func _on_player_ship_destroyed(attacker: Node2D):
	# Handle player death (game over, respawn, etc.)
	print("Player ship destroyed!")

func _integrate_forces(state):
	if hyperspace_state == HyperspaceState.NORMAL:
		handle_input(state)
	else:
		handle_hyperspace_sequence(state)
	
	limit_velocity(state)
	
	# Update player position in PlayerData periodically (not every frame for performance)
	if hyperspace_state == HyperspaceState.NORMAL:
		update_position_tracking()

func handle_input(state):
	# Rotation
	var rotation_input = Input.get_axis("turn_left", "turn_right")
	state.angular_velocity = rotation_input * rotation_speed
	
	# Thrust (with analog support)
	var thrust_strength = Input.get_action_strength("thrust")
	if thrust_strength > 0.0:
		var thrust_vector = Vector2(0, -thrust_power * thrust_strength).rotated(rotation)
		state.apply_central_force(thrust_vector)
		engine_particles.emitting = true 
		# Optional: Scale particle intensity with thrust strength
		#engine_particles.amount = int(600 * thrust_strength)  # Base amount is 600
	else:
		engine_particles.emitting = false
		
func handle_hyperspace_sequence(state):
	"""Handle ship behavior during hyperspace sequence"""
	hyperspace_timer += get_physics_process_delta_time()
	
	# Force camera to stay locked during hyperspace
	if camera:
		camera.global_position = global_position
	
	match hyperspace_phase:
		HyperspacePhase.DECELERATION:
			handle_deceleration_phase(state)
		HyperspacePhase.ROTATION:
			handle_rotation_phase(state)
		HyperspacePhase.ACCELERATION:
			handle_acceleration_phase(state)
		HyperspacePhase.FLASH:
			handle_flash_phase(state)
		HyperspacePhase.ENTRY:
			handle_entry_phase(state)

func handle_deceleration_phase(state):
	"""Phase 1: Automatically decelerate to a stop"""
	deceleration_timer += get_physics_process_delta_time()
	
	var velocity = state.linear_velocity
	var speed = velocity.length()
	
	# If already stopped or nearly stopped, skip to rotation
	if speed <= 20.0 or deceleration_timer < 0.1:  # Check on first frame
		if speed <= 20.0:
			print("Already stopped (speed: ", speed, "), moving to rotation phase")
			state.linear_velocity = Vector2.ZERO  # Full stop
			engine_particles.emitting = false
			hyperspace_phase = HyperspacePhase.ROTATION
			rotation_timer = 0.0
			calculate_target_rotation()
			return
	
	# Timeout check
	if deceleration_timer > 3.0:
		print("Deceleration timeout, forcing stop")
		state.linear_velocity = Vector2.ZERO
		engine_particles.emitting = false
		hyperspace_phase = HyperspacePhase.ROTATION
		rotation_timer = 0.0
		calculate_target_rotation()
		return
	
	# Apply reverse thrust to slow down
	var reverse_direction = -velocity.normalized()
	var decel_force = reverse_direction * thrust_power * 2.0
	state.apply_central_force(decel_force)
	engine_particles.emitting = true
	
	print("Decelerating... Speed: ", speed)

func handle_rotation_phase(state):
	"""Phase 2: Rotate to face the destination system"""
	rotation_timer += get_physics_process_delta_time()
	var angle_diff = angle_difference(rotation, target_rotation)
	
	if abs(angle_diff) > 0.1 and rotation_timer < 1.0:
		var turn_speed = rotation_speed * 2.0
		state.angular_velocity = sign(angle_diff) * turn_speed
	else:
		state.angular_velocity = 0.0
		rotation = target_rotation
		hyperspace_phase = HyperspacePhase.ACCELERATION
		acceleration_timer = 0.0

func handle_acceleration_phase(state):
	"""Phase 3: Dramatically accelerate toward destination"""
	acceleration_timer += get_physics_process_delta_time()
	
	# Apply massive forward thrust
	var thrust_vector = Vector2(0, -hyperspace_thrust_power).rotated(rotation)
	state.apply_central_force(thrust_vector)
	engine_particles.emitting = true
	
	var current_speed = state.linear_velocity.length()
	
	# Save actual travel direction
	if current_speed > 100.0:
		jump_direction = state.linear_velocity.normalized()
	
	print("Accelerating... Speed: ", current_speed)
	
	# After 3 seconds or high speed, trigger flash
	if acceleration_timer >= 3.5 or current_speed >= hyperspace_entry_speed * 4:
		print("Acceleration complete, flash time!")
		hyperspace_phase = HyperspacePhase.FLASH
		flash_timer = 0.0

func handle_flash_phase(state):
	"""Phase 4: Flash effect and system transition"""
	flash_timer += get_physics_process_delta_time()
	
	if flash_timer < 0.3:
		# Show white flash
		if flash_overlay:
			var alpha = sin(flash_timer * PI / 0.3)  # Fade in/out
			flash_overlay.color = Color(1, 1, 1, alpha)
			flash_overlay.visible = true
	else:
		# Flash complete, transition to new system
		print("Flash complete, transitioning to new system")
		if flash_overlay:
			flash_overlay.visible = false
		
		transition_to_new_system()
		hyperspace_phase = HyperspacePhase.ENTRY

func handle_entry_phase(state):
	"""Phase 5: Enter new system and decelerate"""
	var distance_to_target = global_position.distance_to(entry_target)
	var current_speed = state.linear_velocity.length()
	
	print("Entry phase - Speed: ", current_speed, " Distance: ", distance_to_target)
	
	# Complete when close enough or slow enough
	if distance_to_target < 800 or current_speed < max_velocity:
		print("Entry complete - returning control")
		engine_particles.emitting = false
		complete_hyperspace_sequence()
		return
	
	# Apply gentle deceleration
	if current_speed > max_velocity:
		var velocity_direction = state.linear_velocity.normalized()
		var decel_force = -velocity_direction * thrust_power * 1.2
		state.apply_central_force(decel_force)
		engine_particles.emitting = true

func transition_to_new_system():
	"""Handle the actual system change and ship positioning"""
	var destination_name = UniverseManager.get_system_name(hyperspace_destination)
	print("Transitioning to new system: ", destination_name, " (ID: ", hyperspace_destination, ")")
	
	# Calculate entry position based on map direction
	var system_center = Vector2.ZERO
	var edge_distance = 3000.0
	
	# Use the stored map direction (reverse it to enter from opposite side)
	var entry_direction = -map_direction
	entry_position = system_center + entry_direction * edge_distance
	entry_target = system_center
	
	# Set velocity toward center
	linear_velocity = -entry_direction * hyperspace_entry_speed
	
	# Keep the ship's rotation
	print("Entry position: ", entry_position)
	print("Entry velocity: ", linear_velocity)
	print("Ship rotation: ", rad_to_deg(rotation), " degrees")
	
	# Force position update BEFORE changing system
	global_position = entry_position
	
	# Force camera to new position
	if camera:
		camera.global_position = global_position
		camera.reset_smoothing()  # This should reset any interpolation
	
	# Now change the system - FIXED: Now using integer ID
	UniverseManager.change_system(hyperspace_destination)
	
	# Force another camera update after system change
	if camera:
		await get_tree().process_frame  # Wait one frame
		camera.global_position = global_position
		camera.force_update_scroll()

func calculate_target_rotation():
	"""Calculate which direction the ship should face based on map"""
	# Get the direction from hyperspace map
	var system_positions = get_system_positions()
	var current_system = UniverseManager.current_system_id
	
	if current_system in system_positions and hyperspace_destination in system_positions:
		var current_pos = system_positions[current_system]
		var target_pos = system_positions[hyperspace_destination]
		
		# Calculate direction to target
		map_direction = (target_pos - current_pos).normalized()
		
		# Convert to rotation (ship faces up by default, which is -Y direction)
		# So we need to subtract PI/2 instead of adding it
		target_rotation = map_direction.angle() + PI/2
		
		var destination_name = UniverseManager.get_system_name(hyperspace_destination)
		print("Direction to ", destination_name, ": ", map_direction)
		print("Target rotation: ", rad_to_deg(target_rotation), " degrees")
		print("Current rotation: ", rad_to_deg(rotation), " degrees")
	else:
		# Fallback
		target_rotation = 0.0
		map_direction = Vector2(0, -1)

func get_system_positions() -> Dictionary:
	"""Get system positions using same coordinate system as hyperspace map"""
	var positions = {}
	
	# Query database directly for raw coordinates (same as hyperspace map)
	if not UniverseManager.db:
		print("❌ Database not available for position lookup")
		return positions
	
	var systems_query = """
		SELECT id, x, y FROM systems;
	"""
	
	UniverseManager.db.query(systems_query)
	var results = UniverseManager.db.query_result
	
	for system_row in results:
		var system_id = system_row.id
		# Use same coordinate system as hyperspace map (with Y-flip)
		positions[system_id] = Vector2(
			float(system_row.x),
			-float(system_row.y)  # Apply Y-flip to match hyperspace map display
		)
	
	print("Loaded ", positions.size(), " system positions for hyperspace navigation")
	return positions

func angle_difference(current: float, target: float) -> float:
	"""Calculate the shortest angle difference between two angles"""
	var diff = target - current
	# Normalize to [-PI, PI]
	while diff > PI:
		diff -= 2 * PI
	while diff < -PI:
		diff += 2 * PI
	return diff

func limit_velocity(state):
	if hyperspace_state == HyperspaceState.HYPERSPACE_SEQUENCE:
		return
		
	if state.linear_velocity.length() > max_velocity:
		state.linear_velocity = state.linear_velocity.normalized() * max_velocity

func _input(event):
	if hyperspace_state != HyperspaceState.NORMAL:
		return
		
	if event.is_action_pressed("interact") and current_target:
		interact_with_target()
	elif event.is_action_pressed("hyperspace"):
		open_hyperspace_menu()
	elif event.is_action_pressed("land") or event.is_action_pressed("ui_accept"):
		# Land with L key or A button when over a planet
		if attempt_landing():
			# If landing was successful, consume the input to prevent menu issues
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed("mission_log"):
		# Toggle mission log
		toggle_mission_log()
	elif event.is_action_pressed("debug_toggle"):
		# Debug: Test mission system
		if OS.is_debug_build():
			debug_test_mission_system()
# In _input() function, add:
	if event.is_action_pressed("shoot"):  # Space bar or A button
		var combat_system = get_node_or_null("ShipCombatSystem")
		if combat_system:
			combat_system.fire_primary_weapons()
#TEMP below this line
	if event.is_action_pressed("shoot"):
		print("🔫 DIRECT WEAPON TEST")
		
		# Direct hardpoint test
		var hardpoint = get_node_or_null("WeaponHardpoint")
		if hardpoint:
			print("Hardpoint found, trying direct fire...")
			
			# Make sure it has a weapon
			if not hardpoint.weapon_data:
				hardpoint.mount_weapon(Weapon.create_basic_laser())
				print("Mounted basic laser")
			
			# Try to fire
			var fired = hardpoint.try_fire()
			print("Direct fire result: ", fired)
			print("Can fire now: ", hardpoint.can_fire_now())
			print("Reload timer: ", hardpoint.reload_timer)
		else:
			print("❌ No hardpoint found!")
			
	#debug_combat_input(event)
#TEMP above this line

func interact_with_target():
	if current_target.has_method("interact"):
		current_target.interact()

func refresh_interaction_detection():
	"""Force refresh of interaction area detection"""
	current_target = null
	
	# Manually check what's in our interaction area
	var bodies_in_area = interaction_area.get_overlapping_bodies()
	for body in bodies_in_area:
		if body.has_method("can_interact") and body.can_interact():
			current_target = body
			print("Refreshed target: ", body.celestial_data.get("name", "Unknown"))
			break
	
	if not current_target:
		print("No targets found after refresh")

func open_hyperspace_menu():
	var ui = get_tree().get_first_node_in_group("ui")
	if ui and ui.has_method("show_hyperspace_menu"):
		ui.show_hyperspace_menu()

func toggle_mission_log():
	"""Toggle the mission log interface"""
	var ui_controller = get_tree().get_first_node_in_group("ui")
	if not ui_controller:
		print("❌ Could not find UI controller for mission log")
		return
	
	# Get or create the mission log UI
	var mission_log_ui = ui_controller.get_node_or_null("MissionLogUI")
	if not mission_log_ui:
		# Create the mission log UI
		var mission_log_scene = load("res://scenes/MissionLogUI.tscn")
		if not mission_log_scene:
			print("❌ Could not load MissionLogUI.tscn")
			return
		
		mission_log_ui = mission_log_scene.instantiate()
		mission_log_ui.name = "MissionLogUI"
		ui_controller.add_child(mission_log_ui)
		print("Created MissionLogUI")
	
	# Toggle the mission log
	mission_log_ui.toggle_mission_log()

func attempt_landing() -> bool:
	"""Attempt to land on the nearest landable planet. Returns true if successful."""
	var current_speed = linear_velocity.length()
	var max_landing_speed = 150.0
	
	print("=== LANDING ATTEMPT ===")
	print("Current speed: ", current_speed)
	print("Max landing speed: ", max_landing_speed)
	
	# ALWAYS search for the nearest landable planet - don't rely on cached current_target
	var nearby_planet = find_nearby_landable_planet()
	if not nearby_planet:
		print("❌ No landable planet nearby")
		return false
	
	# Update current_target to the nearest planet
	current_target = nearby_planet
	print("Current target: ", current_target.celestial_data.get("name", "Unknown"))
	
	# Check if target can be landed on
	if not current_target.has_method("can_interact") or not current_target.can_interact():
		print("❌ Cannot land on this target: ", current_target.celestial_data.get("name", "Unknown"))
		return false
	
	# Check speed requirement
	if current_speed > max_landing_speed:
		print("❌ Moving too fast to land! Slow down to under ", max_landing_speed, " units/sec")
		print("   (Current speed: ", round(current_speed), ")")
		return false
	
	# All checks passed - show landing interface
	print("✅ Landing conditions met!")
	show_planet_landing_ui()
	return true

func show_planet_landing_ui():
	"""Show the planet landing user interface"""
	var ui_controller = get_tree().get_first_node_in_group("ui")
	if not ui_controller:
		print("❌ Could not find UI controller")
		return
	
	# Get or create the landing UI
	var landing_ui = ui_controller.get_node_or_null("PlanetLandingUI")
	if not landing_ui:
		# Create the landing UI
		var landing_ui_scene = load("res://scenes/PlanetLandingUI.tscn")
		if not landing_ui_scene:
			print("❌ Could not load PlanetLandingUI.tscn")
			return
		
		landing_ui = landing_ui_scene.instantiate()
		landing_ui.name = "PlanetLandingUI"
		ui_controller.add_child(landing_ui)
		print("Created PlanetLandingUI")
	
	# Use the current_target that was just found/updated in attempt_landing()
	var planet_data = current_target.celestial_data
	var system_id = UniverseManager.current_system_id
	
	print("Showing landing UI for: ", planet_data.get("name", "Unknown"))
	landing_ui.show_landing_interface(planet_data, system_id)
	print("✅ Planet landing UI displayed")

func find_nearby_landable_planet() -> Node:
	"""Find a landable planet"""
	var system_scene = get_tree().get_first_node_in_group("system_scene")
	if not system_scene:
		return null
	
	var celestial_container = system_scene.get_node_or_null("CelestialBodies")
	if not celestial_container:
		return null
	
	var closest_planet = null
	var closest_distance = INF
	
	for body in celestial_container.get_children():
		if body.has_method("can_interact") and body.can_interact():
			# Check if player is within this body's interaction area
			var interaction_area = body.get_node_or_null("InteractionArea")
			if interaction_area:
				var overlapping_bodies = interaction_area.get_overlapping_bodies()
				if self in overlapping_bodies:
					# Player is within interaction area - check if it's the closest
					var distance = global_position.distance_to(body.global_position)
					if distance < closest_distance:
						closest_distance = distance
						closest_planet = body
	
	if closest_planet:
		print("Found landable planet: ", closest_planet.celestial_data.get("name", "Unknown"))
	else:
		print("No landable planets within interaction range")
	
	return closest_planet

func check_for_deliveries():
	"""Check if player has missions to deliver to this planet"""
	var planet_id = current_target.celestial_data.get("id", -1)  # FIXED: Now integer
	var system_id = UniverseManager.current_system_id  # FIXED: Now integer
	
	var delivery_mission = PlayerData.has_active_mission_to_planet(planet_id, system_id)
	if not delivery_mission.is_empty():
		print("🎉 DELIVERY COMPLETED!")
		print("Delivered: ", delivery_mission.get("cargo_type", "Unknown Cargo"))
		print("Payment: ", delivery_mission.get("payment", 0), " credits")
		
		# Complete the mission
		var mission_id = delivery_mission.get("id", "")
		if mission_id != "":
			PlayerData.complete_mission(mission_id)
		
		print("✅ Mission completed successfully!")
	else:
		print("No deliveries for this location")

func show_available_missions():
	"""Show missions available for pickup at this planet"""
	var planet_id = current_target.celestial_data.get("id", -1)  # FIXED: Now integer
	if planet_id != -1:
		var missions = UniverseManager.get_missions_for_planet(planet_id)
		print("📦 Available missions at this location: ", missions.size())
		
		if missions.size() > 0:
			print("Available cargo missions:")
			for i in range(missions.size()):
				var mission = missions[i]
				print("  ", i + 1, ". ", MissionGenerator.get_mission_description(mission))
			print("(Mission selection UI will be implemented in Stage 2)")
		else:
			print("No missions available at this location")
	print("=== END LANDING ===")

func debug_test_mission_system():
	"""Debug method to test mission system foundation (remove later)"""
	print("=== TESTING MISSION SYSTEM FOUNDATION ===")
	
	# Test PlayerData
	print("Testing PlayerData...")
	PlayerData.debug_print_status()
	
	# Test MissionGenerator with new pathfinding system
	print("Testing MissionGenerator with pathfinding...")
	MissionGenerator.debug_test_distance_distribution()
	
	# Test system missions
	print("Testing current system missions...")
	var current_system = UniverseManager.get_current_system()
	print("Current system: ", current_system.get("name", "Unknown"))
	
	# Get first landable planet in current system for testing
	var celestial_bodies = current_system.get("celestial_bodies", [])
	var test_planet_id = -1
	var test_planet_name = "Unknown"
	
	for body in celestial_bodies:
		if body.get("can_land", false):
			test_planet_id = body.get("id", -1)
			test_planet_name = body.get("name", "Unknown")
			break
	
	if test_planet_id != -1:
		var planet_missions = UniverseManager.get_missions_for_planet(test_planet_id)
		print(test_planet_name, " has ", planet_missions.size(), " missions:")
		for mission in planet_missions:
			print("  - ", MissionGenerator.get_mission_description(mission))
	else:
		print("No landable planets found in current system for testing")
	
	# Test pathfinding specifically
	print("Testing pathfinding system...")
	var current_system_id = UniverseManager.current_system_id
	UniverseManager.debug_distance_distribution(current_system_id)
	
	print("=== MISSION SYSTEM TEST COMPLETE ===")
	print("Press F12 again to test, L to land on planets")

func _on_interaction_area_entered(body):
	if body.has_method("can_interact") and body.can_interact():
		current_target = body
		print("Can interact with: ", body.celestial_data.name)

func _on_interaction_area_exited(body):
	if body == current_target:
		current_target = null

func start_hyperspace_sequence(destination_system: int):  # FIXED: Now integer parameter
	"""Begin the hyperspace jump sequence"""
	var destination_name = UniverseManager.get_system_name(destination_system)
	print("Starting hyperspace sequence to: ", destination_name, " (ID: ", destination_system, ")")
	
	# Check if player has jumps available
	if not PlayerData.can_hyperspace_jump():
		show_no_jumps_notification()
		return
	
	# Consume a hyperspace jump
	if not PlayerData.consume_hyperspace_jump():
		show_no_jumps_notification()
		return
	
	# Disable camera smoothing for the entire sequence
	if camera:
		camera.position_smoothing_enabled = false
		camera.global_position = global_position
	
	# Reset all state - FIXED: Now using integer ID
	hyperspace_state = HyperspaceState.HYPERSPACE_SEQUENCE
	hyperspace_phase = HyperspacePhase.DECELERATION
	hyperspace_destination = destination_system  # Now integer
	hyperspace_timer = 0.0
	target_rotation = 0.0
	acceleration_timer = 0.0
	flash_timer = 0.0
	rotation_timer = 0.0
	deceleration_timer = 0.0
	entry_position = Vector2.ZERO
	entry_target = Vector2.ZERO
	jump_direction = Vector2.ZERO
	
	print("Phase 1: Beginning deceleration")

func show_no_jumps_notification():
	"""Show notification when player has no hyperspace jumps remaining"""
	print("❌ No hyperspace jumps remaining!")
	
	# Create a notification popup
	var popup = AcceptDialog.new()
	popup.title = "HYPERSPACE DRIVE DEPLETED"
	popup.size = Vector2(500, 300)
	
	# Create custom content
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 15)
	
	# Header
	var header = Label.new()
	header.text = "⚠ HYPERSPACE DRIVE FUEL DEPLETED"
	header.add_theme_color_override("font_color", Color(1, 0.5, 0, 1))  # Orange
	header.add_theme_font_size_override("font_size", 20)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(header)
	
	# Separator
	var separator = HSeparator.new()
	separator.add_theme_color_override("separator", Color(1, 0.5, 0, 1))
	vbox.add_child(separator)
	
	# Details
	var details = Label.new()
	var jumps_info = "Current Jumps: %d/%d" % [PlayerData.get_current_jumps(), PlayerData.get_max_jumps()]
	details.text = "Your hyperspace drive requires fuel to make jumps between systems.\n\n"
	details.text += jumps_info + "\n\n"
	details.text += "Land on a nearby planet or station to recharge your hyperspace drive.\n\n"
	details.text += "Recharge costs 200 credits per jump."
	
	details.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9, 1))
	details.add_theme_font_size_override("font_size", 16)
	details.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(details)
	
	# Add content to popup
	popup.add_child(vbox)
	
	# Style the popup
	var style_box = StyleBoxFlat.new()
	style_box.bg_color = Color(0.1, 0.05, 0, 0.95)  # Dark orange background
	style_box.border_color = Color(1, 0.5, 0, 1)   # Orange border
	style_box.border_width_left = 2
	style_box.border_width_right = 2
	style_box.border_width_top = 2
	style_box.border_width_bottom = 2
	popup.add_theme_stylebox_override("panel", style_box)
	
	# Add to scene and show
	add_child(popup)
	popup.popup_centered()
	
	# Clean up when closed
	popup.confirmed.connect(func(): popup.queue_free())

func update_position_tracking():
	"""Update player position in PlayerData periodically"""
	position_update_timer += get_physics_process_delta_time()
	
	if position_update_timer >= position_update_interval:
		position_update_timer = 0.0
		PlayerData.set_system_position(global_position)

func complete_hyperspace_sequence():
	"""Complete the hyperspace sequence and return control to player"""
	print("Hyperspace sequence complete")
	
	# Re-enable camera smoothing
	if camera:
		camera.position_smoothing_enabled = true
	
	# Update position immediately after hyperspace
	PlayerData.set_system_position(global_position)
	
	# Reset to normal state - FIXED: Reset to integer -1
	hyperspace_state = HyperspaceState.NORMAL
	hyperspace_phase = HyperspacePhase.DECELERATION
	hyperspace_destination = -1  # FIXED: Reset to integer -1
	hyperspace_timer = 0.0
	target_rotation = 0.0
	acceleration_timer = 0.0
	flash_timer = 0.0
	rotation_timer = 0.0
	deceleration_timer = 0.0
	entry_position = Vector2.ZERO
	entry_target = Vector2.ZERO
	jump_direction = Vector2.ZERO
	map_direction = Vector2.ZERO

func create_flash_overlay():
	"""Create the white flash overlay for hyperspace effect"""
	# Create a CanvasLayer to ensure it renders above everything
	var canvas_layer = CanvasLayer.new()
	canvas_layer.name = "FlashLayer"
	canvas_layer.layer = 10  # High layer to be above everything
	add_child(canvas_layer)
	
	# Create the flash overlay
	flash_overlay = ColorRect.new()
	flash_overlay.name = "FlashOverlay"
	flash_overlay.color = Color(1, 1, 1, 0)
	flash_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash_overlay.visible = false
	
	# Make it full screen
	flash_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	
	# Add to canvas layer
	canvas_layer.add_child(flash_overlay)
	
	print("Flash overlay created in CanvasLayer")

func spawn_test_npc():
	"""Spawn a test NPC near the player for combat testing"""
	var npc_scene = load("res://scenes/NPCShip.tscn")
	if not npc_scene:
		print("❌ Could not load NPCShip scene")
		return
	
	var npc = npc_scene.instantiate()
	if not npc:
		print("❌ Could not instantiate NPC")
		return
	
	# Position near player
	var spawn_offset = Vector2(300, 0).rotated(randf() * TAU)
	npc.global_position = global_position + spawn_offset
	npc.linear_velocity = Vector2.ZERO
	
	# Add to scene
	get_tree().current_scene.add_child(npc)
	
	print("✅ Spawned test NPC at: ", npc.global_position)
	print("Press F12 again to damage it and test combat AI")
