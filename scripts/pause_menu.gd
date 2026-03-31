extends CanvasLayer
## Pause menu autoload. process_mode = PROCESS_MODE_ALWAYS so input is
## received even while the tree is paused.

enum MenuState { HIDDEN, MAIN, CONTROLS }

const MENU_OPTIONS: Array[String] = ["RESUME", "RESTART", "CONTROLS"]

var _state: MenuState = MenuState.HIDDEN
var _selected: int = 0
var _overlay: Control

# ── lifecycle ───────────────────────────────────────────────────────────

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 100

	_overlay = Control.new()
	_overlay.name = "PauseOverlay"
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.visible = false
	_overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	_overlay.draw.connect(_on_overlay_draw)
	add_child(_overlay)


func _unhandled_input(event: InputEvent) -> void:
	# ── Open / close triggers ──────────────────────────────────────────
	var is_escape: bool = event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE
	var is_start: bool = event is InputEventJoypadButton and event.pressed and event.button_index == 6
	var is_back: bool = event is InputEventJoypadButton and event.pressed and event.button_index == 1

	if is_escape or is_start:
		match _state:
			MenuState.HIDDEN:
				if _is_pausable_phase():
					_open_menu()
			MenuState.CONTROLS:
				_go_to_main()
			MenuState.MAIN:
				_resume()
		get_viewport().set_input_as_handled()
		return

	if is_back:
		match _state:
			MenuState.CONTROLS:
				_go_to_main()
			MenuState.MAIN:
				_resume()
		get_viewport().set_input_as_handled()
		return

	# Everything below only matters when the menu is visible.
	if _state == MenuState.HIDDEN:
		return

	if _state == MenuState.CONTROLS:
		return  # controls sub-screen only closes via ESC / B

	# ── Navigation ─────────────────────────────────────────────────────
	var nav_up: bool = false
	var nav_down: bool = false
	var confirm: bool = false

	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_W, KEY_UP:
				nav_up = true
			KEY_S, KEY_DOWN:
				nav_down = true
			KEY_SPACE, KEY_ENTER:
				confirm = true

	if event is InputEventJoypadButton and event.pressed:
		match event.button_index:
			11:  # dpad up
				nav_up = true
			12:  # dpad down
				nav_down = true
			0:   # A button
				confirm = true

	if nav_up:
		_selected = (_selected - 1 + MENU_OPTIONS.size()) % MENU_OPTIONS.size()
		_overlay.queue_redraw()
		get_viewport().set_input_as_handled()
	elif nav_down:
		_selected = (_selected + 1) % MENU_OPTIONS.size()
		_overlay.queue_redraw()
		get_viewport().set_input_as_handled()
	elif confirm:
		_activate_option()
		get_viewport().set_input_as_handled()


# ── state helpers ───────────────────────────────────────────────────────

func _open_menu() -> void:
	_state = MenuState.MAIN
	_selected = 0
	get_tree().paused = true
	_overlay.visible = true
	_overlay.queue_redraw()


func _resume() -> void:
	_state = MenuState.HIDDEN
	_overlay.visible = false
	get_tree().paused = false


func _go_to_main() -> void:
	_state = MenuState.MAIN
	_selected = 0
	_overlay.queue_redraw()


func _is_pausable_phase() -> bool:
	var phase: int = GameManager.current_phase
	return phase == GameManager.Phase.COMPETITIVE_1 \
		or phase == GameManager.Phase.COMPETITIVE_2 \
		or phase == GameManager.Phase.COOPERATIVE_1 \
		or phase == GameManager.Phase.COOPERATIVE_2


func _activate_option() -> void:
	match MENU_OPTIONS[_selected]:
		"RESUME":
			_resume()
		"RESTART":
			_state = MenuState.HIDDEN
			_overlay.visible = false
			get_tree().paused = false
			get_tree().reload_current_scene()
		"CONTROLS":
			_state = MenuState.CONTROLS
			_overlay.queue_redraw()


# ── drawing ─────────────────────────────────────────────────────────────

func _on_overlay_draw() -> void:
	var vp_size: Vector2 = _overlay.get_viewport_rect().size
	var font: Font = ThemeDB.fallback_font
	var font_size_title: int = 32
	var font_size_item: int = 24
	var font_size_body: int = 18
	var font_size_small: int = 15

	# Dark overlay
	_overlay.draw_rect(Rect2(Vector2.ZERO, vp_size), Color(0.02, 0.02, 0.06, 0.88))

	if _state == MenuState.MAIN:
		_draw_main_menu(vp_size, font, font_size_title, font_size_item)
	elif _state == MenuState.CONTROLS:
		_draw_controls_screen(vp_size, font, font_size_title, font_size_body, font_size_small)


