class_name SimFlags
extends RefCounted
## Bit allocation of `SimEntity.flags` (a 64-bit int), shared by ALL domains (sim_core 4.3). A bit is WRITTEN
## only by its owner (column "writer" in the spec), READ by anyone. Bits 41-47 are free (an amendment is
## required to use them), 48-63 are reserved. The entity hash stores `flags & 0xFFFFFFFF` and `flags >> 32`.

const F_DEAD: int = 1 << 0  ## hp reached 0; awaiting cleanup (or lingering). Systems skip such entities. Writer: core (kill)
const F_REMOVING: int = 1 << 1  ## removal queued. Writer: core
const F_INSIDE: int = 1 << 2  ## inside a container: not on the map / in the spatial hash. Writer: set_inside
const F_TEMPORARY: int = 1 << 3  ## has a lifetime (expire_tick); never counts toward struct / rebuilder counters. Writer: spawner
const F_SUMMONED: int = 1 << 4  ## created by a power / ability: no salvage, no refund. Writer: spawner
const F_NO_UNIT_CAP: int = 1 << 5  ## excluded from the unit cap. Writer: core (spawn only)
const F_DECOY: int = 1 << 6  ## harmless decoy; no wreck income; never an asset. Writer: ability / economy
const F_NO_COLLISION: int = 1 << 7  ## never blocks movement (data UF_NON_BLOCKING). Writer: movement / ability
const F_INVULNERABLE: int = 1 << 8  ## takes no damage. Writer: data / ability
const F_UNTARGETABLE: int = 1 << 9  ## never auto-acquired. Writer: data
const F_NO_SELECT: int = 1 << 10  ## not selectable by players. Writer: data
const F_TETHERED: int = 1 << 11  ## dies (Cause.ORPHAN) when `parent` is removed. Writer: spawner
const F_HAS_CHILDREN: int = 1 << 12  ## some entity names this one as `parent`. Writer: core
const F_NO_SALVAGE: int = 1 << 13  ## wreck is not salvageable. Writer: core / data
const F_INITIAL: int = 1 << 14  ## placed by the map / start state. Writer: core
const F_EXPIRE_KILLS: int = 1 << 15  ## on expiry die (Cause.EXPIRE, with on_dying) instead of silent removal. Writer: spawner
const F_MOVING: int = 1 << 16  ## movement state mirrors (16-19). Writer: movement
const F_AIRBORNE: int = 1 << 17
const F_BLOCKED: int = 1 << 18
const F_ON_WATER: int = 1 << 19
const F_FIRING: int = 1 << 20  ## fired this tick. Writer: combat (20-22; 23 reserved)
const F_ENGAGED: int = 1 << 21  ## in the combat window
const F_WEAPONS_OFF: int = 1 << 22  ## weapons unavailable
const F_DEPLOYED: int = 1 << 24  ## deployed / transitioning / camouflaged / active ability. Writer: ability (24-27)
const F_DEPLOYING: int = 1 << 25
const F_CLOAKED: int = 1 << 26
const F_ABILITY_ACTIVE: int = 1 << 27
const F_POWERED: int = 1 << 28  ## structure has power. Writer: power
const F_REPAIR_ON: int = 1 << 29  ## auto-repair on. Writer: economy
const F_SELLING: int = 1 << 30  ## being sold. Writer: production (31 reserved)
const F_NO_CAPTURE: int = 1 << 32  ## capture-immune (UF_NO_CAPTURE). Writer: data / spawner
const F_NO_REPAIR: int = 1 << 33  ## cannot be repaired (UF_NO_REPAIR). Writer: data / spawner
const F_NO_VISION_GRANT: int = 1 << 34  ## never reveals fog for its owner. Writer: spawner
const F_NO_FOOTPRINT: int = 1 << 35  ## structure-like entity that does not occupy a map footprint; set AT SPAWN. Writer: spawner
const F_SCRIPTED_MOVE: int = 1 << 36  ## SimMovementSystem skips it. Writer: spawner
const F_EMP_SHUT: int = 1 << 37  ## state mirrors for view / AI / audio. Writer: combat
const F_SUPPRESSED: int = 1 << 38  ## Writer: combat
const F_GARRISONED: int = 1 << 39  ## Writer: cargo
const F_UNDER_CONSTRUCTION: int = 1 << 40  ## Writer: economy

## Either bit set = the entity is leaving the world (tag ALIVE cleared; systems skip it).
const F_GONE: int = F_DEAD | F_REMOVING
