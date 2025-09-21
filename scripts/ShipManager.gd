# =============================================================================
# SHIP MANAGER - Singleton for ship definitions and management
# =============================================================================
# ShipManager.gd - Singleton (AutoLoad)
extends Node

signal ship_purchased(ship_data: Dictionary)
signal ship_changed(new_ship_id: String)

var ships_data: Dictionary = {}
var current_ship_id: String = ""

# Trade-in value percentage
const TRADE_IN_VALUE_PERCENT: float = 0.75

func _ready():
	print("ShipManager singleton initialized")
	load_ships_data()
	
	# FIXED: Only set starting ship if we don't already have one
	# This preserves the player's ship when the scene reloads after death
	if current_ship_id == "":
		var starting_ship = ships_data.get("starting_ship", "scout_mk1")
		current_ship_id = starting_ship
		print("Setting initial starting ship ID to: ", current_ship_id)
	else:
		print("Preserving existing ship ID: ", current_ship_id, " (scene reload)")
	
	# Connect to UniverseManager to know when player ship is available
	if UniverseManager:
		UniverseManager.connect("tree_entered", _on_universe_manager_ready)
	
	# Try to apply stats after a short delay to ensure everything is loaded
	call_deferred("try_apply_initial_ship")

func load_ships_data():
	"""Load ship definitions from ships.json"""
	var file = FileAccess.open("res://data/ships.json", FileAccess.READ)
	if file:
		var json_text = file.get_as_text()
		file.close()
		var json = JSON.new()
		var parse_result = json.parse(json_text)
		if parse_result == OK:
			ships_data = json.data
			print("Loaded ", ships_data.get("ships", {}).size(), " ship definitions")
		else:
			push_error("Failed to parse ships.json: " + json.get_error_message())
	else:
		push_error("Could not open ships.json")

# =============================================================================
# SHIP DATA ACCESS
# =============================================================================

func get_ship_data(ship_id: String) -> Dictionary:
	"""Get complete data for a specific ship"""
	var ships = ships_data.get("ships", {})
	return ships.get(ship_id, {})

func get_current_ship_data() -> Dictionary:
	"""Get data for the currently owned ship"""
	return get_ship_data(current_ship_id)

func get_all_ships() -> Dictionary:
	"""Get all available ship data"""
	return ships_data.get("ships", {})

func get_available_ships() -> Array:
	"""Get list of all available ship IDs"""
	var ships = ships_data.get("ships", {})
	var ship_keys = ships.keys()
	var ship_array: Array = []
	
	# Convert to proper array
	for key in ship_keys:
		ship_array.append(str(key))
	
	return ship_array

func ship_exists(ship_id: String) -> bool:
	"""Check if a ship ID exists in the database"""
	var ships = ships_data.get("ships", {})
	return ships.has(ship_id)

# =============================================================================
# SHIP STATS AND PROPERTIES
# =============================================================================

func get_ship_cost(ship_id: String) -> int:
	"""Get the purchase cost of a ship"""
	var ship_data = get_ship_data(ship_id)
	return ship_data.get("cost", 0)

func get_ship_trade_in_value(ship_id: String) -> int:
	"""Get the trade-in value of a ship (75% of cost)"""
	var cost = get_ship_cost(ship_id)
	return int(cost * TRADE_IN_VALUE_PERCENT)

func get_current_ship_trade_in_value() -> int:
	"""Get trade-in value of currently owned ship"""
	return get_ship_trade_in_value(current_ship_id)

func get_ship_stats(ship_id: String) -> Dictionary:
	"""Get the stats dictionary for a ship"""
	var ship_data = get_ship_data(ship_id)
	return ship_data.get("stats", {})

func get_ship_graphics(ship_id: String) -> Dictionary:
	"""Get the graphics paths for a ship"""
	var ship_data = get_ship_data(ship_id)
	return ship_data.get("graphics", {})

func get_ship_sprite_path(ship_id: String) -> String:
	"""Get the main sprite path for a ship"""
	var graphics = get_ship_graphics(ship_id)
	return graphics.get("sprite", "res://sprites/ships/player_ship.png")  # Default fallback

func get_ship_thumbnail_path(ship_id: String) -> String:
	"""Get the thumbnail path for a ship"""
	var graphics = get_ship_graphics(ship_id)
	return graphics.get("thumbnail", "res://sprites/ships/player_ship.png")  # Default fallback

