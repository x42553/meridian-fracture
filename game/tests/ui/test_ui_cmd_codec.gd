extends RefCounted
## Golden commands of ui.md 6.1 (strings from `describe`, exact int arrays from the `SimCmd` builders).


func _ids(a: Array) -> PackedInt32Array:
	return PackedInt32Array(a)


func _golden(t: TestCtx, cmd: PackedInt32Array, text: String, ints: Array) -> void:
	t.eq(UiCmdCodec.describe(cmd), text)
	t.eq(cmd, PackedInt32Array(ints), text)


func test_goldens_unit_orders(t: TestCtx) -> void:
	_golden(t, UiCmdCodec.move(_ids([7, 3, 12]), 15360, 30720, true), "MOVE ids=[3,7,12] x=15360 y=30720 mode=1 flags=0", [1, 15360, 30720, 1, 0, 3, 7, 12])
	_golden(t, UiCmdCodec.attack(_ids([41]), 907, false), "ATTACK ids=[41] target=907 mode=0 flags=0", [40, 907, 0, 0, 41])
	_golden(t, UiCmdCodec.attack(_ids([5, 6]), 1203, false, true), "ATTACK ids=[5,6] target=1203 mode=0 flags=1", [40, 1203, 0, 1, 5, 6])
	_golden(t, UiCmdCodec.force_fire(_ids([5, 6]), 0, 20480, 20480), "FORCE_FIRE ids=[5,6] target=0 x=20480 y=20480 count=0", [44, 0, 20480, 20480, 0, 5, 6])
	_golden(t, UiCmdCodec.set_stance(_ids([2, 9]), 1), "SET_STANCE ids=[2,9] mode=1", [45, 1, 2, 9])
	_golden(t, UiCmdCodec.guard(_ids([4]), 0, 20480, 10240, false), "GUARD ids=[4] target=0 x=20480 y=10240 mode=0", [42, 0, 20480, 10240, 0, 4])
	_golden(t, UiCmdCodec.patrol(_ids([4, 8]), 30720, 40960, true), "PATROL ids=[4,8] x=30720 y=40960 mode=1 flags=0", [4, 30720, 40960, 1, 0, 4, 8])
	_golden(t, UiCmdCodec.attack_move(_ids([5, 6]), 20480, 10240, false), "ATTACK_MOVE ids=[5,6] x=20480 y=10240 mode=0 flags=0", [41, 20480, 10240, 0, 0, 5, 6])
	_golden(t, UiCmdCodec.move(_ids([7, 3, 12]), 15360, 30720, true, UiCmdCodec.MF_SPEED_MATCH), "MOVE ids=[3,7,12] x=15360 y=30720 mode=1 flags=2", [1, 15360, 30720, 1, 2, 3, 7, 12])
	_golden(t, UiCmdCodec.follow(_ids([5, 6]), 1203, false), "FOLLOW ids=[5,6] target=1203 mode=0", [12, 1203, 0, 5, 6])
	_golden(t, UiCmdCodec.return_to_base(_ids([21, 22]), 640, false), "RETURN_TO_BASE ids=[21,22] target=640 mode=0", [47, 640, 0, 21, 22])
	_golden(t, UiCmdCodec.return_to_base(_ids([21, 22]), 0, false), "RETURN_TO_BASE ids=[21,22] target=0 mode=0", [47, 0, 0, 21, 22])
	_golden(t, UiCmdCodec.harvest(_ids([9]), 49664, 17920, false), "HARVEST ids=[9] target=0 x=49664 y=17920 mode=0", [10, 0, 49664, 17920, 0, 9])
	_golden(t, UiCmdCodec.hold(_ids([4])), "HOLD ids=[4]", [43, 4])


func test_goldens_abilities(t: TestCtx) -> void:
	_golden(t, UiCmdCodec.unload(_ids([70]), true, 0, 66560, 30720), "UNLOAD ids=[70] mode=0 target=0 x=66560 y=30720", [105, 0, 0, 66560, 30720, 70])
	_golden(t, UiCmdCodec.set_mode(_ids([12]), 1, 1), "SET_MODE ids=[12] def=1 mode=1", [102, 1, 1, 12])
	_golden(t, UiCmdCodec.deploy(_ids([6])), "DEPLOY ids=[6] def=-1", [100, -1, 6])
	_golden(t, UiCmdCodec.use_ability(_ids([12]), 2, 0, 5000, 6000), "USE_ABILITY ids=[12] def=2 mode=0 target=0 x=5000 y=6000", [103, 2, 0, 0, 5000, 6000, 12])
	_golden(t, UiCmdCodec.cancel_ability(_ids([12]), 2), "USE_ABILITY ids=[12] def=2 mode=1 target=0 x=-1 y=-1", [103, 2, 1, 0, -1, -1, 12])


