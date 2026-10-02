extends RefCounted
## VIEW-03: fog-of-war feed (byte-grid contract, ping-pong textures, cross-fade, modes, SimFogApi sync) and the fog globals.

const FogFx := preload("res://tests/fixtures/view_fog_fixture.gd")


func _fog(w: int = 48, h: int = 40) -> ViewFogOfWar:
	var f: ViewFogOfWar = ViewFogOfWar.new()
	f.setup(w, h, Vector2(12.0, -6.0), 3.0)
	return f


func test_globals_published_by_setup(t: TestCtx) -> void:
	var f: ViewFogOfWar = _fog(48, 40)
	var r: Vector4 = f.rect
	t.near(r.x, 12.0, 1e-4, "fow_rect origin x")
	t.near(r.y, -6.0, 1e-4, "fow_rect origin z")
	t.near(r.z, 1.0 / (48.0 * 3.0), 1e-6, "fow_rect 1 / size.x")
	t.near(r.w, 1.0 / (40.0 * 3.0), 1e-6, "fow_rect 1 / size.z")
	t.eq(f.current_bytes(), FogFx.uniform(48, 40, 0), "fresh textures are all shroud")


func test_submit_is_raw_bytes_and_pingpongs(t: TestCtx) -> void:
	var f: ViewFogOfWar = _fog()
	var a: PackedByteArray = FogFx.discs(48, 40, [Vector2i(10, 10)], 6.0, 12.0)
	var b: PackedByteArray = FogFx.discs(48, 40, [Vector2i(30, 20)], 6.0, 12.0)
	var tex0: ImageTexture = f.current_texture()
	f.submit(a)
	var tex1: ImageTexture = f.current_texture()
	t.check(tex1 != tex0, "submit flips to the other texture")
	t.eq(f.current_bytes(), a, "uploaded bytes == sim bytes (no conversion)")
	f.submit(b)
	t.check(f.current_texture() == tex0, "second submit flips back")
	t.eq(f.current_bytes(), b, "second grid uploaded")
	t.eq(f.blend(), 0.0, "blend restarts at 0")
	t.eq(f.uploads, 2, "upload counter")
	f.submit(PackedByteArray([1, 2, 3]))
	t.eq(f.uploads, 2, "a wrong-sized grid is ignored")


func test_crossfade_100ms(t: TestCtx) -> void:
	var f: ViewFogOfWar = _fog()
	f.submit(FogFx.uniform(48, 40, 2))
	f.advance(0.05)
	t.near(f.blend(), 0.5, 1e-4, "half way after 50 ms")
	f.advance(0.2)
	t.eq(f.blend(), 1.0, "clamped at 1 after 100 ms")


func test_sync_uploads_only_on_version_change(t: TestCtx) -> void:
	var f: ViewFogOfWar = _fog()
	var api: FogFx.Api = FogFx.Api.new()
	t.check(not f.sync(api, 0), "default (empty) bytes: nothing to upload")
	api.set_bytes(FogFx.discs(48, 40, [Vector2i(5, 5)], 4.0, 8.0))
	t.check(f.sync(api, 0), "first version uploads")
	t.check(not f.sync(api, 0), "same version: no upload")
	api.set_bytes(FogFx.uniform(48, 40, 1))
	t.check(f.sync(api, 0), "new version uploads")
	t.eq(f.current_bytes(), FogFx.uniform(48, 40, 1), "new bytes visible")
	t.eq(f.uploads, 2, "two uploads")


func test_modes(t: TestCtx) -> void:
	var f: ViewFogOfWar = _fog()
	var api: FogFx.Api = FogFx.Api.new()
	api.set_bytes(FogFx.uniform(48, 40, 1))
	f.set_mode(ViewFogOfWar.MODE_SHROUD_FOG)
	t.eq(f.fog_dim, 1.0, "mode 2: fog dimmed")
	f.set_mode(ViewFogOfWar.MODE_EXPLORED_VISIBLE)
	t.eq(f.fog_dim, 0.0, "mode 1: explored undimmed")
	t.check(f.sync(api, 0), "mode 1 still uploads sim bytes")
	f.set_mode(ViewFogOfWar.MODE_NONE)
	t.eq(f.current_bytes(), FogFx.uniform(48, 40, 2), "mode 0: all-visible texture")
	t.check(not f.sync(api, 0), "mode 0: sync uploads nothing")
	f.set_mode(ViewFogOfWar.MODE_SHROUD_FOG)
	f.set_enabled(false)
	t.eq(f.current_bytes(), FogFx.uniform(48, 40, 2), "observer: all visible")
	t.check(not f.sync(api, 0), "disabled: no upload")
	f.set_enabled(true)
	t.check(f.sync(api, 0), "re-enabled: uploads again")
	f.set_local_player(-1)
	t.eq(f.current_bytes(), FogFx.uniform(48, 40, 2), "observer pid -1 shows everything")
	t.check(not f.sync_local(api), "observer never syncs")


func test_upload_cost(t: TestCtx) -> void:
	var f: ViewFogOfWar = _fog(192, 192)
	var g: PackedByteArray = FogFx.discs(192, 192, [Vector2i(90, 90)], 30.0, 50.0)
	var best: int = 1 << 30
	for i: int in 20:
		f.submit(g)
		best = mini(best, f.last_upload_us)
	t.note("192^2 fog upload best of 20: %d us" % best)
	t.lt(best, 800, "192^2 fog submit stays far below a frame (spike 4-12 us)")
