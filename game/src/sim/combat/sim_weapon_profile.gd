class_name SimWeaponProfile
extends RefCounted
## Per-mount weapon profile (private to combat; stored in SimCombatDef.prof, stride PN). The data module has no
## accuracy / burst / guidance numbers, so they are derived here from the DefWeaponSlot + DefWeaponArch of the mount
## (combat 4.2 DefWeapon/DefProjectile/DefMount columns that the data layer does not carry get archetype defaults).

const PN: int = 24
const PF_KIND: int = 0  ## SimCombatConsts.PK_*
const PF_FLAGS: int = 1  ## SimCombatConsts.PF_*
const PF_BURST: int = 2  ## shots per salvo (>= 1)
const PF_BURST_INT: int = 3  ## ticks between shots of a salvo
const PF_AIM_DELAY: int = 4  ## ticks the mount must stay aimed before the first shot of a salvo
const PF_ACC: int = 5  ## hitscan accuracy bp at zero range
const PF_ACC_FALL: int = 6  ## bp lost across the full range
const PF_ACC_MOVE: int = 7  ## bp lost against a target moving at ACC_V_REF u/tick
const PF_ACC_SHOOTER: int = 8  ## bp lost while the shooter moves
const PF_HIT_R: int = 9  ## projectile hit radius (added to the target radius)
const PF_LIFE: int = 10  ## missile life floor (ticks)
const PF_LEAD_BP: int = 11
const PF_SPREAD: int = 12  ## bullet spread half-width (bat)
const PF_SC_MIN: int = 13  ## arc / bomb scatter radius at zero range
const PF_SC_MAX: int = 14  ## ... at full range
const PF_MIN_FLIGHT: int = 15
const PF_MAX_FLIGHT: int = 16
const PF_TURN: int = 17  ## missile turn rate (bat/tick)
const PF_HOMING_DELAY: int = 18
const PF_LAUNCH_DELAY: int = 19
const PF_AMMO_PER_SALVO: int = 20
const PF_SETTLE: int = 21  ## still ticks before a stationary-fire weapon may shoot
const PF_TF: int = 22  ## TF_* target mask (layers + structure)
const PF_BEAM_MAX: int = 23  ## beam overheat ticks (0 = never)

## Bomb fall time (ticks) and beam damage-over-time interval defaults.
const FALL_TICKS: int = 16
const AUTO_MIN_BP: int = 1500


## Profile row of one weapon slot.
static func derive(s: DefWeaponSlot, a: DefWeaponArch) -> PackedInt32Array:
	var p: PackedInt32Array = PackedInt32Array()
	p.resize(PN)
	var indirect: bool = s.fire_mode == DefEnums.FireMode.INDIRECT
	var kind: int = SimCombatConsts.PK_HITSCAN
	match s.proj_kind:
		DefEnums.ProjKind.BEAM:
			kind = SimCombatConsts.PK_BEAM
		DefEnums.ProjKind.BOMB:
			kind = SimCombatConsts.PK_BOMB
		DefEnums.ProjKind.MISSILE:
			kind = SimCombatConsts.PK_ARC if indirect else SimCombatConsts.PK_MISSILE
		DefEnums.ProjKind.ROCKET, DefEnums.ProjKind.GRENADE:
			kind = SimCombatConsts.PK_ARC
		DefEnums.ProjKind.SHELL:
			kind = SimCombatConsts.PK_ARC if indirect else SimCombatConsts.PK_BULLET
		DefEnums.ProjKind.TORPEDO:
			kind = SimCombatConsts.PK_BULLET
		_:
			kind = SimCombatConsts.PK_HITSCAN
	if kind != SimCombatConsts.PK_HITSCAN and kind != SimCombatConsts.PK_BEAM and s.proj_speed <= 0:
		kind = SimCombatConsts.PK_HITSCAN
	var pf: int = 0
	if kind == SimCombatConsts.PK_MISSILE and s.homing:
		pf |= SimCombatConsts.PF_GUIDED
	if kind == SimCombatConsts.PK_ARC or kind == SimCombatConsts.PK_MISSILE:
		if s.interceptable == DefEnums.Interceptable.APS_TRIDENT:
			pf |= SimCombatConsts.PF_APS_INTERCEPTABLE | SimCombatConsts.PF_ZONE_INTERCEPTABLE
		elif s.interceptable == DefEnums.Interceptable.TRIDENT:
			pf |= SimCombatConsts.PF_ZONE_INTERCEPTABLE
	if (s.target_mask & 15) == DefEnums.L_AIR:
		pf |= SimCombatConsts.PF_AIRBURST_ON_EXPIRE
	p[PF_KIND] = kind
	p[PF_FLAGS] = pf
	var burst: int = 1
	if kind != SimCombatConsts.PK_BEAM:
		burst = maxi(1, s.hits_per_volley)
	p[PF_BURST] = burst
	var bi: int = 3 if (kind == SimCombatConsts.PK_HITSCAN or kind == SimCombatConsts.PK_BULLET) else 4
	p[PF_BURST_INT] = clampi((s.reload_ticks - 1) / maxi(burst, 1), 1, bi)
	p[PF_AIM_DELAY] = 0
	var homing: bool = s.homing or (a != null and a.homing)
	if homing:
		p[PF_ACC] = 10000
	else:
		p[PF_ACC] = 8000
		p[PF_ACC_FALL] = 3000
		p[PF_ACC_MOVE] = 1500
		p[PF_ACC_SHOOTER] = 1000
	p[PF_HIT_R] = 96 if kind == SimCombatConsts.PK_MISSILE else 64
	if kind == SimCombatConsts.PK_MISSILE:
		p[PF_LIFE] = (s.range * 2 + maxi(s.proj_speed, 1) - 1) / maxi(s.proj_speed, 1) + 20
	if kind == SimCombatConsts.PK_ARC or kind == SimCombatConsts.PK_BOMB:
		p[PF_LEAD_BP] = 10000 if s.proj_kind == DefEnums.ProjKind.MISSILE else 0
	else:
		p[PF_LEAD_BP] = 10000 if homing else 0
	if kind == SimCombatConsts.PK_BULLET and not homing and s.scatter > 0:
		p[PF_SPREAD] = s.scatter * 652 / maxi(s.range, 1)
	p[PF_SC_MAX] = s.scatter
	p[PF_SC_MIN] = s.scatter / 8
	p[PF_MIN_FLIGHT] = 4
	p[PF_MAX_FLIGHT] = 400
	p[PF_TURN] = 160
	p[PF_AMMO_PER_SALVO] = 1
	p[PF_SETTLE] = 6 if (s.flags & DefEnums.WF_STATIONARY_FIRE) != 0 else 0
	var tf: int = s.target_mask & 15
	if (s.target_mask & (DefEnums.L_GROUND | DefEnums.L_WATER)) != 0:
		tf |= SimCombatConsts.TF_STRUCTURE
	p[PF_TF] = tf
	return p


## true when the weapon must be standing still to fire (WF_STATIONARY_FIRE).
static func stationary(s: DefWeaponSlot) -> bool:
	return (s.flags & DefEnums.WF_STATIONARY_FIRE) != 0
