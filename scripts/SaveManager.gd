# =============================================================================
# SAVE MANAGER - Handles save game creation, loading, and persistence
# =============================================================================
# SaveManager.gd - Singleton (AutoLoad)
extends Node

var current_save_id: String = ""
var save_database: SQLite
var saves_directory: String = "user://saves/"

func _ready():
	print("SaveManager initializing...")
	ensure_saves_directory()

func ensure_saves_directory():
	"""Ensure the saves directory exists"""
	if not DirAccess.dir_exists_absolute(saves_directory):
		DirAccess.open("user://").make_dir_recursive("saves")
		print("Created saves directory: ", saves_directory)

# =============================================================================
# SAVE CREATION AND MANAGEMENT
# =============================================================================

func create_new_save(save_name: String) -> String:
	"""Create a new save game. Returns save_id on success, empty string on failure."""
	var timestamp = Time.get_unix_time_from_system()
	var save_id = "save_" + str(timestamp)
	var save_db_path = saves_directory + save_id + "_save.db"
	
	print("Creating new save: ", save_name, " with ID: ", save_id)
	
	# Copy base universe.db to save location
	if not copy_base_universe_to_save(save_db_path):
		print("Failed to copy base universe database")
		return ""
	
	# Open the new save database
	var db = SQLite.new()
	db.path = save_db_path
	
	if not db.open_db():
		print("Failed to open new save database")
		return ""
	
	# Create player state tables
	if not create_player_tables(db):
		print("Failed to create player tables")
		db.close_db()
		return ""
	
	# Initialize player data
	if not initialize_player_data(db, save_name, timestamp):
		print("Failed to initialize player data")
		db.close_db()
		return ""
	
	db.close_db()
	print("Successfully created save: ", save_name)
	return save_id

func copy_base_universe_to_save(save_db_path: String) -> bool:
	"""Copy the base universe.db to the save location"""
	var source_path = "res://universe.db"
	
	# Read source file
	var source_file = FileAccess.open(source_path, FileAccess.READ)
	if not source_file:
		print("Failed to open source universe.db")
		return false
	
	var data = source_file.get_buffer(source_file.get_length())
	source_file.close()
	
	# Write to save location
	var dest_file = FileAccess.open(save_db_path, FileAccess.WRITE)
	if not dest_file:
		print("Failed to create save database file")
		return false
	
	dest_file.store_buffer(data)
	dest_file.close()
	
	print("Copied universe.db to: ", save_db_path)
	return true

func create_player_tables(db: SQLite) -> bool:
	"""Create player-specific tables in the save database"""
	var tables = [
		# Player basic info
		"""
		CREATE TABLE IF NOT EXISTS player_data (
			id INTEGER PRIMARY KEY,
			save_name TEXT NOT NULL,
			created_timestamp INTEGER NOT NULL,
			last_played_timestamp INTEGER NOT NULL,
			credits INTEGER DEFAULT 50000,
			current_system_id INTEGER DEFAULT 1,
			cargo_capacity INTEGER DEFAULT 100,
			current_cargo_weight INTEGER DEFAULT 0,
			hyperspace_jump_capacity INTEGER DEFAULT 3,
			current_hyperspace_jumps INTEGER DEFAULT 3,
			ship_hull REAL DEFAULT 1000.0,
			ship_max_hull REAL DEFAULT 1000.0,
			ship_shields REAL DEFAULT 1000.0,
			ship_max_shields REAL DEFAULT 1000.0
		);
		""",
		
		# Active missions
		"""
		CREATE TABLE IF NOT EXISTS player_missions (
			id TEXT PRIMARY KEY,
			status TEXT NOT NULL DEFAULT 'active',
			cargo_type TEXT NOT NULL,
			cargo_weight INTEGER NOT NULL,
			origin_planet_id INTEGER NOT NULL,
			origin_system_id INTEGER NOT NULL,
			destination_planet_id INTEGER NOT NULL,
			destination_system_id INTEGER NOT NULL,
			payment INTEGER NOT NULL,
			accepted_timestamp INTEGER NOT NULL,
			completed_timestamp INTEGER DEFAULT NULL
		);
		""",
		
		# Player reputation with factions
		"""
		CREATE TABLE IF NOT EXISTS player_reputation (
			faction_id TEXT PRIMARY KEY,
			reputation INTEGER DEFAULT 0
		);
		""",
		
		# Player ship loadout/equipment
		"""
		CREATE TABLE IF NOT EXISTS player_ship_equipment (
			slot_type TEXT NOT NULL,
			slot_index INTEGER NOT NULL,
			equipment_id TEXT,
			PRIMARY KEY (slot_type, slot_index)
		);
		"""
	]
	
	for table_sql in tables:
		if not db.query(table_sql):
			print("Failed to create table: ", table_sql)
			return false
	
	print("Created player tables successfully")
	return true

func initialize_player_data(db: SQLite, save_name: String, timestamp: int) -> bool:
	"""Initialize player data for new save"""
	var insert_sql = """
		INSERT INTO player_data (
			save_name, created_timestamp, last_played_timestamp,
			credits, current_system_id, cargo_capacity, current_cargo_weight,
			hyperspace_jump_capacity, current_hyperspace_jumps,
			ship_hull, ship_max_hull, ship_shields, ship_max_shields
		) VALUES (?, ?, ?, 50000, 1, 100, 0, 3, 3, 1000.0, 1000.0, 1000.0, 1000.0);
	"""
	
	return db.query_with_bindings(insert_sql, [save_name, timestamp, timestamp])

