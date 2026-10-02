"""MIS3: OPERATION 2, NEC 'Lattice' (op_nec): networked defence of a city with Relay coverage. Fault line: Europe / Order."""
from .lib import *

LEO = "unit.nec.leopard_tank"
JAGER = "unit.nec.jager_squad"
SPIKE = "unit.nec.spike_team"
RAPIER = "unit.nec.rapier_aa"
SIROCCO = "unit.olm.sirocco_tank"
GUARD = "unit.olm.wayfarer_guard"
NEEDLE = "unit.olm.needle_team"
MORTAR = "unit.olm.sandglass_mortar"
RELAY = "structure.nec.relay"
GEN = "structure.shared.generator"
REF = "structure.shared.refinery"
BAR = "structure.shared.barracks"
FAC = "structure.shared.factory"
TUR = "structure.shared.anti_tank_turret"
HQ = "structure.shared.headquarters"
SP = "Lattice Command"
OR = "Solar Directorate"


def build():
    m = Mission("op_nec", "Operation Lattice", "operation", 2,
                {"family": "urban", "size": 128, "seed": 11}, rules={"start_credits": 4000, "fog": 1}, sim_seed=2101)
    m.brief("Situation",
            "Varenne is a mid-sized river city that nobody planned to be important. Then the Long Blackout left its power exchange as the "
            "only working junction between the northern and southern grids, and it became the most valuable ten square kilometres in the "
            "region. The Confederation garrison holds it with three Relay masts that tie every gun in the district into one picture.", "faction.nec")
    m.brief("The Solar Directorate",
            "The Order's Solar Directorate wants custody of the exchange. It points out, correctly, that the Confederation's engineers "
            "set the exchange's standards and could throttle the south at will. The Confederation points out, also correctly, that a "
            "directorate which controls both the sun and the wires has no reason to stop at one city. The talks end tonight. The columns "
            "are already on the road.", "faction.olm")
    m.brief("Orders",
            "Hold the Town Hall (your Headquarters) for fourteen minutes until the relief column from the confederate cities arrives. "
            "Keep at least two of the three Relay masts alive and powered: units within six cells of a powered Relay hit ten per cent harder. "
            "Expect an attempt to cut the grid. If you can, break the siege guns before they find range.")
    m.player(0, "human", "roster.nec.vanilla", 1, "Varenne Garrison", "hq", credits=4000,
             units=[{"def": LEO, "count": 3, "dx": -6, "dy": -2}, {"def": JAGER, "count": 2, "dx": -4, "dy": 4}, {"def": SPIKE, "count": 2, "dx": -7, "dy": 1},
                    {"def": RAPIER, "count": 1, "dx": -2, "dy": 6}],
             structures=[{"def": RELAY, "dx": -9, "dy": -5, "id": "relay_a"}, {"def": RELAY, "dx": -10, "dy": 4, "id": "relay_b"},
                         {"def": RELAY, "dx": -3, "dy": -10, "id": "relay_c"}, {"def": GEN, "dx": 4, "dy": -5, "id": "gen_a"},
                         {"def": GEN, "dx": 4, "dy": 5, "id": "gen_b"}, {"def": REF, "dx": 5, "dy": 0}, {"def": BAR, "dx": -4, "dy": 8},
                         {"def": FAC, "dx": 2, "dy": -9}, {"def": TUR, "dx": -12, "dy": -1}, {"def": TUR, "dx": -7, "dy": -9}])
    m.player(1, "ai", "roster.olm.vanilla", 2, "Solar Directorate", "hq", start_slot=2, ai={"level": 1, "style": 0, "active": False})

    m.circle("a_city", 0, 0, 12, "start:0")
    m.circle("a_w_gate", -34, 0, 5, "start:0")
    m.circle("a_n_gate", -4, -36, 5, "start:0")
    m.circle("a_nw_gate", -30, -30, 5, "start:0")
    m.circle("a_siege", -14, -33, 5, "start:0")
    m.circle("a_front", -14, -6, 6, "start:0")

    m.msg("intro", "Varenne, this is Lattice Command. The Relays are live and the exchange is yours. The Directorate columns are forming up beyond the river. Fourteen minutes.", SP, "match_start_nec")
    m.msg("w1", "Contact on the west road. A raiding party, light armour and infantry.", SP, "base_under_attack")
    m.msg("w2", "A second party from the north gate. Keep your Relays between them and the exchange.", SP, "base_under_attack")
    m.msg("w3", "Armour on the west road and infantry through the north-western blocks. They are probing the Relays.", SP, "base_under_attack")
    m.msg("w4", "Heavy contact from the north-west. This is the main body.", SP, "base_under_attack")
    m.msg("w5", "Everything the Directorate has is coming through the west and north gates at once.", SP, "base_under_attack")
    m.msg("or_talks", "Garrison of Varenne: the Directorate offers custody of the exchange under a joint charter. Lay down your arms and nobody needs to be hurt.", OR)
    m.msg("blackout", "Substation failure! Somebody cut the feeders: both generators are down and the lattice is on battery. Rebuild generation before the Relays drop out.", SP, "low_power")
    m.msg("grid_ok", "Power is back. The Lattice is whole again.", SP, "power_restored")
    m.msg("siege", "Recon reports Sandglass mortars deploying on the northern ridge. Once they have range they will walk shells across the Relays. Break the siege camp if you can spare the force.", SP)
    m.msg("siege_down", "The mortars are silent. The ridge is clear.", SP)
    m.msg("relay_lost", "A Relay mast is down. The lattice is thinner now.", SP, "structure_lost")
    m.msg("relief", "Relief column is on the east road! Hold the exchange for another minute!", SP, "ally_under_attack")
    m.msg("lose_town", "The Town Hall has fallen. Varenne is lost.", SP, "defeat")
    m.msg("lose_lattice", "Two Relay masts are gone. Without the lattice the garrison cannot hold the district.", SP, "defeat")
    m.msg("win", "The relief column is through and the Directorate is falling back across the river. Varenne holds.", SP, "victory")
    m.msg("debrief_win", "DEBRIEF: the exchange stays under Confederation control, for now. The Order will say the garrison fired first; the Confederation will say the Order brought the columns. The treaty talks reopen next week, and both sides will remember that a single city's power is the real bargaining chip.", "Debrief")
    m.msg("debrief_lose", "DEBRIEF: the exchange fell. The Directorate now holds the wires, and the southern towns have not decided yet whether to be grateful.", "Debrief")

    m.objective("hold", "primary", "Hold the Town Hall until the relief column arrives (14:00)", "active")
    m.objective("lattice", "primary", "Keep at least two Relay masts alive and powered", "active")
    m.objective("grid", "primary", "Restore the city's power after the blackout", "hidden")
    m.objective("siege", "secondary", "Destroy the Directorate siege camp on the northern ridge", "hidden")
    m.objective("all_relays", "secondary", "Finish with all three Relay masts standing", "active")
    m.timer("relief_t", 840, "Relief column")

    m.trig("t00_start", time_t(0), [say("intro"), timer_start("relief_t"), music("calm")])
    m.trig("t01_ai_on", time_s(150), [change_ai(1, active=True)])
    # scripted raids: (time, message, [(unit, count, area)...])
    raids = [
        (110, "w1", [(SIROCCO, 2, "a_w_gate"), (GUARD, 2, "a_w_gate")]),
        (230, "w2", [(SIROCCO, 2, "a_n_gate"), (NEEDLE, 2, "a_n_gate")]),
        (350, "w3", [(SIROCCO, 3, "a_w_gate"), (GUARD, 3, "a_nw_gate")]),
        (520, "w4", [(SIROCCO, 4, "a_nw_gate"), (GUARD, 3, "a_nw_gate"), (NEEDLE, 2, "a_w_gate")]),
        (680, "w5", [(SIROCCO, 4, "a_w_gate"), (SIROCCO, 3, "a_n_gate"), (NEEDLE, 3, "a_nw_gate"), (GUARD, 3, "a_n_gate")]),
    ]
    for i, (t, msg, groups) in enumerate(raids):
        acts = [spawn(1, u, n, a, "raid%d" % (i + 1), "attack_move", "a_city") for (u, n, a) in groups]
        m.trig("t1%d_raid" % i, time_s(t), acts + [say(msg), music("combat")])
    m.trig("t20_talks", time_s(300), [say("or_talks")])
    # the blackout and the siege camp
    m.trig("t30_blackout", time_s(420),
           [destroy(placed="gen_a"), destroy(placed="gen_b"), say("blackout"), set_obj("grid", "active"), cam("a_city", seconds=5), music("tense")])
    m.trig("t31_grid", all_(active("grid"), time_s(430), power(0, 0, ">=")), [set_obj("grid", "completed"), say("grid_ok")])
    m.trig("t32_siege", time_s(460),
           [spawn(1, MORTAR, 3, "a_siege", "camp", "hold"), spawn(1, SIROCCO, 2, "a_siege", "camp", "guard", "a_siege"), spawn(1, GUARD, 2, "a_siege", "camp", "guard", "a_siege"),
            set_obj("siege", "active"), say("siege"), reveal(0, "a_siege", 12)])
    m.trig("t33_siege_down", all_(active("siege"), wave("camp", "cleared")), [set_obj("siege", "completed"), say("siege_down")])
    m.trig("t34_relief", time_s(780), [say("relief")])
    # the end
    two_powered = any_(all_(struct("powered", placed="relay_a"), struct("powered", placed="relay_b")),
                       all_(struct("powered", placed="relay_a"), struct("powered", placed="relay_c")),
                       all_(struct("powered", placed="relay_b"), struct("powered", placed="relay_c")))
    m.trig("t80_relay_lost", all_(active("all_relays"), count(0, 3, "<", def_=RELAY)), [set_obj("all_relays", "failed"), say("relay_lost")])
    m.trig("t90_win", all_(timer("relief_t"), count(0, 1, def_=HQ), count(0, 2, def_=RELAY), two_powered),
           [set_obj("hold", "completed"), set_obj("lattice", "completed"), say("win"), say("debrief_win"), win(0), music("victory")])
    m.trig("t91_lose_town", count(0, 0, "<=", def_=HQ), [set_obj("hold", "failed"), say("lose_town"), say("debrief_lose"), lose(0), music("defeat")])
    m.trig("t92_lose_lattice", count(0, 2, "<", def_=RELAY), [set_obj("lattice", "failed"), say("lose_lattice"), say("debrief_lose"), lose(0), music("defeat")])
    m.trig("t93_lose_unpowered", all_(timer("relief_t"), count(0, 1, def_=HQ), count(0, 2, def_=RELAY), not_(two_powered), time_s(1020)),
           [set_obj("lattice", "failed"), say("lose_lattice"), say("debrief_lose"), lose(0)])
    return m
