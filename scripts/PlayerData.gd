# =============================================================================
# PLAYER DATA - Singleton for persistent player information
# =============================================================================
# PlayerData.gd - Singleton (AutoLoad)
extends Node

signal credits_changed(new_amount)
signal mission_accepted(mission_data)
signal mission_completed(mission_data)
signal cargo_changed(current_weight, max_capacity)
signal jumps_changed(current_jumps, max_jumps)


# Player Stats
var credits: int = 50000
var cargo_capacity: int = 100  # tons
var current_cargo_weight: int = 0

# Location Management
var current_system_id: int = 1  # Current system ID

# Ship Management
var current_ship_id: String = "scout_mk1"  # Default starting ship

# Hyperspace Jump System
var hyperspace_jump_capacity: int = 3  # Maximum jumps this ship can store
var current_hyperspace_jumps: int = 3  # Current jumps available

# Position in System
var system_position: Vector2 = Vector2.ZERO  # Current coordinates within the system

# Mission Data
var active_missions: Array[Dictionary] = []
var completed_missions: Array[Dictionary] = []

# Ship stats
var hull: float = 1000.0
var max_hull: float = 1000.0
var shields: float = 1000.0
var max_shields: float = 1000.0

# Mission ID counter for unique IDs
var next_mission_id: int = 1

# Flag to prevent saving before data is loaded
var _data_loaded: bool = false

func _ready():
	print("PlayerData singleton initialized")
	# Don't print starting values here - they'll be loaded from save


func _notification(what):
	"""Handle system notifications"""
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		print("Game closing - saving player data...")
		save_to_database()
		# Allow the game to close
		get_tree().quit()

func initialize_from_save():
	"""Initialize player data from current save"""
	print("DEBUG: initialize_from_save() called")
	
	# Check if SaveManager has a current save loaded
	if SaveManager.current_save_id == "":
		print("ERROR: No save loaded in SaveManager!")
		return
	
	var save_data = SaveManager.load_player_data()
	print("DEBUG: save_data received: ", save_data)
	
	if save_data.is_empty():
		print("ERROR: No save data found, using defaults")
		return
	
	print("DEBUG: Loading data from save...")
	print("  Raw credits: ", save_data.get("credits", "NOT_FOUND"))
	print("  Raw cargo_weight: ", save_data.get("current_cargo_weight", "NOT_FOUND"))
	print("  Raw jumps: ", save_data.get("current_hyperspace_jumps", "NOT_FOUND"))

	# Load basic stats
	credits = save_data.get("credits", 50000)
	cargo_capacity = save_data.get("cargo_capacity", 100)
	current_cargo_weight = save_data.get("current_cargo_weight", 0)
	current_system_id = save_data.get("current_system_id", 1)
	current_ship_id = save_data.get("current_ship_id", "scout_mk1")
	hyperspace_jump_capacity = save_data.get("hyperspace_jump_capacity", 3)
	current_hyperspace_jumps = save_data.get("current_hyperspace_jumps", 3)
	
	# Validate ship stats against ships.json to ensure consistency
	var ship_stats = ShipManager.get_ship_stats(current_ship_id)
	if not ship_stats.is_empty():
		var expected_cargo = ship_stats.get("cargo_capacity", cargo_capacity)
		var expected_jumps = ship_stats.get("hyperspace_jump_capacity", hyperspace_jump_capacity)
		
		# Update if ship data has changed since save was created
		if expected_cargo != cargo_capacity:
			print("Updating cargo capacity from ships.json: ", cargo_capacity, " -> ", expected_cargo)
			cargo_capacity = expected_cargo
		
		if expected_jumps != hyperspace_jump_capacity:
			print("Updating jump capacity from ships.json: ", hyperspace_jump_capacity, " -> ", expected_jumps)
			hyperspace_jump_capacity = expected_jumps
			# Don't exceed new capacity
			current_hyperspace_jumps = min(current_hyperspace_jumps, hyperspace_jump_capacity)
	
	# Apply the loaded ship to ShipManager and update graphics
	ShipManager.set_current_ship(current_ship_id)
	print("Applied loaded ship to ShipManager: ", current_ship_id)
	
	print("DEBUG: After loading:")
	print("  credits = ", credits)
	print("  current_cargo_weight = ", current_cargo_weight)
	print("  current_hyperspace_jumps = ", current_hyperspace_jumps)
	
	# Emit signals to update UI with loaded values
	credits_changed.emit(credits)
	cargo_changed.emit(current_cargo_weight, cargo_capacity)
	jumps_changed.emit(current_hyperspace_jumps, hyperspace_jump_capacity)
	
	# Load position
	var pos_x = save_data.get("system_position_x", 0.0)
	var pos_y = save_data.get("system_position_y", 0.0)
	system_position = Vector2(pos_x, pos_y)
	
	# Load ship stats
	hull = save_data.get("ship_hull", 1000.0)
	max_hull = save_data.get("ship_max_hull", 1000.0)
	shields = save_data.get("ship_shields", 1000.0)
	max_shields = save_data.get("ship_max_shields", 1000.0)
	
	# Load missions
	load_missions_from_save()
	
	print("Player data loaded from save:")
	print("  Credits: ", credits)
	print("  System ID: ", current_system_id)
	print("  Ship: ", current_ship_id)
	print("  Cargo: ", current_cargo_weight, "/", cargo_capacity)
	print("  Jumps: ", current_hyperspace_jumps, "/", hyperspace_jump_capacity)
	print("  Position: ", system_position)
	print("  Hull: ", hull, "/", max_hull)
	print("  Shields: ", shields, "/", max_shields)
	print("  Active missions: ", active_missions.size())
	
	# Debug: Print raw save data to see what was actually loaded
	print("Raw save data:")
	print("  current_cargo_weight: ", save_data.get("current_cargo_weight", "NOT FOUND"))
	print("  current_hyperspace_jumps: ", save_data.get("current_hyperspace_jumps", "NOT FOUND"))
	
	# Mark data as loaded to enable saving
	_data_loaded = true

