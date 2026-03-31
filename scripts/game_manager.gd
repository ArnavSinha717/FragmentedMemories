extends Node

## Global game state manager — tracks fragment order, wins, and scene progression.

signal hue_changed(value: float) # 0.0 = full blame (cold), 1.0 = full denial (warm)
signal fragment_revealed(fragment_id: String)
signal phase_changed(phase: String)

# Fragment IDs
const GOOD_1 = "G1" # Happy times
const GOOD_2 = "G2" # Conversations / promises
const BAD_1 = "B1"  # Lipika crying
const BAD_2 = "B2"  # The accident

# Game phases
enum Phase {
	MAIN_MENU,
	PROLOGUE,
	INTRO_CUTSCENE,
	COMPETITIVE_1,
	WINNER_1,
	FRAGMENT_REVEAL_1,
	COMPETITIVE_2,
	WINNER_2,
	FRAGMENT_REVEAL_2,
	TRANSITION_CUTSCENE,
	COOPERATIVE_1,
	FRAGMENT_REVEAL_3,
	COOPERATIVE_2,
	FRAGMENT_REVEAL_4,
	FULL_MEMORY,
	BOSS_FIGHT,
	FATALITY,
	OUTRO,
	REFLECTION
}

var current_phase: Phase = Phase.MAIN_MENU
var hue_value: float = 0.5 # 0=blame, 1=denial

# Track who wins each competitive minigame
var blame_wins: int = 0
var denial_wins: int = 0
var round_winners: Array[bool] = []  # per-round: true = blame won that round

# Fragments shown so far
var revealed_fragments: Array[String] = []
var fragment_order: Array[String] = [] # Will be built based on wins

# Transition cutscene tracking
var bad2_revealed: bool = false       # True once BAD_2 fragment has been shown
var transition_shown: bool = false    # True once the transition cutscene has played
var coop_phase: int = 0              # 0=not started, 1=done coop1, 2=done coop2

# The 4 fragment queues based on path
var blame_path: Array[String] = [BAD_1, BAD_2, GOOD_1, GOOD_2]
var denial_path: Array[String] = [GOOD_1, GOOD_2, BAD_1, BAD_2]

# Boss
var boss_charge: float = 0.0
const BOSS_CHARGE_MAX: float = 100.0

# --- Global Shard Background ---
const SHARD_COLS := 20
const SHARD_ROWS := 12
var grid_verts: Array[Vector2] = []
var shards: Array[Dictionary] = []
var falling_shards: Array[Dictionary] = []
var shards_generated: bool = false
var collapse_active: bool = false
var collapse_timer: float = 0.0

# --- Music ---
var music_player: AudioStreamPlayer = null

# Scene paths
var scene_map: Dictionary = {
	Phase.MAIN_MENU: "res://scenes/main_menu.tscn",
	Phase.PROLOGUE: "res://scenes/prologue.tscn",
	Phase.INTRO_CUTSCENE: "res://scenes/intro_cutscene.tscn",
	Phase.COMPETITIVE_1: "res://scenes/competitive_fight.tscn",
	Phase.WINNER_1: "res://scenes/winner_screen.tscn",
	Phase.COMPETITIVE_2: "res://scenes/territory_grab.tscn",
	Phase.WINNER_2: "res://scenes/winner_screen.tscn",
	Phase.TRANSITION_CUTSCENE: "res://scenes/transition_cutscene.tscn",
	Phase.COOPERATIVE_1: "res://scenes/push_block.tscn",
	Phase.COOPERATIVE_2: "res://scenes/sync_press.tscn",
	Phase.FULL_MEMORY: "res://scenes/full_memory.tscn",
	Phase.BOSS_FIGHT: "res://scenes/boss_fight.tscn",
	Phase.FATALITY: "res://scenes/fatality.tscn",
	Phase.OUTRO: "res://scenes/outro.tscn",
	Phase.REFLECTION: "res://scenes/reflection.tscn",
	Phase.FRAGMENT_REVEAL_1: "res://scenes/fragment_reveal.tscn",
	Phase.FRAGMENT_REVEAL_2: "res://scenes/fragment_reveal.tscn",
	Phase.FRAGMENT_REVEAL_3: "res://scenes/fragment_reveal.tscn",
	Phase.FRAGMENT_REVEAL_4: "res://scenes/fragment_reveal.tscn",
}


