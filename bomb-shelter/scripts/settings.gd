class_name Settings
## Live-tunable gameplay settings, adjusted from the in-game Quick Settings
## panel. Static so values survive scene reloads (rematches keep your tuning).

static var bombs_per_drop := 1
static var drop_interval := 3.4   ## starting seconds between drops
static var drop_rampup := 0.022   ## seconds shaved off the interval per second of match time
static var blast_scale := 1.0     ## multiplier on blast/kill/carve radius

## Which bomb types spawn, indexed by Bomb.Type: NORMAL, BIG, CLUSTER, BOUNCY.
static var type_enabled: Array[bool] = [true, true, true, true]
