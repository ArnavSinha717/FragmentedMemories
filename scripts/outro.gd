extends Control

## Outro — Filler scenes of Lipika living. Shape animations.
## Visiting Anusha's house, sitting with family, feeding her pet, crying, but also living.

@onready var dialogue: Node = $DialogueSystem

var time_elapsed := 0.0
var scene_index := 0
var scene_timer := 0.0
var fade_alpha := 1.0
var phase: int = 0 # 0=scenes, 1=dialogue, 2=done

# Each scene: small shape vignette
var scenes: Array[Dictionary] = [
	{"title": "She visits the house.", "duration": 4.0, "type": "house"},
	{"title": "She sits with the family.", "duration": 4.0, "type": "family"},
	{"title": "She feeds the pet.", "duration": 3.5, "type": "pet"},
	{"title": "She cries.", "duration": 3.0, "type": "crying"},
	{"title": "But she also lives.", "duration": 4.0, "type": "living"},
]

var image_paths: Array[String] = [
	"res://pictures/door_knock.png",
	"res://pictures/meeting_mom.png",
	"res://pictures/petting_dog.png",
	"res://pictures/happy_crying.png",
	"res://pictures/ending.png",
]

var current_texture: Texture2D = null
var scene_text_alpha := 0.0
var current_scene_type := ""


func _ready() -> void:
	dialogue.dialogue_finished.connect(_on_dialogue_done)
	_start_scene()


func _process(delta: float) -> void:
	time_elapsed += delta
	scene_timer += delta

	match phase:
		0:
			# Fade in
			if scene_timer < 1.0:
				fade_alpha = 1.0 - scene_timer
				scene_text_alpha = scene_timer
			elif scene_timer > scenes[scene_index].duration - 1.0:
				fade_alpha = (scene_timer - (scenes[scene_index].duration - 1.0))
				scene_text_alpha = 1.0 - fade_alpha
			else:
				fade_alpha = 0.0
				scene_text_alpha = 1.0

			if scene_timer >= scenes[scene_index].duration:
				scene_index += 1
				if scene_index >= scenes.size():
					phase = 1
					_start_dialogue()
				else:
					_start_scene()
		1: pass
		2:
			fade_alpha = min(1.0, time_elapsed * 0.6)
			if time_elapsed > 2.0:
				GameManager.advance_phase()

	queue_redraw()


func _start_scene() -> void:
	scene_timer = 0.0
	current_scene_type = scenes[scene_index].type
	if scene_index < image_paths.size():
		var path: String = image_paths[scene_index]
		if ResourceLoader.exists(path):
			current_texture = load(path) as Texture2D
		else:
			current_texture = null
	else:
		current_texture = null


func _draw() -> void:
	draw_rect(Rect2(0, 0, 1280, 720), Color(0.05, 0.05, 0.07))

	# Draw the current image if loaded
	if current_texture != null:
		var img_rect := Rect2(Vector2(340, 80), Vector2(600, 420))
		draw_texture_rect(current_texture, img_rect, false, Color(1, 1, 1, scene_text_alpha))

	# Scene title text
	if scene_index < scenes.size():
		var font := ThemeDB.fallback_font
		var text: String = scenes[scene_index].title
		var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 22)
		draw_string(font, Vector2(640 - text_size.x * 0.5, 600), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 22,
			Color(0.65, 0.65, 0.7, scene_text_alpha * 0.8))

	# Fade overlay
	if fade_alpha > 0.01:
		draw_rect(Rect2(0, 0, 1280, 720), Color(0, 0, 0, fade_alpha))


func _start_dialogue() -> void:
	var lines: Array[Dictionary] = [
		{"speaker": "", "text": "She carries the weight. But she also carries the love.", "color": Color(0.7, 0.65, 0.6)},
		{"speaker": "", "text": "And slowly... she learns that remembering doesn't have to mean drowning.", "color": Color(0.7, 0.65, 0.6)},
	]
	dialogue.play_dialogue(lines)


func _on_dialogue_done() -> void:
	phase = 2
	time_elapsed = 0.0
