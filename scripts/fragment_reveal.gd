extends Control

## Shows a memory fragment with sequenced images, narrator dialogue, and
## post-fragment character reactions, then advances the game phase.

enum RevealPhase {
	FADE_IN,
	SHOW_IMAGE_1,
	SHOW_IMAGE_2,
	NARRATOR,
	POST_DIALOGUE,
	FADE_OUT,
}

@onready var sprite_1: TextureRect = $FragmentSprite
@onready var sprite_2: TextureRect = $FragmentSprite2
@onready var title_label: Label = $TitleLabel
@onready var dialogue: Node = $DialogueSystem

var fragment_id: String = ""
var reveal_phase: RevealPhase = RevealPhase.FADE_IN
var time_elapsed: float = 0.0
var fade_alpha: float = 1.0

# Image data for the current fragment
var image_1_path: String = ""
var image_2_path: String = ""
var has_image_1: bool = false
var has_image_2: bool = false

# Timing constants
const FADE_IN_DURATION: float = 2.0
const IMAGE_HOLD_DURATION: float = 3.0
const CROSSFADE_DURATION: float = 1.5
const FADE_OUT_DURATION: float = 1.5

# Crossfade state
var crossfade_timer: float = 0.0
var crossfade_active: bool = false

# Track whether narrator and post-dialogue are needed
var narrator_lines: Array[Dictionary] = []
var post_dialogue_lines: Array[Dictionary] = []
var has_post_dialogue: bool = false

# BAD_2 special handling: show image 2 mid-narrator
var bad2_narrator_phase: int = 0  # 0=first lines, 1=showed dead, 2=last line
var bad2_waiting_for_image2: bool = false

# Track whether we already connected dialogue signal
var dialogue_connected: bool = false


func _ready() -> void:
	fragment_id = GameManager.get_next_fragment()
	title_label.text = GameManager.get_fragment_title(fragment_id)
	title_label.modulate.a = 0.0

	# Hide both sprites initially
	sprite_1.modulate.a = 0.0
	sprite_2.modulate.a = 0.0

	# Set up image paths and dialogue for this fragment
	_configure_fragment()

	# Load image 1
	if image_1_path != "" and ResourceLoader.exists(image_1_path):
		sprite_1.texture = load(image_1_path)
		has_image_1 = true
	else:
		has_image_1 = false

	# Preload image 2 onto sprite_2 but keep it invisible
	if image_2_path != "" and ResourceLoader.exists(image_2_path):
		sprite_2.texture = load(image_2_path)
		has_image_2 = true
	else:
		has_image_2 = false

	reveal_phase = RevealPhase.FADE_IN
	time_elapsed = 0.0
	fade_alpha = 1.0

	dialogue.dialogue_finished.connect(_on_dialogue_done)
	dialogue_connected = true


