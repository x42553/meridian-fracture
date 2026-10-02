class_name SndEventMap
extends RefCounted
## Parses and validates `events.json` into SndEventDef / SndProfileDef, resolves `sim_map` patterns and reports coverage
## holes (`missing`, QA gate DA-23). Audio spec 3.3 / 7.3.

const FACTION_CODES: PackedStringArray = ["napc", "nec", "olm", "def", "pd", "han", "ae", "sap"]
const POWER_CLASSES: PackedStringArray = ["recon", "repair", "buff", "shield", "cloak", "smoke", "barrage", "generic"]
const SW_NAMES: PackedStringArray = ["atlas", "aurora", "helios", "perun", "tempest", "dragonfall", "horizon", "trident"]

var errors: PackedStringArray = PackedStringArray()
var groups: Dictionary = {}  ## group -> max voices
var power_cues: Dictionary = {}  ## power id -> class
var sw_cues: Dictionary = {}  ## superweapon id -> name
var sim_map: Dictionary = {}
var unit_profile: Dictionary = {}  ## unit id -> profile id (audio's own archetype table)
var structure_profile: Dictionary = {}

var _defs: Dictionary = {}  ## StringName -> SndEventDef
var _sorted: Array[StringName] = []
var _profiles: Dictionary = {}
var _profile_ids: Array[StringName] = []
var _index: SndAssetIndex = null
var _store: SndDataStore = null


func build(store: SndDataStore, index: SndAssetIndex) -> bool:
	errors = PackedStringArray()
	_defs.clear()
	_profiles.clear()
	_store = store
	_index = index
	var ev: Dictionary = store.events
	groups.clear()
	for g: Variant in (ev.get("groups", {}) as Dictionary).keys():
		groups[StringName(str(g))] = int(((ev["groups"] as Dictionary)[g] as Dictionary).get("max_voices", 8))
	var bus_names: Dictionary = {}
	for b: Variant in store.mix.buses:
		bus_names[str((b as Dictionary).get("name", ""))] = true
	var raw: Dictionary = ev.get("events", {})
	var ids: Array = raw.keys()
	ids.sort()
	var seen: Dictionary = {}
	var n: int = 0
	for k: Variant in ids:
		var sid: String = str(k)
		if seen.has(sid.to_lower()):
			_err("events.%s: duplicate id (case-insensitive)" % sid)
			continue
		seen[sid.to_lower()] = true
		var def: SndEventDef = _make_def(sid, raw[k] as Dictionary, bus_names)
		def.index = n
		n += 1
		_defs[def.id] = def
		_sorted.append(def.id)
	_link_check()
	_build_profiles(ev.get("profiles", {}) as Dictionary)
	power_cues = ev.get("power_cues", {})
	sw_cues = ev.get("sw_cues", {})
	sim_map = ev.get("sim_map", {})
	unit_profile = sim_map.get("unit_profile", {})
	structure_profile = sim_map.get("structure_profile", {})
	for pid: Variant in power_cues.keys():
		if not POWER_CLASSES.has(str(power_cues[pid])):
			_err("power_cues.%s: unknown class '%s'" % [str(pid), str(power_cues[pid])])
	for sid: Variant in sw_cues.keys():
		if not SW_NAMES.has(str(sw_cues[sid])):
			_err("sw_cues.%s: unknown superweapon name '%s'" % [str(sid), str(sw_cues[sid])])
	return errors.is_empty()


func _err(msg: String) -> void:
	errors.append(msg)


