#!/usr/bin/env python3
"""Generate docs/CONTROLS.md from game/data/ui/keymap_defaults.json (+ action names from src/ui/ui_action_names.gd).

    python3 tools/py/gen_controls_doc.py            # rewrites docs/CONTROLS.md
"""
from __future__ import annotations

import json
import re
from collections import OrderedDict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
KEYMAP = ROOT / "game/data/ui/keymap_defaults.json"
NAMES = ROOT / "game/src/ui/ui_action_names.gd"
OUT = ROOT / "docs/CONTROLS.md"
GAME_SCREEN = ROOT / "game/src/ui/ui_screen_game.gd"
OBSERVER_CTL = ROOT / "game/src/ui/ui_observer_controller.gd"
INPUT_CTL = ROOT / "game/src/ui/ui_input_controller.gd"
# the camera keys the input controller polls itself every frame (Input.is_action_pressed)
POLLED = {"cam_pan_left", "cam_pan_right", "cam_pan_up", "cam_pan_down", "cam_rotate_left", "cam_rotate_right", "cam_orbit"}

MOUSE_BUTTON = {1: "Left mouse button", 2: "Right mouse button", 3: "Middle mouse button"}


def parse_names() -> tuple[dict, list, dict, list]:
    src = NAMES.read_text(encoding="utf-8")
    names = dict(re.findall(r'"([a-z0-9_]+)":\s*"([^"]*)"', src.split("const NAMES")[1].split("const FAMILIES")[0]))
    families = re.findall(r'\["([a-z0-9_]+)",\s*"([^"]*)"\]', src.split("const FAMILIES")[1].split("static func")[0])
    order = re.findall(r'"([a-z]+)"', src.split("const CATEGORY_ORDER")[1].split("\n")[0])
    titles = dict(re.findall(r'"([a-z]+)":\s*"([^"]*)"', src.split("const CATEGORY_TITLES")[1].split("const NAMES")[0]))
    return names, families, titles, order


def wired_ids() -> set:
    """Action ids that something in the game actually handles. A keymap row is only a registered binding: the key does
    something only when `UiScreenGame._on_action` (match), `UiObserverController.handle_action` (observer / replay) or the
    input controller's dispatch names the id. Static scan of those three functions, so the generated tables follow the code."""
    out: set = set()
    g = GAME_SCREEN.read_text(encoding="utf-8")
    seg = g[g.index("func _on_action"):g.index("## Manual camera input")]
    out |= set(re.findall(r'&"([a-z_0-9]+)"', seg))
    o = OBSERVER_CTL.read_text(encoding="utf-8")
    out |= set(re.findall(r'&"([a-z_0-9]+)"', o[o.index("func handle_action"):]))
    c = INPUT_CTL.read_text(encoding="utf-8")
    out |= set(re.findall(r'&"([a-z_0-9]+)"', c[c.index("func _dispatch_action"):c.index("func _handled")]))
    return out


def observer_only_ids() -> set:
    """Actions that only the observer controller handles (a normal match ignores them even though the keymap lists the game context)."""
    g = GAME_SCREEN.read_text(encoding="utf-8")
    seg = g[g.index("func _on_action"):g.index("## Manual camera input")]
    in_game = set(re.findall(r'&"([a-z_0-9]+)"', seg))
    o = OBSERVER_CTL.read_text(encoding="utf-8")
    return set(re.findall(r'&"([a-z_0-9]+)"', o[o.index("func handle_action"):])) - in_game


def wired_prefixes() -> tuple:
    """Indexed families the game screen / observer controller dispatch by prefix (`UiActions.indexed(id, "power_")`)."""
    g = GAME_SCREEN.read_text(encoding="utf-8")
    o = OBSERVER_CTL.read_text(encoding="utf-8")
    seg = g[g.index("func _on_action"):g.index("## Manual camera input")] + o[o.index("func handle_action"):]
    return tuple(sorted(set(re.findall(r'indexed\(id,\s*"([a-z_0-9]+)"\)', seg))))


WIRED = wired_ids()
OBS_ONLY = observer_only_ids()
WIRED_PREFIXES = wired_prefixes()


def is_wired(aid: str) -> bool:
    return aid in WIRED or aid in POLLED or any(aid.startswith(p) for p in WIRED_PREFIXES)


def dag(aid: str) -> str:
    """Marker appended to a key mentioned in the prose when its action is not connected."""
    return "" if is_wired(aid) else " (\u2020)"


