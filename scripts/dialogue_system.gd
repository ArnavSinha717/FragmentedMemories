extends CanvasLayer

## Typewriter dialogue overlay. Add as child to any scene.
## Call play_dialogue() with an array of {speaker, text, color} dicts.

signal dialogue_finished

@onready var panel: PanelContainer = $Panel
@onready var speaker_label: Label = $Panel/VBox/SpeakerLabel
@onready var text_label: RichTextLabel = $Panel/VBox/TextLabel
@onready var continue_hint: Label = $Panel/VBox/ContinueHint

var dialogue_queue: Array[Dictionary] = []
var current_line: int = -1
var is_typing: bool = false
var full_text: String = ""
var char_index: int = 0
var type_speed: float = 0.03
var type_speed_fast: float = 0.005  # When holding to fast-forward
var type_timer: float = 0.0
var waiting_for_input: bool = false
var is_active: bool = false


func _ready() -> void:
	panel.visible = false
	continue_hint.text = "[ SPACE to continue | Hold to fast-forward ]"
	# Style the panel
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.1, 0.85)
	style.border_color = Color(0.3, 0.3, 0.4, 0.6)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(20)
	panel.add_theme_stylebox_override("panel", style)


func _process(delta: float) -> void:
	if not is_active:
		return

	# Holding attack/space = fast-forward typing
	var holding_skip: bool = Input.is_action_pressed("p1_attack") or Input.is_action_pressed("p2_attack") or Input.is_action_pressed("ui_accept")
	var current_speed: float = type_speed_fast if holding_skip else type_speed

	if is_typing:
		type_timer += delta
		# When holding, advance multiple characters per frame for real speed
		if holding_skip:
			while type_timer >= current_speed and char_index < full_text.length():
				type_timer -= current_speed
				char_index += 1
			if char_index >= full_text.length():
				text_label.text = full_text
				is_typing = false
				waiting_for_input = true
				continue_hint.visible = true
			else:
				text_label.text = full_text.substr(0, char_index)
		else:
			if type_timer >= current_speed:
				type_timer = 0.0
				char_index += 1
				if char_index >= full_text.length():
					text_label.text = full_text
					is_typing = false
					waiting_for_input = true
					continue_hint.visible = true
				else:
					text_label.text = full_text.substr(0, char_index)

	if waiting_for_input:
		if Input.is_action_just_pressed("p1_attack") or Input.is_action_just_pressed("p2_attack") or Input.is_action_just_pressed("ui_accept"):
			_advance()


func play_dialogue(lines: Array[Dictionary]) -> void:
	dialogue_queue.clear()
	for line: Dictionary in lines:
		dialogue_queue.append(line)
	current_line = -1
	is_active = true
	panel.visible = true
	_advance()


func _advance() -> void:
	waiting_for_input = false
	continue_hint.visible = false
	current_line += 1

	if current_line >= dialogue_queue.size():
		# Done
		is_active = false
		panel.visible = false
		dialogue_finished.emit()
		return

	var line: Dictionary = dialogue_queue[current_line]
	var speaker: String = line.get("speaker", "")
	var text: String = line.get("text", "")
	var color: Color = line.get("color", Color.WHITE)

	speaker_label.text = speaker
	speaker_label.add_theme_color_override("font_color", color)
	speaker_label.visible = speaker != ""

	full_text = text
	text_label.text = ""
	char_index = 0
	type_timer = 0.0
	is_typing = true


func skip_to_end() -> void:
	if is_typing:
		text_label.text = full_text
		is_typing = false
		waiting_for_input = true
		continue_hint.visible = true