func get_ship_large_view_path(ship_id: String) -> String:
	"""Get the large view path for a ship"""
	var graphics = get_ship_graphics(ship_id)
	return graphics.get("large_view", "res://sprites/ships/player_ship.png")  # Default fallback

# =============================================================================
# SHIP OWNERSHIP AND SWITCHING
# =============================================================================

func set_current_ship(ship_id: String):
	"""Set the player's current ship"""
	if ship_exists(ship_id):
		current_ship_id = ship_id
		print("Current ship set to: ", ship_id)
		
		# Apply ship stats to player
		apply_ship_to_player()
		
		ship_changed.emit(ship_id)
	else:
		push_error("Attempted to set invalid ship: " + ship_id)

func apply_ship_to_player():
	"""Apply current ship's stats and graphics to the player ship"""
	var ship_stats = get_ship_stats(current_ship_id)
	var ship_graphics = get_ship_graphics(current_ship_id)
	
	if ship_stats.is_empty():
		push_error("No stats found for ship: " + current_ship_id)
		return
	
	# Update player ship stats
	var player_ship = UniverseManager.player_ship
	if player_ship:
		# Apply movement stats
		if ship_stats.has("thrust_power"):
			player_ship.thrust_power = ship_stats.thrust_power
		if ship_stats.has("rotation_speed"):
			player_ship.rotation_speed = ship_stats.rotation_speed
		if ship_stats.has("max_velocity"):
			player_ship.max_velocity = ship_stats.max_velocity
		if ship_stats.has("hyperspace_thrust_power"):
			player_ship.hyperspace_thrust_power = ship_stats.hyperspace_thrust_power
		if ship_stats.has("hyperspace_entry_speed"):
			player_ship.hyperspace_entry_speed = ship_stats.hyperspace_entry_speed
		
		print("Applied ship stats to player ship: ", current_ship_id)
	else:
		print("Player ship not found, stats will be applied when ship is available")
	
	# Update cargo capacity in PlayerData
	if ship_stats.has("cargo_capacity"):
		PlayerData.cargo_capacity = ship_stats.cargo_capacity
		PlayerData.cargo_changed.emit(PlayerData.current_cargo_weight, PlayerData.cargo_capacity)
		print("Updated cargo capacity to: ", ship_stats.cargo_capacity)
	
	# Update player ship graphics
	apply_ship_graphics()

func apply_ship_graphics():
	"""Apply current ship's graphics to the player ship"""
	var player_ship = UniverseManager.player_ship
	if not player_ship:
		print("Player ship not found in UniverseManager, searching scene tree...")
		# Try to find player ship in current scene tree as fallback
		var scene_tree = Engine.get_main_loop() as SceneTree
		if scene_tree and scene_tree.current_scene:
			player_ship = scene_tree.current_scene.find_child("PlayerShip", true, false)
			if not player_ship:
				print("Player ship not found in scene tree either - deferring graphics application")
				# Set up a timer to retry later
				call_deferred("_retry_apply_graphics")
				return
	
	# Double-check player_ship is still valid before accessing its children
	if not player_ship or not is_instance_valid(player_ship):
		print("Player ship became invalid - deferring graphics application")
		call_deferred("_retry_apply_graphics")
		return
	
	var sprite_path = get_ship_sprite_path(current_ship_id)
	var sprite_node = player_ship.get_node_or_null("Sprite2D")
	
	if sprite_node and is_instance_valid(sprite_node):
		var texture = load(sprite_path)
		if texture:
			sprite_node.texture = texture
			print("Applied ship graphics: ", sprite_path, " to player ship")
		else:
			push_warning("Could not load ship sprite: " + sprite_path + " - using default")
			# Fallback to default sprite
			var default_texture = load("res://sprites/ships/player_ship.png")
			if default_texture:
				sprite_node.texture = default_texture
	else:
		print("Could not find valid Sprite2D node in player ship - deferring graphics application")
		call_deferred("_retry_apply_graphics")

# =============================================================================
# SHIP PURCHASING
# =============================================================================

func can_afford_ship(ship_id: String) -> bool:
	"""Check if player can afford a ship (with trade-in)"""
	var ship_cost = get_ship_cost(ship_id)
	var trade_in_value = get_current_ship_trade_in_value()
	var net_cost = ship_cost - trade_in_value
	
	return PlayerData.get_credits() >= net_cost

