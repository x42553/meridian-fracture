class_name MissionGoals
extends RefCounted
## MIS3: per-mission steering of the scripted macro bot (MissionBot) = what a competent human does that SimBot cannot know: where to fight and
## which units to walk where, keyed by objective states. See MissionBot for the goal format. `opts` are SimBot options.

static func config(id: String) -> Dictionary:
	match id:
		"op_napc":
			return {"opts": {"first_attack_tick": 1 << 30}, "goals": [
				{"obj": "checkpoint", "mode": "attack", "area": "a_chk", "min_army": 7},
				{"obj": "live_a", "mode": "rally", "area": "a_wp2"},
				{"obj": "live_b", "mode": "rally", "area": "a_wp2"},
				{"obj": "live_c", "mode": "rally", "area": "a_wp2"},
				{"obj": "recover", "mode": "move_def", "area": "a_post", "defs": ["unit.napc.pathfinder_apc"]},
			]}
		"op_nec":
			return {"opts": {"first_attack_tick": 1 << 30}, "goals": [
				{"obj": "siege", "mode": "attack", "area": "a_siege", "min_army": 9},
				{"obj": "", "mode": "rally", "area": "a_front"},
			]}
		"op_olm":
			return {"opts": {"first_attack_tick": 1 << 30}, "goals": [
				{"obj": "depot", "mode": "attack", "area": "a_depot", "min_army": 9},
				{"obj": "", "mode": "rally", "area": "a_hub"},
			]}
		"op_def":
			return {"opts": {"first_attack_tick": 1 << 30}, "goals": [
				{"obj": "j1", "mode": "attack", "area": "a_j1", "min_army": 12, "from_s": 120},
				{"obj": "j2", "mode": "attack", "area": "a_j2", "min_army": 20, "from_s": 420},
				{"obj": "j3", "mode": "attack", "area": "a_j3", "min_army": 22, "from_s": 640},
				{"obj": "", "mode": "rally", "area": "a_front"},
			]}
		"op_pd":
			return {"opts": {"first_attack_tick": 1 << 30, "amphibious": true}, "goals": [
				{"obj": "seize", "mode": "attack", "area": "a_port", "min_army": 16, "from_s": 200},
				{"obj": "hold", "mode": "rally", "area": "a_port"},
				{"obj": "", "mode": "rally", "area": "a_front"},
			]}
		"op_han":
			return {"opts": {"first_attack_tick": 1 << 30, "include_defs": ["unit.han.link_operator"]}, "goals": [
				{"obj": "n1", "mode": "attack", "area": "a_n1", "min_army": 14, "from_s": 150},
				{"obj": "n2", "mode": "attack", "area": "a_n2", "min_army": 16},
				{"obj": "n3", "mode": "attack", "area": "a_n3", "min_army": 18},
				{"obj": "", "mode": "rally", "area": "a_front"},
			]}
		"op_ae":
			return {"opts": {"first_attack_tick": 1 << 30}, "goals": [
				{"obj": "recover", "mode": "move_def", "area": "a_works", "defs": ["unit.ae.mamba_apc"], "from_s": 100},
				{"obj": "", "mode": "rally", "area": "a_front"},
			]}
		"op_sap":
			return {"opts": {"first_attack_tick": 1 << 30}, "goals": [
				{"obj": "guns", "mode": "launch", "area": "a_lb"},
				{"obj": "lb", "mode": "attack", "area": "a_lb", "min_army": 12, "from_s": 240},
				{"obj": "lc", "mode": "attack", "area": "a_lc", "min_army": 10},
				{"obj": "post", "mode": "attack", "area": "a_post", "min_army": 16},
				{"obj": "", "mode": "rally", "area": "a_front"},
			]}
	return {"opts": {}, "goals": []}