# ─── Character sprite sheets ──────────────────────────────────────────────
var golem_sheet: Texture2D    # Blame (Mecha Golem) — 1000x1000, 100x100 frames, 10 cols x 10 rows
var rogue_sheet: Texture2D    # Denial (Rogue Knight) — 500x444, 50x74 frames, 10 cols x 6 rows
const GOLEM_FW := 100
const GOLEM_FH := 100
const ROGUE_FW := 50
const ROGUE_FH := 37


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_character_sheets()
	_setup_music()
	generate_shards()


func _load_character_sheets() -> void:
	var golem_path := "res://assets/blame_golem/Mecha-stone Golem 0.1/PNG sheet/Character_sheet.png"
	var rogue_path := "res://assets/Fullmain.png"
	if ResourceLoader.exists(golem_path):
		golem_sheet = load(golem_path) as Texture2D
	if ResourceLoader.exists(rogue_path):
		rogue_sheet = load(rogue_path) as Texture2D


## Draw Blame (Golem) sprite at pos (feet position).
## row/col select the animation frame. scl scales from base 100px.
func draw_blame_sprite(canvas: CanvasItem, pos: Vector2, scol: int, srow: int,
		scl: float, flip_h: bool, mod: Color = Color.WHITE) -> void:
	# Tint toward cold blue (blame's emotion color)
	var tint := mod * Color(0.65, 0.7, 1.0)
	# Golem sits in top portion of 100x100 frame — offset down so it rests on ground
	var draw_pos := Vector2(pos.x, pos.y + 25.0 * scl)
	if golem_sheet:
		_draw_sheet_frame(canvas, golem_sheet, draw_pos, GOLEM_FW, GOLEM_FH, scol, srow, scl, flip_h, tint)
	else:
		var hw: float = 18.0 * scl
		var hh: float = 36.0 * scl
		canvas.draw_rect(Rect2(pos.x - hw, pos.y - hh * 2, hw * 2, hh * 2), mod * get_blame_color())


## Draw Blame sprite vertically flipped (for ceiling). pos = head attachment point.
func draw_blame_sprite_flipped(canvas: CanvasItem, pos: Vector2, scol: int, srow: int,
		scl: float, flip_h: bool, mod: Color = Color.WHITE) -> void:
	var tint := mod * Color(0.65, 0.7, 1.0)
	var draw_pos := Vector2(pos.x, pos.y - 25.0 * scl)
	if golem_sheet:
		_draw_sheet_frame(canvas, golem_sheet, draw_pos, GOLEM_FW, GOLEM_FH, scol, srow, scl, flip_h, tint, true)
	else:
		var hw: float = 18.0 * scl
		var hh: float = 36.0 * scl
		canvas.draw_rect(Rect2(pos.x - hw, pos.y, hw * 2, hh * 2), mod * get_blame_color())


## Draw Denial (Rogue) sprite at pos (feet position).
func draw_denial_sprite(canvas: CanvasItem, pos: Vector2, scol: int, srow: int,
		scl: float, flip_h: bool, mod: Color = Color.WHITE) -> void:
	# Tint toward warm orange (denial's emotion color)
	var tint := mod * Color(1.0, 0.75, 0.55)
	if rogue_sheet:
		_draw_sheet_frame(canvas, rogue_sheet, pos, ROGUE_FW, ROGUE_FH, scol, srow, scl, flip_h, tint)
	else:
		var r: float = 18.0 * scl
		canvas.draw_circle(Vector2(pos.x, pos.y - r), r, mod * get_denial_color())