func load_missions_from_save():
	"""Load active missions from save database"""
	var db = SaveManager.get_current_save_database()
	if not db:
		return
	
	var query_sql = """
		SELECT * FROM player_missions WHERE status = 'active';
	"""
	
	db.query(query_sql)
	var results = db.query_result
	
	active_missions.clear()
	for mission_row in results:
		var mission_data = {
			"id": mission_row.id,
			"status": mission_row.status,
			"cargo_type": mission_row.cargo_type,
			"cargo_weight": mission_row.cargo_weight,
			"origin_planet": mission_row.origin_planet_id,
			"origin_system": mission_row.origin_system_id,
			"destination_planet": mission_row.destination_planet_id,
			"destination_system": mission_row.destination_system_id,
			"destination_planet_name": mission_row.get("destination_planet_name", "Unknown"),
			"destination_system_name": mission_row.get("destination_system_name", "Unknown System"),
			"payment": mission_row.payment,
			"accepted_timestamp": mission_row.accepted_timestamp
		}
		active_missions.append(mission_data)
	
	print("Loaded ", active_missions.size(), " active missions from save")

# =============================================================================
# CREDITS MANAGEMENT
# =============================================================================

func add_credits(amount: int):
	"""Add credits to player account"""
	print("DEBUG: add_credits called with amount: ", amount, " (current: ", credits, ")")
	credits += amount
	credits_changed.emit(credits)
	save_to_database()
	print("Credits added: +", amount, " (Total: ", credits, ")")

func subtract_credits(amount: int) -> bool:
	"""Subtract credits if player has enough. Returns true if successful."""
	print("DEBUG: subtract_credits called with amount: ", amount, " (current: ", credits, ")")
	if credits >= amount:
		credits -= amount
		credits_changed.emit(credits)
		save_to_database()
		print("Credits spent: -", amount, " (Total: ", credits, ")")
		return true
	else:
		print("Insufficient credits! Need: ", amount, " Have: ", credits)
		return false

func get_credits() -> int:
	"""Get current credit amount"""
	return credits

# =============================================================================
# HYPERSPACE JUMP MANAGEMENT
# =============================================================================

func get_current_jumps() -> int:
	"""Get current available hyperspace jumps"""
	return current_hyperspace_jumps

func get_max_jumps() -> int:
	"""Get maximum hyperspace jump capacity"""
	return hyperspace_jump_capacity

func can_hyperspace_jump() -> bool:
	"""Check if player has jumps available"""
	return current_hyperspace_jumps > 0

