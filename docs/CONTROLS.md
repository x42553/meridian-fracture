# Controls

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
| Force fire | Hold `Ctrl` (Windows/Linux) or `Option` (macOS) while right-clicking: attack anything, including the ground and friendlies. The key `Y` arms force fire for the next click |
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
| Move | `M` | Plain move, ignoring enemies on the way (a plain right click is the same without the key) |
| Guard | `G` | Guard the clicked friendly unit or point |
| Patrol | `P` | Patrol between the current position and the clicked point |
| Follow | `Ctrl+F` (`Cmd+F` on macOS) | Follow the clicked friendly unit |
| Force fire | `Y` | Fire at the clicked target or ground |
| Ping map | `J` | Ping the point for your team |
| Repair tool | `R` | Click your damaged structures to toggle repair (credits are spent while repairing) |
| Sell tool | `Delete` | Click a structure to sell it (refund is half the price paid; the structure becomes inert while it is sold) |
| Rally tool | `F` | Click ground or a unit to set the rally point of the selected producers |
| Waypoint mode | `W` | Every order is queued after the current ones until the mode is left |
| Rotate placement | `Ctrl+R` | Rotates a rotatable structure (Dock) while its ghost is on the cursor |

Instant commands (no click): `S` stop, `X` scatter, `H` hold position, `D` deploy (MCV, deployable units), `Z` cycle stance, `V` return to base/pad, `U` unload. `Ctrl+Delete` scuttles the selected units after a confirmation (they leave no wreck). `I O K L` use the 1st to 4th ability button of the selected unit (the buttons show their key).

### Placing structures

Left click the finished structure card, move the ghost (green means valid, red means blocked; the ring shows the 8-cell build radius around each Headquarters), click to place. Right click or `Esc` returns to the game; the finished item stays ready. Superweapons and targeted powers use the same targeting cursor (click the power icon in the dock or press its `F` key); the preview turns red and hatches your own units when the strike would hit them. Line and corridor powers: press on the start point, drag to set the direction and release (or click the start, move the pointer, click again).

## Keyboard

### Camera

| Action | Default key | Notes |
|---|---|---|
| Pan left | `Left` |  |
| Pan right | `Right` |  |
| Pan up | `Up` |  |
| Pan down | `Down` |  |
| Rotate left | `Q` |  |
| Rotate right | `E` |  |
| Tilt up | `PageUp` |  |
| Tilt down | `PageDown` |  |
| Zoom in | `Equal` |  |
| Zoom out | `Minus` |  |
| Centre on base | `Home` |  |
| Centre on selection | `Period` |  |
| Jump to last alert | `Space` |  |
| Reset camera | `Backspace` |  |
| Orbit (hold) | Middle mouse button (drag) |  |
| Toggle edge scrolling | `Ctrl+E` |  |
| Go to camera bookmark N | `F9` ... `F12` |  |
| Set camera bookmark N | `Ctrl+F9` ... `Ctrl+F12` |  |

### Selection and groups

| Action | Default key | Notes |
|---|---|---|
| Select all combat units | `Ctrl+A` |  |
| Select all combat units on screen | `Ctrl+Shift+A` |  |
| Select same type on screen | `T` |  |
| Select same type everywhere | `Ctrl+T` |  |
| Next idle unit | `N` |  |
| Previous idle unit | `Shift+N` |  |
| Next collector | `C` |  |
| Next producer | `B` |  |
| Select headquarters | `Ctrl+Home` |  |
| Cycle sub-group | `Ctrl+Tab` |  |
| Next control group | `Ctrl+G` |  |
| Select control group N | `1` ... `0` |  |
| Assign selection to group N | `Ctrl+1` ... `Ctrl+0` | macOS also: `Ctrl+1` / `Cmd+1` |
| Add selection to group N | `Ctrl+Shift+1` ... `Ctrl+Shift+0` |  |
| Add group N to selection | `Shift+1` ... `Shift+0` |  |

### Orders

| Action | Default key | Notes |
|---|---|---|
| Attack-move | `A` |  |
| Move | `M` |  |
| Guard | `G` |  |
| Patrol | `P` |  |
| Stop | `S` |  |
| Scatter | `X` |  |
| Hold position | `H` |  |
| Follow | `Ctrl+F` | macOS also: `Ctrl+F` / `Cmd+F` |
| Deploy | `D` |  |
| Cycle stance | `Z` |  |
| Force fire | `Y` |  |
| Return to base | `V` |  |
| Unload | `U` |  |
| Ability 1 | `I` |  |
| Ability 2 | `O` |  |
| Ability 3 | `K` |  |
| Ability 4 | `L` |  |
| Scuttle | `Ctrl+Delete` |  |
| Ping map | `J` |  |

### Tools

| Action | Default key | Notes |
|---|---|---|
| Repair tool | `R` |  |
| Sell tool | `Delete` |  |
| Rally point tool | `F` |  |
| Waypoint mode | `W` |  |
| Rotate placement | `Ctrl+R` |  |