## Draw Denial sprite vertically flipped (for ceiling). pos = head attachment point.
func draw_denial_sprite_flipped(canvas: CanvasItem, pos: Vector2, scol: int, srow: int,
		scl: float, flip_h: bool, mod: Color = Color.WHITE) -> void:
	var tint := mod * Color(1.0, 0.75, 0.55)
	if rogue_sheet:
		_draw_sheet_frame(canvas, rogue_sheet, pos, ROGUE_FW, ROGUE_FH, scol, srow, scl, flip_h, tint, true)
	else:
		var r: float = 18.0 * scl
		canvas.draw_circle(Vector2(pos.x, pos.y + r), r, mod * get_denial_color())


func _draw_sheet_frame(canvas: CanvasItem, tex: Texture2D, pos: Vector2,
		fw: int, fh: int, scol: int, srow: int, scl: float, flip_h: bool, mod: Color,
		flip_v: bool = false) -> void:
	var src := Rect2(scol * fw, srow * fh, fw, fh)
	var dw: float = float(fw) * scl
	var dh: float = float(fh) * scl
	# pos is feet — sprite draws upward from feet, centered horizontally
	var dest: Rect2
	if flip_v:
		# Inverted: sprite draws DOWNWARD from head position
		dest = Rect2(pos.x - dw * 0.5, pos.y, dw, dh)
		src.position.y += src.size.y
		src.size.y = -src.size.y
	else:
		dest = Rect2(pos.x - dw * 0.5, pos.y - dh, dw, dh)
	if flip_h:
		src.position.x += src.size.x
		src.size.x = -src.size.x
	canvas.draw_texture_rect_region(tex, dest, src, mod)


## Convenience: get an animation frame index from time
func anim_frame(time: float, frame_count: int, fps: float = 10.0, looping: bool = true) -> int:
	var frame: int = int(time * fps)
	if looping:
		return frame % maxi(frame_count, 1)
	else:
		return mini(frame, frame_count - 1)


func _setup_music() -> void:
	music_player = AudioStreamPlayer.new()
	add_child(music_player)
	music_player.bus = "Master"
	music_player.volume_db = -6.0
	var music_path := "res://assets/audio/background_music.mp3"
	if ResourceLoader.exists(music_path):
		var stream: AudioStream = load(music_path)
		if stream:
			music_player.stream = stream
			music_player.play()
			music_player.finished.connect(_on_music_finished)


func _on_music_finished() -> void:
	music_player.play()


# --- Global Shard System ---
func generate_shards() -> void:
	shards.clear()
	grid_verts.clear()
	falling_shards.clear()
	collapse_active = false
	collapse_timer = 0.0

	var cell_w: float = 1280.0 / float(SHARD_COLS)
	var cell_h: float = 720.0 / float(SHARD_ROWS)

	for row in range(SHARD_ROWS + 1):
		for col in range(SHARD_COLS + 1):
			var x: float = float(col) * cell_w
			var y: float = float(row) * cell_h
			if col > 0 and col < SHARD_COLS and row > 0 and row < SHARD_ROWS:
				x += randf_range(-cell_w * 0.25, cell_w * 0.25)
				y += randf_range(-cell_h * 0.25, cell_h * 0.25)
			grid_verts.append(Vector2(x, y))

	for row in range(SHARD_ROWS):
		for col in range(SHARD_COLS):
			var tl_idx: int = row * (SHARD_COLS + 1) + col
			var tr_idx: int = tl_idx + 1
			var bl_idx: int = (row + 1) * (SHARD_COLS + 1) + col
			var br_idx: int = bl_idx + 1
			var vtl: Vector2 = grid_verts[tl_idx]
			var vtr: Vector2 = grid_verts[tr_idx]
			var vbl: Vector2 = grid_verts[bl_idx]
			var vbr: Vector2 = grid_verts[br_idx]

			if randf() > 0.5:
				_add_global_shard(PackedVector2Array([vtl, vtr, vbr]), col, row)
				_add_global_shard(PackedVector2Array([vtl, vbr, vbl]), col, row)
			else:
				_add_global_shard(PackedVector2Array([vtl, vtr, vbl]), col, row)
				_add_global_shard(PackedVector2Array([vtr, vbr, vbl]), col, row)

	shards_generated = true


