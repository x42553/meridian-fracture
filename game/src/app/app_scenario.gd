class_name AppScenario
extends RefCounted
## Deterministic debug scenario of the GUI test boot (`--scenario=showcase`, task VQ2B): LOCAL runs only (it edits the sim outside the
## command stream, like AppStress, so it is never networked). It exists so full-match screenshots of late-game moments can be taken in
## seconds instead of half an hour: rich credits, an instantly built tech base (generators, Radar, Laboratory and the roster's superweapon
## launcher, tech-ups instantly), the superweapon charged and launched at a fixed tick, and optional staged battles.
##
##   --scenario=showcase            enable (all flags below are optional)
##   --credits=N                    credits of every player (default 60000)
##   --sw-at=T                      tick of the superweapon launch (default 60; 0 = no launch)
##   --sw-pids=0,1 | all            who launches (default 0), each at the nearest enemy start
##   --sw-target=cx,cy              target cell override of the launch(es)
##   --sw-angle=A                   binary angle 0..4095 of line weapons (default 0)
##   --army=N                       N extra ground units per player next to their bases at tick 5 (AppStress)
##   --battle=ground|air|naval      staged fight of player 0 against the first enemy between the two bases
##   --battle-n=N                   units per side (default 60)
##   --battle-at=T                  tick at which the battle is spawned (default 10)
## Printed lines: `APPSCEN ...` (greppable).

var kind: String = ""
var credits: int = 60000
var sw_at: int = 60
var sw_pids: PackedInt32Array = PackedInt32Array([0])
var sw_all: bool = false
var sw_target: Vector2i = Vector2i(-1, -1)
var sw_angle: int = 0
var army: int = 0
var battle: String = ""
var battle_n: int = 60
var battle_at: int = 10

var _setup_done: bool = false
var _army_done: bool = false
var _battle_done: bool = false
var _launched: PackedInt32Array = PackedInt32Array()
var _forced: PackedInt32Array = PackedInt32Array()


static func from_args(args: AppLaunchArgs) -> AppScenario:
	var scn: String = str(args.extras.get("scenario", ""))
	if scn == "":
		return null
	var s: AppScenario = AppScenario.new()
	s.kind = scn
	s.credits = int(str(args.extras.get("credits", "60000")))
	s.sw_at = int(str(args.extras.get("sw-at", "60")))
	var pids: String = str(args.extras.get("sw-pids", "0"))
	if pids == "all":
		s.sw_all = true
	else:
		s.sw_pids = PackedInt32Array()
		for p: String in pids.split(",", false):
			s.sw_pids.append(p.to_int())
	var tgt: PackedStringArray = str(args.extras.get("sw-target", "")).split(",", false)
	if tgt.size() == 2:
		s.sw_target = Vector2i(tgt[0].to_int(), tgt[1].to_int())
	s.sw_angle = int(str(args.extras.get("sw-angle", "0")))
	s.army = int(str(args.extras.get("army", "0")))
	s.battle = str(args.extras.get("battle", ""))
	s.battle_n = int(str(args.extras.get("battle-n", "60")))
	s.battle_at = int(str(args.extras.get("battle-at", "10")))
	return s


## Once per rendered frame while the match is PLAYING (cheap: every branch is a one-shot or a tick compare).
func step(w: SimWorld) -> void:
	if w == null:
		return
	if not _setup_done and w.tick >= 2:
		_setup_done = true
		_setup(w)
	if army > 0 and not _army_done and w.tick >= 5:
		_army_done = true
		AppStress.spawn(w, army)
		_say("APPSCEN army=%d" % army)
	if battle != "" and not _battle_done and w.tick >= battle_at:
		_battle_done = true
		_spawn_battle(w)
	if _setup_done:
		_charge_and_launch(w)


# ---- tech base -----------------------------------------------------------------------------------------------------------

func _setup(w: SimWorld) -> void:
	for pid: int in w.players.size():
		var p: SimPlayer = w.players[pid]
		if p == null or p.roster == null or p.eliminated != 0:
			continue
		p.credits = maxi(p.credits, credits)
		var home: Vector2i = _home_cell(w, pid)
		if home.x < 0:
			continue
		for i: int in 6:
			_place(w, pid, "structure.shared.generator", home.x + 5 + 3 * (i % 3), home.y + 5 + 3 * (i / 3))
		_place(w, pid, "structure.shared.radar", home.x - 8, home.y + 6)
		_place(w, pid, "structure.shared.laboratory", home.x - 8, home.y - 6)
		var slot: SimPowerSlot = p.econ.slots[SimEconConst.SLOT_SW]
		if slot.def_idx >= 0:
			var sw: DefSuperweapon = w.data.superweapons[slot.def_idx]
			if sw.launcher >= 0:
				_place(w, pid, w.data.structures[sw.launcher].id, home.x + 10, home.y - 8)
		_say("APPSCEN setup pid=%d roster=%s credits=%d sw=%s" % [pid, p.roster.id, p.credits,
			w.data.superweapons[slot.def_idx].id if slot.def_idx >= 0 else "none"])


