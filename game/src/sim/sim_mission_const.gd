class_name SimMissionConst
extends RefCounted
## Constants of the mission system (SimMissionSystem). Mission design: docs in DefMissionParser (JSON schema) and
## SimMissionSystem (runtime semantics).

const EVAL_PERIOD: int = 5  ## triggers are evaluated when world.tick % EVAL_PERIOD == 0

# objective states (DefMissionObjective.STATE_NAMES order)
const OBJ_HIDDEN: int = 0
const OBJ_ACTIVE: int = 1
const OBJ_COMPLETED: int = 2
const OBJ_FAILED: int = 3

# timer states
const TM_STOPPED: int = 0
const TM_RUNNING: int = 1
const TM_EXPIRED: int = 2

# mission result
const RES_NONE: int = 0
const RES_WIN: int = 1
const RES_LOSE: int = 2

# structure condition states (DefMissionScript.STRUCT_STATES order)
const ST_EXISTS: int = 0
const ST_POWERED: int = 1
const ST_DESTROYED: int = 2
const ST_CAPTURED: int = 3

## A support power locked by a mission has ready_tick = POWER_LOCK_TICK ("never"); UIs show it as locked.
const POWER_LOCK_TICK: int = 0x3FFFFFFF

const SPAWN_SEARCH_RADIUS: int = 12  ## rings searched for a free spawn cell
const STRUCT_SEARCH_RADIUS: int = 6  ## rings searched for a buildable structure origin
