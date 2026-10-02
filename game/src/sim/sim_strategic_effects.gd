class_name SimStrategicEffects
extends RefCounted
## Support-power recipes (economy 5.16-5.18; task EC3B, E7). The framework half of a power: classification into the ten
## effect kinds, the validation rules (prerequisites, power, credits, target vision and terrain), the activation flow
## (spend -> cooldown -> events -> effect -> warning -> effect end) and the packet choke point. The effect itself is
## executed by SimPowerFx (AB3) from the data-encoded actions of the power (`DefPower.actions`): zones, summons, strikes,
## marks and global effects. Stateless: everything is stored in SimStrategicSystem / SimPlayerEcon.


# ---- classification (economy 5.18) -----------------------------------------------------------------------------------

## EK_* of a power, derived from its actions: a global effect chosen on a structure = STRUCT_BUFF, otherwise WINDOW; a strike
## = BOMBARD (Counterlaunch Plot: strike + mark); a lone mark = MARK; a zone by its kind (REVEAL, SMOKE, DECOY, REPAIR,
## BUFF); a lone summon = RECON_SUMMON.
static func kind_of(world: SimWorld, p: DefPower) -> int:
	var has_strike: bool = false
	var has_mark: bool = false
	var zone_kind: int = -1
	var has_summon: bool = false
	for a: DefPowerAction in p.actions:
		match a.op:
			DefEnums.PowerOp.GLOBAL_EFFECT:
				return SimEconConst.EK_STRUCT_BUFF if str(a.params.get("scope", "")) == "chosen_target" else SimEconConst.EK_WINDOW
			DefEnums.PowerOp.STRIKE:
				has_strike = true
			DefEnums.PowerOp.MARK:
				has_mark = true
				if not a.impacts.is_empty():
					has_strike = true
			DefEnums.PowerOp.SUMMON:
				has_summon = true
			DefEnums.PowerOp.ZONE:
				if zone_kind < 0 and a.zone >= 0:
					zone_kind = world.data.zones[a.zone].zone_kind
	if has_strike:
		return SimEconConst.EK_BOMBARD
	if has_mark:
		return SimEconConst.EK_MARK
	match zone_kind:
		DefEnums.ZoneKind.REVEAL:
			return SimEconConst.EK_REVEAL_ZONE
		DefEnums.ZoneKind.SMOKE:
			return SimEconConst.EK_SMOKE
		DefEnums.ZoneKind.DECOY:
			return SimEconConst.EK_DECOY
		DefEnums.ZoneKind.REPAIR:
			return SimEconConst.EK_REPAIR
		DefEnums.ZoneKind.BUFF:
			return SimEconConst.EK_BUFF
	if has_summon:
		return SimEconConst.EK_RECON_SUMMON
	return SimEconConst.EK_BUFF


## TK_* of the power's target.
static func target_kind(p: DefPower) -> int:
	match p.target_mode:
		DefEnums.TargetMode.POINT:
			return SimEconConst.TK_AREA if p.radius > 0 else SimEconConst.TK_POINT
		DefEnums.TargetMode.LINE:
			return SimEconConst.TK_LINE
		DefEnums.TargetMode.OWN_STRUCTURE:
			return SimEconConst.TK_OWN_STRUCTURE
	return SimEconConst.TK_NONE


## VR_* of the power's target vision (reconnaissance = NONE, decoys = EXPLORED, everything else CURRENT). A power with a mark
## action (Counterbattery Solution, Counterlaunch Plot) is reconnaissance whatever its data row says.
static func vision_rule(p: DefPower) -> int:
	for a: DefPowerAction in p.actions:
		if a.op == DefEnums.PowerOp.MARK:
			return SimEconConst.VR_NONE  # the two fire-log powers name where enemy artillery fired: reconnaissance (5.16)
	match p.target_vision:
		DefEnums.TargetVision.ANY:
			return SimEconConst.VR_NONE
		DefEnums.TargetVision.EXPLORED:
			return SimEconConst.VR_EXPLORED
	return SimEconConst.VR_CURRENT


