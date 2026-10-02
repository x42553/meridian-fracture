class_name UiLobbyNet
extends RefCounted
## The bridge between the replicated lobby model of net (`NetLobbyState`, owned by `NetLobby`) and the widgets of the lobby screen,
## which edit a `UiLobbyState` (ui.md 5.14, LAN roles HOST and CLIENT). Pure functions, no nodes, unit tested on fixtures:
##   * `pull` mirrors the authoritative state into the UI model (roster tokens become faction + subfaction picks, slot kinds are mapped),
##   * `diff` compares the UI model after ONE widget edit with the authoritative state and returns the `NetLobby` calls that express
##     that edit, filtered by the permissions of the role (the host edits everything, a client only its own row, 5.14.2),
##   * `execute` runs those calls; `result_text` explains a refusal.
## The screen writes optimistically into the UI model, sends the diff and pulls again when the snapshot arrives, so a refused edit
## snaps back and a granted one shows the host's normalisation (colour / start swaps, unique names).

enum Role { LOCAL = 0, HOST = 1, CLIENT = 2 }

const RULE_KEYS: PackedStringArray = ["start_credits", "unit_cap", "superweapons", "fog", "shared_vision", "veterancy"]


static func kind_to_net(kind: int) -> int:
	match kind:
		UiLobbyState.Kind.HUMAN:
			return NetProtocol.SlotKind.HUMAN
		UiLobbyState.Kind.AI:
			return NetProtocol.SlotKind.AI
		UiLobbyState.Kind.OPEN:
			return NetProtocol.SlotKind.OPEN
	return NetProtocol.SlotKind.CLOSED


static func kind_from_net(kind: int) -> int:
	match kind:
		NetProtocol.SlotKind.HUMAN:
			return UiLobbyState.Kind.HUMAN
		NetProtocol.SlotKind.AI:
			return UiLobbyState.Kind.AI
		NetProtocol.SlotKind.OPEN:
			return UiLobbyState.Kind.OPEN
	return UiLobbyState.Kind.CLOSED


# ---------------------------------------------------------------- roster picks (ui.md 5.14.3, net.md 5.3.4)

## The roster id or random token a faction + subfaction pick stands for. Faction -1 is Random; a faction with sub 4 is "any of its
## four rosters". "" for an out-of-range faction.
static func roster_token(data: GameData, faction: int, sub: int) -> String:
	if data == null:
		return ""
	if faction < 0:
		return ["random.vanilla", "random.subfaction", "random"][clampi(sub, 0, 2)]
	if faction >= data.factions.size():
		return ""
	var f: DefFaction = data.factions[faction]
	if sub == 0:
		return data.rosters[f.vanilla_roster].id
	if sub >= 1 and sub <= f.sub_rosters.size():
		return data.rosters[f.sub_rosters[sub - 1]].id
	return "random." + f.code.to_lower()


## `Vector2i(faction, sub)` of a roster id or token (the inverse of `roster_token`); an unknown id becomes Random / Any.
static func roster_pick(data: GameData, roster_id: String) -> Vector2i:
	if data == null:
		return Vector2i(-1, 2)
	match roster_id:
		"random":
			return Vector2i(-1, 2)
		"random.vanilla":
			return Vector2i(-1, 0)
		"random.subfaction":
			return Vector2i(-1, 1)
	if roster_id.begins_with("random."):
		var code: String = roster_id.substr(7)
		for i: int in data.factions.size():
			if data.factions[i].code.to_lower() == code:
				return Vector2i(i, 4)
		return Vector2i(-1, 2)
	for fi: int in data.factions.size():
		var f: DefFaction = data.factions[fi]
		if data.rosters[f.vanilla_roster].id == roster_id:
			return Vector2i(fi, 0)
		for k: int in f.sub_rosters.size():
			if data.rosters[f.sub_rosters[k]].id == roster_id:
				return Vector2i(fi, k + 1)
	return Vector2i(-1, 2)


# ---------------------------------------------------------------- net -> UI model

## Mirrors the replicated state into the UI model (every slot, the map, the rules and the host options).
static func pull(net: NetLobbyState, ui: UiLobbyState) -> void:
	var data: GameData = ui.data()
	ui.net_layout = net.layout_players
	ui.family = net.map_family
	ui.size = net.map_size
	ui.seed_value = net.map_seed & 0xFFFFFFFF
	ui.start_credits = int(net.rules.get("start_credits", ui.start_credits))
	ui.unit_cap = int(net.rules.get("unit_cap", ui.unit_cap))
	ui.superweapons = int(net.rules.get("superweapons", 1)) != 0
	ui.fog = int(net.rules.get("fog", 1)) != 0
	ui.shared_vision = int(net.rules.get("shared_vision", 0)) != 0
	ui.veterancy = int(net.rules.get("veterancy", 0)) != 0
	ui.speed_pct = NetProtocol.SPEED_PCT[clampi(net.speed_code, 0, NetProtocol.SPEED_PCT.size() - 1)]
	ui.pause_policy = net.pause_policy
	ui.on_disconnect = net.on_disconnect
	ui.auto_drop_ms = net.auto_drop_ms
	ui.allow_spectators = net.allow_spectators
	ui.lobby_name = net.host_name
	ui.password_set = net.password_set
	ui.spectators = net.spectators.duplicate(true)
	for i: int in mini(UiLobbyState.MAX_SLOTS, net.slots.size()):
		var n: NetPlayerSlot = net.slots[i]
		var s: UiLobbyState.Slot = ui.slots[i]
		s.kind = kind_from_net(n.kind)
		s.ai_level = n.ai_level
		var pick: Vector2i = roster_pick(data, n.roster_id)
		s.faction = pick.x
		s.sub = pick.y
		s.team = n.team
		s.color = n.color
		s.start = n.start
		s.name = n.name
		s.handicap = n.handicap_pct
		s.peer_id = n.peer_id
		s.ready = n.ready or n.kind == NetProtocol.SlotKind.AI or n.peer_id == 1
		s.connected = n.connected
		s.ping_ms = n.ping_ms


