class_name SimImpactPacket
extends RefCounted
## Reusable impact-packet record (economy 4.4). Pooled by the strategic system and never retained by combat; it is
## a scratch record, so it has no hash.

var x: int = 0
var y: int = 0
var radius: int = 0  ## sub-cells, outer radius
var radius_min: int = 0  ## 0 = full disc, > 0 = annulus
var damage: int = 0  ## at the centre, before falloff / armor / resist
var dmg_type: int = 0
var dmg_sub: int = 0
var falloff_edge_bp: int = 0
var struct_mult_bp: int = 10000
var team_mask: int = 0
var layer_mask: int = 0
var pre_resist_bp: int = 0
var flags: int = 0  ## PKT_*
var src_x: int = -1
var src_y: int = -1
var src_pid: int = -1
var src_kind: int = 0
var src_idx: int = -1
var attack_id: int = 0
