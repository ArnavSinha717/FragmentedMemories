extends Node2D

## Persistent shard background drawn behind all scenes.
## Lives inside a CanvasLayer at layer -1 (behind everything).
## Reads shard data from GameManager and draws every frame.

var time_elapsed: float = 0.0
var ambient_timer: float = 0.0


func _process(delta: float) -> void:
	time_elapsed += delta

	if not GameManager.shards_generated:
		return

	# Ambient progressive decay — shards break slowly during gameplay
	if not GameManager.collapse_active:
		var phase: GameManager.Phase = GameManager.current_phase
		var decay_interval: float = 999.0  # No decay by default
		match phase:
			GameManager.Phase.MAIN_MENU: decay_interval = 999.0
			GameManager.Phase.INTRO_CUTSCENE: decay_interval = 12.0
			GameManager.Phase.COMPETITIVE_1: decay_interval = 1.5
			GameManager.Phase.COMPETITIVE_2: decay_interval = 3.0
			GameManager.Phase.COOPERATIVE_1: decay_interval = 4.0
			GameManager.Phase.COOPERATIVE_2: decay_interval = 5.0
			GameManager.Phase.TRANSITION_CUTSCENE: decay_interval = 6.0
			GameManager.Phase.FULL_MEMORY: decay_interval = 999.0
			_: decay_interval = 8.0

		ambient_timer += delta
		if ambient_timer >= decay_interval:
			ambient_timer = 0.0
			GameManager.break_random_shards(1)

	# Update falling shards
	for i in range(GameManager.falling_shards.size() - 1, -1, -1):
		var fs: Dictionary = GameManager.falling_shards[i]
		fs.vel = (fs.vel as Vector2) + Vector2(0, 150) * delta
		fs.center = (fs.center as Vector2) + (fs.vel as Vector2) * delta
		fs.alpha = (fs.alpha as float) - delta * 0.35
		if (fs.alpha as float) <= 0 or (fs.center as Vector2).y > 800:
			GameManager.falling_shards.remove_at(i)

	# Corruption: GUILT turns all shards black, spreading from center
	if GameManager.collapse_active:
		GameManager.collapse_timer += delta
		var center := Vector2(640, 360)
		var spread_radius: float = GameManager.collapse_timer * 300.0  # Expands outward
		var any_uncorrupted: bool = false
		for shard: Dictionary in GameManager.shards:
			if shard.get("corrupted", false):
				continue
			var dist: float = (shard.center as Vector2).distance_to(center)
			if dist < spread_radius:
				# Corrupt this shard — turn it black
				shard.surface_color = Color(0.03, 0.02, 0.05, 1.0)
				shard.revealed_color = Color(0.03, 0.02, 0.05, 1.0)
				shard.edge_color = Color(0.08, 0.04, 0.1, 0.5)
				shard["corrupted"] = true
			else:
				any_uncorrupted = true
		if not any_uncorrupted:
			GameManager.collapse_active = false

	queue_redraw()


func _draw() -> void:
	if not GameManager.shards_generated:
		draw_rect(Rect2(0, 0, 1280, 720), Color(0.08, 0.08, 0.12))
		return

	# Base background color
	draw_rect(Rect2(0, 0, 1280, 720), GameManager.get_bg_color())

	# Draw all shards
	for shard: Dictionary in GameManager.shards:
		var pts: PackedVector2Array = shard.points
		if shard.alive:
			draw_colored_polygon(pts, shard.surface_color as Color)
			for j in range(pts.size()):
				draw_line(pts[j], pts[(j + 1) % pts.size()], shard.edge_color as Color, 1.0)
		else:
			draw_colored_polygon(pts, shard.revealed_color as Color)

	# Draw falling shards
	for fs: Dictionary in GameManager.falling_shards:
		var col: Color = fs.color
		col.a = fs.alpha
		var offset: Vector2 = (fs.center as Vector2) - _poly_center(fs.points as PackedVector2Array)
		var shifted := PackedVector2Array()
		for p in (fs.points as PackedVector2Array):
			shifted.append(p + offset)
		if shifted.size() >= 3:
			draw_colored_polygon(shifted, col)

	# Phase-specific overlays
	var phase: GameManager.Phase = GameManager.current_phase
	match phase:
		# Fog walk needs dark overlay — the scene handles its own darkness
		# but we still want the shard bg to show through faintly
		GameManager.Phase.COOPERATIVE_2:
			draw_rect(Rect2(0, 0, 1280, 720), Color(0.0, 0.0, 0.02, 0.85))
		# Fragment reveals: slight dim so images pop
		GameManager.Phase.FRAGMENT_REVEAL_1, GameManager.Phase.FRAGMENT_REVEAL_2, \
		GameManager.Phase.FRAGMENT_REVEAL_3, GameManager.Phase.FRAGMENT_REVEAL_4:
			draw_rect(Rect2(0, 0, 1280, 720), Color(0.0, 0.0, 0.0, 0.5))
		# Outro + reflection: mostly revealed, calm
		GameManager.Phase.REFLECTION:
			draw_rect(Rect2(0, 0, 1280, 720), Color(0.02, 0.02, 0.04, 0.3))


func _poly_center(pts: PackedVector2Array) -> Vector2:
	var sum := Vector2.ZERO
	for p in pts:
		sum += p
	return sum / maxf(float(pts.size()), 1.0)