func consume_hyperspace_jump() -> bool:
	"""Consume one hyperspace jump. Returns true if successful."""
	print("DEBUG: consume_hyperspace_jump called (current: ", current_hyperspace_jumps, ")")
	if current_hyperspace_jumps > 0:
		current_hyperspace_jumps -= 1
		jumps_changed.emit(current_hyperspace_jumps, hyperspace_jump_capacity)
		save_to_database()
		print("Hyperspace jump consumed. Remaining: ", current_hyperspace_jumps, "/", hyperspace_jump_capacity)
		return true
	else:
		print("No hyperspace jumps remaining!")
		return false

func set_jump_capacity(new_capacity: int):
	"""Set maximum jump capacity (called when changing ships)"""
	hyperspace_jump_capacity = new_capacity
	
	# Fill to capacity when getting a new ship
	current_hyperspace_jumps = hyperspace_jump_capacity
	
	jumps_changed.emit(current_hyperspace_jumps, hyperspace_jump_capacity)
	print("Jump capacity set to: ", hyperspace_jump_capacity, " (filled to capacity)")

func recharge_hyperspace_jumps(jumps_to_add: int, cost_per_jump: int) -> Dictionary:
	"""Recharge hyperspace jumps. Returns result dictionary with success/failure info."""
	var total_cost = jumps_to_add * cost_per_jump
	var max_possible_jumps = hyperspace_jump_capacity - current_hyperspace_jumps
	
	# Validate input
	if jumps_to_add <= 0:
		return {"success": false, "message": "Invalid jump amount"}
	
	if current_hyperspace_jumps >= hyperspace_jump_capacity:
		return {"success": false, "message": "Jump drive already at full capacity"}
	
	if credits < cost_per_jump:
		return {"success": false, "message": "Insufficient credits for even one jump"}
	
	# Calculate how many jumps we can actually buy
	var affordable_jumps = min(jumps_to_add, credits / cost_per_jump)
	affordable_jumps = min(affordable_jumps, max_possible_jumps)
	
	if affordable_jumps <= 0:
		return {"success": false, "message": "Cannot afford any jumps"}
	
	# Perform the transaction
	var actual_cost = affordable_jumps * cost_per_jump
	subtract_credits(actual_cost)
	current_hyperspace_jumps += affordable_jumps
	
	jumps_changed.emit(current_hyperspace_jumps, hyperspace_jump_capacity)
	
	print("Recharged ", affordable_jumps, " jumps for ", actual_cost, " credits")
	
	return {
		"success": true,
		"jumps_recharged": affordable_jumps,
		"cost_paid": actual_cost,
		"current_jumps": current_hyperspace_jumps,
		"max_jumps": hyperspace_jump_capacity
	}

func get_jumps_needed_for_full() -> int:
	"""Get number of jumps needed to fill to capacity"""
	return hyperspace_jump_capacity - current_hyperspace_jumps

# =============================================================================
# SHIP MANAGEMENT
# =============================================================================

func set_current_ship(ship_id: String):
	"""Set the current ship ID and apply ship stats"""
	current_ship_id = ship_id
	
	# Load ship stats and apply them
	var ship_stats = ShipManager.get_ship_stats(ship_id)
	if not ship_stats.is_empty():
		# Update cargo capacity
		var new_cargo_capacity = ship_stats.get("cargo_capacity", cargo_capacity)
		if new_cargo_capacity != cargo_capacity:
			cargo_capacity = new_cargo_capacity
			# Ensure current cargo doesn't exceed new capacity
			if current_cargo_weight > cargo_capacity:
				print("WARNING: Current cargo exceeds new ship capacity!")
			cargo_changed.emit(current_cargo_weight, cargo_capacity)
		
		# Update jump capacity
		var new_jump_capacity = ship_stats.get("hyperspace_jump_capacity", hyperspace_jump_capacity)
		if new_jump_capacity != hyperspace_jump_capacity:
			set_jump_capacity(new_jump_capacity)
		
		print("Applied ship stats for: ", ship_id)
		print("  Cargo capacity: ", cargo_capacity)
		print("  Jump capacity: ", hyperspace_jump_capacity)
	
	# Also update ShipManager's current ship
	ShipManager.set_current_ship(ship_id)
	
	save_to_database()
	print("Current ship set to: ", ship_id)

func get_current_ship() -> String:
	"""Get the current ship ID"""
	return current_ship_id

