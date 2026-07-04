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

## Android

Every push that touches `bomb-shelter/` runs a GitHub Actions workflow
(`.github/workflows/build-bomb-shelter-android.yml`) that builds a debug APK
on GitHub's runners and attaches it to a release. On your phone, open
**github.com/uchy4/dummy/releases**, download `bomb-shelter.apk` from the
latest *Bomb Shelter Android build*, and allow "install from unknown sources"
when prompted.

On a touchscreen the game switches to single-player automatically, with
on-screen buttons: `<` / `>` to move under your left thumb, `^` to jump under
your right. Tap the win screen for a rematch.

## Controls

| Player | Move | Jump | Kick |
|---|---|---|---|
| P1 (purple) | A / D | W | S |
| P2 (red) | ← / → | ↑ | ↓ |
| P3 (green) | J / L | I | K |
| P4 (yellow) | F / H (or numpad 4/6) | T (or numpad 8) | G (or numpad 5) |

**Kick** launches any bomb next to you at 45° upward in the direction you
face — the fastest way to get a ticking bomb into a tunnel mouth. It also
punts other players (less far). Both kick powers are sliders in Quick
Settings. Touch and web players get a KICK button next to jump.

- **R** — restart with a freshly generated map (any time)
- **Enter** — rematch from the win screen

Player count is the `num_players` export on the `Main` node (default 4).

## 2.5D graphics (KayKit)

The game renders in **2.5D by default**: the exact same 2D simulation runs
underneath (physics, bots, web join — all unchanged), drawn with
[KayKit](https://kaylousberg.com/) assets — BlockBits voxel terrain via
MultiMesh, Adventurers characters (Knight, Barbarian, Mage, Rogue, Ranger,
Rogue Hooded — one per player slot) with team rings, name tags and
procedural run/jump motion, bomb spheres with 3D fuse labels, blast lights,
and a gold block finish line. A Quick Settings checkbox switches back to
the classic flat 2D look (applies on restart). Both asset packs are CC0 —
licenses in `assets/kaykit/`.

## Quick Settings (in-game tuning)

Press **Esc** (or tap the **⚙ settings** button) any time — the game pauses
and a panel opens. Changes apply the moment you resume and persist across
rematches (R / Enter):

- **Bombs per drop** — how many fall in each wave (1–6)
- **Seconds between drops** — the starting drop interval
- **Drop speed-up per second** — how quickly the rain intensifies over the match
- **Blast size** — multiplier on explosion/kill/carve radius (0.5×–2.5×)
- **Bomb types in the mix** — toggle which types spawn:
  - **Normal** — the classic
  - **Big** — heavyweight, ~1.6× blast, longer fuse, hits like a meteor
  - **Cluster** — splits into 3 short-fuse bomblets that fly outward
  - **Bouncy** — barely any friction and a rubber shell; ricochets into places you thought were safe

## Two APKs, and native LAN play

CI publishes **two flavors that install side by side**:
`bomb-shelter-2d.apk` (classic flat renderer, package
`com.uchy4.bombshelter`) and `bomb-shelter-3d.apk` (KayKit 2.5D, package
`com.uchy4.bombshelter3d`). Each is locked to its renderer.

Both boot into a **menu**: **HOST GAME** starts a match on this device
(and broadcasts a UDP discovery beacon on the LAN), while the **Join over
local Wi-Fi** list shows any hosted games it hears — tap one to join as a
full native player, rendered in whichever flavor you're running. The
native client mirrors the host's match via the same WebSocket state
stream the browser client uses, driving puppet entities so both
renderers work unchanged. 2D and 3D flavors can play together freely.

## Web join (play from your phone)

Open **Quick Settings → Show web-join QR**. The game hosts a tiny web server
on the local network; anyone on the **same Wi-Fi** (or the host phone's
hotspot) scans the QR, picks a name and color, and joins live — spawning in
the shelter. Up to 8 players total.

The phone page is a **full lightweight game client** (~10 KB, hand-written
canvas renderer — no engine download): it shows the whole match with a
camera that follows your own character, terrain destruction mirrored via
carve events, bombs with fuse tickers, explosion flashes, death bursts, the
finish line, and a win banner — with the touch controls overlaid. The host
streams compact snapshots at ~15 Hz over the same WebSocket the controls
use; the host stays fully authoritative.

Local players change colors from the pickers in Quick Settings; web players
change theirs from their phone (top-right swatch).

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