func _configure_fragment() -> void:
	var blame_color: Color = GameManager.get_blame_color_light()
	var denial_color: Color = GameManager.get_denial_color_light()
	var narrator_warm: Color = Color(0.9, 0.7, 0.5)
	var narrator_cold: Color = Color(0.5, 0.5, 0.65)
	var narrator_dark: Color = Color(0.6, 0.2, 0.2)
	var narrator_grey: Color = Color(0.5, 0.5, 0.55)

	match fragment_id:
		GameManager.BAD_1:
			image_1_path = "res://pictures/sad_crying.png"
			image_2_path = ""
			narrator_lines = [
				{"speaker": "", "text": "Tears. A room that feels too empty. The kind of crying that comes from somewhere you can't name.", "color": narrator_cold},
			]
			post_dialogue_lines = [
				{"speaker": "Denial", "text": "But... why am I crying?", "color": denial_color},
				{"speaker": "Blame", "text": "You don't remember that either?", "color": blame_color},
				{"speaker": "Denial", "text": "I don't know what you're talking about.", "color": denial_color},
				{"speaker": "Blame", "text": "Neither of us has the full picture, do we.", "color": blame_color},
			]
			has_post_dialogue = true

		GameManager.GOOD_1:
			image_1_path = "res://pictures/smiling_friends.png"
			image_2_path = "res://pictures/besties_forever.png"
			narrator_lines = [
				{"speaker": "", "text": "A memory surfaces... warmth. Laughter. Two people who understood each other without words.", "color": narrator_warm},
			]
			post_dialogue_lines = [
				{"speaker": "Denial", "text": "I remember this. We were so happy.", "color": denial_color},
				{"speaker": "Blame", "text": "Yeah.. I never knew we hung out so much.", "color": blame_color},
				{"speaker": "Denial", "text": "Wait, what? Who are you?", "color": denial_color},
				{"speaker": "Blame", "text": "What do you mean? Who the hell are you?", "color": blame_color},
			]
			has_post_dialogue = true

		GameManager.BAD_2:
			image_1_path = "res://pictures/saving.png"
			image_2_path = "res://pictures/dead.png"
			# BAD_2 has special mid-narrator image switching, handled manually
			narrator_lines = [
				{"speaker": "", "text": "...", "color": narrator_grey},
				{"speaker": "", "text": "A street. A car. A choice made in less than a second.", "color": narrator_dark},
			]
			post_dialogue_lines = []
			has_post_dialogue = false

		GameManager.GOOD_2:
			image_1_path = "res://pictures/bucket_list.png"
			image_2_path = "res://pictures/school_promise.png"
			narrator_lines = [
				{"speaker": "", "text": "Promises made in the quiet hours. 'If something ever happens to me... you live your life.'", "color": narrator_warm},
			]
			post_dialogue_lines = []
			has_post_dialogue = false

		_:
			image_1_path = ""
			image_2_path = ""
			narrator_lines = []
			post_dialogue_lines = []
			has_post_dialogue = false


func _process(delta: float) -> void:
	time_elapsed += delta

	match reveal_phase:
		RevealPhase.FADE_IN:
			_process_fade_in(delta)
		RevealPhase.SHOW_IMAGE_1:
			_process_show_image_1(delta)
		RevealPhase.SHOW_IMAGE_2:
			_process_show_image_2(delta)
		RevealPhase.NARRATOR:
			_process_narrator(delta)
		RevealPhase.POST_DIALOGUE:
			pass  # Waiting for dialogue_finished signal
		RevealPhase.FADE_OUT:
			_process_fade_out(delta)

	queue_redraw()


func _process_fade_in(_delta: float) -> void:
	# Fade black overlay from 1.0 to 0.0
	fade_alpha = maxf(0.0, 1.0 - time_elapsed / FADE_IN_DURATION)
	# Fade in image 1 and title
	var image_alpha: float = minf(1.0, time_elapsed / FADE_IN_DURATION)
	sprite_1.modulate.a = image_alpha
	title_label.modulate.a = minf(1.0, time_elapsed / (FADE_IN_DURATION * 0.8))

	if time_elapsed >= FADE_IN_DURATION:
		sprite_1.modulate.a = 1.0
		title_label.modulate.a = 1.0
		fade_alpha = 0.0
		_transition_to(RevealPhase.SHOW_IMAGE_1)


func _process_show_image_1(_delta: float) -> void:
	# Hold image 1 for IMAGE_HOLD_DURATION, then decide next step
	if time_elapsed >= IMAGE_HOLD_DURATION:
		if fragment_id == GameManager.BAD_2:
			# BAD_2: go straight to narrator with special handling
			_start_bad2_narrator()
		elif has_image_2:
			# Start crossfade to image 2
			_transition_to(RevealPhase.SHOW_IMAGE_2)
			crossfade_timer = 0.0
			crossfade_active = true
		else:
			# No second image, go to narrator
			_start_narrator()


func _process_show_image_2(delta: float) -> void:
	if crossfade_active:
		crossfade_timer += delta
		var t: float = minf(1.0, crossfade_timer / CROSSFADE_DURATION)
		sprite_1.modulate.a = 1.0 - t
		sprite_2.modulate.a = t

		if t >= 1.0:
			crossfade_active = false
			sprite_1.modulate.a = 0.0
			sprite_2.modulate.a = 1.0
			time_elapsed = 0.0  # Reset for hold timer
	else:
		# Holding image 2
		if time_elapsed >= IMAGE_HOLD_DURATION:
			_start_narrator()


