class_name SimEvent
extends RefCounted
## Event record layout, core event codes, the block map and the reason enums (sim_core 4.9 / 6.2 / 4.1).
## A record is STRIDE (10) int32s: [type, tick, x, y, a, b, c, d, e, f]; x,y are sub-cell units, (0, 0) when the
## event has no place. Events are output-only (DR-12). Each domain owns the layout of its block; the field
## meanings of the core events below are written as "a . b . c . d . e . f".

## Record layout.
const STRIDE: int = 10  # == SimConfig.EVENT_STRIDE
const I_TYPE: int = 0
const I_TICK: int = 1
const I_X: int = 2
const I_Y: int = 3
const I_A: int = 4
const I_B: int = 5
const I_C: int = 6
const I_D: int = 7
const I_E: int = 8
const I_F: int = 9

## emit_throttled() accepts types below this bound.
const THROTTLE_TYPES: int = 512

# ---- block map (first, last inclusive) ----
const BLOCK_CORE_FIRST: int = 1  ## 1-99 core (below)
const BLOCK_CORE_LAST: int = 99
const BLOCK_MOVEMENT_FIRST: int = 100  ## 100-129 movement (EV_MOVE_FAILED 100 ... EV_STUCK 108)
const BLOCK_MOVEMENT_LAST: int = 129
const BLOCK_MISSION_FIRST: int = 130  ## 130-159 scripted missions (MISSION_OBJECTIVE 130 ... MISSION_REVEAL 140; SimMissionSystem)
const BLOCK_MISSION_LAST: int = 159
const BLOCK_COMBAT_FIRST: int = 200  ## 200-229 combat (EV_FIRE 200 ... EV_WEAPON_LOCK 220)
const BLOCK_COMBAT_LAST: int = 229
const BLOCK_ABILITIES_FIRST: int = 230  ## 230-259 abilities (EV_CLOAK_CHANGED 230 ... EV_BUFF_APPLIED 259)
const BLOCK_ABILITIES_LAST: int = 259
const BLOCK_ECONOMY_FIRST: int = 300  ## 300-499 economy / production / power
const BLOCK_ECONOMY_LAST: int = 499
const BLOCK_PRESENTATION_FIRST: int = 500  ## 500-999 presentation-local ids, never emitted by the sim
const BLOCK_PRESENTATION_LAST: int = 999

# ---- core events (emitted by the kernel) ----
const SPAWNED: int = 1  ## id . kind . def_idx . owner . facing . reason (SPAWN_*); always the first event of its entity
const REMOVED: int = 2  ## id . kind . def_idx . owner . reason (REM_*)
const OWNER_CHANGED: int = 3  ## id . old_owner . new_owner . reason (OWNER_CAPTURE / OWNER_SCRIPT)
const CASH: int = 4  ## pid . delta . new_total . reason (CASH_*) . source_id
const CMD_REJECTED: int = 5  ## pid . op . err (SimCommand.Err) . detail . target-or-def; throttled REJECT_GAP ticks per player
const ORDER_FAILED: int = 6  ## unit id . order type . err (o.fail) . detail
const PLAYER_ELIMINATED: int = 7  ## pid . reason (SimPlayer.Elim) . team
const MATCH_END: int = 8  ## winner_team (-1 none) . reason (SimWorld.EndReason) . tick
const NAV_CHANGED: int = 9  ## packed bbox cx0<<24|cy0<<16|cx1<<8|cy1 . map.nav_version . structure id . 1 occupied / 0 vacated

# ---- mission events (block 130-159; emitted only by SimMissionSystem, UI / audio only). Indices are positions in the DefMission lists ----
const MISSION_OBJECTIVE: int = 130  ## objective idx . new state (SimMissionConst.OBJ_*) . kind (DefMissionObjective.Kind) . previous state
const MISSION_MESSAGE: int = 131  ## message idx . announcer idx into DefMission.announcers (-1 none) . 0
const MISSION_TIMER: int = 132  ## timer idx . 0 started / 1 stopped / 2 expired . duration ticks
const MISSION_RESULT: int = 133  ## pid . 1 win / 2 lose . team of pid
const MISSION_CAMERA: int = 134  ## x, y = target (sub-cell units) . area idx (-1) . display ticks
const MISSION_MUSIC: int = 135  ## state (DefMissionAction.MUSIC_NAMES index)
const MISSION_WAVE: int = 136  ## wave idx . 0 spawned / 1 cleared . unit count
const MISSION_TRIGGER: int = 137  ## trigger idx . times fired so far (diagnostic)
const MISSION_POWER: int = 138  ## pid . slot . 1 locked / 0 granted
const MISSION_AI: int = 139  ## pid . active 0 / 1 . level . aggression
const MISSION_REVEAL: int = 140  ## pid . area idx . ticks

# ---- OWNER_CHANGED.d ----
const OWNER_CAPTURE: int = 0
const OWNER_SCRIPT: int = 1

# ---- cash reasons (CASH.d, add_credits / try_spend) ----
const CASH_START: int = 0
const CASH_HARVEST: int = 1
const CASH_SALVAGE: int = 2
const CASH_REFUND: int = 3
const CASH_SELL: int = 4
const CASH_SPEND: int = 5
const CASH_SCRIPT: int = 6

# ---- spawn reasons (SPAWNED.f) ----
const SPAWN_INITIAL: int = 0
const SPAWN_PRODUCED: int = 1
const SPAWN_PLACED: int = 2
const SPAWN_DEPLOYED: int = 3
const SPAWN_SUMMONED: int = 4
const SPAWN_WRECK: int = 5
const SPAWN_SCRIPT: int = 6

# ---- remove reasons (REMOVED.e) ----
const REM_KILLED: int = 0
const REM_SOLD: int = 1
const REM_EXPIRED: int = 2
const REM_DEPLOYED: int = 3
const REM_CONSUMED: int = 4
const REM_SCRIPT: int = 5