# =============================================================================
# POSITION MANAGEMENT
# =============================================================================

func set_system_position(position: Vector2):
	"""Set current position within the system"""
	system_position = position
	save_to_database()

func get_system_position() -> Vector2:
	"""Get current position within the system"""
	return system_position

func move_to_position(position: Vector2):
	"""Move to a new position within the system"""
	set_system_position(position)
	print("Moved to position: ", position)

# =============================================================================
# CARGO MANAGEMENT
# =============================================================================

func get_available_cargo_space() -> int:
	"""Get remaining cargo capacity in tons"""
	return cargo_capacity - current_cargo_weight

func can_accept_cargo(weight: int) -> bool:
	"""Check if player has enough cargo space"""
	return current_cargo_weight + weight <= cargo_capacity

func add_cargo(weight: int) -> bool:
	"""Add cargo weight if there's space. Returns true if successful."""
	print("DEBUG: add_cargo called with weight: ", weight, " (current: ", current_cargo_weight, ")")
	if can_accept_cargo(weight):
		current_cargo_weight += weight
		cargo_changed.emit(current_cargo_weight, cargo_capacity)
		save_to_database()
		print("Cargo loaded: +", weight, " tons (", current_cargo_weight, "/", cargo_capacity, ")")
		return true
	else:
		print("Insufficient cargo space! Need: ", weight, " tons, Available: ", get_available_cargo_space())
		return false

func remove_cargo(weight: int):
	"""Remove cargo weight (used when completing missions)"""
	print("DEBUG: remove_cargo called with weight: ", weight, " (current: ", current_cargo_weight, ")")
	current_cargo_weight = max(0, current_cargo_weight - weight)
	cargo_changed.emit(current_cargo_weight, cargo_capacity)
	save_to_database()
	print("Cargo unloaded: -", weight, " tons (", current_cargo_weight, "/", cargo_capacity, ")")

# =============================================================================
# MISSION MANAGEMENT
# =============================================================================

func accept_mission(mission_data: Dictionary) -> bool:
	"""Accept a new mission if player has cargo space"""
	var cargo_weight = mission_data.get("cargo_weight", 0)
	
	if not can_accept_cargo(cargo_weight):
		print("Cannot accept mission: insufficient cargo space")
		return false
	
	# Add unique ID and set status
	mission_data["id"] = "mission_" + str(next_mission_id)
	mission_data["status"] = "active"
	next_mission_id += 1
	
	# Add cargo weight and mission to active list
	add_cargo(cargo_weight)
	active_missions.append(mission_data)
	
	# Save mission to database
	save_mission_to_database(mission_data)
	
	# Remove mission from available missions in the current system
	var origin_planet = mission_data.get("origin_planet", -1)
	if origin_planet != -1:
		UniverseManager.remove_mission_from_system(origin_planet, mission_data)
	
	mission_accepted.emit(mission_data)
	print("Mission accepted: ", mission_data.get("cargo_type", "Unknown"), " to ", mission_data.get("destination_planet", "Unknown"))
	
	return true

func complete_mission(mission_id: String) -> bool:
	"""Complete a mission by ID, award credits and remove cargo"""
	for i in range(active_missions.size()):
		var mission = active_missions[i]
		if mission.get("id", "") == mission_id:
			# Award credits
			var payment = mission.get("payment", 0)
			add_credits(payment)
			
			# Remove cargo
			var cargo_weight = mission.get("cargo_weight", 0)
			remove_cargo(cargo_weight)
			
			# Update mission status in database
			update_mission_status_in_database(mission_id, "completed")
			
			# Move mission to completed list
			mission["status"] = "completed"
			completed_missions.append(mission)
			active_missions.remove_at(i)
			
			mission_completed.emit(mission)
			print("Mission completed: ", mission.get("cargo_type", "Unknown"), " - Payment: ", payment, " credits")
			
			return true
	
	print("Mission not found: ", mission_id)
	return false

func get_active_missions() -> Array[Dictionary]:
	"""Get array of active missions"""
	return active_missions.duplicate()

func get_completed_missions() -> Array[Dictionary]:
	"""Get array of completed missions"""
	return completed_missions.duplicate()

