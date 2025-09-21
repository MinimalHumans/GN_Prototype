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

# Hyperspace Jump System
var hyperspace_jump_capacity: int = 3  # Maximum jumps this ship can store
var current_hyperspace_jumps: int = 3  # Current jumps available

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

func _ready():
	print("PlayerData singleton initialized")
	# Don't print starting values here - they'll be loaded from save

func initialize_from_save():
	"""Initialize player data from current save"""
	var save_data = SaveManager.load_player_data()
	if save_data.is_empty():
		print("No save data found, using defaults")
		return
	
	# Load basic stats
	credits = save_data.get("credits", 50000)
	cargo_capacity = save_data.get("cargo_capacity", 100)
	current_cargo_weight = save_data.get("current_cargo_weight", 0)
	hyperspace_jump_capacity = save_data.get("hyperspace_jump_capacity", 3)
	current_hyperspace_jumps = save_data.get("current_hyperspace_jumps", 3)
	
	# Load ship stats
	hull = save_data.get("ship_hull", 1000.0)
	max_hull = save_data.get("ship_max_hull", 1000.0)
	shields = save_data.get("ship_shields", 1000.0)
	max_shields = save_data.get("ship_max_shields", 1000.0)
	
	# Load missions
	load_missions_from_save()
	
	print("Player data loaded from save:")
	print("  Credits: ", credits)
	print("  Cargo: ", current_cargo_weight, "/", cargo_capacity)
	print("  Jumps: ", current_hyperspace_jumps, "/", hyperspace_jump_capacity)
	print("  Hull: ", hull, "/", max_hull)
	print("  Shields: ", shields, "/", max_shields)
	print("  Active missions: ", active_missions.size())

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
	credits += amount
	credits_changed.emit(credits)
	save_to_database()
	print("Credits added: +", amount, " (Total: ", credits, ")")

func subtract_credits(amount: int) -> bool:
	"""Subtract credits if player has enough. Returns true if successful."""
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
	if can_accept_cargo(weight):
		current_cargo_weight += weight
		cargo_changed.emit(current_cargo_weight, cargo_capacity)
		print("Cargo loaded: +", weight, " tons (", current_cargo_weight, "/", cargo_capacity, ")")
		return true
	else:
		print("Insufficient cargo space! Need: ", weight, " tons, Available: ", get_available_cargo_space())
		return false

func remove_cargo(weight: int):
	"""Remove cargo weight (used when completing missions)"""
	current_cargo_weight = max(0, current_cargo_weight - weight)
	cargo_changed.emit(current_cargo_weight, cargo_capacity)
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
	print("Cargo: ", current_cargo_weight, "/", cargo_capacity, " tons")
	print("Hyperspace jumps: ", current_hyperspace_jumps, "/", hyperspace_jump_capacity)
	print("Active missions: ", active_missions.size())
	print("Completed missions: ", completed_missions.size())
	print("=====================")

func set_current_system(system_id: int):
	"""Set current system and save to database"""
	save_to_database()

func save_to_database():
	"""Save current player state to database"""
	var player_data = {
		"credits": credits,
		"current_system_id": UniverseManager.current_system_id,
		"cargo_capacity": cargo_capacity,
		"current_cargo_weight": current_cargo_weight,
		"hyperspace_jump_capacity": hyperspace_jump_capacity,
		"current_hyperspace_jumps": current_hyperspace_jumps,
		"ship_hull": hull,
		"ship_max_hull": max_hull,
		"ship_shields": shields,
		"ship_max_shields": max_shields
	}
	
	SaveManager.save_player_data(player_data)

func save_mission_to_database(mission_data: Dictionary):
	"""Save a mission to the database"""
	var db = SaveManager.get_current_save_database()
	if not db:
		return
	
	var insert_sql = """
		INSERT INTO player_missions (
			id, status, cargo_type, cargo_weight, origin_planet_id, origin_system_id,
			destination_planet_id, destination_system_id, payment, accepted_timestamp
		) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
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
