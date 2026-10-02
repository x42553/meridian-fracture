class_name UiDlgFirewallHelp
extends UiDialog
## The one-time explainer before the first LAN socket is opened (ui.md 5.15, net.md 5.13): what the operating system is about to ask
## (Windows Defender Firewall / the macOS "Local Network" permission / a Debian firewall rule) and which ports the game uses. The
## text is chosen by `AppLan.platform_key(OS.get_name())`; `platform` overrides it for tests and screenshots. `closed(1)` = Got it,
## `closed(0)` = Esc. The caller stores `net/help_shown` (`AppLan.mark_help_shown`) and only then starts browsing or hosting.

const RESULT_OK: int = 1


func _init(platform: String = "") -> void:
	super._init("Before you play over the network", 560)
	var key: String = platform if platform != "" else AppLan.platform_key()
	var t: Dictionary = AppLan.firewall_text(key)
	var head: Label = add_text(str(t["title"]).to_upper(), &"HeaderLabel")
	head.custom_minimum_size = Vector2.ZERO
	add_text(str(t["body"]))
	add_text(str(t["ports"]), &"DimLabel")
	add_button("Got it", RESULT_OK, &"primary")


## Builds the dialog and puts it on the modal stack of `AppScenes` (no-op without it); returns it.
static func open(platform: String = "") -> UiDlgFirewallHelp:
	var d: UiDlgFirewallHelp = UiDlgFirewallHelp.new(platform)
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var scenes: Node = tree.root.get_node_or_null("AppScenes") if tree != null else null
	if scenes != null:
		scenes.call("modal", d)
	return d
