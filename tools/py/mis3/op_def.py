"""MIS3: OPERATION 4, DEF 'Iron Schedule' (op_def): rail-junction push with artillery saturation. Fault line: Eurasia / Han Empire."""
from .lib import *

HAMMER = "unit.def.hammer_tank"
ANVIL = "unit.def.anvil_rocket_battery"
CONS = "unit.def.line_conscript"
RECOIL = "unit.def.recoil_team"
BANNER = "unit.han.banner_infantry"
LANCE = "unit.han.lance_team"
OX = "unit.han.ox_tank"
NEST = "unit.han.nest_rocket_drone"
FIREFLY = "unit.han.firefly_aa_drone"
GEN = "structure.shared.generator"
REF = "structure.shared.refinery"
BAR = "structure.shared.barracks"
FAC = "structure.shared.factory"
LAB = "structure.shared.laboratory"
TUR = "structure.shared.anti_tank_turret"
WT = "structure.shared.watchtower"
HQ = "structure.shared.headquarters"
SP = "Supply Ministry"
HN = "Border Depot Command"


def junction(m, n, area):
    # a control post, two turrets, a watchtower, a garrison
    return [spawn_s(1, LAB, area, id="jct%d" % n), spawn_s(1, TUR, area, id="jt%da" % n), spawn_s(1, TUR, area, id="jt%db" % n), spawn_s(1, WT, area, id="jw%d" % n),
            spawn(1, BANNER, (3, 4, 5)[n - 1], area, "g%d" % n, "guard", area), spawn(1, LANCE, (2, 3, 3)[n - 1], area, "g%d" % n, "guard", area), spawn(1, OX, (1, 2, 2)[n - 1], area, "g%d" % n, "guard", area)]