## Ticks the power's effect runs after activation (0 = instant): the longest action, a zone template's own duration when the
## action names none; strike powers add their warning (shells leave when it ends).
static func duration_of(world: SimWorld, p: DefPower) -> int:
	var best: int = 0
	for a: DefPowerAction in p.actions:
		var d: int = a.duration_t
		for fx: DefEffect in a.effects:
			d = maxi(d, fx.duration_t)
		if a.zone >= 0 and a.op == DefEnums.PowerOp.ZONE:
			var z: DefZone = world.data.zones[a.zone]
			d = maxi(d, z.duration_t)
			for zfx: DefEffect in z.effects:
				d = maxi(d, zfx.duration_t)
		best = maxi(best, d)
	if best > 0 and kind_of(world, p) == SimEconConst.EK_BOMBARD and not SimPowerFx.self_warned(world, p.index):
		best += p.warning_t
	elif best == 0 and p.warning_t > 0:
		best = p.warning_t
	return best


## Static terrain rule of the site powers (decoys, workshops, pontoons): the cell must not be a cliff or void.
static func terrain_ok(world: SimWorld, p: DefPower, x: int, y: int) -> bool:
	var cx: int = x >> 10
	var cy: int = y >> 10
	if not world.map.in_bounds(cx, cy):
		return false
	var k: int = kind_of(world, p)
	if k == SimEconConst.EK_DECOY or k == SimEconConst.EK_REPAIR or k == SimEconConst.EK_RECON_SUMMON:
		return world.map.is_passable_ground(cx, cy) or world.map.is_water(cx, cy)
	return true


# ---- validation ------------------------------------------------------------------------------------------------------

## The full CMD_USE_POWER validation for slot 0..2 (economy 5.16, first failure wins).
static func can_use(world: SimWorld, p: SimPlayer, slot: int, tx: int, ty: int, angle: int, target_id: int) -> int:
	var pe: SimPlayerEcon = p.econ
	var s: SimPowerSlot = pe.slots[slot]
	if s.def_idx < 0 or s.def_idx >= world.data.powers.size():
		return SimEconConst.RSN_INVALID_INDEX
	var d: DefPower = world.data.powers[s.def_idx]
	if world.tick < s.ready_tick:
		return SimEconConst.RSN_COOLDOWN
	if not SimStrategicSystem.prereqs_present(pe, d.requires_mask):
		return SimEconConst.RSN_PREREQ
	if d.requires_powered and not world.strategic.prereqs_online(world, p.pid, d.requires_mask):
		return SimEconConst.RSN_NO_POWER
	if p.credits < d.cost:
		return SimEconConst.RSN_NO_CREDITS
	return _check_target(world, p.pid, d, tx, ty, angle, target_id)


static func _check_target(world: SimWorld, pid: int, d: DefPower, tx: int, ty: int, angle: int, target_id: int) -> int:
	var tk: int = target_kind(d)
	match tk:
		SimEconConst.TK_NONE:
			pass
		SimEconConst.TK_OWN_STRUCTURE:
			var t: SimEntity = world.get_entity(target_id)
			if t == null or (t.flags & SimFlags.F_GONE) != 0 or t.owner != pid:
				return SimEconConst.RSN_BAD_TARGET
			if t.kind != SimEntity.Kind.STRUCTURE:
				return SimEconConst.RSN_WRONG_KIND
			if d.params.has("target_structure_idx") and not (d.params["target_structure_idx"] as PackedInt32Array).has(t.def_idx):
				return SimEconConst.RSN_WRONG_KIND
			if t.econ == null or t.econ.st != SimEconConst.ST_ACTIVE:
				return SimEconConst.RSN_BAD_TARGET
			if bool(d.params.get("target_powered_required", false)) and not world.economy.life.structure_online(world, t):
				return SimEconConst.RSN_NO_POWER
		SimEconConst.TK_OWN_UNIT:
			var u: SimEntity = world.get_entity(target_id)
			if u == null or (u.flags & SimFlags.F_GONE) != 0 or u.owner != pid or u.kind != SimEntity.Kind.UNIT:
				return SimEconConst.RSN_BAD_TARGET
		_:
			var cx: int = tx >> 10
			var cy: int = ty >> 10
			if tx < 0 or ty < 0 or not world.map.in_bounds(cx, cy):
				return SimEconConst.RSN_TERRAIN
			if tk == SimEconConst.TK_LINE and (angle < 0 or angle > Fp.ANGLE_MASK):
				return SimEconConst.RSN_BAD_TARGET
			match vision_rule(d):
				SimEconConst.VR_EXPLORED:
					if not world.cell_explored(pid, cx, cy):
						return SimEconConst.RSN_NOT_EXPLORED
				SimEconConst.VR_CURRENT:
					if not world.cell_visible(pid, cx, cy):
						return SimEconConst.RSN_NO_VISION
			if not terrain_ok(world, d, tx, ty):
				return SimEconConst.RSN_TERRAIN
	var v: int = SimPowerFx.validate(world, d.index, pid, tx, ty)
	if v == SimZoneConsts.PW_ERR_LIMIT:
		return SimEconConst.RSN_BUSY
	if v != SimZoneConsts.PW_OK:
		return SimEconConst.RSN_NOT_AVAILABLE
	return SimEconConst.RSN_OK