func _make_def(sid: String, e: Dictionary, bus_names: Dictionary) -> SndEventDef:
	var d: SndEventDef = SndEventDef.new()
	d.id = StringName(sid)
	d.attach_index(_index)
	d.category = StringName(str(e.get("category", "")))
	d.bus = StringName(str(e.get("bus", "Sfx")))
	if not bus_names.has(str(d.bus)):
		_err("events.%s: unknown bus '%s'" % [sid, str(d.bus)])
	d.priority = int(e.get("priority", 50))
	if d.priority < 0 or d.priority > 100:
		_err("events.%s: priority %d outside 0..100" % [sid, d.priority])
	d.volume_db = float(e.get("volume_db", 0.0))
	if d.volume_db < -24.0 or d.volume_db > 3.0:
		_err("events.%s: volume_db %.1f outside [-24, 3]" % [sid, d.volume_db])
	d.volume_jitter_db = float(e.get("volume_jitter_db", 0.0))
	d.pitch = float(e.get("pitch", 1.0))
	d.pitch_jitter_semitones = float(e.get("pitch_jitter_semitones", 0.0))
	d.cull_below_db = float(e.get("cull_below_db", -42.0))
	if d.cull_below_db < -80.0 or d.cull_below_db > -10.0:
		_err("events.%s: cull_below_db %.1f outside [-80, -10]" % [sid, d.cull_below_db])
	d.loop = bool(e.get("loop", false))
	d.fade_in_ms = int(e.get("fade_in_ms", 120 if d.loop else 0))
	d.fade_out_ms = int(e.get("fade_out_ms", 200 if d.loop else 0))
	var sp: Dictionary = e.get("spatial", {}) as Dictionary if e.get("spatial") is Dictionary else {}
	var mode: String = str(sp.get("mode", "ui"))
	d.spatial = SndEventDef.SPATIAL_NAMES.find(mode)
	if d.spatial < 0:
		_err("events.%s: spatial.mode '%s'" % [sid, mode])
		d.spatial = SndEventDef.Spatial.UI
	d.unit_size_m = float(sp.get("unit_size_m", 20.0))
	d.max_distance_m = float(sp.get("max_distance_m", 0.0))
	d.attenuation = maxi(SndEventDef.ATTEN_NAMES.find(str(sp.get("attenuation", "inverse"))), 0)
	d.lowpass_hz = float(sp.get("lowpass_hz", 20500.0))
	d.panning_strength = float(sp.get("panning_strength", 1.0))
	d.doppler = bool(sp.get("doppler", false))
	d.propagation = bool(sp.get("propagation", false))
	d.fog = maxi(SndEventDef.FOG_NAMES.find(str(sp.get("fog", "hidden"))), 0)
	d.fog_gain_db = float(sp.get("fog_gain_db", _store.mix.fog_muffled_gain_db))
	d.fog_lowpass_hz = float(sp.get("fog_lowpass_hz", _store.mix.fog_muffled_lowpass_hz))
	if d.spatial == SndEventDef.Spatial.WORLD_3D and d.unit_size_m <= 0.0:
		_err("events.%s: unit_size_m must be > 0" % sid)
	var lim: Dictionary = e.get("limit", {}) as Dictionary if e.get("limit") is Dictionary else {}
	d.group = StringName(str(lim.get("group", "")))
	d.max_instances = int(lim.get("max_instances", 8))
	d.min_interval_ms = int(lim.get("min_interval_ms", 0))
	d.steal = maxi(SndEventDef.STEAL_NAMES.find(str(lim.get("steal", "oldest"))), 0)
	if d.group != &"" and not groups.has(d.group):
		_err("events.%s: limit.group '%s' is not declared in groups" % [sid, str(d.group)])
	var link: Dictionary = e.get("link", {}) as Dictionary if e.get("link") is Dictionary else {}
	d.link_loop = StringName(str(link.get("loop", "")))
	d.link_end = StringName(str(link.get("end", "")))
	for t: Variant in e.get("tags", []):
		d.tags.append(str(t))
	_expand_variants(sid, e.get("variants", []), d.var_ids, d.var_weights)
	if d.var_ids.is_empty():
		_err("events.%s: no variants" % sid)
	var fl: Dictionary = e.get("flavours", {}) as Dictionary if e.get("flavours") is Dictionary else {}
	for f: Variant in fl.keys():
		var code: String = str(f)
		if not FACTION_CODES.has(code):
			_err("events.%s: flavour '%s' is not a faction code" % [sid, code])
			continue
		var fi: PackedStringArray = PackedStringArray()
		var fw: PackedFloat32Array = PackedFloat32Array()
		_expand_variants(sid + ".flavours." + code, fl[f], fi, fw)
		if not fi.is_empty():
			d.flavour_ids[StringName(code)] = fi
			d.flavour_weights[StringName(code)] = fw
	if _index != null and _index.assets.size() > 0:
		var want_loop: bool = d.loop
		for vid: String in d.var_ids:
			if _index.has_asset(vid) and _index.is_loop(vid) != want_loop:
				_err("events.%s: loop=%s but asset %s loop=%s" % [sid, str(want_loop), vid, str(_index.is_loop(vid))])
	return d