func _process_narrator(delta: float) -> void:
	# Narrator dialogue is playing via DialogueSystem, handled by signal
	# BAD_2 crossfade during narrator is handled in _on_dialogue_done
	if crossfade_active:
		crossfade_timer += delta
		var t: float = minf(1.0, crossfade_timer / CROSSFADE_DURATION)
		sprite_1.modulate.a = 1.0 - t
		sprite_2.modulate.a = t
		if t >= 1.0:
			crossfade_active = false
			sprite_1.modulate.a = 0.0
			sprite_2.modulate.a = 1.0


func _process_fade_out(_delta: float) -> void:
	fade_alpha = minf(1.0, time_elapsed / FADE_OUT_DURATION)
	if time_elapsed >= FADE_OUT_DURATION:
		GameManager.advance_phase()


func _transition_to(new_phase: RevealPhase) -> void:
	reveal_phase = new_phase
	time_elapsed = 0.0


func _start_narrator() -> void:
	_transition_to(RevealPhase.NARRATOR)
	if narrator_lines.size() > 0:
		dialogue.play_dialogue(narrator_lines)
	else:
		# No narrator lines, skip to post-dialogue or fade out
		_after_narrator()


func _start_bad2_narrator() -> void:
	# BAD_2 special flow:
	# 1. Play "..." and "A street. A car..." with image 1 (saving.png)
	# 2. Crossfade to dead.png
	# 3. Play "She pushed her out of the way."
	# 4. Fade out (no post-dialogue)
	_transition_to(RevealPhase.NARRATOR)
	bad2_narrator_phase = 0
	dialogue.play_dialogue(narrator_lines)


func _after_narrator() -> void:
	if has_post_dialogue and post_dialogue_lines.size() > 0:
		_transition_to(RevealPhase.POST_DIALOGUE)
		dialogue.play_dialogue(post_dialogue_lines)
	else:
		_transition_to(RevealPhase.FADE_OUT)


func _on_dialogue_done() -> void:
	match reveal_phase:
		RevealPhase.NARRATOR:
			if fragment_id == GameManager.BAD_2 and bad2_narrator_phase == 0:
				# First narrator batch done ("..." and "A street...").
				# Now crossfade to dead.png, then show final line.
				bad2_narrator_phase = 1
				crossfade_active = true
				crossfade_timer = 0.0

				# Wait for crossfade, then play final narrator line
				_start_bad2_crossfade_then_final()
				return

			# Normal narrator done, move to post-dialogue or fade out
			_after_narrator()

		RevealPhase.POST_DIALOGUE:
			_transition_to(RevealPhase.FADE_OUT)

		_:
			# Safety fallback
			_transition_to(RevealPhase.FADE_OUT)


func _start_bad2_crossfade_then_final() -> void:
	# We start the crossfade and use a simple timer approach via _process
	# Once crossfade finishes, we play the final line
	# We track this with bad2_waiting_for_image2
	bad2_waiting_for_image2 = true


## Override _process to also handle BAD_2 crossfade-then-dialogue
## We patch this into the NARRATOR phase processing
func _physics_process(_delta: float) -> void:
	if bad2_waiting_for_image2 and not crossfade_active:
		# Crossfade to dead.png is complete, now show final narrator line
		bad2_waiting_for_image2 = false
		bad2_narrator_phase = 2
		var narrator_grey: Color = Color(0.5, 0.5, 0.55)
		var final_line: Array[Dictionary] = [
			{"speaker": "", "text": "She pushed her out of the way.", "color": narrator_grey},
		]
		dialogue.play_dialogue(final_line)


func _draw() -> void:
	# Background
	draw_rect(Rect2(0, 0, 1280, 720), Color(0.05, 0.05, 0.08))

	# Fade overlay (black)
	if fade_alpha > 0.01:
		draw_rect(Rect2(0, 0, 1280, 720), Color(0, 0, 0, fade_alpha))
