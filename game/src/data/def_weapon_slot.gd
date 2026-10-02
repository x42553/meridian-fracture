class_name DefWeaponSlot
extends RefCounted
## A weapon instance on a unit / structure: the resolved numbers combat reads (data_balance 4.2). Deep-copied into
## every roster clone (a resolved slot never aliases the base slot). Locked archetype attributes (dtype, fire_mode,
## proj_kind, interceptable, homing) are copied here for one-lookup access.

var arch: int = 0  ## DefEnums.WeaponArch
var slot: int = 0
var mount: int = 0  ## 0 hull, 1 turret
var mode_mask: int = 0  ## bit m = active in mode m; 0 = always
var damage: int = 0  ## per hit
var hits_per_volley: int = 1
var dtype: int = 0
var fire_mode: int = 0
var interceptable: int = 0
var proj_kind: int = 0
@warning_ignore("shadowed_global_identifier")
var range: int = 0  ## u (max)
var min_range: int = 0
var reload_mt: int = 0  ## milli-ticks
var reload_ticks: int = 1  ## ceil_div(reload_mt, 1000), >= 1
var proj_speed: int = 0  ## upt, 0 = hitscan
var homing: bool = false
var splash_radius: int = 0
var splash_edge_bp: int = 0
var scatter: int = 0
var target_mask: int = 0  ## DefEnums layer mask
var flags: int = 0  ## DefEnums.WF_*
var ammo_volleys: int = 0  ## 0 = unlimited
var turret_turn: int = 0  ## apt, 0 = fixed
var fire_arc: int = 4096  ## angle units (full width)
var ramp_t: int = 0
var ramp_max_bp: int = 10000
var deploy_t: int = 0
var requires_surface_t: int = 0
var cond_vals: Array[DefCondVal] = []
var ui_label: String = ""  ## weapon-instance label "weapon.<code>.<name>" (label only, not hashed)


func copy_resolved() -> DefWeaponSlot:
	return DefBase.deep_copy(self) as DefWeaponSlot
