# Minimal Runner Game – Logic Overview

This document explains how the **Minimal Runner** game in `lib/main.dart` works: the game loop, physics, obstacles, scoring, controls, and rendering.

---

## 1. High‑Level Gameplay

- You control a **runner character** that automatically stays at a fixed horizontal position on the left side of the screen.
- **Ghost obstacles** move from right to left along the ground.
- You **jump** to avoid colliding with the ghost.
- The longer you survive, the **higher your score** and the **harder** the game becomes (faster obstacles and a slightly larger player).
- When a collision happens, the game shows a **“Game Over”** overlay with your final score, and a tap/space press restarts the run.

---

## 2. World & Coordinate System

Internally, the game uses a **normalized 0–1 coordinate system** for positions and sizes, then converts these to pixels with `LayoutBuilder`.

- **Ground line**
  - `_groundY = 0.9` – vertical position of the ground as a fraction of screen height (10% from the bottom).
- **Player base parameters**
  - `_playerX = 0.2` – fixed horizontal position (20% of screen width from the left).
  - `_playerBaseWidth = 0.06`
  - `_playerBaseHeight = 0.14`
- **Obstacle base parameters**
  - `_obstacleWidth = 0.06`
  - `_obstacleHeight = 0.16`
- **Scaling over time**
  - Player grows using `_sizeLevel`:
    - `_playerWidth  = _playerBaseWidth  * (1 + 0.5 * _sizeLevel)`
    - `_playerHeight = _playerBaseHeight * (1 + 0.5 * _sizeLevel)`
  - Ghost size is randomized via `_obstacleScale`:
    - `_currentObstacleWidth  = _obstacleWidth  * _obstacleScale`
    - `_currentObstacleHeight = _obstacleHeight * _obstacleScale`

At render time, these logical values are mapped to pixels:

- `playerPixelWidth  = width  * _playerWidth`
- `playerPixelHeight = height * _playerHeight`
- `playerCenterX     = width  * _playerX`
- `playerBottomY     = height * _playerY`
- `obstacleLeftX     = width  * _obstacleX`
- `obstacleBottomY   = groundPixelY = height * _groundY`

This makes the game automatically adapt to different screen sizes.

---

## 3. Game State & Difficulty

Key state variables:

- `_playerY` – player’s vertical position (0–1, bottom = 1.0).
- `_playerVelocity` – vertical velocity for jump/gravity.
- `_obstacleX` – obstacle’s left position in 0–1 world units.
- `_elapsedSeconds` – total time survived in seconds.
- `_score` – integer score; floor of `_elapsedSeconds`.
- `_isGameOver` – whether the player has collided.
- `_sizeLevel` – player growth level.
- `_obstacleScale` – random size multiplier for the ghost.

Difficulty scaling:

- **Score**
  - Every frame: `_elapsedSeconds += dt;`
  - `_score = _elapsedSeconds.floor();` → 1 point per second survived.
- **Player growth**
  - `newSizeLevel = (_elapsedSeconds ~/ 15);`
  - The player grows in size every **15 seconds** (affects hitbox and visual size).
- **Obstacle speed**
  - `_baseObstacleSpeed = 0.5` (fraction of screen per second).
  - `speedLevel = (_elapsedSeconds ~/ 10);`
  - `_currentObstacleSpeed = _baseObstacleSpeed * (1 + 0.1 * speedLevel);`
  - Every **10 seconds**, obstacle speed increases by **10%**, making dodging harder.

---

## 4. Game Loop & Timer

The game loop uses a fixed-period timer:

- `Timer.periodic(const Duration(milliseconds: 16), ...)` in `_startGameLoop()`
  - Approximately **60 updates per second**.
  - Each tick computes `dt` = seconds since last update.
  - Calls `_updateGame(dt)` to advance the simulation.

Core update logic in `_updateGame(dt)`:

1. If `_isGameOver` is `true`, return early (no movement/physics).
2. Update **time & score**:
   - `_elapsedSeconds += dt;`
   - `_score = _elapsedSeconds.floor();`
3. Update **player size level** based on total time.
4. Apply **physics** (gravity and vertical movement).
5. Move the **obstacle** left and respawn it if it leaves the screen.
6. Check **collision** between player and obstacle.
7. If there is a collision, set `_isGameOver = true`.

Mermaid diagram of the loop:

```mermaid
flowchart TD
  start[StartOrReset] --> loopTick[TimerTick(16ms)]
  loopTick --> checkGameOver{isGameOver?}
  checkGameOver -- "Yes" --> waitInput[WaitForTapOrSpaceToReset]
  waitInput --> start
  checkGameOver -- "No" --> updateTime[UpdateTimeAndScore]
  updateTime --> growPlayer[UpdatePlayerSizeLevel]
  growPlayer --> applyPhysics[ApplyGravityAndMovePlayer]
  applyPhysics --> moveObstacle[MoveObstacleLeft]
  moveObstacle --> maybeRespawn{ObstacleOffScreen?}
  maybeRespawn -- "Yes" --> respawn[RespawnAndRandomizeSize]
  respawn --> collide[CheckCollision]
  maybeRespawn -- "No" --> collide[CheckCollision]
  collide -- "Collision" --> setGameOver[SetGameOverTrue]
  setGameOver --> waitInput
  collide -- "NoCollision" --> loopTick
```

---

## 5. Player Physics & Jumping

Physics constants:

- `_gravity = 5.0` – downward acceleration (fraction/s²).
- `_shortJumpVelocity = -2.0` – small jump (single tap/space).
-.`_highJumpVelocity = -3.2` – higher jump (double space press).

Each update:

1. Apply gravity:
   - `_playerVelocity += _gravity * dt;`
2. Move player vertically:
   - `_playerY += _playerVelocity * dt;`
3. Clamp to ground:
   - If `_playerY > _groundY`, then:
     - `_playerY = _groundY;`
     - `_playerVelocity = 0;`

Jumping is handled via `_jump(double velocity)`:

- Only allowed when the player is on (or very close to) the ground:
  - `if ((_playerY - _groundY).abs() < 0.005) { _playerVelocity = velocity; }`
- This prevents **double jumps** in mid‑air.

Two main ways to trigger a jump:

- `_handleTap()` – used for screen taps:
  - If game over → calls `_resetGame()`.
  - Else → `_jump(_shortJumpVelocity);`
- `_handleSpaceJump({required bool high})` – used for spacebar:
  - If game over → calls `_resetGame()`.
  - Else → `_jump(high ? _highJumpVelocity : _shortJumpVelocity);`

---

## 6. Obstacle Movement & Respawn

The ghost obstacle constantly moves left:

- On each update:
  - `_obstacleX -= _currentObstacleSpeed * dt;`
- When it’s fully off the left side:
  - Condition: `_obstacleX + _currentObstacleWidth < 0`
  - Reset:
    - `_obstacleX = 1.2;` (starts off-screen to the right)
    - `_randomizeObstacleSize();`

Randomized size:

- `_randomizeObstacleSize()`:
  - `_obstacleScale = 0.7 + _random.nextDouble() * 0.8;`
  - Ghost size varies between **70% and 150%** of its base size.
  - This makes each obstacle visually and mechanically slightly different.

---

## 7. Collision Detection & Game Over

Collision is calculated as **axis-aligned bounding box (AABB)** overlap in normalized world units:

- Player box:
  - `playerLeft   = _playerX - _playerWidth / 2;`
  - `playerRight  = _playerX + _playerWidth / 2;`
  - `playerTop    = _playerY - _playerHeight;`
  - `playerBottom = _playerY;`