### Build sidebar

| Action | Default key | Notes |
|---|---|---|
| Next build tab | `Tab` |  |
| Previous build tab | `Shift+Tab` |  |
| Build card N (slot in the visible grid) | `Alt+Q` ... `Alt+V` |  |
| Queue 5 of build card N | `Alt+Shift+Q` ... `Alt+Shift+V` |  |

### Powers

| Action | Default key | Notes |
|---|---|---|
| Support power 1 | `F5` |  |
| Support power 2 | `F6` |  |
| Support power 3 | `F7` |  |
| Superweapon | `F8` |  |

### Interface

| Action | Default key | Notes |
|---|---|---|
| Game menu | `Escape` | everywhere |
| Pause | `Pause` / `Ctrl+P` |  |
| Chat to all | `Enter` |  |
| Chat to team | `Shift+Enter` |  |
| Field Manual | `F1` |  |
| Scoreboard | `F2` | observer/replay only |
| Mission objectives | `Ctrl+O` | missions only |
| Network overlay | `F3` |  |
| Hide interface | `F4` |  |
| Screenshot | `Print` |  |
| Toggle fullscreen | `Alt+Enter` |  |

### Observer and replay

| Action | Default key | Notes |
|---|---|---|
| Observe all players | `0` | observer/replay only |
| Next player | `Tab` | observer/replay only |
| Toggle fog of war | `F` | observer/replay only |
| Pause replay | `Space` | observer/replay only |
| Faster replay | `BracketRight` | observer/replay only |
| Slower replay | `BracketLeft` | observer/replay only |
| Follow the viewed player | `C` | observer/replay only |
| Next replay event | `N` | observer/replay only |
| Previous replay event | `B` | observer/replay only |
| Back 10 seconds | `Comma` | observer/replay only |
| Forward 10 seconds | `Period` | observer/replay only |
| Observe player N | `1` ... `8` | observer/replay only |

Keys are named as Godot names them (`Equal` is `=`, `Minus` is `-`, `Period` is `.`, `BracketLeft` is `[`). The `Alt+Q ...` build-card keys follow the physical key positions of a QWERTY block.

## Control groups

`Ctrl+1..9,0` (macOS also `Cmd+1..9,0`) stores the selection; `1..9,0` recalls it; pressing the same number twice (within 350 ms) centres the camera on the group; `Shift+n` adds that group to the current selection; `Ctrl+Shift+n` adds the current selection to the group. `Ctrl+G` selects the next assigned group (wrapping) and `Ctrl+Tab` cycles the sub-group of a mixed selection (the one shown in the portrait and the ability bar).

## Build queue

Left click on a card queues one, right click removes one, and the queue strip under the grid shows progress and lets you cancel or hold items. `Tab` / `Shift+Tab` switch the sidebar tab. `Alt+Q W E R / A S D F / Z X C V` (`Option` on macOS) press the 12 card slots of the visible grid (the cards show their key), and `Alt+Shift` plus the same key queues five. The first producer of each kind is the **primary** building where units of that kind appear; select a producer and use the sidebar or command bar to make another one primary.

## Alerts, chat, interface

`Space` jumps the camera to the latest alert (base under attack, lost headquarters, enemy superweapon); alerts also appear as toasts, edge markers and pings on the minimap. `J` arms a ping: click the world or the minimap and your teammates in a LAN match see it too (alone you only see your own marker). `Enter` / `Shift+Enter` open the chat input in a LAN match (everybody / team only; `Esc` closes it, and while you type no hotkey fires); in a single-player match they say there is nobody to talk to. `F4` hides and shows every panel for a clean view, `Print` saves the frame as a PNG in `user://screenshots/` (a message names the file), `Alt+Enter` switches between a window and fullscreen (the setting is saved; both work inside a match, Options > Graphics has the same fullscreen setting for the menus). `F1` opens the Field Manual, `F3` the network overlay, `Esc` the game menu, `Pause` / `Ctrl+P` pause (single-player and host rules).

## Missions

`Ctrl+O` folds the **objectives panel** open and closed (it also peeks open by itself when an objective changes). Mission messages, timers and the objectives ribbon need no keys.

## Observer and replay

When you watch a replay (or a match as an observer: an all-AI match, or after you surrender or are defeated) the sidebar is replaced by the observer bar and the replay bar sits at the bottom: `1..8` follow one player, `0` shows all players with fog off, `Tab` cycles players, `F` toggles fog, `C` follows the action, `F2` toggles the **scoreboard**, `Space` pauses, `[` and `]` change the speed (1/4, 1/2, 1x, 2x, 4x, 8x, MAX), `,` and `.` jump 10 s back and forward, `N` and `B` jump to the next and previous event. The replay bar has the same functions as buttons and a seek slider; dragging it rebuilds the world up to that tick. Moving the camera by hand ends the follow camera. `Esc` opens the replay menu (Resume, Options, Field Manual, Leave replay).