# ---- activation ------------------------------------------------------------------------------------------------------

## Pays, starts the cooldown, announces, runs the effect and books the warning / window records. Validation already passed.
static func activate(world: SimWorld, sys: SimStrategicSystem, p: SimPlayer, slot: int, x: int, y: int, angle: int, target_id: int) -> int:
	var pid: int = p.pid
	var s: SimPowerSlot = p.econ.slots[slot]
	var d: DefPower = world.data.powers[s.def_idx]
	if d.cost > 0 and not world.economy.spend(world, pid, d.cost, SimEconConst.CR_POWER_USE):
		return SimEconConst.RSN_NO_CREDITS
	s.ready_tick = world.tick + d.cooldown_t
	s.uses += 1
	s.last_activation_tick = world.tick
	world.emit(SimEconConst.EVT_POWER_ACTIVATED, x, y, pid, slot, d.index, x, y, angle)
	var aux: int = world.rng.next_u32() & 0x7FFFFFFF  # the ONE draw of this activation (decoy scatter, shell scatter, capsule angles)
	if d.params.has("target_structure_idx"):
		aux = target_id
	var self_warned: bool = SimPowerFx.self_warned(world, d.index)
	var shift: int = d.warning_t if (d.warning_t > 0 and not self_warned) else 0
	var res: int = SimPowerFx.apply(world, d.index, pid, x, y, angle, aux, shift)
	if res != SimZoneConsts.PW_OK:
		Log.error("strategic", "power %s: SimPowerFx.apply returned %d after validation" % [d.id, res])
	var dur: int = duration_of(world, d)
	if kind_of(world, d) == SimEconConst.EK_WINDOW:
		mirror_knobs(world, pid, d, world.tick + dur)
	if d.warning_t > 0:
		var kind: int = SimEconConst.WK_SCAN if self_warned else SimEconConst.WK_POWER
		var geom: PackedInt32Array = PackedInt32Array([x, y, x, y, maxi(d.radius, 1024), 0, angle])
		var w: SimWarning = sys.add_warning(world, kind, d.index, pid, 0, geom, d.warning_t, maxi(dur - d.warning_t, 0) if not self_warned else dur)
		sys.schedule(w.exec_tick, SimEconConst.SK_WARNING_END, pid, d.index, w.id, x, y, 0, aux, angle)
	if dur > 0:
		sys.set_window(pid, d.index, world.tick + dur)
		sys.schedule(world.tick + dur, SimEconConst.SK_WINDOW_END, pid, d.index, 0)
	return SimEconConst.RSN_OK


