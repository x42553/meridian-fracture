extends RefCounted
## Checksum vectors of sim_core 10.1.


func test_fnv_bytes(t: TestCtx) -> void:
	t.eq(Checksum.fnv_bytes("foobar".to_utf8_buffer()), 0xBF9CF968, "fnv(foobar)")
	t.eq(Checksum.fnv_bytes("a".to_utf8_buffer()), 0xE40C292C, "fnv(a)")
	t.eq(Checksum.fnv_bytes(PackedByteArray()), 0x811C9DC5, "fnv(empty)")
	t.eq(Checksum.fnv_string("foobar"), 0xBF9CF968, "fnv_string")


func test_mix64(t: TestCtx) -> void:
	for v: int in [-2, 5000000000]:
		var want: int = Checksum.mix(Checksum.mix(Checksum.FNV_OFFSET, v & 0xFFFFFFFF), (v >> 32) & 0xFFFFFFFF)
		t.eq(Checksum.mix64(Checksum.FNV_OFFSET, v), want, "mix64(%d)" % v)


func test_accumulator(t: TestCtx) -> void:
	var c: Checksum = Checksum.new()
	c.add(1)
	c.add(-1)
	c.add64(-2)
	c.add64(5000000000)
	t.eq(c.h, 0x29A072D1, "raw state")
	t.eq(c.value(), 0xE1C8E810, "finalised")
	c.reset()
	t.eq(c.h, Checksum.FNV_OFFSET, "reset")


func test_digest32(t: TestCtx) -> void:
	var a: PackedInt32Array = PackedInt32Array([1, 2, 3, -4, 100000])
	t.eq(Checksum.digest32(a), 0xDB16CE4B, "digest32")
	t.eq(Checksum.digest32(a), 3675704907, "digest32 decimal")
	t.eq(Checksum.digest32(PackedInt32Array()), Checksum.EMPTY_DIGEST, "empty")
	t.eq(Checksum.EMPTY_DIGEST, 3649838548, "EMPTY_DIGEST decimal")
	t.eq(Checksum.digest32_bytes(PackedByteArray()), Checksum.EMPTY_DIGEST, "empty bytes")


func test_add_packed(t: TestCtx) -> void:
	var c: Checksum = Checksum.new()
	c.add_packed(PackedInt32Array([1, 2, 3, -4, 100000]))
	t.eq(c.h, 0xE08A87EE, "add_packed raw")


func test_scratch_context_is_stateless(t: TestCtx) -> void:
	var a: PackedInt32Array = PackedInt32Array([7, 8, 9])
	var d1: int = Checksum.digest32(a)
	Checksum.digest32(PackedInt32Array([1]))
	t.eq(Checksum.digest32(a), d1, "same digest after interleaved use")
