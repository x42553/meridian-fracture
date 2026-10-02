"""MIS3: OPERATION 3, OLM 'Deep Wells' (op_olm): desalination wells defended by concealment and mobility. Fault line: Order / African Empire."""
from .lib import *

TANK = "unit.olm.sirocco_tank"
GUARD = "unit.olm.wayfarer_guard"
NEEDLE = "unit.olm.needle_team"
AA = "unit.olm.crescent_aa"
OBS = "unit.olm.mirage_observer"
BUF = "unit.ae.buffalo_tank"
UG = "unit.ae.union_guard"
PIKE = "unit.ae.pike_team"
MAMBA = "unit.ae.mamba_apc"
GEN = "structure.shared.generator"
REF = "structure.shared.refinery"
BAR = "structure.shared.barracks"
TUR = "structure.shared.anti_tank_turret"
WT = "structure.shared.watchtower"
HQ = "structure.shared.headquarters"
SP = "Well Command"
AE = "Corridor Authority"


def build():
    m = Mission("op_olm", "Operation Deep Wells", "operation", 3,
                {"family": "open", "size": 128, "seed": 21, "params": {"biome": 1}}, rules={"start_credits": 5000, "fog": 1}, sim_seed=3101)
    m.brief("Situation",
            "Three deep desalination wells feed the coastal enclaves of the eastern basin, and their pumps run on the Order's own solar fields. "
            "The wells are the reason the enclaves signed the Oath. They are also the reason the Corridor Authority, which taxes every cargo "
            "moving along the coast road, would like them to belong to someone else.", "faction.olm")
    m.brief("The Corridor Authority",
            "The African Empire's corridor stewards say they want a treaty on water. They also want the pumps' control software, and a "
            "raiding force with salvage crews is gathering to take both. Trade between the Order and the Empire is the only thing keeping "
            "the coast alive, which is why nobody on either side wants to be the one who says this is a war.", "faction.ae")
    m.brief("Orders",
            "Keep at least two of the three well pumps running for thirteen minutes. You cannot cover all three with walls, so do not try: "
            "keep your armour mobile, hide it with Mirage Observers and the Dust Screen, and strike the raiders where they gather. "
            "When the Authority's forward depot appears, destroy it: it is where every later wave comes from.")
    m.player(0, "human", "roster.olm.vanilla", 1, "Well Guard", "hq", credits=5000,
             units=[{"def": TANK, "count": 3, "dx": -5, "dy": -3}, {"def": GUARD, "count": 2, "dx": -4, "dy": 4}, {"def": NEEDLE, "count": 2, "dx": -7, "dy": 1},
                    {"def": AA, "count": 1, "dx": -2, "dy": 6}, {"def": OBS, "count": 1, "dx": -6, "dy": -6}],
             structures=[{"def": GEN, "dx": 5, "dy": 4}, {"def": REF, "dx": 5, "dy": -2}, {"def": BAR, "dx": -3, "dy": 8},
                         {"def": GEN, "dx": -13, "dy": -10, "id": "well_a"}, {"def": GEN, "dx": -8, "dy": 15, "id": "well_b"}, {"def": GEN, "dx": -27, "dy": -3, "id": "well_c"},
                         {"def": WT, "dx": -13, "dy": -8}, {"def": WT, "dx": -8, "dy": 13}])
    m.player(1, "ai", "roster.ae.vanilla", 2, "Corridor Authority", "hq", start_slot=2, ai={"level": 1, "style": 0, "active": False})

    m.circle("a_base", 0, 0, 12, "start:0")
    m.circle("a_well_a", -13, -10, 5, "start:0")
    m.circle("a_well_b", -8, 15, 5, "start:0")
    m.circle("a_well_c", -27, -3, 5, "start:0")
    m.circle("a_hub", -16, 2, 7, "start:0")
    m.circle("a_dunes_n", -30, -30, 5, "start:0")
    m.circle("a_dunes_s", -45, 14, 5, "start:0")
    m.circle("a_depot", -38, -24, 6, "start:0")

    m.msg("intro", "Well Guard, this is Well Command. All three pumps are running. The Authority's raiders are massing behind the dunes. Thirteen minutes, two pumps.", SP, "match_start_olm")
    m.msg("r1", "Raiders on the west dunes heading for the far pump.", SP, "base_under_attack")
    m.msg("r2", "A second party is coming up from the south dunes toward the southern pump.", SP, "base_under_attack")
    m.msg("hint_mob", "Remember what we are: do not sit on the pumps. Strike where they gather and fall back before the second party arrives. A Mirage Observer that stands still for six seconds disappears; the Dust Screen hides a whole formation.", SP)
    m.msg("depot", "Scouts report the Authority has raised a forward depot in the western dunes, with a crane, a repair bay and guns. Every raid since this morning has been resupplied from there. Take it down and the raids end.", SP, "enemy_sw_charging")
    m.msg("au_talks", "Well Guard: the Authority proposes joint custody of the pumps under a treaty. Withdraw your defenders and we will guarantee the water.", AE)
    m.msg("depot_down", "The forward depot is burning. No more raids will leave it.", SP)
    m.msg("pump_lost", "A pump is down. The enclaves will notice within the hour.", SP, "structure_lost")
    m.msg("last_push", "Everything the Authority has left is coming for the pumps. Hold on.", SP, "base_under_attack")
    m.msg("lose_pumps", "Two of the three pumps are lost. The enclaves have no water.", SP, "defeat")
    m.msg("lose_base", "The Well Guard headquarters has fallen.", SP, "defeat")
    m.msg("win", "Thirteen minutes. The pumps are running and the depot is gone. The enclaves keep their water.", SP, "victory")
    m.msg("debrief_win", "DEBRIEF: the Order kept its wells and the Empire kept its corridor. The Authority's stewards will tell their council they were testing the Oath; the Order's solar directorate will use the episode to ask for exclusive custody of the pump controls. Everyone in the basin can see where that leads.", "Debrief")
    m.msg("debrief_lose", "DEBRIEF: the pumps changed hands. The Authority promises a fair tariff. The enclaves have heard that before.", "Debrief")

    m.objective("pumps", "primary", "Keep at least two of the three well pumps running for 13:00", "active")
    m.objective("depot", "primary", "Destroy the Authority's forward depot", "hidden")
    m.objective("hq", "primary", "Do not lose the headquarters", "active")
    m.objective("all_pumps", "secondary", "Finish with all three pumps running", "active")
    m.objective("observer", "secondary", "Keep your Mirage Observer alive", "active")
    m.timer("hold_t", 780, "Pumps must run")

    m.trig("t00_start", time_t(0), [say("intro"), timer_start("hold_t"), music("calm")])
    m.trig("t01_ai_on", time_s(150), [change_ai(1, active=True)])
    m.trig("t02_hint", time_s(60), [say("hint_mob")])
    # first raids come from the dunes
    m.trig("t10_r1", time_s(210), [spawn(1, BUF, 2, "a_dunes_n", "r1", "attack_move", "a_well_c"), spawn(1, UG, 2, "a_dunes_n", "r1", "attack_move", "a_well_c"),
                                   say("r1"), music("combat")])
    m.trig("t11_r2", time_s(330), [spawn(1, BUF, 2, "a_dunes_s", "r2", "attack_move", "a_well_b"), spawn(1, PIKE, 2, "a_dunes_s", "r2", "attack_move", "a_well_b"),
                                   say("r2")])
    m.trig("t12_talks", time_s(300), [say("au_talks")])
    # twist: the forward depot appears (it resupplies repeating raids until it is destroyed)
    m.trig("t20_depot", time_s(420),
           [spawn_s(1, TUR, "a_depot", id="dep1"), spawn_s(1, TUR, "a_depot", id="dep2"), spawn_s(1, WT, "a_depot", id="dep3"), spawn_s(1, BAR, "a_depot", id="dep4"),
            spawn(1, BUF, 2, "a_depot", "dep_guard", "guard", "a_depot"), spawn(1, PIKE, 2, "a_depot", "dep_guard", "guard", "a_depot"),
            set_obj("depot", "active"), say("depot"), reveal(0, "a_depot", 15), cam("a_depot", seconds=6), music("tense"),
            enable("t30_resupply_a"), enable("t31_resupply_b"), enable("t32_resupply_c")])
    m.trig("t21_reveal", all_(active("depot")), [reveal(0, "a_depot", 8)], once=False, cooldown=45)
    # resupplied raids until the depot is destroyed
    m.trig("t30_resupply_a", time_s(480), [spawn(1, BUF, 2, "a_depot", "res_a", "attack_move", "a_well_c"), spawn(1, UG, 1, "a_depot", "res_a", "attack_move", "a_well_c"),
                                         spawn(1, PIKE, 1, "a_depot", "res_a", "attack_move", "a_well_c")], once=False, cooldown=150, enabled=False)
    m.trig("t31_resupply_b", time_s(560), [spawn(1, BUF, 1, "a_dunes_s", "res_b", "attack_move", "a_well_b"), spawn(1, MAMBA, 1, "a_dunes_s", "res_b", "attack_move", "a_well_b"),
                                         spawn(1, UG, 2, "a_dunes_s", "res_b", "attack_move", "a_well_b")], once=False, cooldown=170, enabled=False)
    m.trig("t32_resupply_c", time_s(640), [spawn(1, BUF, 2, "a_dunes_n", "res_c", "attack_move", "a_well_a"), spawn(1, PIKE, 2, "a_dunes_n", "res_c", "attack_move", "a_well_a")],
           once=False, cooldown=200, enabled=False)
    m.trig("t33_depot_down", all_(active("depot"), struct("destroyed", placed="dep1"), struct("destroyed", placed="dep2"), struct("destroyed", placed="dep4")),
           [set_obj("depot", "completed"), say("depot_down"), disable("t30_resupply_a"), disable("t31_resupply_b"), disable("t32_resupply_c"), disable("t21_reveal")])
    m.trig("t40_last", time_s(660), [spawn(1, BUF, 1, "a_dunes_n", "last", "attack_move", "a_well_a"), spawn(1, BUF, 2, "a_dunes_s", "last", "attack_move", "a_well_b"),
                                     spawn(1, UG, 2, "a_dunes_n", "last", "attack_move", "a_well_c"), spawn(1, PIKE, 1, "a_dunes_s", "last", "attack_move", "a_well_c"),
                                     say("last_push")])
    m.trig("t50_pump_lost", all_(active("all_pumps"), any_(struct("destroyed", placed="well_a"), struct("destroyed", placed="well_b"), struct("destroyed", placed="well_c"))),
           [set_obj("all_pumps", "failed"), say("pump_lost")])
    m.trig("t51_obs_lost", all_(active("observer"), count(0, 1, "<", def_=OBS)), [set_obj("observer", "failed")])
    two_alive = any_(all_(not_(struct("destroyed", placed="well_a")), not_(struct("destroyed", placed="well_b"))),
                     all_(not_(struct("destroyed", placed="well_a")), not_(struct("destroyed", placed="well_c"))),
                     all_(not_(struct("destroyed", placed="well_b")), not_(struct("destroyed", placed="well_c"))))
    m.trig("t90_win", all_(timer("hold_t"), done("depot"), two_alive, count(0, 1, def_=HQ)),
           [set_obj("pumps", "completed"), set_obj("hq", "completed"), say("win"), say("debrief_win"), win(0), music("victory")])
    m.trig("t91_lose_pumps", not_(two_alive), [set_obj("pumps", "failed"), say("lose_pumps"), say("debrief_lose"), lose(0), music("defeat")])
    m.trig("t92_lose_hq", count(0, 0, "<=", def_=HQ), [set_obj("hq", "failed"), say("lose_base"), say("debrief_lose"), lose(0), music("defeat")])
    return m