func test_goldens_economy(t: TestCtx) -> void:
	_golden(t, UiCmdCodec.train(88, 17, 5), "TRAIN target=88 def=17 count=5", [124, 88, 17, 5])
	_golden(t, UiCmdCodec.train_cancel(88, 1), "TRAIN_CANCEL target=88 mode=1", [125, 88, 1])
	_golden(t, UiCmdCodec.queue_hold(UiCmdCodec.Hold.PRODUCER, _ids([88]), true), "QUEUE_HOLD ids=[88] mode=1", [126, 1, 88])
	_golden(t, UiCmdCodec.queue_hold(UiCmdCodec.Hold.CONSTRUCTION, PackedInt32Array(), true), "BUILD_HOLD mode=1", [122, 1])
	_golden(t, UiCmdCodec.queue_hold(UiCmdCodec.Hold.RESEARCH, PackedInt32Array(), false), "RESEARCH_HOLD mode=0", [131, 0])
	_golden(t, UiCmdCodec.build_place(9, 30, 41, 1), "BUILD_PLACE def=9 x=30 y=41 mode=1", [123, 9, 30, 41, 1])
	_golden(t, UiCmdCodec.use_power(1, 65536, 40960, 1024), "USE_POWER def=1 x=65536 y=40960 angle=1024 target=0", [140, 1, 65536, 40960, 1024, 0])
	_golden(t, UiCmdCodec.set_rally(_ids([88, 90]), 10240, 12288), "SET_RALLY ids=[88,90] x=10240 y=12288 target=0 flags=0", [127, 10240, 12288, 0, 0, 88, 90])
	_golden(t, UiCmdCodec.sell(_ids([31, 32])), "SELL ids=[31,32]", [132, 31, 32])
	_golden(t, UiCmdCodec.build_start(9, 1), "BUILD_START def=9 count=1", [120, 9, 1])
	_golden(t, UiCmdCodec.build_cancel(0), "BUILD_CANCEL mode=0", [121, 0])
	_golden(t, UiCmdCodec.set_struct_repair(_ids([31]), 1), "SET_STRUCT_REPAIR ids=[31] mode=1", [133, 1, 31])
	_golden(t, UiCmdCodec.undeploy_hq(_ids([31])), "UNDEPLOY_HQ ids=[31]", [134, 31])
	_golden(t, UiCmdCodec.launch_superweapon(100, 200, 4095), "LAUNCH_SUPERWEAPON x=100 y=200 angle=4095", [141, 100, 200, 4095])
	_golden(t, UiCmdCodec.set_rally(_ids([88]), 0, 0, 0, true), "SET_RALLY ids=[88] x=0 y=0 target=0 flags=1", [127, 0, 0, 0, 1, 88])
	_golden(t, UiCmdCodec.research(3), "RESEARCH def=3", [129, 3])
	_golden(t, UiCmdCodec.set_primary(88), "SET_PRIMARY target=88", [128, 88])


func test_verify_against_sim(t: TestCtx) -> void:
	t.eq(UiCmdCodec.verify_against_sim(), PackedStringArray(), "every op known, layouts as assumed")