func _add_global_shard(pts: PackedVector2Array, col: int, _row: int) -> void:
	var norm_x: float = float(col) / float(SHARD_COLS)
	var warm_bias: float = 1.0 - norm_x
	# Muted revealed colors — subtle, not distracting during gameplay
	var revealed_color: Color
	if randf() < warm_bias:
		revealed_color = Color(randf_range(0.25, 0.38), randf_range(0.15, 0.22), randf_range(0.1, 0.16), 0.9)
	else:
		revealed_color = Color(randf_range(0.08, 0.15), randf_range(0.1, 0.18), randf_range(0.2, 0.32), 0.9)

	var grey_val: float = randf_range(0.12, 0.22)
	var center: Vector2 = (pts[0] + pts[1] + pts[2]) / 3.0

	shards.append({
		"points": pts,
		"center": center,
		"alive": true,
		"surface_color": Color(grey_val, grey_val, grey_val + 0.02, 1.0),
		"revealed_color": revealed_color,
		"owner": 0,
		"edge_color": Color(grey_val + 0.06, grey_val + 0.06, grey_val + 0.08, 0.35)
	})


func break_shards_near(impact_pos: Vector2, radius: float, breaker: int) -> int:
	var broken_count: int = 0
	for shard: Dictionary in shards:
		if not (shard.alive as bool):
			continue
		var dist: float = (shard.center as Vector2).distance_to(impact_pos)
		if dist < radius:
			var chance: float = 1.0 - (dist / radius)
			if randf() < chance * 0.8:
				_shatter_shard(shard, impact_pos)
				shard.owner = breaker
				broken_count += 1
	return broken_count


func break_random_shards(count: int) -> void:
	var alive_indices: Array[int] = []
	for i in range(shards.size()):
		if shards[i].alive:
			alive_indices.append(i)
	if alive_indices.is_empty():
		return
	for n in range(mini(count, alive_indices.size())):
		var pick: int = randi() % alive_indices.size()
		var idx: int = alive_indices[pick]
		_shatter_shard(shards[idx], (shards[idx].center as Vector2) + Vector2(0, -30))
		alive_indices.remove_at(pick)


func trigger_collapse() -> void:
	collapse_active = true
	collapse_timer = 0.0


func _shatter_shard(shard: Dictionary, impact_pos: Vector2) -> void:
	shard.alive = false
	var center: Vector2 = shard.center
	var vel: Vector2 = (center - impact_pos).normalized() * randf_range(20, 80)
	vel.y -= randf_range(15, 50)
	falling_shards.append({
		"points": shard.points,
		"center": Vector2(center.x, center.y),
		"vel": vel,
		"alpha": 1.0,
		"color": shard.surface_color
	})


func get_alive_shard_count() -> int:
	var count: int = 0
	for shard: Dictionary in shards:
		if shard.alive:
			count += 1
	return count


func get_uncorrupted_count() -> int:
	var count: int = 0
	for shard: Dictionary in shards:
		if not shard.get("corrupted", false):
			count += 1
	return count


func _unhandled_input(event: InputEvent) -> void:
	# DEBUG: Press F9 to skip current scene (for development only)
	if event is InputEventKey and (event as InputEventKey).pressed and (event as InputEventKey).keycode == KEY_F9:
		_debug_skip()


func reset_game() -> void:
	current_phase = Phase.MAIN_MENU
	hue_value = 0.5
	blame_wins = 0
	denial_wins = 0
	round_winners.clear()
	revealed_fragments.clear()
	fragment_order.clear()
	boss_charge = 0.0
	bad2_revealed = false
	transition_shown = false
	coop_phase = 0
	generate_shards()


