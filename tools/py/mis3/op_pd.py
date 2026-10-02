"""MIS3: OPERATION 5, PD 'Marais Landing' (op_pd): amphibious landing to seize a treaty port. Fault line: Pacific / Han Empire."""
from .lib import *

TIDE = "unit.pd.tide_tank"
RANGER = "unit.pd.ranger_marine"
HARPOON = "unit.pd.harpoon_team"
SKIM = "unit.pd.wake_skimmer"
STORM = "unit.pd.storm_aa"
BANNER = "unit.han.banner_infantry"
LANCE = "unit.han.lance_team"
OX = "unit.han.ox_tank"
NEST = "unit.han.nest_rocket_drone"
JADE = "unit.han.jade_carrier"
GEN = "structure.shared.generator"
REF = "structure.shared.refinery"
BAR = "structure.shared.barracks"
FAC = "structure.shared.factory"
DOCK = "structure.shared.dock"
TUR = "structure.shared.anti_tank_turret"
AAB = "structure.shared.aa_battery"
WT = "structure.shared.watchtower"
HQ = "structure.shared.headquarters"
SP = "Landing Group"
HN = "Harbour Command"


def build():
    m = Mission("op_pd", "Operation Marais Landing", "operation", 5,
                {"family": "coast", "size": 128, "seed": 3, "params": {"water_pct": 25, "start_near_water": 1}}, rules={"start_credits": 5500, "fog": 1}, sim_seed=5101)
    m.brief("Situation",
            "Port Marais is a treaty port: a free harbour that belongs to nobody and trades with everybody under a charter signed in the "
            "last year of the corridor settlement. Eleven days ago a Han Empire harbour command moved in 'to guarantee the schedule', and "
            "the port's shipping council has been unable to meet since. The Dominion does not claim the port. It claims the right of "
            "its ships to dock there.", "faction.pd")
    m.brief("The Han Harbour Command",
            "The Empire says the garrison is temporary. It has been temporary for eleven days, and it has brought turrets, anti-aircraft "
            "guns and a drone nest. The Dominion Landing Group has the amphibious tanks and skimmers to cross the bay and take the quays. "
            "Taking a port is the easy half. The harder half is persuading the people who live there to accept whoever wins.", "faction.han")
    m.brief("Orders",
            "Land, clear the port district and hold it. Once the harbour is yours the Empire will try to take it back: hold it for seven "
            "minutes. Do not shell the harbour office, it is the one building the shipping council still uses. Amphibious units cross water "
            "at nearly full speed; use the bay, not the coast road. A seized port in seven minutes would make the right point to the right people.")
    m.player(0, "human", "roster.pd.vanilla", 1, "Landing Group", "hq", credits=5500,
             units=[{"def": TIDE, "count": 4, "dx": 6, "dy": 2}, {"def": RANGER, "count": 3, "dx": 5, "dy": 6}, {"def": HARPOON, "count": 2, "dx": 3, "dy": 7},
                    {"def": SKIM, "count": 2, "dx": 7, "dy": -3}, {"def": STORM, "count": 1, "dx": 2, "dy": 8}],
             structures=[{"def": GEN, "dx": -5, "dy": 4}, {"def": GEN, "dx": -5, "dy": -5}, {"def": REF, "dx": -7, "dy": 0}, {"def": BAR, "dx": -3, "dy": 9},
                         {"def": FAC, "dx": 2, "dy": -9}, {"def": TUR, "dx": -11, "dy": -4}])
    m.player(1, "ai", "roster.han.vanilla", 2, "Harbour Command", "hq", start_slot=2, ai={"level": 0, "style": 0, "active": False})

    m.circle("a_base", 0, 0, 12, "start:0")
    m.circle("a_port", 500, 345, 7, "map")
    m.circle("a_port_wide", 500, 345, 13, "map")
    m.circle("a_office", 530, 330, 3, "map")
    m.circle("a_beach", 500, 400, 6, "map")
    m.circle("a_north", 380, 250, 6, "map")
    m.circle("a_west", 250, 420, 6, "map")
    m.circle("a_front", -14, -14, 7, "start:0")

    m.msg("intro", "Landing Group, this is the fleet. The bay is calm and the harbour is in sight. Clear the quays and hold them. Seven minutes would make the right point.", SP, "match_start_pd")
    m.msg("seized", "The quays are ours. The shipping council is signalling from the harbour office. Hold the port for seven minutes: the Empire will not leave it at that.", SP, "building_captured")
    m.msg("counter1", "Han counter-attack from the north road: drone nests and armour. The port is the prize, not the road.", SP, "base_under_attack")
    m.msg("counter2", "Second counter-attack from the west road and a jade carrier on the bay.", SP, "base_under_attack")
    m.msg("counter3", "They are throwing everything at the quays. Seven minutes, Landing Group.", SP, "base_under_attack")
    m.msg("counter4", "Last wave: everything the harbour command has left, from the north road, the west road and the bay.", SP, "base_under_attack")
    m.msg("han_voice", "Dominion units: you are in violation of the Treaty Port Charter. Withdraw and the council will be reconvened under neutral chairmanship.", HN)
    m.msg("office_lost", "The harbour office has been hit. The shipping council has lost its meeting hall, and they will remember who fired.", SP, "structure_lost")
    m.msg("fast", "The port fell inside seven minutes. The fleet will remember it.", SP)
    m.msg("slow", "Seven minutes are gone. The right people will have made up their minds already.", SP)
    m.msg("lose_hq", "The beachhead is overrun. The Landing Group is withdrawing under fire.", SP, "defeat")
    m.msg("lose_port", "The port has been retaken. The Landing Group has no foothold left.", SP, "defeat")
    m.msg("lose_time", "The window for the landing has closed. The fleet is recalled.", SP, "defeat")
    m.msg("win", "Seven minutes. The port is quiet and the council is in session. The treaty port is open to every flag again.", SP, "victory")
    m.msg("debrief_win", "DEBRIEF: the Landing Group holds the quays and the shipping council meets under Dominion escort. The Empire protests that the charter forbids foreign garrisons, and the Dominion answers that its own garrison is eleven days shorter than the Empire's. Residents on the quayside are not sure which of them they trust less.", "Debrief")
    m.msg("debrief_lose", "DEBRIEF: the landing failed. The Empire's garrison is now permanent, and so is the shipping council's silence.", "Debrief")

    m.objective("seize", "primary", "Land, clear the Port of Marais and take the quays", "active")
    m.objective("hold", "primary", "Hold the port for 7:00 against the counter-attack", "hidden")
    m.objective("hq", "primary", "Keep your beachhead headquarters standing", "active")
    m.objective("office", "secondary", "Spare the harbour office", "active")
    m.objective("swift", "secondary", "Take the port within 7:00", "active")
    m.timer("hold_t", 420, "Hold the port")
    m.timer("c2_t", 60, "Second counter-attack")
    m.timer("c3_t", 150, "Third counter-attack")
    m.timer("c4_t", 280, "Fourth counter-attack")

    garrison = [spawn_s("neutral", DOCK, "a_port", id="p_dock"), spawn_s("neutral", REF, "a_port", id="p_hall"), spawn_s(1, TUR, "a_port", id="p_t1"), spawn_s(1, TUR, "a_port", id="p_t2"),
                spawn_s(1, AAB, "a_port", id="p_aa"), spawn_s(1, WT, "a_port", id="p_wt"), spawn_s("neutral", REF, "a_office", id="harbour_office"),
                spawn(1, BANNER, 4, "a_port", "garrison", "guard", "a_port"), spawn(1, LANCE, 3, "a_port", "garrison", "guard", "a_port"),
                spawn(1, OX, 2, "a_port", "garrison", "guard", "a_port")]
    m.trig("t00_start", time_t(0), [say("intro"), music("calm")] + garrison)
    m.trig("t01_ai_on", time_s(150), [change_ai(1, active=True)])
    m.trig("t02_reveal", active("seize"), [reveal(0, "a_port_wide", 10)], once=False, cooldown=60)
    port_clear = all_(count("enemies_of:0", 0, "==", of="any", area="a_port_wide"), count(0, 4, area="a_port"), time_s(5))
    m.trig("t10_seize", all_(active("seize"), port_clear),
           [set_obj("seize", "completed"), set_obj("hold", "active"), say("seized"), say("han_voice"), transfer(0, placed="p_dock"), transfer(0, placed="p_hall"),
            timer_start("hold_t"), timer_start("c2_t"), timer_start("c3_t"), timer_start("c4_t"), enable("t23_c4"), enable("t20_c1"), enable("t21_c2"), enable("t22_c3"), music("combat"), cam("a_port", seconds=5)])
    m.trig("t11_swift_ok", all_(done("seize"), active("swift")), [set_obj("swift", "completed"), say("fast")])
    m.trig("t12_swift_fail", all_(active("seize"), active("swift"), time_s(420)), [set_obj("swift", "failed"), say("slow")])
    # the counter-attack once the port is taken
    m.trig("t20_c1", done("seize"), [spawn(1, NEST, 3, "a_north", "c1", "attack_move", "a_port"), spawn(1, BANNER, 2, "a_north", "c1", "attack_move", "a_port"),
                                 spawn(1, OX, 1, "a_north", "c1", "attack_move", "a_port"), say("counter1")], enabled=False)
    m.trig("t21_c2", timer("c2_t"), [spawn(1, BANNER, 3, "a_west", "c2", "attack_move", "a_port"), spawn(1, LANCE, 1, "a_west", "c2", "attack_move", "a_port"),
                                    spawn(1, OX, 1, "a_west", "c2", "attack_move", "a_port"), spawn(1, JADE, 1, "a_beach", "c2", "attack_move", "a_port"), say("counter2")], enabled=False)
    m.trig("t22_c3", timer("c3_t"), [spawn(1, NEST, 2, "a_west", "c3", "attack_move", "a_port"), spawn(1, OX, 2, "a_north", "c3", "attack_move", "a_port"),
                                    spawn(1, BANNER, 3, "a_north", "c3", "attack_move", "a_port"), say("counter3")], enabled=False)
    m.trig("t23_c4", timer("c4_t"), [spawn(1, NEST, 2, "a_north", "c4", "attack_move", "a_port"), spawn(1, OX, 2, "a_west", "c4", "attack_move", "a_port"),
                                    spawn(1, BANNER, 3, "a_west", "c4", "attack_move", "a_port"), spawn(1, JADE, 1, "a_beach", "c4", "attack_move", "a_port"), say("counter4")], enabled=False)
    m.trig("t30_office", all_(active("office"), struct("destroyed", placed="harbour_office")), [set_obj("office", "failed"), say("office_lost")])
    holding = count(0, 2, area="a_port_wide")
    m.trig("t90_win", all_(active("hold"), timer("hold_t"), holding), [set_obj("hold", "completed"), say("win"), say("debrief_win"), win(0), music("victory")])
    m.trig("t91_lose_hq", count(0, 0, "<=", def_=HQ), [set_obj("hq", "failed"), say("lose_hq"), say("debrief_lose"), lose(0), music("defeat")])
    m.trig("t92_lose_port", all_(active("hold"), all_(not_(count(0, 1, area="a_port_wide")), count("enemies_of:0", 3, area="a_port_wide"))),
           [set_obj("hold", "failed"), say("lose_port"), say("debrief_lose"), lose(0), music("defeat")])
    m.trig("t93_lose_time", all_(active("seize"), time_s(1080)), [set_obj("seize", "failed"), say("lose_time"), say("debrief_lose"), lose(0), music("defeat")])
    return m
