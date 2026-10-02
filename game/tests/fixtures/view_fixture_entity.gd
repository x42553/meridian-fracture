extends RefCounted
## Test double for a ViewEntity (VIEW-W1 owns the real class): exactly the duck-typed fields the unit backends read / write.
## No class_name on purpose.

var id: int = 0
var style_id: StringName = &"napc"
var team_index: int = 0
var rig: Object = null
var slot: int = -1
var roll_m: float = 0.0
var move01: float = 0.0
var turret_yaw: float = 0.0
var elevation: float = 0.0
var recoil: float = 0.0
var deploy: float = 0.0
var spin_angle: float = 0.0
var damage: float = 0.0
var selected: float = 0.0
var flash: float = 0.0
var flags: int = 0
var cloak: float = 0.0
var mnt: PackedFloat32Array = PackedFloat32Array()
var sink_m: float = 0.0