func _debug_skip() -> void:
	match current_phase:
		Phase.COMPETITIVE_1:
			if round_winners.size() < 1:
				register_competitive_win(randf() > 0.5)
		Phase.WINNER_1, Phase.WINNER_2:
			pass
		Phase.COMPETITIVE_2:
			if round_winners.size() < 2:
				register_competitive_win(randf() > 0.5)
		Phase.FRAGMENT_REVEAL_1, Phase.FRAGMENT_REVEAL_2, Phase.FRAGMENT_REVEAL_3, Phase.FRAGMENT_REVEAL_4:
			# Build default order if somehow empty (skipped all competitive)
			if fragment_order.is_empty():
				register_competitive_win(true)
				register_competitive_win(false)
			if revealed_fragments.size() < fragment_order.size():
				get_next_fragment()
		Phase.COOPERATIVE_1:
			if fragment_order.is_empty():
				register_competitive_win(true)
				register_competitive_win(false)
			coop_phase = maxi(coop_phase, 1)
		Phase.COOPERATIVE_2:
			coop_phase = maxi(coop_phase, 2)
		Phase.FULL_MEMORY:
			if fragment_order.is_empty():
				register_competitive_win(true)
				register_competitive_win(false)
			while revealed_fragments.size() < fragment_order.size():
				get_next_fragment()
			collapse_active = false
		Phase.BOSS_FIGHT:
			collapse_active = false
		Phase.FATALITY:
			collapse_active = false

	advance_phase()


func set_hue(value: float) -> void:
	hue_value = clampf(value, 0.0, 1.0)
	hue_changed.emit(hue_value)


func register_competitive_win(blame_won: bool) -> void:
	round_winners.append(blame_won)
	if blame_won:
		blame_wins += 1
	else:
		denial_wins += 1
	_rebuild_fragment_order()
	print("[GM] register_competitive_win: blame_won=", blame_won, " round_winners=", round_winners, " -> fragment_order=", fragment_order)


func get_last_winner_is_blame() -> bool:
	if round_winners.is_empty():
		return true
	return round_winners[-1]


func _rebuild_fragment_order() -> void:
	fragment_order.clear()
	# Winner of each round gets their next unseen fragment.
	# Blame queue: B1, B2.  Denial queue: G1, G2.
	var blame_queue: Array[String] = [BAD_1, BAD_2]
	var denial_queue: Array[String] = [GOOD_1, GOOD_2]
	var competitive_fragments: Array[String] = []

	for i: int in round_winners.size():
		if round_winners[i]:
			# Blame won this round — pop next blame fragment
			if not blame_queue.is_empty():
				competitive_fragments.append(blame_queue.pop_front())
		else:
			# Denial won this round — pop next denial fragment
			if not denial_queue.is_empty():
				competitive_fragments.append(denial_queue.pop_front())

	# Cooperative rounds get whatever remains (blame leftovers then denial leftovers)
	var remaining: Array[String] = []
	remaining.append_array(denial_queue)
	remaining.append_array(blame_queue)

	fragment_order = competitive_fragments + remaining


func get_next_fragment() -> String:
	var idx := revealed_fragments.size()
	if idx < fragment_order.size():
		var frag: String = fragment_order[idx]
		revealed_fragments.append(frag)
		if frag == BAD_2:
			bad2_revealed = true
		fragment_revealed.emit(frag)
		print("[GM] get_next_fragment: idx=", idx, " frag=", frag, " order=", fragment_order, " revealed=", revealed_fragments)
		return frag
	print("[GM] get_next_fragment: NO FRAGMENT LEFT, idx=", idx, " order=", fragment_order)
	return ""


func get_current_fragment_id() -> String:
	# Returns the fragment that should be shown next (without consuming it)
	var idx := revealed_fragments.size()
	if idx < fragment_order.size():
		return fragment_order[idx]
	return ""


