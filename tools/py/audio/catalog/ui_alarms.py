"""ui_alarms.py - `snd.ui.*` (32 ids) and `snd.alarm.*` (6 ids) of audio spec 4.8.

UI notes: [kind, freq_hz, start_s, dur_s, gain].  Loudness targets (5.1): hover -28, click -22, confirm / error -18, others
between; all peak <= -4.5 dBTP.  UI sounds are 2D: stereo masters (mono where there is no stereo content)."""
from __future__ import annotations

from catalog import AssetSpec, add

E5, B5, C5, G5, E6 = 659.3, 987.8, 523.3, 784.0, 1318.5
UI: dict[str, dict] = {
    "click": dict(lufs=-22, ch="mono", tail=0.16, notes=[["tick", 2600, 0.0, 0.05, 0.8], ["pluck", 1800, 0.0, 0.16, 0.8], ["pluck", 420, 0.0, 0.1, 0.4]]),
    "hover": dict(lufs=-28, ch="mono", tail=0.14, notes=[["ping", 2600, 0.0, 0.14, 0.9], ["ping", 5200, 0.0, 0.1, 0.2]]),
    "confirm": dict(lufs=-18, ch="stereo", tail=0.9, room="plate", wet=0.16, width=1.3, notes=[["bell", E5, 0.0, 0.9, 0.8], ["bell", B5, 0.085, 0.8, 1.0]]),
    "error": dict(lufs=-18, ch="mono", tail=0.42, notes=[["buzz", 150, 0.02, 0.11, 1.0], ["buzz", 128, 0.17, 0.11, 1.0]]),
    "back": dict(lufs=-24, ch="mono", tail=0.35, notes=[["pluck", B5, 0.0, 0.25, 0.7], ["pluck", E5, 0.07, 0.28, 0.8]]),
    "tab": dict(lufs=-25, ch="mono", tail=0.14, notes=[["tick", 1500, 0.0, 0.06, 0.7], ["pluck", 1400, 0.0, 0.12, 0.6]]),
    "toggle_on": dict(lufs=-23, ch="mono", tail=0.3, notes=[["pluck", 880, 0.0, 0.16, 0.7], ["pluck", 1320, 0.06, 0.24, 0.9]]),
    "toggle_off": dict(lufs=-24, ch="mono", tail=0.3, notes=[["pluck", 1320, 0.0, 0.16, 0.7], ["pluck", 880, 0.06, 0.24, 0.8]]),
    "slider_tick": dict(lufs=-30, ch="mono", tail=0.06, notes=[["tick", 2200, 0.0, 0.05, 0.9]]),
    "queue_add": dict(lufs=-22, ch="mono", tail=0.3, notes=[["pluck", 700, 0.0, 0.14, 0.8], ["pluck", 1050, 0.05, 0.22, 0.9]]),
    "queue_cancel": dict(lufs=-22, ch="mono", tail=0.3, notes=[["pluck", 900, 0.0, 0.14, 0.7], ["buzz", 220, 0.05, 0.2, 0.6]]),
    "queue_hold": dict(lufs=-27, ch="mono", tail=0.3, notes=[["tick", 800, 0.0, 0.08, 0.8], ["tick", 800, 0.11, 0.08, 0.6]]),
    "build_ready": dict(lufs=-17, ch="stereo", tail=1.2, room="plate", wet=0.2, width=1.3,
                        notes=[["bell", C5 * 2, 0.0, 0.8, 0.7], ["bell", E6 * 0.5 * 1.26, 0.09, 0.8, 0.7], ["bell", G5 * 2, 0.18, 0.8, 0.8], ["bell", C5 * 4, 0.28, 1.0, 0.9]]),
    "place_ok": dict(lufs=-21, ch="mono", tail=0.3, notes=[["pluck", 660, 0.0, 0.14, 0.7], ["bell", 990, 0.05, 0.25, 0.8]]),
    "place_fail": dict(lufs=-20, ch="mono", tail=0.34, notes=[["buzz", 190, 0.0, 0.12, 0.9], ["buzz", 160, 0.11, 0.15, 0.9]]),
    "sell_mode": dict(lufs=-22, ch="mono", tail=0.4, notes=[["sweep", 1400, 0.0, 0.3, 0.7], ["ping", 2450, 0.22, 0.16, 0.6]]),
    "repair_mode": dict(lufs=-22, ch="mono", tail=0.4, notes=[["tick", 1800, 0.0, 0.05, 0.6], ["tick", 1800, 0.07, 0.05, 0.6], ["sweepup", 1300, 0.13, 0.26, 0.7]]),
    "group_set": dict(lufs=-21, ch="mono", tail=0.32, notes=[["pluck", 780, 0.0, 0.14, 0.8], ["pluck", 780, 0.09, 0.2, 0.9], ["tick", 2400, 0.09, 0.05, 0.4]]),
    "group_recall": dict(lufs=-23, ch="mono", tail=0.2, notes=[["pluck", 880, 0.0, 0.18, 0.8], ["tick", 2200, 0.0, 0.05, 0.4]]),
    "waypoint": dict(lufs=-25, ch="mono", tail=0.16, notes=[["tick", 1600, 0.0, 0.1, 0.8]]),
    "rally_set": dict(lufs=-21, ch="mono", tail=0.3, notes=[["tick", 900, 0.0, 0.06, 0.9], ["pluck", 1100, 0.02, 0.24, 0.8]]),
    "minimap_ping": dict(lufs=-20, ch="stereo", tail=0.9, room="plate", wet=0.28, width=1.3, notes=[["ping", 1200, 0.0, 0.5, 1.0], ["ping", 1200, 0.28, 0.4, 0.3]]),
    "minimap_click": dict(lufs=-27, ch="mono", tail=0.08, notes=[["tick", 2000, 0.0, 0.05, 0.9]]),
    "alert": dict(lufs=-17, ch="stereo", tail=0.9, room="room", wet=0.12, width=1.2, notes=[["bell", 880, 0.0, 0.3, 0.9], ["bell", 660, 0.22, 0.3, 0.9], ["bell", 880, 0.44, 0.4, 1.0]]),
    "chat": dict(lufs=-24, ch="mono", tail=0.3, notes=[["pluck", 1174, 0.0, 0.1, 0.7], ["pluck", 1568, 0.07, 0.2, 0.8]]),
    "lobby_join": dict(lufs=-21, ch="stereo", tail=0.6, room="plate", wet=0.12, notes=[["pluck", 587, 0.0, 0.2, 0.8], ["bell", 880, 0.09, 0.5, 0.9]]),
    "lobby_leave": dict(lufs=-22, ch="stereo", tail=0.6, room="plate", wet=0.12, notes=[["pluck", 880, 0.0, 0.2, 0.8], ["bell", 587, 0.09, 0.5, 0.7]]),
    "lobby_ready": dict(lufs=-20, ch="stereo", tail=0.6, room="plate", wet=0.12, notes=[["bell", 784, 0.0, 0.5, 0.8], ["bell", 1175, 0.07, 0.5, 0.9]]),
    "lobby_countdown_tick": dict(lufs=-21, ch="mono", tail=0.25, notes=[["ping", 1000, 0.0, 0.2, 1.0], ["tick", 3000, 0.0, 0.04, 0.4]]),
    "lobby_start": dict(lufs=-17, ch="stereo", tail=1.4, room="hall", wet=0.16, width=1.3,
                        notes=[["bell", C5, 0.0, 1.0, 0.7], ["bell", G5, 0.10, 1.0, 0.7], ["bell", C5 * 2, 0.20, 1.1, 0.8], ["bell", G5 * 2, 0.32, 1.2, 0.9]], noise_sweep=[400, 6000, 0.25]),
    "menu_transition": dict(lufs=-24, ch="stereo", tail=0.9, room="plate", wet=0.1, width=1.3, notes=[["sweepup", 700, 0.0, 0.5, 0.25]], noise_sweep=[300, 5200, 0.5]),
    "notify": dict(lufs=-21, ch="stereo", tail=0.7, room="plate", wet=0.14, notes=[["bell", 1046.5, 0.0, 0.6, 0.8], ["bell", 1568, 0.11, 0.5, 0.5]]),
}
for name, d in UI.items():
    params = {"notes": d["notes"], "tail": d["tail"]}
    for k in ("room", "wet", "width", "noise_sweep"):
        if k in d:
            params[k] = d[k]
    add(AssetSpec(f"ui/{name}", "ui_voice", channels=d["ch"], peak_db=-4.5, lufs=float(d["lufs"]), params=params, tags=("ui",)))

ALARMS = [
    ("sw_siren", "sw_siren", "stereo", True, -16.0),
    ("countdown_tick", "countdown_tick", "mono", False, -16.0),
    ("countdown_final", "countdown_final", "stereo", False, -14.0),
    ("base_attack", "base_attack", "stereo", False, -16.0),
    ("incoming", "incoming", "stereo", False, -15.0),
    ("low_power", "low_power", "stereo", False, -16.0),
]
for name, recipe, ch, loop, lufs in ALARMS:
    add(AssetSpec(f"alarm/{name}", recipe, channels=ch, loop=loop, peak_db=-6.0 if loop else -4.5, lufs=lufs, tags=("alarm",)))
