extends RefCounted
## VIEW-M9 wiring: build cards, queue strip and the selection portrait ask the view for baked icons (`request_icon`), keep the
## glyph placeholder until an icon is ready, and pick it up on `icon_ready`. A view without icons (the fixture) is untouched.

const H := preload("res://tests/ui/ui_harness.gd")
const _Rig := preload("res://tests/ui/ui_hud_rig.gd")


class IconView extends UiViewPortFixture:
	var ready_tex: Dictionary = {}  ## "def|size" -> Texture2D
	var asked: Array[Array] = []

	func icons_available() -> bool:
		return true

	func request_icon(def_id: String, roster_id: String, size: int) -> Texture2D:
		asked.append([def_id, roster_id, size])
		return ready_tex.get("%s|%d" % [def_id, size]) as Texture2D

	func prewarm() -> void:
		asked.append(["prewarm"])


func _tex(c: Color) -> Texture2D:
	var img: Image = Image.create(8, 8, false, Image.FORMAT_RGBA8)
	img.fill(c)
	return ImageTexture.create_from_image(img)


func _rig() -> Array:
	var h: H.Rig = await H.make(Vector2i(1920, 1080))
	var r: _Rig = _Rig.new()
	r.build(h.root, {"seed": 3, "warm": 300, "render": false})
	await H.frames(2)
	return [h, r]


func test_cards_ask_for_card_icons_and_take_them_on_icon_ready(t: TestCtx) -> void:
	var a: Array = await _rig()
	var h: H.Rig = a[0]
	var r: _Rig = a[1]
	var fv: IconView = IconView.new(r.sim, 0.0, false)
	r.presenter._view = fv
	fv.icon_ready.connect(r.presenter._on_icon_ready)
	r.presenter._apply_icons()
	t.gt(fv.asked.size(), 5, "structure and unit cards ask for icons")
	for q: Array in fv.asked:
		t.eq(q[2], UiViewPort.ICON_SIZE_CARD, "cards use the CARD size")
		t.eq(q[1], r.roster.id, "in the style of the local roster")
	var first: UiBuildItem = null
	for it: UiBuildItem in r.presenter.model().items(UiBuildModel.Tab.STRUCTURES):
		t.is_null(it.icon, "no icon yet: the glyph placeholder stays")
		if first == null:
			first = it
	var tex: Texture2D = _tex(Color.RED)
	fv.ready_tex["%s|%d" % [first.id, UiViewPort.ICON_SIZE_CARD]] = tex
	fv.icon_ready.emit(&"x")
	t.check(first.icon == tex, "icon_ready hands the texture to the card")
	for it2: UiBuildItem in r.presenter.model().items(UiBuildModel.Tab.POWERS):
		t.check(it2.kind != UiBuildItem.Kind.STRUCTURE and it2.kind != UiBuildItem.Kind.UNIT, "only the powers tab here")
		t.is_null(it2.icon, "powers keep their glyph")
	for q2: Array in fv.asked:
		t.check(not str(q2[0]).begins_with("power."), "no icon request for a power")
	H.done(h)


func test_plain_view_keeps_glyphs(t: TestCtx) -> void:
	var a: Array = await _rig()
	var h: H.Rig = a[0]
	var r: _Rig = a[1]
	for tab: int in UiBuildModel.TAB_COUNT:
		for it: UiBuildItem in r.presenter.model().items(tab):
			t.is_null(it.icon, "the fixture view bakes nothing: %s stays a glyph" % it.id)
	H.done(h)


func test_selection_entry_carries_a_banner_portrait(t: TestCtx) -> void:
	var a: Array = await _rig()
	var h: H.Rig = a[0]
	var r: _Rig = a[1]
	var fv: IconView = IconView.new(r.sim, 0.0, false)
	r.presenter._view = fv
	var ids: PackedInt32Array = r.own(UiSimPort.KM_STRUCTURE)
	t.gt(ids.size(), 0, "own structures exist")
	var e: Dictionary = r.presenter._entry_of(ids[0])
	t.check(e.has("portrait"), "entry has a portrait slot")
	var banner_asked: bool = false
	for q: Array in fv.asked:
		banner_asked = banner_asked or (q.size() > 2 and q[2] == UiViewPort.ICON_SIZE_BANNER)
	t.check(banner_asked, "the portrait is a BANNER (2:1) request")
	fv.ready_tex["%s|%d" % [fv.asked[fv.asked.size() - 1][0], UiViewPort.ICON_SIZE_BANNER]] = _tex(Color.BLUE)
	var e2: Dictionary = r.presenter._entry_of(ids[0])
	t.check(e2["portrait"] is Texture2D, "and returns the baked banner once ready")
	H.done(h)


class MenuIcons extends UiViewPortWorld:
	var tex: Texture2D = null
	var asked: Array[String] = []

	func request_icon(def_id: String, roster_id: String, size: int) -> Texture2D:
		asked.append("%s|%s|%d" % [def_id, roster_id, size])
		return tex


func _find_texture_rect(n: Node) -> TextureRect:
	if n is TextureRect:
		return n as TextureRect
	for c: Node in n.get_children():
		var f: TextureRect = _find_texture_rect(c)
		if f != null:
			return f
	return null


func test_field_manual_head_shows_the_baked_portrait(t: TestCtx) -> void:
	var h: H.Rig = await H.make(Vector2i(1920, 1080))
	var scr: UiScreenFieldManual = UiScreenFieldManual.new()
	h.root.add_child(scr)
	UiLayerRoot.fill(scr)
	scr.enter({"roster_id": "roster.napc.canada", "page": &"overview", "focus_id": "unit.napc.rifle_squad", "data": GameData.load_default()})
	await H.frames(2)
	var mi: MenuIcons = MenuIcons.new(null)
	scr._icons = mi
	mi.icon_ready.connect(scr._on_icon_ready)
	scr._render_detail()
	t.gt(mi.asked.size(), 0, "the card asks for its portrait")
	t.check(mi.asked[0].ends_with("|roster.napc.canada|%d" % UiViewPort.ICON_SIZE_PORTRAIT), "PORTRAIT size in the roster's style: %s" % mi.asked[0])
	t.is_null(_find_texture_rect(scr._detail_box), "no picture while the icon is being baked (the glyph tile stays)")
	mi.tex = _tex(Color.GREEN)
	mi.icon_ready.emit(StringName("unit.napc.rifle_squad|roster.napc.canada|%d" % UiViewPort.ICON_SIZE_PORTRAIT))
	await H.frames(1)
	var pic: TextureRect = _find_texture_rect(scr._detail_box)
	t.not_null(pic, "icon_ready redraws the card with the portrait")
	if pic != null:
		t.check(pic.texture == mi.tex, "the baked texture")
	scr.exit()
	H.done(h)
