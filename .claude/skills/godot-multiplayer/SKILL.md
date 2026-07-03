---
name: godot-multiplayer
description: Godot 4.x multiplayer/networking — high-level MultiplayerAPI, ENet/WebSocket/WebRTC peers, @rpc annotations, MultiplayerSpawner and MultiplayerSynchronizer, server-authoritative patterns, and lobby/connection flow. Use when adding online or LAN multiplayer, co-op, or fixing RPC/replication issues in a Godot game.
---

# Godot Multiplayer (4.x high-level API)

## Architecture decision first

- **Server-authoritative** (server simulates, clients send input, server replicates state): default for anything competitive or cheat-sensitive. One player can host (listen server) or run dedicated (`--headless`).
- **Peer-trusting / client-authority** (each client owns its player object): fine for co-op with friends, jam games. Massively simpler; use `MultiplayerSynchronizer` with per-object authority.
- Deterministic lockstep / rollback: not what the high-level API does — reach for addons or custom netcode (out of scope here).

Transports: **ENetMultiplayerPeer** (UDP — desktop/mobile default), **WebSocketMultiplayerPeer** (web exports; TCP so expect latency spikes), **WebRTCMultiplayerPeer** (web P2P, needs a signaling server). Steam/Epic transports via third-party GDExtensions (GodotSteam etc.).

## Connection bootstrap

```gdscript
const PORT := 7777

func host() -> void:
    var peer := ENetMultiplayerPeer.new()
    var err := peer.create_server(PORT, 8)     # max 8 clients
    if err != OK: push_error("host failed: %s" % err); return
    multiplayer.multiplayer_peer = peer
    multiplayer.peer_connected.connect(_on_peer_connected)
    multiplayer.peer_disconnected.connect(_on_peer_disconnected)
    _spawn_player(1)                            # server is always peer 1

func join(ip: String) -> void:
    var peer := ENetMultiplayerPeer.new()
    peer.create_client(ip, PORT)
    multiplayer.multiplayer_peer = peer
    multiplayer.connected_to_server.connect(_on_connected)
    multiplayer.connection_failed.connect(_on_failed)
    multiplayer.server_disconnected.connect(_on_server_gone)
```

- `multiplayer.get_unique_id()` — my peer id; `multiplayer.is_server()`; `multiplayer.get_remote_sender_id()` inside an RPC.
- Disconnect/cleanup: `multiplayer.multiplayer_peer = null` (or `OfflineMultiplayerPeer.new()`); free per-peer nodes on `peer_disconnected`.
- The API works offline too — single-player runs the same code with everything local-authority (id 1), so you don't need two code paths.

## RPCs

```gdscript
# mode: "authority" (default — only the node's authority may call it on others)
#       | "any_peer" (any client may call — VALIDATE SENDER)
# sync: "call_remote" (default) | "call_local" (also runs on the caller)
# transfer: "reliable" | "unreliable" | "unreliable_ordered", plus channel int

@rpc("any_peer", "call_local", "reliable")
func request_fire(dir: Vector2) -> void:
    if not multiplayer.is_server(): return              # server executes
    var sender := multiplayer.get_remote_sender_id()
    if sender != get_multiplayer_authority(): return    # only your own pawn
    if not _can_fire(): return                          # server-side validation
    _do_fire.rpc(dir)                                   # broadcast result

@rpc("authority", "call_local", "unreliable_ordered")
func _do_fire(dir: Vector2) -> void:
    _spawn_muzzle_flash(dir)
```

Calling: `fn.rpc(args...)` = everyone (per mode); `fn.rpc_id(peer_id, args...)` = one peer (`rpc_id(1, ...)` = to server).