func _draw_main_menu(vp_size: Vector2, font: Font, title_size: int, item_size: int) -> void:
	var center_x: float = vp_size.x * 0.5
	var start_y: float = vp_size.y * 0.30

	# Title
	var title_text: String = "PAUSED"
	var title_w: float = font.get_string_size(title_text, HORIZONTAL_ALIGNMENT_CENTER, -1, title_size).x
	_overlay.draw_string(font, Vector2(center_x - title_w * 0.5, start_y), title_text, HORIZONTAL_ALIGNMENT_LEFT, -1, title_size, Color(0.75, 0.72, 0.80))

	# Menu items
	var item_y: float = start_y + 70.0
	var spacing: float = 52.0

	for i: int in MENU_OPTIONS.size():
		var text: String = MENU_OPTIONS[i]
		var text_w: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, item_size).x
		var color: Color
		if i == _selected:
			color = Color(1.0, 1.0, 1.0)
			# Selection indicator
			var indicator_x: float = center_x - text_w * 0.5 - 22.0
			var indicator_y: float = item_y + i * spacing - 8.0
			_overlay.draw_rect(Rect2(indicator_x, indicator_y, 10.0, 10.0), Color(0.85, 0.55, 0.55))
		else:
			color = Color(0.50, 0.48, 0.55)
		_overlay.draw_string(font, Vector2(center_x - text_w * 0.5, item_y + i * spacing), text, HORIZONTAL_ALIGNMENT_LEFT, -1, item_size, color)

	# Hint
	var hint: String = "ESC / B  Back     W/S  Navigate     Space/Enter/A  Select"
	var hint_w: float = font.get_string_size(hint, HORIZONTAL_ALIGNMENT_CENTER, -1, 14).x
	_overlay.draw_string(font, Vector2(center_x - hint_w * 0.5, vp_size.y - 40.0), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.38, 0.36, 0.42))