static func _say(line: String) -> void:
	# lint-allow: L006 greppable test-boot protocol line (APPSCEN ...)
	print(line)


func _home_cell(w: SimWorld, pid: int) -> Vector2i:
	var best: SimEntity = null
	for e: SimEntity in w.structures_of(pid):
		if best == null or e.id < best.id:
			best = e
	if best != null:
		return Vector2i(best.x >> SimConfig.CELL_SHIFT, best.y >> SimConfig.CELL_SHIFT)
	return Vector2i(-1, -1)


## Spawns structure `id` of `pid` on the first valid site around the cell; the placement rules apply (radius ignored by the ring search
## because the HQ is near), so an unlucky terrain only loses that structure.
func _place(w: SimWorld, pid: int, id: String, cx: int, cy: int) -> SimEntity:
	var idx: int = w.data.structure_idx(id)
	if idx < 0:
		return null
	var cell: PackedInt32Array = PackedInt32Array()
	if not SimPlacement.find_site(w, pid, idx, cx, cy, 14, cell):
		_say("APPSCEN no site for %s of pid %d" % [id, pid])
		return null
	return w.spawn_structure(idx, pid, SimPlacement.footprint_center_x(w, idx, cell[0], 0), SimPlacement.footprint_center_y(w, idx, cell[1], 0), 0, 0,
		w.data.structures[idx].cost)


# ---- superweapon -----------------------------------------------------------------------------------------------------------

func _charge_and_launch(w: SimWorld) -> void:
	for pid: int in w.players.size():
		var p: SimPlayer = w.players[pid]
		if p == null or p.roster == null or p.eliminated != 0:
			continue
		var s: SimPowerSlot = p.econ.slots[SimEconConst.SLOT_SW]
		if s.def_idx < 0 or not (sw_all or sw_pids.has(pid)):
			continue
		if s.sw_state == SimEconConst.SW_CHARGING and not _forced.has(pid):
			_forced.append(pid)  # fast-forward: the 9600-tick charge is skipped, every other rule is unchanged
			s.charge = s.recharge_ticks
			s.sw_state = SimEconConst.SW_READY
		if sw_at > 0 and w.tick >= sw_at and s.sw_state == SimEconConst.SW_READY and not _launched.has(pid):
			var t: Vector2i = sw_target if sw_target.x >= 0 else _enemy_cell(w, pid)
			if t.x < 0:
				continue
			_launched.append(pid)
			var cx: int = t.x * SimConfig.CELL + SimConfig.CELL / 2
			var cy: int = t.y * SimConfig.CELL + SimConfig.CELL / 2
			w.submit_raw(pid, SimCmd.launch_superweapon(cx, cy, sw_angle))
			_say("APPSCEN launch pid=%d sw=%s tick=%d target=%d,%d" % [pid, w.data.superweapons[s.def_idx].id, w.tick, t.x, t.y])


## The cell of the nearest enemy structure (the enemy HQ area), (-1, -1) when there is no enemy.
func _enemy_cell(w: SimWorld, pid: int) -> Vector2i:
	var home: Vector2i = _home_cell(w, pid)
	var best: Vector2i = Vector2i(-1, -1)
	var best_d: int = 0x7FFFFFFF
	for e: SimEntity in w.entities:
		if e.kind != SimEntity.Kind.STRUCTURE or e.owner == pid or e.owner < 0 or w.players[e.owner].team == w.players[pid].team:
			continue
		var c: Vector2i = Vector2i(e.x >> SimConfig.CELL_SHIFT, e.y >> SimConfig.CELL_SHIFT)
		var d: int = absi(c.x - home.x) + absi(c.y - home.y)
		if d < best_d:
			best_d = d
			best = c
	return best


# ---- staged battles ----------------------------------------------------------------------------------------------------------