func get_net_ship_cost(ship_id: String) -> int:
	"""Get the net cost of a ship after trade-in"""
	var ship_cost = get_ship_cost(ship_id)
	var trade_in_value = get_current_ship_trade_in_value()
	return ship_cost - trade_in_value

func purchase_ship(ship_id: String) -> bool:
	"""Purchase a new ship, trading in the current one"""
	if not ship_exists(ship_id):
		push_error("Attempted to purchase invalid ship: " + ship_id)
		return false
	
	if ship_id == current_ship_id:
		print("Player already owns this ship")
		return false
	
	if not can_afford_ship(ship_id):
		print("Player cannot afford ship: ", ship_id)
		return false
	
	# Calculate costs
	var ship_cost = get_ship_cost(ship_id)
	var trade_in_value = get_current_ship_trade_in_value()
	var net_cost = ship_cost - trade_in_value
	
	# Process the transaction
	var old_ship_id = current_ship_id
	PlayerData.subtract_credits(net_cost)
	set_current_ship(ship_id)
	
	# Emit purchase signal
	var ship_data = get_ship_data(ship_id)
	ship_purchased.emit(ship_data)
	
	print("Ship purchased! ", old_ship_id, " -> ", ship_id)
	print("Cost: ", ship_cost, " - Trade-in: ", trade_in_value, " = Net: ", net_cost)
	
	return true

# =============================================================================
# DEBUG AND UTILITY METHODS
# =============================================================================

func debug_print_all_ships():
	"""Print all available ships for debugging"""
	print("=== ALL AVAILABLE SHIPS ===")
	var ships = get_all_ships()
	for ship_id in ships:
		var ship_data = ships[ship_id]
		print(ship_id, ": ", ship_data.get("name", "Unknown"), " - ", ship_data.get("cost", 0), " credits")
	print("=== TOTAL: ", ships.size(), " ships ===")

func debug_print_current_ship():
	"""Print current ship info for debugging"""
	print("=== CURRENT SHIP ===")
	var ship_data = get_current_ship_data()
	print("ID: ", current_ship_id)
	print("Name: ", ship_data.get("name", "Unknown"))
	print("Cost: ", ship_data.get("cost", 0))
	print("Trade-in Value: ", get_current_ship_trade_in_value())
	print("Stats: ", ship_data.get("stats", {}))
	print("===================")

func format_credits(amount: int) -> String:
	"""Format credit amounts with commas (borrowed from MissionGenerator)"""
	return MissionGenerator.format_credits(amount)

func try_apply_initial_ship():
	"""Try to apply initial ship stats, with retry if player ship not ready"""
	if UniverseManager.player_ship:
		print("Player ship found, applying initial ship stats")
		apply_ship_to_player()
		ship_changed.emit(current_ship_id)
	else:
		print("Player ship not ready yet, will try again...")
		# Try again after another frame
		await get_tree().process_frame
		if UniverseManager.player_ship:
			print("Player ship found on retry, applying initial ship stats")
			apply_ship_to_player() 
			ship_changed.emit(current_ship_id)
		else:
			print("Player ship still not ready - will be applied when ship registers")
			await get_tree().process_frame
			apply_ship_graphics()

func _retry_apply_graphics():
	"""Retry applying graphics after a delay"""
	await get_tree().create_timer(0.5).timeout
	
	var player_ship = UniverseManager.player_ship
	if not player_ship:
		var scene_tree = Engine.get_main_loop() as SceneTree
		if scene_tree and scene_tree.current_scene:
			player_ship = scene_tree.current_scene.find_child("PlayerShip", true, false)
	
	# Validate player_ship before proceeding
	if player_ship and is_instance_valid(player_ship):
		var sprite_path = get_ship_sprite_path(current_ship_id)
		var sprite_node = player_ship.get_node_or_null("Sprite2D")
		
		if sprite_node and is_instance_valid(sprite_node):
			var texture = load(sprite_path)
			if texture:
				sprite_node.texture = texture
				print("Applied ship graphics on retry: ", sprite_path)
			else:
				push_warning("Could not load ship sprite on retry: " + sprite_path)
		else:
			print("Still could not find valid Sprite2D node on retry")
	else:
		print("Player ship still not available or invalid after retry")

func _on_universe_manager_ready():
	"""Called when UniverseManager is ready"""
	try_apply_initial_ship()
