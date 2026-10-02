extends SceneTree
## MIS3 mission runner (dev tool / acceptance driver, not part of the suite): plays shipped missions with the MissionRun harness and prints one
## `MIS3_RESULT {json}` line per run.
##   tools/gd run res://tests/scenarios/mis3_run.gd -- mission=op_napc driver=ai ai_seed=777 sim_seed=-1 minutes=25 [level=2] [bonus=0]
##   mission=all runs every shipped mission of the group `operation`/`tutorial`. driver = ai | idle | none.

func _initialize() -> void:
	var a: Dictionary = {}
	for s: String in OS.get_cmdline_user_args():
		if "=" in s:
			var kv: PackedStringArray = s.split("=", true, 1)
			a[kv[0]] = kv[1]
	var d: GameData = MissionKit.data()
	var ids: PackedStringArray = PackedStringArray()
	if str(a.get("mission", "all")) == "all":
		for id: String in SimMissionSetup.ids_in_order(d):
			if not id.begins_with("demo"):
				ids.append(id)
	else:
		ids = str(a["mission"]).split(",", false)
	var rc: int = 0
	for id: String in ids:
		var tp: TutorialPlayer = TutorialPlayer.new() if str(a.get("driver", "ai")) == "tutorial" else null
		var o: Dictionary = {"driver": "idle" if tp != null else str(a.get("driver", "ai")), "assist": (func(w: SimWorld, _t: int, _c: Dictionary) -> void: tp.act(w)) if tp != null else Callable(), "ai_seed": int(a.get("ai_seed", 777)), "sim_seed": int(a.get("sim_seed", -1)),
			"human_level": int(a.get("level", 2)), "ai_level_bonus": int(a.get("bonus", 0)), "events": false, "label": str(a.get("driver", "ai"))}
		var m: Dictionary = MissionRun.make(d, id, o)
		if m.is_empty():
			print("MIS3_RESULT {\"id\":\"%s\",\"outcome\":\"invalid\"}" % id)
			rc = 1
			continue
		var trace_every: int = int(a.get("trace", 0))
		var cb: Callable = Callable()
		if trace_every > 0:
			cb = func(_m: Dictionary, rec: Dictionary) -> void:
				if int(rec["t"]) % trace_every == 0:
					var w2: SimWorld = _m["world"]
					var objs: PackedStringArray = PackedStringArray()
					for oid: String in MissionRun.objective_states(w2):
						if MissionRun.objective_states(w2)[oid] == "active":
							objs.append(oid)
					if a.has("tracedef"):
						var hp2: PackedStringArray = PackedStringArray()
						for u2: SimEntity in w2.units_of(int(_m["human_pid"])):
							var uid2: String = str(w2.data.id_of(DefEnums.Kind.UNIT, u2.def_idx))
							if uid2.contains(str(a["tracedef"])):
								hp2.append("%s@(%d,%d)" % [uid2.get_slice(".", 2), u2.x >> 10, u2.y >> 10])
						print("  OWN " + " ".join(hp2))
					if a.has("tracepos"):
						var pp: PackedStringArray = PackedStringArray()
						for pl: SimPlayer in w2.players:
							if pl.pid != int(_m["human_pid"]):
								for u: SimEntity in w2.units_of(pl.pid):
									pp.append("p%d:%s@(%d,%d)" % [pl.pid, str(w2.data.id_of(DefEnums.Kind.UNIT, u.def_idx)).get_slice(".", 2), u.x >> 10, u.y >> 10])
						print("  POS " + " ".join(pp.slice(0, 12)))
					var rr: Dictionary = SimMatchKit.report(w2, int(_m["human_pid"]))
					var ex: String = ""
					for pl2: SimPlayer in w2.players:
						if pl2.pid != int(_m["human_pid"]):
							var re: Dictionary = SimMatchKit.report(w2, pl2.pid)
							ex += " | P%d s=%d c=%d k=%d l=%d" % [pl2.pid, re["structures"], re["combat_units"], re["killed"], re["lost"]]
					print("TRACE t=%ds cred=%d u=%d s=%d combat=%d harv=%d k=%d l=%d%s | %s" % [rec["t"], rec["cred"], rec["units"], rec["structs"], rr["combat_units"], rr["harvested"], rr["killed"], rr["lost"], ex, ",".join(objs)])
		var r: Dictionary = MissionRun.play(m, int(a.get("minutes", 25)) * 60 * MissionRun.TPS, cb)
		var brief: Dictionary = r.duplicate()
		if not bool(a.has("full")):
			brief.erase("fired")
		print("MIS3_RESULT " + JSON.stringify(brief))
		if not (r["errors"] as Array).is_empty():
			rc = 1
		MissionRun.dispose(m)
	MissionKit.release()
	quit(rc)