def build():
    m = Mission("op_def", "Operation Iron Schedule", "operation", 4,
                {"family": "open", "size": 128, "seed": 31, "params": {"biome": 2}}, rules={"start_credits": 6000, "fog": 1}, sim_seed=4101)
    m.brief("Situation",
            "The Eurasian rail grid has three junctions on the border belt between the Federation's industrial districts and the Han "
            "Empire's northern depots. Whoever holds the junctions writes the freight timetable for a continent. The border depots "
            "were meant to be neutral. This winter the Empire's depot commands began refusing Federation trains, calling it scheduling.", "faction.def")
    m.brief("The Junctions",
            "The Supply Ministry has ordered a push: take the three junction control posts, one after the other, and put the timetable in "
            "Federation hands. Rocket batteries first, tanks second, conscripts third. The Han depot commanders are dug in with drones and "
            "short-range anti-armour. Do not send armour into a junction before the guns have finished with it.", "faction.han")
    m.brief("Orders",
            "Destroy the control posts at Junction One, Two and Three. Keep your Anvil batteries alive, they are what wins this. "
            "Near Junction Two stands a grain depot that feeds a district which did not vote for this war; rocket saturation does not "
            "distinguish between a post and the shed beside it. The Ministry says that is a detail. The district disagrees.")
    m.player(0, "human", "roster.def.vanilla", 1, "Staging Camp", "hq", credits=6000,
             units=[{"def": HAMMER, "count": 4, "dx": -6, "dy": -3}, {"def": ANVIL, "count": 2, "dx": -3, "dy": 6}, {"def": CONS, "count": 4, "dx": -7, "dy": 2},
                    {"def": RECOIL, "count": 2, "dx": -4, "dy": -7}],
             structures=[{"def": GEN, "dx": 5, "dy": 4}, {"def": GEN, "dx": 5, "dy": -5}, {"def": REF, "dx": 6, "dy": 0}, {"def": BAR, "dx": -2, "dy": 9},
                         {"def": FAC, "dx": -9, "dy": 4}, {"def": TUR, "dx": -11, "dy": -5}])
    m.player(1, "ai", "roster.han.vanilla", 2, "Border Depots", "hq", start_slot=2, ai={"level": 0, "style": 0, "active": False})

    m.circle("a_camp", 0, 0, 12, "start:0")
    m.circle("a_j1", -28, -14, 6, "start:0")
    m.circle("a_j2", -46, -38, 6, "start:0")
    m.circle("a_j3", -62, -58, 6, "start:0")
    m.circle("a_grain", -42, -33, 3, "start:0")
    m.circle("a_front", -14, -8, 6, "start:0")
    m.circle("a_drone_n", -25, -40, 6, "start:0")
    m.circle("a_drone_w", -45, -4, 6, "start:0")

    m.msg("intro", "Staging Camp, this is the Supply Ministry. The timetable begins at Junction One. Guns first. Move at your own discretion, but move.", SP, "match_start_def")
    m.msg("j1_down", "Junction One is ours. The Ministry notes the timetable has changed. On to Junction Two.", SP, "building_captured")
    m.msg("j2_down", "Junction Two has fallen. Two of three. The Han depot commands are no longer answering the Ministry's signals.", SP, "building_captured")
    m.msg("j3_down", "Junction Three is down. The northern belt is under Federation schedule.", SP, "building_captured")
    m.msg("twist", "Staging Camp: the Han depot command is not waiting. A drone swarm is coming out of the western belt for your camp. Your guns are forward. Decide who defends the camp.", SP, "base_under_attack")
    m.msg("han_voice", "Federation column, you are in breach of the Border Depot Charter. Withdraw and the timetable is yours by treaty in the spring.", HN)
    m.msg("grain_lost", "The grain depot is gone. The district's delegates are already leaving the assembly.", SP, "structure_lost")
    m.msg("late", "The Ministry's patience is not unlimited. Two minutes remain in the window.", SP)
    m.msg("lose_camp", "The Staging Camp is lost. The push is over.", SP, "defeat")
    m.msg("lose_time", "The window has closed. The Ministry is recalling the column.", SP, "defeat")
    m.msg("win", "All three junctions are in Federation hands. The timetable is written.", SP, "victory")
    m.msg("debrief_win", "DEBRIEF: the Federation now schedules the northern belt. The Ministry calls this industrial recovery. The Han depot commands call it occupation, and the district behind the grain depot calls it neither, because nobody asked it. In the capitals both sides are already negotiating who owns the timetable the rail will actually run on.", "Debrief")
    m.msg("debrief_lose", "DEBRIEF: the push stalled. The junctions stay under Han schedule; the Ministry will ask the districts for more quotas, and the districts will answer.", "Debrief")

    m.objective("j1", "primary", "Destroy the control post at Junction One", "active")
    m.objective("j2", "primary", "Destroy the control post at Junction Two", "hidden")
    m.objective("j3", "primary", "Destroy the control post at Junction Three", "hidden")
    m.objective("grain", "secondary", "Do not destroy the grain depot beside Junction Two", "hidden")
    m.objective("guns", "secondary", "Finish with at least two Anvil batteries", "active")

    m.trig("t00_start", time_t(0), [say("intro"), music("calm")] + junction(m, 1, "a_j1"))
    m.trig("t01_ai_on", time_s(360), [change_ai(1, active=True)])
    m.trig("t05_garrison_2", time_s(1), junction(m, 2, "a_j2") + [spawn_s("neutral", REF, "a_grain", id="grain_depot"), set_obj("grain", "active")])
    m.trig("t06_garrison_3", time_s(2), junction(m, 3, "a_j3"))
    m.trig("t10_reveal1", active("j1"), [reveal(0, "a_j1", 10)], once=False, cooldown=60)
    m.trig("t11_reveal2", active("j2"), [reveal(0, "a_j2", 10)], once=False, cooldown=60)
    m.trig("t12_reveal3", active("j3"), [reveal(0, "a_j3", 10)], once=False, cooldown=60)
    m.trig("t20_j1", all_(active("j1"), struct("destroyed", placed="jct1")), [set_obj("j1", "completed"), set_obj("j2", "active"), say("j1_down"), cam("a_j2", seconds=5)])
    m.trig("t21_j2", all_(active("j2"), struct("destroyed", placed="jct2")),
           [set_obj("j2", "completed"), set_obj("j3", "active"), say("j2_down"), say("han_voice"), cam("a_j3", seconds=5), music("tense")])
    m.trig("t22_j3", all_(active("j3"), struct("destroyed", placed="jct3")), [set_obj("j3", "completed")])
    # the twist: a drone swarm hits the camp when the second junction falls (or at 9:00)
    m.trig("t30_swarm", any_(done("j2"), time_s(540)),
           [spawn(1, NEST, 4, "a_drone_n", "swarm", "attack_move", "a_camp"), spawn(1, FIREFLY, 2, "a_drone_n", "swarm", "attack_move", "a_camp"),
            spawn(1, BANNER, 4, "a_drone_w", "swarm", "attack_move", "a_camp"), spawn(1, OX, 2, "a_drone_w", "swarm", "attack_move", "a_camp"), say("twist"), music("combat")])
    m.trig("t31_swarm2", time_s(780), [spawn(1, NEST, 4, "a_drone_w", "swarm2", "attack_move", "a_camp"), spawn(1, BANNER, 4, "a_drone_n", "swarm2", "attack_move", "a_camp"),
                                       spawn(1, OX, 2, "a_drone_n", "swarm2", "attack_move", "a_camp")])
    m.trig("t40_grain", all_(active("grain"), struct("destroyed", placed="grain_depot")), [set_obj("grain", "failed"), say("grain_lost")])
    m.trig("t41_guns", all_(active("guns"), count(0, 2, "<", def_=ANVIL)), [set_obj("guns", "failed")])
    m.trig("t80_late", time_s(1080), [say("late")])
    m.trig("t90_win", all_(done("j1"), done("j2"), done("j3")), [say("win"), say("debrief_win"), win(0), music("victory")])
    m.trig("t91_lose_camp", count(0, 0, "<=", def_=HQ), [say("lose_camp"), say("debrief_lose"), lose(0), music("defeat")])
    m.trig("t92_lose_time", time_s(1200), [say("lose_time"), say("debrief_lose"), lose(0), music("defeat")])
    return m