Hard rules:
- **Node path + name must match on every peer** for RPCs to route — same scene structure, same node names. Most "rpc not received" bugs are name/path mismatch (or the node not yet existing on the receiver — sequence your spawns).
- Only Variant-serializable args; no Objects by default (`allow_object_decoding` exists — leave it OFF; it's an attack surface).
- `"any_peer"` handlers are your public API surface: check `get_remote_sender_id()`, validate ranges/cooldowns/ownership. Never trust client-sent positions or damage numbers in authoritative designs.
- Channels: put chat / bulky state on separate channels so they don't head-of-line-block input (reliable channels order within themselves).
- Movement/state ticks: `unreliable` (or `unreliable_ordered`), sent from `_physics_process`, full-state snapshots so drops don't matter. Events (death, pickup): `reliable`.

## Replication nodes

**MultiplayerSpawner** — replicates node *creation/deletion* from authority to clients:
- Set `spawn_path` (parent whose children get replicated) and add spawnable scene(s).
- Server: `spawner_parent.add_child(scene.instantiate())` → clients auto-instance it.
- Custom data at spawn: set `spawn_function` (server calls `spawner.spawn(data)`; function runs on ALL peers and must return the node).

**MultiplayerSynchronizer** — replicates *property values* on a schedule:
- Child of the replicated node; edit its ReplicationConfig: choose properties, per-property mode (on-spawn only / always / on-change "watch").
- `public_visibility` / `set_visibility_for()` for interest management (don't sync what a peer can't see).
- Sync transform of physics bodies: sync `position` (+ maybe `velocity` for extrapolation), and on clients make the body non-simulating (client-side the pawn is a puppet: disable its `_physics_process` input branch when `not is_multiplayer_authority()`).

**Authority**: `set_multiplayer_authority(peer_id)` (default authority = server 1; propagates to children unless overridden — synchronizers use it to decide who sends).

Per-player pawn pattern:
```gdscript
func _spawn_player(id: int) -> void:            # server only
    var p := PLAYER_SCENE.instantiate()
    p.name = str(id)                            # deterministic name = stable paths
    players_node.add_child(p, true)             # true = force readable name

# player.gd
func _enter_tree() -> void:
    set_multiplayer_authority(name.to_int())    # runs on all peers before ready
func _physics_process(delta: float) -> void:
    if not is_multiplayer_authority(): return   # puppets are driven by the synchronizer
    ...input + movement...
```

## Smoothness: interpolation & prediction

Raw synced positions at 10–30Hz look teleporty. Ladder of effort:
1. **Remote interpolation** (do this always): puppet lerps toward the last received position — `global_position = global_position.lerp(target, 12.0 * delta)`, snap if error > threshold. Or buffer two snapshots and interpolate between them at render time (smoother, adds ~1 tick latency).
2. **Client-side prediction for your own pawn** (authoritative servers): apply input locally immediately, send inputs with a sequence number, reconcile when server state arrives (replay unacknowledged inputs). Only build this if input latency actually hurts the feel.
3. Lag compensation (server rewinds for hit registration) — competitive shooters only.

Co-op reality check: client-authority pawns + synchronizers + interpolation ships most co-op games without any of layer 2–3.

## Lobby / flow skeleton

1. Menu scene: host/join UI → set up peer (code above).
2. Registration: on `connected_to_server`, client sends `register.rpc_id(1, player_name)`; server builds a `players: Dictionary[int, Dictionary]` and broadcasts the roster (reliable).
3. Start: server loads the game scene (`change_scene` on all via an RPC or a spawner watching the root), then spawns pawns for every id in the roster.
4. Join-in-progress: MultiplayerSpawner replays existing spawns to late joiners automatically; synchronizers with on-spawn properties fill state. Anything outside spawner/synchronizer must be re-sent manually to the new peer (`rpc_id(new_peer, full_state)`).
5. Disconnects: server frees the pawn (spawner despawns it everywhere) and rebroadcasts the roster; handle `server_disconnected` on clients (back to menu with an error toast).

## Testing & debugging

- Editor: Debug > "Run Multiple Instances" (set 2–4) — one hosts, others join localhost. Add `--` args or use `OS.get_cmdline_user_args()` to auto-host/join per instance.
- Simulate badness early: clumsy/netem, or at minimum test WebSocket builds over real internet — LAN-perfect code often breaks at 100ms+.
- Log every RPC entry point with sender id while developing; most desyncs are "ran on the wrong peer" — assert `is_server()` in server-only paths.
- Profiler has a Network tab (bandwidth per node/synchronizer); watch synchronizer rates — default replication interval every frame is often overkill; set `replication_interval`/`delta_interval` on synchronizers.
- Web export: WebSocket (or WebRTC) only — ENet doesn't run in browsers. TLS (`wss://`) required on HTTPS pages; terminate TLS at a reverse proxy in production.

## Pitfalls

1. RPC silently dropped: node missing/renamed on receiver, differing scene tree, or calling before the peer finished connecting. Await your own registration handshake before gameplay RPCs.
2. Trusting `any_peer` input — validate everything server-side.
3. Spawning on clients directly (clients should never `add_child` replicated gameplay objects — ask the server via RPC).
4. Random names (`@` auto-names) break paths — `add_child(node, true)` and deterministic names for anything RPC'd.
5. Forgetting `call_local` and wondering why the host doesn't see their own effect.
6. Syncing physics-simulated bodies from both sides — pick one authority; puppets must not simulate.
7. Sending big dictionaries reliably every tick — snapshot deltas, unreliable channel, or synchronizer watch-mode.
8. Using `multiplayer` before setting `multiplayer_peer`, or in `_ready` racing the connection — sequence with signals.
9. Storing per-match state in autoloads that survive returning to lobby — reset on disconnect.
10. NAT: raw ENet needs port forwarding for internet play; plan for a relay (or Steam/Epic transport) if targeting the public.
