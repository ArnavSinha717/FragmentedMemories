# Fractured Memories — Developer Guide

## What This Is
A 2-player same-screen 2D game built in Godot 4.6.1. Two psychological states (Blame & Denial) inside one fractured mind process a traumatic loss through competitive and cooperative minigames. The mechanic IS the message.

## Tech Stack
- **Engine:** Godot 4.6.1 (2D, GL Compatibility renderer)
- **Language:** GDScript
- **Resolution:** 1280x720, stretch mode `canvas_items`
- **Art style:** Primitive shapes (circles, rectangles, triangles) + hand-drawn PNG fragments

## Project Structure
```
scenes/          — .tscn scene files (one per game phase)
scripts/         — .gd scripts (one per scene + game_manager autoload)
assets/fragments/— placeholder SVG fragments (replaced by pictures/)
pictures/        — hand-drawn PNGs for fragment reveals and outro
shaders/         — (empty, available for future use)
```

## Architecture

### GameManager (autoload singleton)
`scripts/game_manager.gd` — the brain. Controls:
- **Phase state machine:** 16 phases from MAIN_MENU → REFLECTION
- **Fragment order system:** 4 fragments (G1, G2, B1, B2) shown in different order based on who wins competitive rounds
- **Hue system:** 0.0 (cold/blame) to 1.0 (warm/denial), drives background colors
- **BAD_2 gating:** Transition cutscene only triggers after the accident fragment is revealed
- **Cooperative phase tracking:** `coop_phase` variable routes correctly after transition

### Scene Flow
```
Menu → Intro → Fight → Fragment → Catch Memories → Fragment
  → [Transition if BAD_2 seen] → Push Block → Fragment
  → [Transition if BAD_2 seen] → Fog Walk → Fragment
  → Full Memory → Boss → Fatality → Outro → Reflection
```

### DialogueSystem (reusable)
`scenes/dialogue_system.tscn` — instanced as child in any scene that needs dialogue. Typewriter text with hold-to-fast-forward. Call `dialogue.play_dialogue(lines)`, connect `dialogue.dialogue_finished`.

## Controls

| Action | P1 Keyboard | P2 Keyboard | Controller |
|--------|------------|------------|------------|
| Move | WASD | Arrows | Left Stick / D-pad |
| Jump | W | Up | A (Cross) |
| Light Attack | F | Enter | X (Square) |
| Heavy Attack | G | Right Shift | Y (Triangle) |
| Dodge Roll | R | Numpad 0 | B (Circle) |

P1 = Controller 0, P2 = Controller 1.

## The 5 Minigames

### 1. Competitive Fight (`competitive_fight.gd`)
Platform fighter on shattered glass background. Shared vertex grid generates seamless triangle shards. Hits break shards near impact revealing warm/cold colors underneath. Ambient random shard breaking. Light attack, heavy attack (windup), dodge roll with i-frames. Winner = most shards broken.

### 2. Catch Falling Memories (`territory_grab.gd`)
Memory fragments rain from the sky. Blame catches cold/dark shapes, Denial catches warm/bright shapes. Wrong color = -1 point + shatter effect. 3 floating platforms. 35-second match.

### 3. Platformer Block Puzzle (`push_block.gd`)
Cooperative. 3 blocks must reach 3 target zones across a multi-platform level. Both players must push a block from the same side simultaneously. Blocks have gravity. 60-second timer.

### 4. Fog Walking Together (`sync_press.gd`)
Cooperative. Nearly black screen, each player emits light. Stay close = combined brighter light. GUILT sends projectiles: cold shards (Denial blocks), warm embers (Blame blocks), shadow orbs (both must be near). Guilt walls dissolve when both stand near. Memory wisps grant light bursts. 3-phase escalation. GUILT appears at the end.

### 5. Boss Fight — GUILT (`boss_fight.gd`)
Both players attack simultaneously (within 0.35s window) to damage GUILT. Solo attacks do nothing. Charge meter builds with sync hits. Boss fires projectiles that drain world color. When charge is full, both trigger fatality.

## Fragment System
4 fragments, order determined by competitive wins:
- **G1 (Happy Times):** smiling_friends.png → besties_forever.png
- **G2 (The Promise):** bucket_list.png → school_promise.png
- **B1 (Tears):** sad_crying.png
- **B2 (The Accident):** saving.png → dead.png

Blame winning → bad memories surface first. Denial winning → good memories first. Same ending either way.

## Coding Conventions
- **No BG ColorRect in scenes that use `_draw()`** — draw background as first line: `draw_rect(Rect2(0, 0, 1280, 720), color)`
- **Explicit types everywhere** to avoid Godot's Variant inference errors: `var x: Type = ...` for array/dict access
- **Use typed float builtins:** `maxf()`, `minf()`, `absf()`, `clampf()`, `lerpf()` instead of generic `max()`, `min()`, etc.
- **Type loop variables:** `for item: Dictionary in array:`
- **Dialogue pattern:** Create `Array[Dictionary]` of `{speaker, text, color}`, call `dialogue.play_dialogue(lines)`
- **Phase advancement:** Always call `GameManager.advance_phase()` to move to next scene

## Adding a New Scene
1. Create `scripts/my_scene.gd` extending `Control`
2. Create `scenes/my_scene.tscn` with the script attached
3. Add phase to `GameManager.Phase` enum
4. Add scene path to `GameManager.scene_map`
5. Wire up `advance_phase()` routing
6. Instance `dialogue_system.tscn` as child if needed

## Assets Needed
- Fragment PNGs go in `pictures/` (currently provided)
- Replace `assets/fragments/*.svg` placeholders if desired
- Audio files (`.ogg` music, `.wav` sfx) go in `assets/audio/` — not yet implemented
- Sprite replacements for characters go in `assets/shapes/` — planned for later phases

## Running
Open `project.godot` in Godot 4.6.1 → press F5.