def label(aid: str, names: dict, families: list) -> str:
    if aid in names:
        return names[aid]
    for prefix, fmt in families:
        if aid.startswith(prefix) and aid[len(prefix):].isdigit():
            return fmt.replace("%s", aid[len(prefix):])
    m = re.match(r"card_5x_(\d+)$", aid)
    if m:
        return f"Build card {m.group(1)} (queue 5)"
    m = re.match(r"card_(\d+)$", aid)
    if m:
        return f"Build card {m.group(1)}"
    return aid.replace("_", " ").capitalize()


def main() -> None:
    names, families, titles, order = parse_names()
    actions = json.loads(KEYMAP.read_text(encoding="utf-8"))["actions"]
    by_cat: "OrderedDict[str, list]" = OrderedDict((c, []) for c in order)
    for a in actions:
        by_cat.setdefault(a["category"], []).append(a)
    # collapse numbered families into one row
    lines: list[str] = []
    for cat, items in by_cat.items():
        if not items:
            continue
        lines.append(f"### {titles.get(cat, cat.title())}\n")
        lines.append("| Action | Default key | Notes |")
        lines.append("|---|---|---|")
        seen_fam: dict[str, list] = {}
        rows: list[tuple[str, str, str]] = []
        for a in items:
            aid = a["id"]
            keys = a.get("keys") or []
            keytxt = " / ".join(f"`{k}`" for k in keys)
            if a.get("mouse"):
                keytxt = " / ".join(MOUSE_BUTTON.get(b, f"mouse {b}") for b in a["mouse"]) + " (drag)"
            notes = []
            if a.get("mac_keys") and a["mac_keys"] != keys:
                notes.append("macOS also: " + " / ".join(f"`{k}`" for k in a["mac_keys"]))
            elif a.get("mac_keys"):
                notes.append("macOS: `Cmd` variant also bound")
            if "observer" in a.get("contexts", []) and "game" not in a["contexts"]:
                notes.append("observer/replay only")
            elif a.get("contexts") == ["global"]:
                notes.append("everywhere")
            if not is_wired(aid):
                notes.append("\u2020 not connected in this build")
            elif aid in OBS_ONLY and "observer/replay only" not in notes and aid != "obs_pause":
                notes.append("works in observer/replay only")
            if aid == "toggle_objectives":
                notes.append("missions only")
            m = re.match(r"^(group_select|group_assign|group_add|group_append|card_5x|card|obs_player|cam_bookmark_set|cam_bookmark)_(\d+)$", aid)
            if m:
                seen_fam.setdefault(m.group(1), []).append((m.group(2), keytxt, "; ".join(notes)))
                continue
            rows.append((label(aid, names, families), keytxt, "; ".join(notes)))
        fam_titles = {
            "group_select": "Select control group N", "group_assign": "Assign selection to group N",
            "group_add": "Add selection to group N", "group_append": "Add group N to selection",
            "card_5x": "Queue 5 of build card N", "card": "Build card N (slot in the visible grid)",
            "obs_player": "Observe player N", "cam_bookmark_set": "Set camera bookmark N", "cam_bookmark": "Go to camera bookmark N",
        }
        for fam, entries in seen_fam.items():
            keys = [e[1] for e in entries]
            txt = f"{keys[0]} ... {keys[-1]}" if len(keys) > 2 else " / ".join(keys)
            note = entries[0][2]
            rows.append((fam_titles[fam], txt, note))
        for r in rows:
            lines.append(f"| {r[0]} | {r[1]} | {r[2]} |")
        lines.append("")
    doc = fill(HEADER) + "\n".join(lines) + fill(FOOTER)
    OUT.write_text(doc, encoding="utf-8")
    print(f"wrote {OUT.relative_to(ROOT)} ({len(actions)} actions)")


def fill(text: str) -> str:
    """Replaces every `@@action_id@@` marker of the prose by the dagger of an unconnected action (or nothing)."""
    return re.sub(r"@@([a-z_0-9]+)@@", lambda m: dag(m.group(1)), text)