func advance_phase() -> void:
	var next_phase: Phase
	match current_phase:
		Phase.MAIN_MENU:
			next_phase = Phase.PROLOGUE
		Phase.PROLOGUE:
			next_phase = Phase.INTRO_CUTSCENE
		Phase.INTRO_CUTSCENE:
			next_phase = Phase.COMPETITIVE_1
		Phase.COMPETITIVE_1:
			next_phase = Phase.WINNER_1
		Phase.WINNER_1:
			next_phase = Phase.FRAGMENT_REVEAL_1
		Phase.FRAGMENT_REVEAL_1:
			next_phase = Phase.COMPETITIVE_2
		Phase.COMPETITIVE_2:
			next_phase = Phase.WINNER_2
		Phase.WINNER_2:
			next_phase = Phase.FRAGMENT_REVEAL_2
		Phase.FRAGMENT_REVEAL_2:
			next_phase = Phase.COOPERATIVE_1
		Phase.TRANSITION_CUTSCENE:
			# Kept for safety but no longer triggered
			if coop_phase == 0:
				next_phase = Phase.COOPERATIVE_1
			else:
				next_phase = Phase.COOPERATIVE_2
		Phase.COOPERATIVE_1:
			coop_phase = 1
			next_phase = Phase.FRAGMENT_REVEAL_3
		Phase.FRAGMENT_REVEAL_3:
			next_phase = Phase.COOPERATIVE_2
		Phase.COOPERATIVE_2:
			coop_phase = 2
			next_phase = Phase.FRAGMENT_REVEAL_4
		Phase.FRAGMENT_REVEAL_4:
			next_phase = Phase.FULL_MEMORY
		Phase.FULL_MEMORY:
			next_phase = Phase.BOSS_FIGHT
		Phase.BOSS_FIGHT:
			next_phase = Phase.FATALITY
		Phase.FATALITY:
			next_phase = Phase.OUTRO
		Phase.OUTRO:
			next_phase = Phase.REFLECTION
		Phase.REFLECTION:
			next_phase = Phase.MAIN_MENU
			reset_game()
		_:
			next_phase = Phase.MAIN_MENU

	print("[GM] advance_phase: ", Phase.keys()[current_phase], " -> ", Phase.keys()[next_phase])
	current_phase = next_phase
	phase_changed.emit(Phase.keys()[current_phase])
	_load_phase_scene()


func _load_phase_scene() -> void:
	if scene_map.has(current_phase):
		get_tree().change_scene_to_file(scene_map[current_phase])


func go_to_phase(phase: Phase) -> void:
	current_phase = phase
	phase_changed.emit(Phase.keys()[current_phase])
	_load_phase_scene()


# Color helpers
func get_blame_color() -> Color:
	return Color(0.2, 0.25, 0.45) # Cold dark blue

func get_blame_color_light() -> Color:
	return Color(0.35, 0.4, 0.65)

func get_denial_color() -> Color:
	return Color(0.88, 0.48, 0.37) # Warm muted orange

func get_denial_color_light() -> Color:
	return Color(0.95, 0.65, 0.5)

func get_grey() -> Color:
	return Color(0.35, 0.35, 0.38)

func get_bg_color() -> Color:
	# Interpolate between blame (cold) and denial (warm) based on hue_value
	var blame_bg := Color(0.08, 0.08, 0.15)
	var denial_bg := Color(0.18, 0.12, 0.1)
	return blame_bg.lerp(denial_bg, hue_value)


# Fragment texture paths
func get_fragment_texture_path(fragment_id: String) -> String:
	match fragment_id:
		GOOD_1: return "res://assets/fragments/G1_happy_times.png"
		GOOD_2: return "res://assets/fragments/G2_conversations.png"
		BAD_1: return "res://assets/fragments/B1_crying.png"
		BAD_2: return "res://assets/fragments/B2_accident.png"
	return ""


func get_fragment_title(fragment_id: String) -> String:
	match fragment_id:
		GOOD_1: return "Happy Times"
		GOOD_2: return "The Promise"
		BAD_1: return "Tears"
		BAD_2: return "The Accident"
	return ""