## The knob table (economy 4.5) mirrors the window of a player-wide power, so that the UI, the AI and the other domains
## read one number: relay / command field windows (damage OVR, radius ADD in cells), Joint Landing, Recovery Priority. The
## production-rate and salvage knobs are written by SimPowerFx itself. The effects act through the aura windows and the
## timed effects of SimPowerFx (AB3); these temp knobs are the readable copy and expire on their own with `until`.
static func mirror_knobs(world: SimWorld, pid: int, p: DefPower, until: int) -> void:
	for a: DefPowerAction in p.actions:
		if a.op != DefEnums.PowerOp.GLOBAL_EFFECT:
			continue
		for fx: DefEffect in a.effects:
			if fx.op == DefEnums.EffectOp.PARAM_MOD and fx.scope == DefEnums.ParamScope.ABILITY:
				var relay: bool = fx.ability_kind == DefEnums.AbilityKind.RELAY_FIELD
				if not relay and fx.ability_kind != DefEnums.AbilityKind.COMMAND_FIELD:
					continue
				if fx.key == "damage_bonus_bp":
					world.economy.set_knob_temp(pid, SimEconConst.K_RELAY_DAMAGE_BP if relay else SimEconConst.K_CMD_DAMAGE_BP, fx.value, until)
				elif fx.key == "radius_u":
					world.economy.set_knob_temp(pid, SimEconConst.K_RELAY_RADIUS_CELLS if relay else SimEconConst.K_CMD_RADIUS_CELLS, fx.value / Fp.CELL, until)
			elif fx.cond_codes.has(DefEnums.Cond.RECENTLY_DISEMBARKED):
				world.economy.set_knob_temp(pid, SimEconConst.K_JOINT_LANDING, 1, until)
			elif fx.op == DefEnums.EffectOp.STAT_MOD and fx.stat == DefEnums.Stat.SPEED:
				world.economy.set_knob_temp(pid, SimEconConst.K_RECOVERY_PRIORITY, 1, until)


## End of a running effect: HUD event, registry entry removed, production rates refreshed.
static func window_end(world: SimWorld, sys: SimStrategicSystem, rec: SimScheduled) -> void:
	sys.clear_window(rec.owner, rec.src_idx)
	if rec.owner >= 0 and rec.owner < world.players.size() and world.players[rec.owner].econ != null:
		world.players[rec.owner].econ.rates_dirty = true
	world.emit(SimEconConst.EVT_POWER_EFFECT_END, 0, 0, rec.owner, rec.src_idx)


# ---- packet choke point ----------------------------------------------------------------------------------------------

## A strategic / shell impact described by a SimImpactPacket enters combat as a remote strike detonating now; combat applies
## falloff, structure multiplier, armour, the 50 % resistance cap and Trident's interception at detonation. Beam and EMP
## packets are never interceptable; PKT_SHELL packets are ordinary shells (one Trident charge each). `team_mask`, `layer_mask`
## and `radius_min` have no counterpart in combat's warhead table: friendly fire follows the warhead (EMP spares allies).
static func emit_packet(world: SimWorld, pk: SimImpactPacket) -> void:
	if world.combat == null or pk.src_pid < 0 or pk.src_pid >= world.players.size():
		return
	var dp: DefImpactPacket = DefImpactPacket.new()
	dp.damage = pk.damage
	dp.dtype = pk.dmg_type
	dp.radius = pk.radius
	dp.edge_bp = pk.falloff_edge_bp
	dp.non_lethal = (pk.flags & SimEconConst.PKT_EMP) != 0
	if (pk.flags & SimEconConst.PKT_BEAM) != 0:
		dp.params = {"per_second": true}
	var shell: bool = (pk.flags & SimEconConst.PKT_SHELL) != 0
	var key: String = "pkt:%d:%d:%d:%d:%d" % [pk.dmg_type, pk.damage, pk.radius, pk.falloff_edge_bp, pk.flags]
	var wh: int = SimPowerFx.warhead_for(world, pk.src_pid, key, dp, null, shell)
	SimPowerFx.strike_packet(world, pk.src_pid, 0, wh, pk.x, pk.y, 0, shell)
	if (pk.flags & SimEconConst.PKT_SHELL) == 0:
		world.emit(SimEconConst.EVT_SW_IMPACT, pk.x, pk.y, pk.src_idx, pk.x, pk.y, pk.radius, pk.dmg_type)