func _spawn_battle(w: SimWorld) -> void:
	var a: int = 0
	var b: int = -1
	for pid: int in range(1, w.players.size()):
		if w.players[pid] != null and w.players[pid].roster != null and w.players[pid].team != w.players[a].team:
			b = pid
			break
	if b < 0:
		return
	var ha: Vector2i = _home_cell(w, a)
	var hb: Vector2i = _home_cell(w, b)
	var layer: int = {"ground": SimEntity.Layer.GROUND, "air": SimEntity.Layer.AIR, "naval": SimEntity.Layer.SURFACE}.get(battle, SimEntity.Layer.GROUND)
	var mid: Vector2i = Vector2i((ha.x + hb.x) / 2, (ha.y + hb.y) / 2)
	var layer_a: int = layer
	var layer_b: int = SimEntity.Layer.GROUND if layer == SimEntity.Layer.AIR else layer
	var ca: Vector2i = mid
	var cb: Vector2i = mid
	if layer == SimEntity.Layer.SURFACE:
		var water: Vector2i = _water_spot(w, mid)
		if water.x < 0:
			_say("APPSCEN battle=naval: no water on this map")
			return
		ca = water + Vector2i(-7, 0)
		cb = water + Vector2i(7, 0)
	else:
		var dir: Vector2i = Vector2i(signi(hb.x - ha.x), signi(hb.y - ha.y))
		ca = mid - dir * 4
		cb = mid + dir * 4
	var ids_a: PackedInt32Array = _spawn_group(w, a, layer_a, battle_n, ca)
	var ids_b: PackedInt32Array = _spawn_group(w, b, layer_b, battle_n, cb)
	w.submit_raw(a, SimCmd.attack_move(ids_a, cb.x * SimConfig.CELL, cb.y * SimConfig.CELL))
	w.submit_raw(b, SimCmd.attack_move(ids_b, ca.x * SimConfig.CELL, ca.y * SimConfig.CELL))
	_say("APPSCEN battle=%s a=%d(%d units at %d,%d) b=%d(%d units at %d,%d)" % [battle, a, ids_a.size(), ca.x, ca.y, b, ids_b.size(), cb.x, cb.y])


func _water_spot(w: SimWorld, near: Vector2i) -> Vector2i:
	var best: Vector2i = Vector2i(-1, -1)
	var best_d: int = 0x7FFFFFFF
	for cy: int in range(8, w.map.h - 8, 2):
		for cx: int in range(8, w.map.w - 8, 2):
			var ok: bool = true
			for dx: int in range(-9, 10, 3):
				for dy: int in range(-4, 5, 2):
					if not w.map.is_clear(cx + dx, cy + dy, SimEntity.Layer.SURFACE):
						ok = false
			if ok:
				var d: int = absi(cx - near.x) + absi(cy - near.y)
				if d < best_d:
					best_d = d
					best = Vector2i(cx, cy)
	return best


## Spawns `n` armed units of the player's roster on `layer` around cell `c` on a grid (2-cell spacing); returns their entity ids.
func _spawn_group(w: SimWorld, pid: int, layer: int, n: int, c: Vector2i) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	var defs: PackedInt32Array = PackedInt32Array()
	for idx: int in w.players[pid].roster.producible_units:
		var d: DefUnit = w.data.units[idx]
		if d.home_layer == layer and d.weapons.size() > 0 and d.cost > 0 and (layer == SimEntity.Layer.AIR or d.speed > 0 or d.speed_water > 0):
			defs.append(idx)
	if defs.is_empty():
		return out
	var taken: Dictionary = {}
	for ring: int in range(0, 30):
		for gy: int in range(-ring, ring + 1):
			for gx: int in range(-ring, ring + 1):
				if maxi(absi(gx), absi(gy)) != ring or out.size() >= n:
					continue
				var cx: int = c.x + gx * 2
				var cy: int = c.y + gy * 2
				if taken.has(cy * 4096 + cx):
					continue
				if layer != SimEntity.Layer.AIR and not w.map.is_clear(cx, cy, layer):
					continue
				if not w.map.in_bounds(cx, cy):
					continue
				taken[cy * 4096 + cx] = true
				var e: SimEntity = w.spawn_unit(defs[out.size() % defs.size()], pid, cx * SimConfig.CELL + SimConfig.CELL / 2,
					cy * SimConfig.CELL + SimConfig.CELL / 2, 0, 0, 0, 0, SimEvent.SPAWN_PRODUCED)
				if e != null:
					out.append(e.id)
	return out