func _expand_variants(ctx: String, variants: Variant, ids: PackedStringArray, weights: PackedFloat32Array) -> void:
	if not (variants is Array):
		return
	for v: Variant in variants:
		if not (v is Dictionary):
			_err("events.%s: variant must be an object" % ctx)
			continue
		var vd: Dictionary = v
		var w: float = float(vd.get("weight", 1.0))
		if w <= 0.0:
			_err("events.%s: variant weight must be > 0" % ctx)
			continue
		if vd.has("stream"):
			var sid: String = str(vd["stream"])
			_check_asset(ctx, sid)
			ids.append(sid)
			weights.append(w)
		elif vd.has("group"):
			var g: String = str(vd["group"])
			var members: PackedStringArray = _index.group_members(g) if _index != null else PackedStringArray()
			if members.is_empty():
				if _index != null and _index.has_asset(g):
					ids.append(g)
					weights.append(w)
				else:
					_err("events.%s: asset group '%s' not in the asset index" % [ctx, g])
				continue
			for m: String in members:
				ids.append(m)
				weights.append(w)
		else:
			_err("events.%s: variant needs 'stream' or 'group'" % ctx)


func _check_asset(ctx: String, sid: String) -> void:
	if _index != null and not _index.has_asset(sid):
		_err("events.%s: stream '%s' not in the asset index" % [ctx, sid])


func _link_check() -> void:
	for k: StringName in _sorted:
		var d: SndEventDef = _defs[k]
		for l: StringName in [d.link_loop, d.link_end]:
			if l != &"" and not _defs.has(l):
				_err("events.%s: link target '%s' is not an event" % [str(k), str(l)])


func _build_profiles(raw: Dictionary) -> void:
	var ids: Array = raw.keys()
	ids.sort()
	for k: Variant in ids:
		var e: Dictionary = raw[k]
		var p: SndProfileDef = SndProfileDef.new()
		p.id = StringName(str(k))
		p.parent = StringName(str(e.get("parent", "")))
		if e.has("voice_class"):
			p.voice_class = SndUnits.VOICE_CLASS_NAMES.find(str(e["voice_class"]))
			if p.voice_class < 0:
				_err("profiles.%s: voice_class '%s'" % [str(k), str(e["voice_class"])])
		p.weapon_variant = e.get("weapon_variant", {})
		p.die = StringName(str(e.get("die", "")))
		p.spawn = StringName(str(e.get("spawn", "")))
		p.select_fx = StringName(str(e.get("select_fx", "")))
		p.scalars = e.get("scalars", {})
		p.loops_explicit = e.has("loops")
		for l: Variant in e.get("loops", []):
			var ld: Dictionary = l
			var w: int = SndProfileDef.WHEN_NAMES.find(str(ld.get("when", "always")))
			if w < 0:
				_err("profiles.%s: loops.when '%s'" % [str(k), str(ld.get("when"))])
				w = 0
			var ev: StringName = StringName(str(ld.get("event", "")))
			if not _defs.has(ev):
				_err("profiles.%s: loop event '%s' is not an event" % [str(k), str(ev)])
			p.loops.append({"event": ev, "when": w, "gain_db": float(ld.get("gain_db", 0.0)), "pitch_speed": bool(ld.get("pitch_speed", false))})
		for key: String in [str(p.die), str(p.spawn), str(p.select_fx)]:
			if key != "" and not _defs.has(StringName(key)):
				_err("profiles.%s: override event '%s' is not an event" % [str(k), key])
		_profiles[p.id] = p
		_profile_ids.append(p.id)
	# inheritance (acyclic, depth <= 4)
	for pid: StringName in _profile_ids:
		var p2: SndProfileDef = _profiles[pid]
		var chain: Array[SndProfileDef] = []
		var cur: SndProfileDef = p2
		var depth: int = 0
		while cur != null and cur.parent != &"" and depth < 6:
			var par: SndProfileDef = _profiles.get(cur.parent)
			if par == null:
				_err("profiles.%s: parent '%s' missing" % [str(cur.id), str(cur.parent)])
				break
			chain.append(par)
			cur = par
			depth += 1
		if depth > 4:
			_err("profiles.%s: parent chain deeper than 4 or cyclic" % str(pid))
			continue
		for par2: SndProfileDef in chain:
			if p2.voice_class < 0:
				p2.voice_class = par2.voice_class
			if not p2.loops_explicit and par2.loops_explicit:
				p2.loops = par2.loops
				p2.loops_explicit = true
			for wk: Variant in par2.weapon_variant.keys():
				if not p2.weapon_variant.has(wk):
					p2.weapon_variant[wk] = par2.weapon_variant[wk]
			if p2.die == &"":
				p2.die = par2.die
			if p2.spawn == &"":
				p2.spawn = par2.spawn
			if p2.select_fx == &"":
				p2.select_fx = par2.select_fx
	for pid2: StringName in _profile_ids:
		var pp: SndProfileDef = _profiles[pid2]
		if pp.voice_class < 0:
			pp.voice_class = SndUnits.VoiceClass.VEHICLE