func test_queue_mode_only_on_flagged_ops(t: TestCtx) -> void:
	var q_ops: Array[PackedInt32Array] = [
		UiCmdCodec.move(_ids([1]), 0, 0, true), UiCmdCodec.patrol(_ids([1]), 0, 0, true), UiCmdCodec.load_units(_ids([1]), 2, true),
		UiCmdCodec.garrison(_ids([1]), 2, true), UiCmdCodec.capture(_ids([1]), 2, true), UiCmdCodec.repair(_ids([1]), 2, true),
		UiCmdCodec.salvage(_ids([1]), 2, true), UiCmdCodec.harvest(_ids([1]), 0, 0, true), UiCmdCodec.return_cargo(_ids([1]), 2, true),
		UiCmdCodec.follow(_ids([1]), 2, true), UiCmdCodec.attack(_ids([1]), 2, true), UiCmdCodec.attack_move(_ids([1]), 0, 0, true),
		UiCmdCodec.guard(_ids([1]), 2, 0, 0, true), UiCmdCodec.return_to_base(_ids([1]), 2, true),
	]
	for cmd: PackedInt32Array in q_ops:
		t.check(UiCmdCodec.describe(cmd).contains("mode=1"), "Shift appends: %s" % UiCmdCodec.describe(cmd))
	t.eq(UiCmdCodec.queue_mode(SimCmd.FORCE_FIRE, true), 0, "force_fire has no queue mode")
	t.eq(UiCmdCodec.queue_mode(SimCmd.DEPLOY, true), 0)
	t.eq(UiCmdCodec.queue_mode(SimCmd.TRAIN, true), 0)
	t.eq(UiCmdCodec.queue_mode(SimCmd.STOP, true), 0)
	t.eq(UiCmdCodec.queue_mode(SimCmd.MOVE, false), 0)


func test_split_ids(t: TestCtx) -> void:
	var ids450: PackedInt32Array = PackedInt32Array()
	for i: int in 450:
		ids450.append(i + 1)
	t.eq(UiCmdCodec.split_ids(ids450).size(), 1, "450 ids are one chunk")
	var ids600: PackedInt32Array = PackedInt32Array()
	for i: int in 600:
		ids600.append(600 - i)
	var chunks: Array[PackedInt32Array] = UiCmdCodec.split_ids(ids600)
	t.eq(chunks.size(), 2)
	t.eq(chunks[0].size(), 512)
	t.eq(chunks[1].size(), 88)
	t.eq(chunks[0][0], 1, "chunks are ascending")
	t.eq(chunks[1][87], 600)
	t.eq(UiCmdCodec.move(ids450, 0, 0, false).size(), 1 + 4 + 450, "STOP-sized commands stay one array")


func test_world_and_minimap_to_sim(t: TestCtx) -> void:
	t.eq(UiCmdCodec.world_to_sim(45.0, 90.0, 128, 128), Vector2i(15360, 30720))
	t.eq(UiCmdCodec.world_to_sim(45.7, 90.1, 128, 128), Vector2i(15599, 30754))
	t.eq(UiCmdCodec.world_to_sim(-10.0, -1.0, 128, 128), Vector2i(0, 0))
	t.eq(UiCmdCodec.world_to_sim(9999.0, 9999.0, 128, 128), Vector2i(131071, 131071))
	t.eq(UiCmdCodec.norm_to_sim(0.5, 0.5, 128, 128), Vector2i(65536, 65536))
	t.eq(UiCmdCodec.norm_to_sim(2.0, -1.0, 128, 128), Vector2i(131071, 0))
	t.eq(UiCmdCodec.angle_of(0.0, 1.0), 1024, "atan2(1,0) = quarter turn = 1024")
	t.eq(UiCmdCodec.angle_of(1.0, 0.0), 0)
	t.eq(UiCmdCodec.angle_of(-1.0, 0.0), 2048)
	t.eq(UiCmdCodec.angle_of(0.0, -1.0), 3072)
	t.eq(UiCmdCodec.cell_center(48), 49664)
	t.eq(UiCmdCodec.cell_center(17), 17920)


func test_describe_edge_cases(t: TestCtx) -> void:
	t.eq(UiCmdCodec.describe(PackedInt32Array()), "EMPTY")
	t.check(UiCmdCodec.describe(PackedInt32Array([9999, 1, 2])).begins_with("OP9999"))
	t.eq(UiCmdCodec.describe(SimCmd.stop(_ids([9, 9, 4]))), "STOP ids=[4,9]", "the builder sorts and de-duplicates ids")


func test_builders_equal_sim_builders(t: TestCtx) -> void:
	t.eq(UiCmdCodec.train(1, 2, 3), SimCmd.train(1, 2, 3))
	t.eq(UiCmdCodec.build_place(1, 2, 3, 2), SimCmd.build_place(1, 2, 3, 2))
	t.eq(UiCmdCodec.set_autocast(_ids([3]), 1, true), SimCmd.set_autocast(_ids([3]), 1, 1))
	t.eq(UiCmdCodec.set_autocast(_ids([3]), 1, false), SimCmd.set_autocast(_ids([3]), 1, 0))
	t.eq(UiCmdCodec.unload(_ids([3]), false, 55, 1, 2), SimCmd.unload(_ids([3]), 1, 55, 1, 2))