# ---------------------------------------------------------------- permissions

## Whether `role` may edit the pickers of slot `index` (`local_slot` = the slot of this peer, -1 for a spectator). Open and closed
## rows have no pickers; the host edits every seated row, a client only its own.
static func can_edit_row(role: int, index: int, local_slot: int, ui: UiLobbyState) -> bool:
	if not ui.slots[index].active():
		return false
	match role:
		Role.HOST:
			return true
		Role.CLIENT:
			return index == local_slot
	return true


## Whether `role` may change the slot kind (Open / Closed / AI level) of row `index`: only the host, and never its own row.
static func can_edit_kind(role: int, index: int, local_slot: int) -> bool:
	return role == Role.LOCAL and index != 0 or role == Role.HOST and index != local_slot


# ---------------------------------------------------------------- UI model -> net calls

## The `NetLobby` calls that turn the authoritative state `net` into the UI model `ui` for `role`. Each entry is
## `{call: String, args: Array}`; unpermitted differences are dropped. A changed map (family / size / seed / layout) returns only the
## map call: the lobby itself opens / closes slots and clears the ready flags, and the caller pulls before anything else is compared.
static func diff(net: NetLobbyState, ui: UiLobbyState, role: int, local_slot: int) -> Array[Dictionary]:
	var ops: Array[Dictionary] = []
	var data: GameData = ui.data()
	if role == Role.HOST:
		if ui.family != net.map_family or ui.size != net.map_size or (ui.seed_value & 0xFFFFFFFF) != net.map_seed or ui.layout_players() != net.layout_players:
			ops.append(_op("host_set_map", [ui.family, ui.size, ui.seed_value & 0xFFFFFFFF, ui.layout_players()]))
			return ops
		var rules: Dictionary = {}
		var mine: Dictionary = {"start_credits": ui.start_credits, "unit_cap": ui.unit_cap, "superweapons": ui.superweapons, "fog": ui.fog,
			"shared_vision": ui.shared_vision, "veterancy": ui.veterancy}
		for key: String in RULE_KEYS:
			var want: Variant = mine[key]
			var have: int = int(net.rules.get(key, 0))
			if (int(want) if typeof(want) != TYPE_BOOL else (1 if bool(want) else 0)) != have:
				rules[key] = want
		if not rules.is_empty():
			ops.append(_op("host_set_rules", [rules]))
		var nopts: Dictionary = {}
		if ui.speed_pct != NetProtocol.SPEED_PCT[clampi(net.speed_code, 0, NetProtocol.SPEED_PCT.size() - 1)]:
			nopts["speed_pct"] = ui.speed_pct
		if ui.pause_policy != net.pause_policy:
			nopts["pause_policy"] = ui.pause_policy
		if ui.on_disconnect != net.on_disconnect:
			nopts["on_disconnect"] = ui.on_disconnect
		if ui.auto_drop_ms != net.auto_drop_ms:
			nopts["auto_drop_ms"] = ui.auto_drop_ms
		if ui.allow_spectators != net.allow_spectators:
			nopts["allow_spectators"] = ui.allow_spectators
		if not nopts.is_empty():
			ops.append(_op("host_set_net_options", [nopts]))
		for i: int in mini(UiLobbyState.MAX_SLOTS, net.slots.size()):
			_host_slot_ops(ops, net.slots[i], ui.slots[i], data, i)
	elif role == Role.CLIENT and local_slot >= 0 and local_slot < net.slots.size():
		var n: NetPlayerSlot = net.slots[local_slot]
		var s: UiLobbyState.Slot = ui.slots[local_slot]
		var want_roster: String = roster_token(data, s.faction, s.sub)
		if want_roster != "" and want_roster != n.roster_id:
			ops.append(_op("set_roster", [want_roster]))
		if s.team != n.team:
			ops.append(_op("set_team", [s.team]))
		if s.color != n.color:
			ops.append(_op("set_color", [s.color]))
		if s.start != n.start:
			ops.append(_op("set_start", [s.start]))
	return ops


