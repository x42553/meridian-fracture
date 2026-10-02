class_name SimConfig
extends RefCounted
## Single home of the simulation's physical / engine constants (ARCHITECTURE section 3, sim_core 3.2.1).
## No number in this file may be duplicated elsewhere. `core/` files do not reference each other, so CELL and
## CELL_SHIFT are literals that tests assert equal to `Fp.CELL` / `Fp.CELL_SHIFT`.

## Bump on ANY change that alters simulation results; mixed into every checksum.
const SIM_VERSION: int = 1

## Ticks per second, milliseconds per tick, ticks per network turn.
const TPS: int = 20
const TICK_MS: int = 50
const TURN_TICKS: int = 2

## Ticks between checkpoints (checksum snapshots) and how many checkpoints keep their part digests.
const CHECKSUM_PERIOD: int = 20
const SNAPSHOT_KEEP: int = 64

## Sub-cell units per terrain cell (== Fp.CELL) and its shift.
const CELL: int = 1024
const CELL_SHIFT: int = 10

## Players: pids 0..7, NEUTRAL owner -1 (slot 8, see slot_of()).
const MAX_PLAYERS: int = 8
const NEUTRAL: int = -1
const NEUTRAL_SLOT: int = 8

const MIN_MAP_CELLS: int = 96
const MAX_MAP_CELLS: int = 256

const DEFAULT_UNIT_CAP: int = 150
const DEFAULT_START_CREDITS: int = 7500

## Live-entity hard cap and order-queue length.
const MAX_ENTITIES: int = 8192
const MAX_ORDERS: int = 32

## Command envelope: ints per command (net XR-2) and entity ids per command.
const MAX_CMD_INTS: int = 1024
const MAX_CMD_IDS: int = 512

## "Long ago" sentinel for domain timestamps (absolute ticks).
const NEVER: int = -1000000

## Event record width (ints) and the drop threshold of the event buffer (131 072 events).
const EVENT_STRIDE: int = 10
const EVENT_SOFT_CAP_INTS: int = 1310720

## Spatial-hash bucket shift: 4096 units = 4 cells per bucket.
const SPATIAL_SHIFT: int = 12

## Defeat cascade rate (entities killed per tick per eliminated player) and CMD_REJECTED throttle gap.
const DEFEAT_KILLS_PER_TICK: int = 6
const REJECT_GAP: int = 10


## Maps an owner (pid 0..7 or -1 neutral) to its dense slot 0..8 (neutral -> 8).
static func slot_of(owner: int) -> int:
	return NEUTRAL_SLOT if owner < 0 else owner