HEADER = """# Controls

> The keyboard tables in this file are **generated** from `game/data/ui/keymap_defaults.json` by
> `python3 tools/py/gen_controls_doc.py`, which also scans the game code for the actions that are really connected.
> Every action can be rebound in **Options > Controls** (key conflicts are detected and offered as a swap); "Reset all"
> restores these defaults. The mouse and mode descriptions come from the input model in `docs/spec/ui.md` section 5.5-5.7
> and were checked against the code and, for the keys marked below, by pressing them in a running match.
>
> **Every action in the keymap is connected.** `tests/ui/test_hot1_keys.gd` presses the default key of each one as a real key
> event in a live match and checks its effect; the generator marks an action **(†)** if the game code ever stops handling it.
> Mouse alternatives exist for most keys (buttons, cards, the power dock, the camera pad under the minimap). In-match chat
> exists in LAN matches only.

## Mouse

| Input | Effect |
|---|---|
| Left click | Select a unit or structure (replaces the selection) |
| Left drag | Box-select own units (structures are picked only when the box holds no unit) |
| `Shift` + click | Add or remove one unit from the selection |
| `Shift` + drag | Add a box to the selection |
| Double click | Select every unit of the same type on screen (`T` does it by key, `Ctrl+T` selects them on the whole map) |
| Right click | Context order for the selection (see below) |
| `Shift` + right click | Queue the order after the current ones (waypoints); the latch also exists as **Waypoint mode** (`W`) |
| Force fire | Hold `Ctrl` (Windows/Linux) or `Option` (macOS) while right-clicking: attack anything, including the ground and friendlies. The key `Y`@@cmd_force_fire_mode@@ arms force fire for the next click |
| Middle mouse drag | Orbit the camera (hold, or click-to-toggle via Options > Interface > Camera) |
| Mouse wheel | Zoom towards the cursor (trackpad pinch and two-finger scroll also zoom) |
| Screen edge | Scroll the camera (toggle with `Ctrl+E`; speed in Options > Interface > Camera) |
| Minimap left click / drag | Move the camera; a double click snaps to the point |
| Minimap right click | Issue the context order to that point of the map (`Shift` queues it) |
| Selection tile click | Replace the selection with that unit; `Shift` removes it; `Ctrl` (`Cmd` on macOS) keeps only that unit type |
| Build card left click | Queue one (a structure card starts construction; a ready structure card starts placement) |
| Build card right click | Cancel or remove one from the queue (refunds what was paid) |
| Command bar, power dock | Click the button or the power icon, or press `F5` to `F7` (support powers) and `F8` (superweapon) |

There is deliberately **no Alt+mouse gesture**: many Linux window managers grab it. What would have been Alt+click lives in the armed modes below.

### What a right click does

The rules are evaluated per unit, first match wins, so a mixed selection issues one order per unit group:

1. Force fire held: attack the target or the ground.
2. Engineer on a capturable neutral structure: capture. Squad next to a garrisonable structure: garrison.
3. Passenger on a friendly transport with room: load.
4. Repairer on a damaged friendly vehicle or structure: repair. Salvager on a wreck: salvage.
5. Collector on a deposit: harvest. Collector on a friendly Refinery: return cash.
6. Aircraft on a friendly Airfield or carrier: return to base.
7. Armed unit on a visible enemy that it can hit: attack. On a remembered (ghost) enemy: attack-move to that spot. Units that cannot hit the target's layer are left out of the order.
8. A structure that produces units, on ground or an entity: set the rally point.
9. Any mobile unit on ground: move. Collectors, MCVs, engineers and transports never follow an attack target.

### Armed modes and tools

Pressing a command key (or its button on the command bar) arms the next click: left click executes, right click or `Esc` cancels. The mode ends after one order unless Options > Controls > "Sticky order modes" is on or `Shift` is held while clicking.

| Mode | Key | Click does |
|---|---|---|
| Attack-move | `A` | Advance to the point, engaging anything on the way (drag sets a formation line) |
| Move | `M`@@cmd_move@@ | Plain move, ignoring enemies on the way (a plain right click is the same without the key) |
| Guard | `G` | Guard the clicked friendly unit or point |
| Patrol | `P` | Patrol between the current position and the clicked point |
| Follow | `Ctrl+F` (`Cmd+F` on macOS) | Follow the clicked friendly unit |
| Force fire | `Y`@@cmd_force_fire_mode@@ | Fire at the clicked target or ground |
| Ping map | `J`@@cmd_ping@@ | Ping the point for your team |
| Repair tool | `R` | Click your damaged structures to toggle repair (credits are spent while repairing) |
| Sell tool | `Delete` | Click a structure to sell it (refund is half the price paid; the structure becomes inert while it is sold) |
| Rally tool | `F` | Click ground or a unit to set the rally point of the selected producers |
| Waypoint mode | `W` | Every order is queued after the current ones until the mode is left |
| Rotate placement | `Ctrl+R` | Rotates a rotatable structure (Dock) while its ghost is on the cursor |

Instant commands (no click): `S` stop, `X` scatter, `H` hold position, `D` deploy (MCV, deployable units), `Z` cycle stance, `V` return to base/pad, `U` unload. `Ctrl+Delete`@@cmd_scuttle@@ scuttles the selected units after a confirmation (they leave no wreck). `I O K L`@@cmd_ability_1@@ use the 1st to 4th ability button of the selected unit (the buttons show their key).

### Placing structures

Left click the finished structure card, move the ghost (green means valid, red means blocked; the ring shows the 8-cell build radius around each Headquarters), click to place. Right click or `Esc` returns to the game; the finished item stays ready. Superweapons and targeted powers use the same targeting cursor (click the power icon in the dock or press its `F` key); the preview turns red and hatches your own units when the strike would hit them. Line and corridor powers: press on the start point, drag to set the direction and release (or click the start, move the pointer, click again).

## Keyboard

"""