static func _host_slot_ops(ops: Array[Dictionary], n: NetPlayerSlot, s: UiLobbyState.Slot, data: GameData, i: int) -> void:
	var have_kind: int = kind_from_net(n.kind)
	if s.kind != have_kind and s.kind != UiLobbyState.Kind.HUMAN:
		if n.kind == NetProtocol.SlotKind.HUMAN and n.peer_id == 1:
			return  # the host's own row never changes kind
		ops.append(_op("host_set_slot_kind", [i, kind_to_net(s.kind)]))
		if s.kind == UiLobbyState.Kind.AI and s.ai_level != 1:
			ops.append(_op("host_set_ai", [i, s.ai_level, 0]))
		return
	if not n.is_active():
		return
	if n.kind == NetProtocol.SlotKind.AI and s.ai_level != n.ai_level:
		ops.append(_op("host_set_ai", [i, s.ai_level, n.ai_style]))
	var want_roster: String = roster_token(data, s.faction, s.sub)
	if want_roster != "" and want_roster != n.roster_id:
		ops.append(_op("host_set_slot_roster", [i, want_roster]))
	if s.team != n.team:
		ops.append(_op("host_set_slot_team", [i, s.team]))
	if s.color != n.color:
		ops.append(_op("host_set_slot_color", [i, s.color]))
	if s.start != n.start:
		ops.append(_op("host_set_slot_start", [i, s.start]))
	if s.handicap != n.handicap_pct and s.handicap >= 50 and s.handicap <= 200:
		ops.append(_op("host_set_slot_handicap", [i, s.handicap]))


static func _op(call_name: String, args: Array) -> Dictionary:
	return {"call": call_name, "args": args}


## Runs the calls of `diff` on `lobby`; returns the first result that was not OK (`NetLobby.Result`), else OK.
static func execute(lobby: NetLobby, ops: Array[Dictionary]) -> int:
	var first_bad: int = NetLobby.Result.OK
	for op: Dictionary in ops:
		var r: int = int(lobby.callv(StringName(str(op["call"])), op["args"] as Array))
		if r != NetLobby.Result.OK and first_bad == NetLobby.Result.OK:
			first_bad = r
	return first_bad


## One line for a refused edit (`NetLobby.Result`).
static func result_text(result: int) -> String:
	match result:
		NetLobby.Result.DENIED:
			return "The host controls that setting."
		NetLobby.Result.INVALID:
			return "That value is not allowed."
		NetLobby.Result.LOCKED:
			return "The game is starting; settings are locked."
		NetLobby.Result.CONFLICT:
			return "That slot is not free."
		NetLobby.Result.FULL:
			return "There is no free slot."
	return ""


# ---------------------------------------------------------------- display helpers

## "READY" / "NOT READY" / "DISCONNECTED" / "HOST" / "AI" / "OPEN" / "CLOSED" for a row, and the theme variation to draw it with.
static func status_of(s: UiLobbyState.Slot) -> Dictionary:
	match s.kind:
		UiLobbyState.Kind.HUMAN:
			if not s.connected:
				return {"text": "DISCONNECTED", "variation": &"DangerLabel"}
			if s.peer_id == 1:
				return {"text": "HOST", "variation": &"OkLabel"}
			if s.ready:
				return {"text": "READY", "variation": &"OkLabel"}
			return {"text": "NOT READY", "variation": &"WarnLabel"}
		UiLobbyState.Kind.AI:
			return {"text": "READY", "variation": &"OkLabel"}
		UiLobbyState.Kind.OPEN:
			return {"text": "OPEN", "variation": &"MuteLabel"}
	return {"text": "CLOSED", "variation": &"MuteLabel"}


## "23 ms" for a seated remote human, "" otherwise.
static func ping_text(s: UiLobbyState.Slot) -> String:
	if s.kind == UiLobbyState.Kind.HUMAN and s.peer_id != 1 and s.connected and s.ping_ms > 0:
		return "%d ms" % s.ping_ms
	return ""


## The rows the start error of `NetLobby.StartError` points at (5.14.4): a slot index list, or empty for a whole-panel error.
static func error_rows(err: int, ui: UiLobbyState) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	match err:
		UiLobbyState.Err.HUMAN_NOT_READY:
			for i: int in UiLobbyState.MAX_SLOTS:
				var s: UiLobbyState.Slot = ui.slots[i]
				if s.kind == UiLobbyState.Kind.HUMAN and s.peer_id != 1 and not s.ready:
					out.append(i)
		UiLobbyState.Err.HUMAN_DISCONNECTED:
			for i: int in UiLobbyState.MAX_SLOTS:
				if ui.slots[i].kind == UiLobbyState.Kind.HUMAN and not ui.slots[i].connected:
					out.append(i)
		UiLobbyState.Err.NOT_ENOUGH_PLAYERS:
			for i: int in UiLobbyState.MAX_SLOTS:
				if ui.slots[i].kind == UiLobbyState.Kind.OPEN:
					out.append(i)
					break
		UiLobbyState.Err.SINGLE_TEAM, UiLobbyState.Err.COLOR_CONFLICT, UiLobbyState.Err.START_CONFLICT, UiLobbyState.Err.BAD_ROSTER:
			for i: int in UiLobbyState.MAX_SLOTS:
				if ui.slots[i].active():
					out.append(i)
	return out
