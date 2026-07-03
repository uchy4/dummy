# Bomb Shelter

A 2D party game for **2–4 players on one keyboard**, built with **Godot 4.4+**.

You all start on a flat strip of grass about 100 feet wide. After a short grace
period, bombs start falling from the sky — each with a visible fuse ticker.
When one goes off it blasts a chunk out of the ground, kicks anything nearby,
and **sets off the fuse of any bomb caught in the blast** (short random fuse,
so chains ripple instead of detonating all at once).

Below the surface is a starting **shelter** and around ten caverns and tunnel
systems — but **every route down is a dead end**: each tunnel stops a few feet
short of the next cavern. The only way through is a bomb. Push a ticking bomb
into a tunnel mouth, let it roll down to the plug, and run.

**First player to touch the gold FINISH line at the bottom of the map wins.**

## Running it

1. Install [Godot 4.4 or newer](https://godotengine.org/download) (standard build, not .NET — it's all GDScript).
2. Open Godot → **Import** → select this folder's `project.godot`.
3. Press **F5** (or the Play button).

There are no art/audio assets to download — the terrain tiles, characters,
bombs, and UI are all generated in code, so the project runs straight from a
fresh clone.

## Controls

| Player | Move | Jump |
|---|---|---|
| P1 (blue) | A / D | W |
| P2 (red) | ← / → | ↑ |
| P3 (green) | J / L | I |
| P4 (yellow) | F / H (or numpad 4/6) | T (or numpad 8) |

- **R** — restart with a freshly generated map (any time)
- **Enter** — rematch from the win screen

Player count is the `num_players` export on the `Main` node (default 4).

## How to play (the logic to test)

- **Dirt blocks blasts.** An explosion raycasts to each player/bomb; if solid
  ground is in the way you take almost nothing. That's why the shelter (and
  any tunnel) protects you — depth is safety, the surface is death.
- **Walk into a bomb to push it.** Shove ticking bombs into shafts and tunnel
  mouths so they roll down to the dead-end plug and blow it open.
- **Chain reactions dig.** Bombs stack in craters; one blast propels and
  ignites the others, so clusters excavate deep, ragged holes — sometimes
  opening routes for you (or your opponents).
- **Dying costs time.** A lethal blast kills you; you respawn in the shelter
  3 s later with brief invulnerability. Deaths are tallied but only reaching
  the finish line matters.
- Bomb drops speed up over time, so the surface becomes uninhabitable and the
  race gets faster the longer a match runs.

## Map generation (new every match)

- Flat grass surface (~100 cells wide, 16 px per cell), bedrock frame that
  can't be destroyed.
- Shelter room under the middle of the map with an open entrance shaft.
- 4 depth bands × 2–3 elliptical caverns each (~10 rooms), each connected to
  the nearest room above by a winding tunnel that **stops 4 cells short**
  (the dead-end plug), plus a few decoy tunnels and two open surface shafts.
- A finish hall spanning the bottom with the checkered gold line just above
  the bedrock floor. Tunnels into the hall are plugged too.

## Tuning knobs

| What | Where |
|---|---|
| Map size / tile size / plug thickness | `scripts/terrain.gd` constants |
| Fuse length, blast/kill/carve radius, chain fuse | `scripts/bomb.gd` constants |
| Drop rate ramp, aim-at-player chance, grace period | `scripts/bomb_spawner.gd` |
| Movement feel (speed, jump, push force), respawn time | `scripts/player.gd` |
| Camera zoom range / margin / shake | `scripts/game_camera.gd` |

## Roadmap

- **2.5D version**: same logic re-rendered in 3D (extruded terrain, orthogonal
  camera) once the 2D rules feel right — the terrain grid, fuse/chain, and
  dead-end generation port straight across.
- Gamepad support (the input map is built in code in `main.gd`; adding
  joypad events per player is a small change).
- Sound effects (ticking, thud, boom) and music.
- Incoming-bomb warning markers at the top of the screen.
