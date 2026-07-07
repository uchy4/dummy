class_name Settings
## Live-tunable gameplay settings, adjusted from the in-game Quick Settings
## panel. Static so values survive scene reloads (rematches keep your tuning).

static var bombs_per_drop := 1    ## bombs per wave at MAX difficulty
static var drop_interval := 3.4   ## starting seconds between drops
static var ramp_time := 120.0     ## seconds until the bombardment reaches max difficulty
static var blast_scale := 1.0     ## multiplier on blast/kill/carve radius

## Which bomb types spawn, indexed by Bomb.Type: NORMAL, BIG, CLUSTER,
## BOUNCY, STICKY, SHOCKWAVE.
static var type_enabled: Array[bool] = [true, true, true, true, true, true]

## 2.5D rendering: the 2D sim runs unchanged, drawn with KayKit 3D assets.
## Applies on restart. Untick for the classic flat look.
static var mode_3d := true

## Camera zoom multiplier — higher zooms in toward the character. Applies
## live to the local camera and streams to web viewers.
static var zoom_scale := 1.0

## Camera framing: false frames the whole group (default), true follows a
## single player (parity with the web view).
static var camera_follow := false

## Hard AI opponents, spawned at match start (change applies on restart).
static var bot_count := 0

## Elimination mode: dying puts you out for the match (no respawns).
## Last player standing wins.
static var one_life := true

## Kick launch speeds (px/s at 45 degrees up), tunable in Quick Settings.
static var kick_bomb_power := 430.0
static var kick_player_power := 280.0

## Ragdoll-stun length (seconds) after surviving a blast or a direct bomb
## hit. 0 disables stun entirely.
static var stun_time := 1.0

## Touch layout: jump/kick buttons sit on the right by default; flip them
## to the left from Quick Settings or the on-screen swap icon.
static var touch_buttons_left := false

## Local players' chosen colors (set from the Quick Settings pickers).
## Filled with the defaults by Main on first run.
static var player_colors: Array[Color] = []

## LAN join handoff from the menu to the client scene.
static var join_ip := ""
static var join_ws_port := 0
static var join_name := "Guest"