func has_active_mission_to_planet(planet_id: int, system_id: int) -> Dictionary:
	"""Check missions using integer IDs"""
	for mission in active_missions:
		if mission.get("destination_planet", -1) == planet_id and mission.get("destination_system", -1) == system_id:
			return mission
	return {}

func get_mission_count() -> Dictionary:
	"""Get mission statistics"""
	return {
		"active": active_missions.size(),
		"completed": completed_missions.size(),
		"total": active_missions.size() + completed_missions.size()
	}

# =============================================================================
# DEBUG METHODS
# =============================================================================

func debug_print_status():
	"""Print current player status for debugging"""
	print("=== PLAYER STATUS ===")
	print("Credits: ", credits)
	print("Ship: ", current_ship_id)
	print("Cargo: ", current_cargo_weight, "/", cargo_capacity, " tons")
	print("Hyperspace jumps: ", current_hyperspace_jumps, "/", hyperspace_jump_capacity)
	print("Position: ", system_position)
	print("Active missions: ", active_missions.size())
	print("Completed missions: ", completed_missions.size())
	print("=====================")

func set_current_system(system_id: int):
	"""Set current system and save to database"""
	current_system_id = system_id
	save_to_database()
	print("Current system set to: ", system_id)

func get_current_system() -> int:
	"""Get current system ID"""
	return current_system_id

func save_to_database():
	"""Save current player state to database"""
	# Don't save until data has been loaded from save file
	if not _data_loaded:
		print("DEBUG: Skipping save - data not yet loaded from save file")
		return
	
	var player_data = {
		"credits": credits,
		"current_system_id": current_system_id,
		"current_ship_id": current_ship_id,
		"cargo_capacity": cargo_capacity,
		"current_cargo_weight": current_cargo_weight,
		"hyperspace_jump_capacity": hyperspace_jump_capacity,
		"current_hyperspace_jumps": current_hyperspace_jumps,
		"system_position_x": system_position.x,
		"system_position_y": system_position.y,
		"ship_hull": hull,
		"ship_max_hull": max_hull,
		"ship_shields": shields,
		"ship_max_shields": max_shields
	}
	
	var success = SaveManager.save_player_data(player_data)
	if not success:
		print("ERROR: Failed to save player data!")
		print("  Credits: ", credits)
		print("  Cargo: ", current_cargo_weight, "/", cargo_capacity)
		print("  Jumps: ", current_hyperspace_jumps, "/", hyperspace_jump_capacity)

func save_mission_to_database(mission_data: Dictionary):
	"""Save a mission to the database"""
	var db = SaveManager.get_current_save_database()
	if not db:
		return
	
	var insert_sql = """
		INSERT INTO player_missions (
			id, status, cargo_type, cargo_weight, origin_planet_id, origin_system_id,
			destination_planet_id, destination_system_id, destination_planet_name, 
			destination_system_name, payment, accepted_timestamp
		) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
	"""
	
	var timestamp = Time.get_unix_time_from_system()
	var bindings = [
		mission_data.get("id", ""),
		mission_data.get("status", "active"),
		mission_data.get("cargo_type", ""),
		mission_data.get("cargo_weight", 0),
		mission_data.get("origin_planet", -1),
		mission_data.get("origin_system", -1),
		mission_data.get("destination_planet", -1),
		mission_data.get("destination_system", -1),
		mission_data.get("destination_planet_name", "Unknown"),
		mission_data.get("destination_system_name", "Unknown System"),
		mission_data.get("payment", 0),
		timestamp
	]
	
	db.query_with_bindings(insert_sql, bindings)

func update_mission_status_in_database(mission_id: String, status: String):
	"""Update mission status in database"""
	var db = SaveManager.get_current_save_database()
	if not db:
		return
	
	var update_sql = """
		UPDATE player_missions SET status = ?, completed_timestamp = ?
		WHERE id = ?;
	"""
	
	var timestamp = Time.get_unix_time_from_system() if status == "completed" else null
	db.query_with_bindings(update_sql, [status, timestamp, mission_id])

func debug_add_test_mission():
	"""Add a test mission for debugging"""
	var test_mission = {
		"cargo_type": "Test Cargo",
		"cargo_weight": 25,
		"origin_planet": "earth",
		"origin_system": "sol_system", 
		"destination_planet": "new_geneva",
		"destination_system": "alpha_centauri",
		"payment": 5000
	}
	accept_mission(test_mission)