func _draw_controls_screen(vp_size: Vector2, font: Font, title_size: int, body_size: int, small_size: int) -> void:
	var center_x: float = vp_size.x * 0.5
	var top_y: float = 40.0

	# Title
	var title_text: String = "CONTROLS"
	var title_w: float = font.get_string_size(title_text, HORIZONTAL_ALIGNMENT_CENTER, -1, title_size).x
	_overlay.draw_string(font, Vector2(center_x - title_w * 0.5, top_y + 32.0), title_text, HORIZONTAL_ALIGNMENT_LEFT, -1, title_size, Color(0.75, 0.72, 0.80))

	# Player colors
	var blame_color: Color = Color(0.85, 0.55, 0.55)
	var denial_color: Color = Color(0.55, 0.55, 0.85)
	if GameManager.has_method("get_blame_color_light"):
		blame_color = GameManager.get_blame_color_light()
	if GameManager.has_method("get_denial_color_light"):
		denial_color = GameManager.get_denial_color_light()

	# Build controls text based on current phase
	var blame_lines: Array[String] = []
	var denial_lines: Array[String] = []
	var shared_lines: Array[String] = []
	var phase_label: String = ""

	var phase: int = -1
	if "current_phase" in GameManager:
		phase = GameManager.current_phase

	# Phase enum values: COMPETITIVE_1 = 0, COMPETITIVE_2 = 1, COOPERATIVE_1 = 2, COOPERATIVE_2 = 3
	# We match by value since we reference GameManager's Phase enum.
	var is_competitive_1: bool = false
	var is_competitive_2: bool = false
	var is_cooperative_1: bool = false
	var is_cooperative_2: bool = false

	if "Phase" in GameManager:
		if phase == GameManager.Phase.COMPETITIVE_1:
			is_competitive_1 = true
		elif phase == GameManager.Phase.COMPETITIVE_2:
			is_competitive_2 = true
		elif phase == GameManager.Phase.COOPERATIVE_1:
			is_cooperative_1 = true
		elif phase == GameManager.Phase.COOPERATIVE_2:
			is_cooperative_2 = true

	if is_competitive_1:
		phase_label = "CLASH OF EMOTIONS"
		blame_lines = [
			"BLAME (P1)",
			"Move: WASD  /  Left Stick",
			"Jump: W  /  A button",
			"Guilt Slam: F  /  X button",
			"Accusation: G  /  Y button",
			"Burden Zone: R  /  B button",
			"Self-Punishment: L2 + R2",
		]
		denial_lines = [
			"DENIAL (P2)",
			"Move: Arrows  /  Left Stick",
			"Jump: Up  /  A button",
			"Suppress: Enter  /  X button",
			"Deflect: RShift  /  Y button",
			"Forget: Num0  /  B button",
			"Bright Burst: L2 + R2",
		]
	elif is_competitive_2:
		phase_label = "GRAVITY RUN"
		blame_lines = [
			"BLAME (P1)",
			"Move: A / D  /  Left Stick",
			"Flip Gravity: W  /  A button",
			"Catch BLUE fragments",
		]
		denial_lines = [
			"DENIAL (P2)",
			"Move: Left / Right  /  Left Stick",
			"Flip Gravity: Up  /  A button",
			"Catch ORANGE fragments",
		]
	elif is_cooperative_1:
		phase_label = "CARRYING THE WEIGHT"
		blame_lines = [
			"BLAME (P1)",
			"Move: A / D  /  Left Stick",
			"Jump: W  /  A button",
			"BLUE platforms solidify near you",
		]
		denial_lines = [
			"DENIAL (P2)",
			"Move: Left / Right  /  Left Stick",
			"Jump: Up  /  A button",
			"ORANGE platforms solidify near you",
		]
	elif is_cooperative_2:
		phase_label = "INTO THE FOG"
		blame_lines = [
			"BLAME (P1)",
			"Move: WASD  /  Left Stick",
			"Block embers: F  /  X button",
			"Stay close for more light",
		]
		denial_lines = [
			"DENIAL (P2)",
			"Move: Arrows  /  Left Stick",
			"Block shards: Enter  /  X button",
			"Stay close for more light",
		]
	else:
		phase_label = ""
		blame_lines = [
			"BLAME (P1)",
			"Move: WASD  /  Left Stick",
			"Jump: W  /  A button",
			"Action: F  /  X button",
		]
		denial_lines = [
			"DENIAL (P2)",
			"Move: Arrows  /  Left Stick",
			"Jump: Up  /  A button",
			"Action: Enter  /  X button",
		]

	var content_y: float = top_y + 80.0

	# Phase label
	if phase_label != "":
		var pl_w: float = font.get_string_size(phase_label, HORIZONTAL_ALIGNMENT_CENTER, -1, body_size).x
		_overlay.draw_string(font, Vector2(center_x - pl_w * 0.5, content_y), phase_label, HORIZONTAL_ALIGNMENT_LEFT, -1, body_size, Color(0.62, 0.58, 0.68))
		content_y += 36.0

	var line_height: float = float(small_size) + 8.0

	if blame_lines.size() > 0 and denial_lines.size() > 0:
		# Two-column layout
		var col_left_x: float = vp_size.x * 0.12
		var col_right_x: float = vp_size.x * 0.55

		# Separator line
		var sep_x: float = center_x - 1.0
		_overlay.draw_rect(Rect2(sep_x, content_y - 6.0, 2.0, maxf(blame_lines.size(), denial_lines.size()) * line_height + 20.0), Color(0.25, 0.24, 0.30))

		# Blame column
		for j: int in blame_lines.size():
			var col: Color = blame_color if j == 0 else Color(0.72, 0.70, 0.76)
			var fs: int = body_size if j == 0 else small_size
			_overlay.draw_string(font, Vector2(col_left_x, content_y + j * line_height), blame_lines[j], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)

		# Denial column
		for j: int in denial_lines.size():
			var col: Color = denial_color if j == 0 else Color(0.72, 0.70, 0.76)
			var fs: int = body_size if j == 0 else small_size
			_overlay.draw_string(font, Vector2(col_right_x, content_y + j * line_height), denial_lines[j], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
	elif shared_lines.size() > 0:
		# Single centered column
		for j: int in shared_lines.size():
			var text: String = shared_lines[j]
			var col: Color = Color(0.80, 0.70, 0.85) if j == 0 else Color(0.72, 0.70, 0.76)
			var fs: int = body_size if j == 0 else small_size
			var tw: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, fs).x
			_overlay.draw_string(font, Vector2(center_x - tw * 0.5, content_y + j * line_height), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)

	# Back hint
	var back_hint: String = "ESC / B  Back"
	var bh_w: float = font.get_string_size(back_hint, HORIZONTAL_ALIGNMENT_CENTER, -1, 14).x
	_overlay.draw_string(font, Vector2(center_x - bh_w * 0.5, vp_size.y - 40.0), back_hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.38, 0.36, 0.42))