# =============================================================================
# SAVE LOADING
# =============================================================================

func load_save(save_id: String) -> bool:
	"""Load a save game and set it as current"""
	var save_db_path = saves_directory + save_id + "_save.db"
	
	if not FileAccess.file_exists(save_db_path):
		print("Save file not found: ", save_db_path)
		return false
	
	# Close current save if any
	if save_database:
		save_database.close_db()
	
	# Open save database
	save_database = SQLite.new()
	save_database.path = save_db_path
	
	if not save_database.open_db():
		print("Failed to open save database: ", save_db_path)
		return false
	
	current_save_id = save_id
	
	# Update last played timestamp
	update_last_played_timestamp()
	
	print("Loaded save: ", save_id)
	return true

func get_current_save_database() -> SQLite:
	"""Get the current save database connection"""
	return save_database

func update_last_played_timestamp():
	"""Update the last played timestamp for current save"""
	if not save_database:
		return
	
	var timestamp = Time.get_unix_time_from_system()
	var update_sql = "UPDATE player_data SET last_played_timestamp = ? WHERE id = 1;"
	save_database.query_with_bindings(update_sql, [timestamp])

# =============================================================================
# SAVE LISTING
# =============================================================================

func get_available_saves() -> Array[Dictionary]:
	"""Get list of available save games"""
	var saves: Array[Dictionary] = []
	var dir = DirAccess.open(saves_directory)
	
	if not dir:
		return saves
	
	dir.list_dir_begin()
	var file_name = dir.get_next()
	
	while file_name != "":
		if file_name.ends_with("_save.db"):
			var save_id = file_name.replace("_save.db", "")
			var save_info = get_save_info(save_id)
			if not save_info.is_empty():
				saves.append(save_info)
		
		file_name = dir.get_next()
	
	# Sort by last played (most recent first)
	saves.sort_custom(func(a, b): return a.timestamp > b.timestamp)
	
	return saves

func get_save_info(save_id: String) -> Dictionary:
	"""Get information about a specific save"""
	var save_db_path = saves_directory + save_id + "_save.db"
	
	if not FileAccess.file_exists(save_db_path):
		return {}
	
	var db = SQLite.new()
	db.path = save_db_path
	
	if not db.open_db():
		return {}
	
	var query_sql = """
		SELECT save_name, created_timestamp, last_played_timestamp, 
			   credits, current_system_id
		FROM player_data WHERE id = 1;
	"""
	
	db.query(query_sql)
	var results = db.query_result
	
	db.close_db()
	
	if results.is_empty():
		return {}
	
	var data = results[0]
	var last_played = Time.get_datetime_string_from_unix_time(data.last_played_timestamp)
	
	return {
		"save_id": save_id,
		"name": data.save_name,
		"credits": data.credits,
		"current_system_id": data.current_system_id,
		"timestamp": data.last_played_timestamp,
		"last_played": last_played
	}

# =============================================================================
# SAVE DELETION
# =============================================================================

func delete_save(save_id: String) -> bool:
	"""Delete a save game"""
	var save_db_path = saves_directory + save_id + "_save.db"
	
	if not FileAccess.file_exists(save_db_path):
		print("Save file not found for deletion: ", save_db_path)
		return false
	
	# Close database if it's currently open
	if current_save_id == save_id and save_database:
		save_database.close_db()
		save_database = null
		current_save_id = ""
	
	# Delete the file
	var dir = DirAccess.open("user://")
	if dir.remove(save_db_path.replace("user://", "")) == OK:
		print("Deleted save: ", save_id)
		return true
	else:
		print("Failed to delete save file: ", save_db_path)
		return false

# =============================================================================
# PERSISTENCE HELPERS
# =============================================================================

func save_player_data(player_data: Dictionary) -> bool:
	"""Save player data to current save database"""
	if not save_database:
		print("No save database available")
		return false
	
	var update_sql = """
		UPDATE player_data SET 
			credits = ?, current_system_id = ?, cargo_capacity = ?, 
			current_cargo_weight = ?, hyperspace_jump_capacity = ?, 
			current_hyperspace_jumps = ?, ship_hull = ?, ship_max_hull = ?,
			ship_shields = ?, ship_max_shields = ?, last_played_timestamp = ?
		WHERE id = 1;
	"""
	
	var timestamp = Time.get_unix_time_from_system()
	var bindings = [
		player_data.get("credits", 50000),
		player_data.get("current_system_id", 1),
		player_data.get("cargo_capacity", 100),
		player_data.get("current_cargo_weight", 0),
		player_data.get("hyperspace_jump_capacity", 3),
		player_data.get("current_hyperspace_jumps", 3),
		player_data.get("ship_hull", 1000.0),
		player_data.get("ship_max_hull", 1000.0),
		player_data.get("ship_shields", 1000.0),
		player_data.get("ship_max_shields", 1000.0),
		timestamp
	]
	
	return save_database.query_with_bindings(update_sql, bindings)

func load_player_data() -> Dictionary:
	"""Load player data from current save database"""
	if not save_database:
		print("No save database available")
		return {}
	
	var query_sql = """
		SELECT * FROM player_data WHERE id = 1;
	"""
	
	save_database.query(query_sql)
	var results = save_database.query_result
	
	if results.is_empty():
		print("No player data found in save")
		return {}
	
	return results[0]

# =============================================================================
# CLEANUP
# =============================================================================

func _exit_tree():
	if save_database:
		save_database.close_db()
		print("Save database connection closed")