FOOTER = """
Keys are named as Godot names them (`Equal` is `=`, `Minus` is `-`, `Period` is `.`, `BracketLeft` is `[`). The `Alt+Q ...` build-card keys follow the physical key positions of a QWERTY block.

## Control groups

`Ctrl+1..9,0` (macOS also `Cmd+1..9,0`) stores the selection; `1..9,0` recalls it; pressing the same number twice (within 350 ms) centres the camera on the group; `Shift+n` adds that group to the current selection; `Ctrl+Shift+n` adds the current selection to the group. `Ctrl+G`@@sel_group_next@@ selects the next assigned group (wrapping) and `Ctrl+Tab`@@sel_subgroup_next@@ cycles the sub-group of a mixed selection (the one shown in the portrait and the ability bar).

## Build queue

Left click on a card queues one, right click removes one, and the queue strip under the grid shows progress and lets you cancel or hold items. `Tab` / `Shift+Tab`@@tab_next@@ switch the sidebar tab. `Alt+Q W E R / A S D F / Z X C V`@@card_1@@ (`Option` on macOS) press the 12 card slots of the visible grid (the cards show their key), and `Alt+Shift`@@card_5x_1@@ plus the same key queues five. The first producer of each kind is the **primary** building where units of that kind appear; select a producer and use the sidebar or command bar to make another one primary.

## Alerts, chat, interface

`Space`@@cam_jump_alert@@ jumps the camera to the latest alert (base under attack, lost headquarters, enemy superweapon); alerts also appear as toasts, edge markers and pings on the minimap. `J`@@cmd_ping@@ arms a ping: click the world or the minimap and your teammates in a LAN match see it too (alone you only see your own marker). `Enter`@@chat_all@@ / `Shift+Enter`@@chat_team@@ open the chat input in a LAN match (everybody / team only; `Esc` closes it, and while you type no hotkey fires); in a single-player match they say there is nobody to talk to. `F4`@@hide_ui@@ hides and shows every panel for a clean view, `Print`@@screenshot@@ saves the frame as a PNG in `user://screenshots/` (a message names the file), `Alt+Enter`@@toggle_fullscreen@@ switches between a window and fullscreen (the setting is saved; both work inside a match, Options > Graphics has the same fullscreen setting for the menus). `F1` opens the Field Manual, `F3` the network overlay, `Esc` the game menu, `Pause` / `Ctrl+P` pause (single-player and host rules).

## Missions

`Ctrl+O` folds the **objectives panel** open and closed (it also peeks open by itself when an objective changes). Mission messages, timers and the objectives ribbon need no keys.

## Observer and replay

When you watch a replay (or a match as an observer: an all-AI match, or after you surrender or are defeated) the sidebar is replaced by the observer bar and the replay bar sits at the bottom: `1..8` follow one player, `0` shows all players with fog off, `Tab` cycles players, `F` toggles fog, `C` follows the action, `F2` toggles the **scoreboard**, `Space` pauses, `[` and `]` change the speed (1/4, 1/2, 1x, 2x, 4x, 8x, MAX), `,` and `.` jump 10 s back and forward, `N` and `B` jump to the next and previous event. The replay bar has the same functions as buttons and a seek slider; dragging it rebuilds the world up to that tick. Moving the camera by hand ends the follow camera. `Esc` opens the replay menu (Resume, Options, Field Manual, Leave replay).
"""

if __name__ == "__main__":
    main()