- Obstacle box:
  - `obstacleLeft   = _obstacleX;`
  - `obstacleRight  = _obstacleX + _currentObstacleWidth;`
  - `obstacleTop    = _groundY - _currentObstacleHeight;`
  - `obstacleBottom = _groundY;`

Overlap test:

- Horizontal overlap:
  - `overlapX = playerRight > obstacleLeft && playerLeft < obstacleRight;`
- Vertical overlap:
  - `overlapY = playerBottom > obstacleTop && playerTop < obstacleBottom;`
- Collision:
  - `return overlapX && overlapY;`

If `_checkCollision()` returns `true`:

- `_isGameOver = true;`
- The game stops updating movement and shows the **game over overlay**.

Resetting the game (`_resetGame()`):

- Resets:
  - `_playerY`, `_playerVelocity`, `_obstacleX`
  - `_elapsedSeconds`, `_score`, `_isGameOver`, `_sizeLevel`
  - `_lastSpaceDownMs`
- Randomizes obstacle size and restarts the timer loop.

---

## 8. Controls & Input Handling

### 8.1 Touch / Mouse (Tap)

- The whole screen is wrapped in a `GestureDetector` with `onTap: _handleTap`.
- Behavior:
  - If **game over**: restart the game (`_resetGame()`).
  - Otherwise: perform a **small jump** with `_shortJumpVelocity`.

### 8.2 Keyboard (Spacebar)

- A `RawKeyboardListener` with a `FocusNode` listens for space key presses.
- On `RawKeyDownEvent` for space:
  - Record `now = millisecondsSinceEpoch`.
  - Compare with `_lastSpaceDownMs`:
    - If the time difference is within `_doublePressThresholdMs = 250` ms, treat it as a **double-press**.
  - Call `_handleSpaceJump(high: isDouble);`:
    - Single space press → **small jump**.
    - Rapid double space press → **high jump**.
- On the web/desktop, this provides finer control compared to tap-only input.

### 8.3 Restarting

- On both tap and space:
  - If `_isGameOver` is `true`, the input **restarts** the game instead of jumping.

---

## 9. Rendering & UI Layout

Rendering is built with a `Stack` inside `LayoutBuilder`:

1. **Background**
   - `Image.asset('assets/background.jpg', fit: BoxFit.cover)` fills the whole screen.
2. **Ground overlay**
   - A semi-transparent black `Container` from the ground line downwards for a clear horizon.
3. **Runner character**
   - Positioned according to calculated pixel coordinates:
     - Horizontal: centered at `playerCenterX`.
     - Vertical: feet aligned to the ground (with optional bottom offset, currently 0).
   - Uses `assets/game_character.png`.
4. **Ghost obstacle**
   - Aligned so the base of the ghost touches the same ground line (with optional offset).
   - Uses `assets/ghost.png`.
5. **HUD (Heads-Up Display)**
   - Left-top: **Score** (`Score: _score`), sized responsively from screen width.
   - Right-top: **Control hints**:
     - On web: `"Tap / Space to jump"` and `"Single space: small | Double: high jump"`.
     - On mobile: `"Tap to jump"` and `"Avoid the ghost and survive"`.
6. **Game Over Overlay**
   - When `_isGameOver` is `true`, a centered `Column` displays:
     - `"Game Over"` title.
     - Final score.
     - `"Tap anywhere to restart"` hint inside a bordered container.

This layered `Stack` approach lets the background, ground, sprites, HUD, and overlays compose cleanly.

---

## 10. Summary

- The game uses a **simple physics model** (gravity + jump velocity) with a **normalized coordinate system**.
- A **timer-driven loop** updates time, score, physics, obstacle position, and collision each frame.
- Difficulty ramps up over time by **increasing obstacle speed** and **growing the player**.
- Input is minimal but expressive:
  - **Tap** / **space** for small jumps.
  - **Quick double space** for a higher jump on web/desktop.
- The result is a compact, easy-to-read example of a **runner game** in pure Flutter using only widgets, timers, and basic math.


