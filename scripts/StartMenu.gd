# =============================================================================
# START MENU - Game entry point with save system
# =============================================================================
# StartMenu.gd
extends Control

@onready var new_game_button = $MainContainer/ButtonContainer/NewGameButton
@onready var continue_button = $MainContainer/ButtonContainer/ContinueButton
@onready var load_game_button = $MainContainer/ButtonContainer/LoadGameButton
@onready var quit_button = $MainContainer/ButtonContainer/QuitButton

@onready var save_list_container = $MainContainer/SaveListContainer
@onready var save_list = $MainContainer/SaveListContainer/SaveList
@onready var load_selected_button = $MainContainer/SaveListContainer/SaveButtonContainer/LoadSelectedButton
@onready var delete_save_button = $MainContainer/SaveListContainer/SaveButtonContainer/DeleteSaveButton
@onready var back_button = $MainContainer/SaveListContainer/SaveButtonContainer/BackButton

@onready var new_game_dialog = $NewGameDialog
@onready var save_name_input = $NewGameDialog/NewGameContainer/SaveNameInput
@onready var create_button = $NewGameDialog/NewGameContainer/ButtonContainer/CreateButton
@onready var cancel_button = $NewGameDialog/NewGameContainer/ButtonContainer/CancelButton

var available_saves: Array[Dictionary] = []

func _ready():
	# Connect buttons
	new_game_button.pressed.connect(_on_new_game_pressed)
	continue_button.pressed.connect(_on_continue_pressed)
	load_game_button.pressed.connect(_on_load_game_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	
	# Save list buttons
	load_selected_button.pressed.connect(_on_load_selected_pressed)
	delete_save_button.pressed.connect(_on_delete_save_pressed)
	back_button.pressed.connect(_on_back_pressed)
	
	# New game dialog
	create_button.pressed.connect(_on_create_save_pressed)
	cancel_button.pressed.connect(_on_cancel_new_game_pressed)
	save_name_input.text_submitted.connect(_on_save_name_submitted)
	
	# Load available saves
	refresh_save_list()
	
	# Enable/disable continue button based on most recent save
	continue_button.disabled = available_saves.is_empty()

func refresh_save_list():
	"""Refresh the list of available save games"""
	available_saves = SaveManager.get_available_saves()
	
	save_list.clear()
	for save_data in available_saves:
		var display_text = "%s - %s" % [save_data.name, save_data.last_played]
		save_list.add_item(display_text)
	
	# Update button states
	continue_button.disabled = available_saves.is_empty()
	load_selected_button.disabled = true
	delete_save_button.disabled = true

func _on_new_game_pressed():
	"""Show new game dialog"""
	save_name_input.text = ""
	save_name_input.placeholder_text = "Save Game " + str(available_saves.size() + 1)
	new_game_dialog.popup_centered()
	save_name_input.grab_focus()

func _on_continue_pressed():
	"""Continue from most recent save"""
	if available_saves.is_empty():
		return
	
	# Find most recent save
	var most_recent_save = available_saves[0]
	for save_data in available_saves:
		if save_data.timestamp > most_recent_save.timestamp:
			most_recent_save = save_data
	
	load_save_game(most_recent_save.save_id)

func _on_load_game_pressed():
	"""Show load game interface"""
	save_list_container.visible = true
	$MainContainer/ButtonContainer.visible = false
	refresh_save_list()

func _on_quit_pressed():
	"""Quit the game"""
	get_tree().quit()

func _on_load_selected_pressed():
	"""Load the selected save game"""
	var selected_index = save_list.get_selected_items()
	if selected_index.is_empty():
		return
	
	var save_data = available_saves[selected_index[0]]
	load_save_game(save_data.save_id)

func _on_delete_save_pressed():
	"""Delete the selected save game"""
	var selected_index = save_list.get_selected_items()
	if selected_index.is_empty():
		return
	
	var save_data = available_saves[selected_index[0]]
	
	# Show confirmation dialog
	var confirm_dialog = ConfirmationDialog.new()
	confirm_dialog.dialog_text = "Delete save game '%s'?\nThis cannot be undone." % save_data.name
	add_child(confirm_dialog)
	confirm_dialog.popup_centered()
	
	await confirm_dialog.confirmed
	
	# Delete the save
	if SaveManager.delete_save(save_data.save_id):
		print("Save deleted: ", save_data.name)
		refresh_save_list()
	else:
		print("Failed to delete save: ", save_data.name)
	
	confirm_dialog.queue_free()

func _on_back_pressed():
	"""Return to main menu"""
	save_list_container.visible = false
	$MainContainer/ButtonContainer.visible = true

func _on_create_save_pressed():
	"""Create new save game"""
	var save_name = save_name_input.text.strip_edges()
	if save_name.is_empty():
		save_name = save_name_input.placeholder_text
	
	create_new_game(save_name)

func _on_cancel_new_game_pressed():
	"""Cancel new game creation"""
	new_game_dialog.hide()

func _on_save_name_submitted(text: String):
	"""Handle enter key in save name input"""
	_on_create_save_pressed()

func create_new_game(save_name: String):
	"""Create a new save game and start playing"""
	print("Creating new game: ", save_name)
	
	var save_id = SaveManager.create_new_save(save_name)
	if save_id.is_empty():
		print("Failed to create new save game")
		return
	
	new_game_dialog.hide()
	load_save_game(save_id)

func load_save_game(save_id: String):
	"""Load a save game and transition to main game"""
	print("Loading save game: ", save_id)
	
	if not SaveManager.load_save(save_id):
		print("Failed to load save game: ", save_id)
		return
	
	# Transition to main game scene
	get_tree().change_scene_to_file("res://scenes/Main.tscn")

func _on_save_list_item_selected(index: int):
	"""Handle save list selection"""
	load_selected_button.disabled = false
	delete_save_button.disabled = false

func _input(event):
	"""Handle global input"""
	if event.is_action_pressed("ui_cancel"):
		if new_game_dialog.visible:
			new_game_dialog.hide()
		elif save_list_container.visible:
			_on_back_pressed()
