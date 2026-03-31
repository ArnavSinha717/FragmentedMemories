# FRACTURED MEMORIES — Hackathon Presentation

---

## SLIDE 1: Title

**FRACTURED MEMORIES**

*A 2-player cooperative game about grief, memory, and acceptance*

Two halves. One fractured mind.

---

## SLIDE 2: The Problem

**Grief is not a single emotion.**

When we lose someone, our mind doesn't process it cleanly. It fractures — into blame, denial, anger, acceptance. These emotions fight each other, each believing they're right.

Most games treat mental health as a mechanic. We wanted to make a game where **the mechanic IS the message**.

---

## SLIDE 3: The Concept

**What if two players each controlled a different side of the same grieving mind?**

- **Player 1: BLAME** — The weight of what happened. Cold. Unforgiving.
- **Player 2: DENIAL** — The refusal to remember. Warm. Desperate.

They start as enemies. They end as one.

The journey mirrors the five stages of grief — but through gameplay, not cutscenes.

---

## SLIDE 4: How It Works

**The game has 3 acts:**

**ACT 1 — CONFLICT** (Competitive)
- Players fight each other in asymmetric combat
- The winner's emotion determines which memory surfaces first
- Blame winning = painful memories first. Denial winning = happy memories first.

**ACT 2 — COOPERATION** (Cooperative)
- Players realize they're the same person
- Must work together to navigate challenges
- Ghost platforms only solidify when the right player is near
- Darkness only lifts when both stay close

**ACT 3 — ACCEPTANCE** (Boss Fight)
- Both players fight GUILT together
- Can only deal damage through synchronized attacks
- The final message: healing requires facing the truth together

---

## SLIDE 5: The Story (No Spoilers)

Two best friends. One night changed everything.

From the grief, memory fragments surface — but they're fractured:
- Happy times together
- A promise made
- Tears that won't stop
- The accident

**Who wins the competitive rounds determines the ORDER memories are revealed.**
Every playthrough tells the same story — but the emotional journey is different.

---

## SLIDE 6: Game Modes

| Mode | Type | Mechanic |
|------|------|----------|
| **Clash of Emotions** | Competitive | Asymmetric fighter — Blame is heavy/slow, Denial is fast/tricky |
| **Gravity Run** | Competitive | Flip gravity to catch memory fragments mid-flight |
| **Carrying the Weight** | Cooperative | Platforms only exist when the matching player is near |
| **Into the Fog** | Cooperative | Dark maze — players start separated, must find each other |
| **GUILT Boss Fight** | Cooperative | Synchronized attacks only — solo hits do nothing |

---

## SLIDE 7: Adaptive Narrative

**The game remembers who wins.**

- If Blame wins Round 1 → painful memory surfaces first → heavier emotional start
- If Denial wins Round 1 → happy memory first → the pain hits harder later
- Mixed results → the most emotionally complex path

**Same ending. Different emotional journeys. 4 possible fragment orderings.**

Post-fragment dialogue adapts based on what's been seen before — characters react differently depending on context.

---

## SLIDE 8: Technical Highlights

- **Engine:** Godot 4.6.1 (open source, lightweight)
- **Language:** GDScript
- **Rendering:** All visuals drawn programmatically via `_draw()` — no scene editor UI needed
- **Sprite System:** Custom sprite sheet renderer with animation, tinting, and vertical flip support
- **Architecture:** Single autoload GameManager controlling a 18-phase state machine
- **Input:** Full keyboard + dual controller support with separate jump/movement actions
- **Pause System:** Global CanvasLayer autoload with context-aware controls display

---

## SLIDE 9: Design Philosophy

**Every mechanic serves the narrative:**

- Competitive → Blame and Denial are in conflict
- The winner shapes what's remembered first → emotions control memory
- Cooperative → They realize they need each other
- Ghost platforms → You literally need the other person to move forward
- Fog walk → You can't see without each other
- Boss fight → You can only hurt GUILT together
- Fatality → They merge into one person

**Nothing is arbitrary. The gameplay IS the therapy.**

---

## SLIDE 10: The Message

> "She didn't save you so you could spend your life drowning."
>
> "Live. Remember and honour her by living."

*For everyone who carries someone they've lost.*

---

## SLIDE 11: What Makes This Different

1. **The mechanic IS the message** — not cutscenes explaining emotions, but gameplay that makes you FEEL them
2. **Asymmetric multiplayer** — each player has a genuinely different experience and moveset
3. **Adaptive narrative** — competitive results change the emotional arc
4. **Cooperative climax** — the game teaches collaboration through mechanics, not tutorials
5. **Replayable** — 4 different fragment orderings, each with unique dialogue paths

---

## SLIDE 12: Demo

*[Live gameplay demo]*

- Show the main menu with fractured title
- Play through a competitive fight
- Show how the winner determines the memory
- Show a cooperative level (fog walk with maze)
- Show the boss fight synchronized attacks

---

## SLIDE 13: Future Scope

- Original soundtrack reflecting emotional states
- Sound effects for combat, UI, and narrative moments
- More competitive/cooperative minigame variants
- Accessibility options (colorblind modes, difficulty scaling)
- Online multiplayer support
- Mobile touch controls
- Localization

---

## SLIDE 14: Team / Credits

**Fractured Memories**

Built for [Hackathon Name]

*A game about the hardest thing we do — learning to live after loss.*

---

## TALKING POINTS (Speaker Notes)

### Opening (30 seconds)
"Have you ever lost someone? Not the clean kind of grief you see in movies. The messy kind — where part of you blames yourself, part of you refuses to believe it happened, and both parts are fighting each other. That's what our game is about."

### The Hook (15 seconds)
"What if you could play BOTH sides of that fight? What if two players each controlled a different emotion inside the same fractured mind?"

### Demo Transition (10 seconds)
"Let me show you what that looks like. This is Fractured Memories."

### Closing (20 seconds)
"Every mechanic in this game serves one purpose — to make you feel what grief actually feels like. Not through words. Through play. And the ending isn't about winning. It's about acceptance."