## Clears the per-event counters the voice pool keeps on the defs (new match, tests).
func reset_bookkeeping() -> void:
	for k: StringName in _sorted:
		var d: SndEventDef = _defs[k]
		d.active_count = 0
		d.last_play_ms = -1000000
		d._last_variant.clear()


func has_event(id: StringName) -> bool:
	return _defs.has(id)


func get_def(id: StringName) -> SndEventDef:
	return _defs.get(id)


func event_ids() -> Array[StringName]:
	return _sorted


func get_profile(id: StringName) -> SndProfileDef:
	return _profiles.get(id)


func profile_ids() -> Array[StringName]:
	return _profile_ids


func group_limit(group: StringName) -> int:
	return int(groups.get(group, 1000000))


func def_count() -> int:
	return _defs.size()


func assign_bus_indices() -> void:
	for k: StringName in _sorted:
		var d: SndEventDef = _defs[k]
		d.bus_index = AudioServer.get_bus_index(d.bus)


## `sim_map` pattern -> an existing event id; the rule's fallback when the pattern names nothing; else &"".
func resolve(kind: StringName, tags: Dictionary) -> StringName:
	var rule: Variant = sim_map.get(String(kind))
	if not (rule is Dictionary):
		return &""
	var pat: String = str((rule as Dictionary).get("pattern", ""))
	for t: Variant in tags.keys():
		pat = pat.replace("{%s}" % str(t), str(tags[t]))
	var id: StringName = StringName(pat)
	if _defs.has(id):
		return id
	var fb: StringName = StringName(str((rule as Dictionary).get("fallback", "")))
	return fb if _defs.has(fb) else &""


func ensure_flavours(_flavours: PackedStringArray) -> void:
	pass  # streams are resolved lazily from the cache; nothing to do


## QA gate DA-23: "kind:id" strings, empty = complete.
func missing(data: GameData = null) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for code: int in SndEventCodes.consumed_codes():
		if SndSimBridge.route_of(code) == SndSimBridge.R_IGNORE and not SndEventCodes.is_ignored(code):
			out.append("route:%d" % code)
	for k: Variant in sim_map.keys():
		var rule: Variant = sim_map[k]
		if rule is Dictionary and (rule as Dictionary).has("fallback"):
			var fb: StringName = StringName(str((rule as Dictionary)["fallback"]))
			if not _defs.has(fb) and not _profiles.has(fb):
				out.append("sim_map:%s" % str(fb))
	for uid: Variant in unit_profile.keys():
		if not _profiles.has(StringName(str(unit_profile[uid]))):
			out.append("profile:%s" % str(unit_profile[uid]))
	var lines: Dictionary = _store.announcer.get("lines", {})
	for l: String in SndSimBridge.LINES_USED:
		if not lines.has(l):
			out.append("line:%s" % l)
	for ev: String in SndSimBridge.EVENTS_USED:
		if not _defs.has(StringName(ev)):
			out.append("event:%s" % ev)
	if data != null:
		var bank: SndSoundBank = SndSoundBank.new()
		bank.bake(data, self, _store.mix)
		for u: String in bank.unresolved:
			out.append(u)
	return out
