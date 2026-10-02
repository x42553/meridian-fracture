"""MIS3: OPERATION 8, SAP 'Slow Tide' (op_sap): protected advance with interception and layered defences. Fault line: Pacific / Protectorate."""
from .lib import *

BUL = "unit.sap.bulwark_tank"
SHIELD = "unit.sap.shield_rifle_squad"
KAV = "unit.sap.kavach_team"
MON = "unit.sap.monsoon_howitzer"
VAJRA = "unit.sap.vajra_aa"
RANGER = "unit.pd.ranger_marine"
HARPOON = "unit.pd.harpoon_team"
TIDE = "unit.pd.tide_tank"
BREAKER = "unit.pd.breaker_howitzer"
STORM = "unit.pd.storm_aa"
SKIM = "unit.pd.wake_skimmer"
GEN = "structure.shared.generator"
REF = "structure.shared.refinery"
BAR = "structure.shared.barracks"
FAC = "structure.shared.factory"
RAD = "structure.shared.radar"
LAB = "structure.shared.laboratory"
TUR = "structure.shared.anti_tank_turret"
AAB = "structure.shared.aa_battery"
WT = "structure.shared.watchtower"
HQ = "structure.shared.headquarters"
TRIDENT = "structure.sap.trident_interception_array"
BASTION = "structure.sap.bastion_missile_tower"
SP = "Protectorate Council"
PD = "Inspection Fleet"


def build():
    m = Mission("op_sap", "Operation Slow Tide", "operation", 8,
                {"family": "coast", "size": 128, "seed": 5, "params": {"water_pct": 20, "start_near_water": 1}}, rules={"start_credits": 9000, "fog": 1}, sim_seed=8101)
    m.brief("Situation",
            "The strait road is the last land route along which the Protectorate can move evacuation convoys. Three weeks ago the Dominion's "
            "Inspection Fleet declared a customs post at the mouth of the road, 'to inspect cargo for the safety of every flag'. Nothing "
            "has passed it since. The Protectorate and the Dominion share a history of evacuation work and a growing argument about who "
            "may inspect whose cargo and where foreign bases may stand.", "faction.sap")
    m.brief("The Inspection Post",
            "The Dominion's customs post is real, armed and artillery-supported. Its howitzers can reach the road from two ridges. "
            "The Council does not want a war: it wants the road open before the evacuation window closes. It is not willing to send "
            "armour down a road covered by guns, so the advance will be slow, protected and layered.", "faction.pd")
    m.brief("Orders",
            "Advance in three lines. Line Bravo, Line Charlie, then the customs post itself. At each line your army holds under fire "
            "until the line is quiet: use the Trident Interception Array to blanket the army when the guns open, Protected Advance and "
            "the Emergency Fortification for the infantry screen, and keep the base behind you layered with turrets and towers: "
            "the Dominion will land marines behind your line once it realises what you are doing. The post is yours when its Inspection Hall is rubble.")
    m.player(0, "human", "roster.sap.vanilla", 1, "Strait Column", "hq", credits=9000,
             units=[{"def": BUL, "count": 4, "dx": -6, "dy": -3}, {"def": SHIELD, "count": 4, "dx": -4, "dy": 5}, {"def": KAV, "count": 2, "dx": -8, "dy": 1},
                    {"def": MON, "count": 2, "dx": -3, "dy": 8}, {"def": VAJRA, "count": 1, "dx": -2, "dy": -7}],
             structures=[{"def": GEN, "dx": 5, "dy": 4}, {"def": GEN, "dx": 5, "dy": -5}, {"def": GEN, "dx": 9, "dy": 0}, {"def": REF, "dx": 6, "dy": -9}, {"def": REF, "dx": 8, "dy": 5},
                         {"def": BAR, "dx": -2, "dy": 9}, {"def": FAC, "dx": 2, "dy": -10}, {"def": RAD, "dx": 9, "dy": 8}, {"def": TUR, "dx": -11, "dy": -4},
                         {"def": AAB, "dx": -10, "dy": 4}, {"def": TRIDENT, "dx": -8, "dy": 9, "id": "trident"}])
    m.player(1, "ai", "roster.pd.vanilla", 2, "Inspection Fleet", "hq", start_slot=3, ai={"level": 0, "style": 0, "active": False})

    m.circle("a_base", 0, 0, 12, "start:0")
    m.circle("a_lb", -4, -24, 6, "start:0")
    m.circle("a_lc", -4, -38, 6, "start:0")
    m.circle("a_post", -6, -58, 7, "start:0")
    m.circle("a_ridge_w", -13, -29, 3, "start:0")
    m.circle("a_ridge_e", 5, -31, 3, "start:0")
    m.circle("a_beach", 14, 6, 5, "start:0")
    m.circle("a_flank", -26, 4, 5, "start:0")
    m.circle("a_front", -4, -12, 6, "start:0")

    m.msg("intro", "Strait Column, Protectorate Council. The road is open as far as Line Bravo. Advance in order, under the Trident, and do not outrun your own guns.", SP, "match_start_sap")
    m.msg("hint_trident", "The Trident Array in your base takes about six minutes to charge. Aim it at the army when the Dominion guns open: for twenty-five seconds every shell that crosses the ring is destroyed.", SP, "sw_charging")
    m.msg("lb_in", "Line Bravo reached. Hold it until the guns have found you, then we move.", SP)
    m.msg("lb_done", "Line Bravo is quiet. On to Line Charlie.", SP, "building_captured")
    m.msg("guns", "Dominion howitzers have opened from the ridges! Interception now, or take cover!", SP, "base_under_attack")
    m.msg("guns_out", "The ridge guns are silent. Line Bravo is quiet.", SP)
    m.msg("lc_in", "Line Charlie reached. The customs post is in sight.", SP)
    m.msg("lc_done", "Line Charlie is held. The Inspection Hall is the last objective.", SP, "building_captured")
    m.msg("landing", "Dominion marines are coming ashore behind the column! Your base is the next target. Turn and defend the road!", SP, "base_under_attack")
    m.msg("pd_voice", "Protectorate column: the customs post is neutral ground. Turn back and the Fleet will guarantee safe passage by sea.", PD)
    m.msg("tower_lost", "The interception array is down. The guns will find the column.", SP, "structure_lost")
    m.msg("lose_hq", "The base has fallen behind the column. There is no road to hold.", SP, "defeat")
    m.msg("lose_time", "The evacuation window has closed. The Council recalls the column.", SP, "defeat")
    m.msg("win", "The Inspection Hall is rubble and the road is open. The evacuees are moving.", SP, "victory")
    m.msg("debrief_win", "DEBRIEF: the strait road is open and the first evacuation convoy moved within the hour. The Dominion calls the action a breach of the customs charter; the Council calls it a rescue. Reformers in the Council point out that the Protectorate's guards were not asked to leave when the emergency ended either, and that this is what both sides have in common.", "Debrief")
    m.msg("debrief_lose", "DEBRIEF: the advance failed. The post stays, the guns stay, and the evacuees stay on the wrong side of both.", "Debrief")

    m.objective("advance", "primary", "Advance in order: Line Bravo (silence the ridge guns, hold), then Line Charlie (hold)", "active")
    m.objective("lb", "hidden", "Line Bravo", "active")
    m.objective("lc", "hidden", "Line Charlie", "hidden")
    m.objective("post", "primary", "Destroy the Inspection Hall at the customs post", "hidden")
    m.objective("base", "primary", "Do not lose the base", "active")
    m.objective("guns", "hidden", "Dominion guns firing on Line Bravo", "hidden")
    m.objective("trident", "secondary", "Keep the Trident Interception Array alive", "active")
    m.objective("layers", "secondary", "Layer the base: build at least four defensive structures", "active")
    m.timer("hold_b", 120, "Hold Line Bravo")
    m.timer("hold_c", 90, "Hold Line Charlie")

    # the post: hall + turrets + AA + garrison; two howitzer ridges
    post = [spawn_s(1, LAB, "a_post", id="hall"), spawn_s(1, TUR, "a_post", id="pt1"), spawn_s(1, AAB, "a_post", id="paa"), spawn_s(1, WT, "a_post", id="pwt"),
            spawn(1, RANGER, 3, "a_post", "post_g", "guard", "a_post"), spawn(1, HARPOON, 2, "a_post", "post_g", "guard", "a_post"), spawn(1, TIDE, 1, "a_post", "post_g", "guard", "a_post")]
    m.trig("t00_start", time_t(0), [say("intro"), set_obj("lb", "active"), music("calm")] + post)
    m.trig("t01_ai_on", time_s(360), [change_ai(1, active=True)])
    m.trig("t02_hint", time_s(60), [say("hint_trident")])
    m.trig("t03_pd_voice", time_s(480), [say("pd_voice")])
    m.trig("t05_reveal_lb", active("lb"), [reveal(0, "a_lb", 6)], once=False, cooldown=90)
    # line bravo: army in the area, then the guns open, then the hold timer
    bravo_in = count(0, 6, tag="combat", area="a_lb")
    m.trig("t10_lb_in", all_(active("lb"), bravo_in, time_s(340)),
           [set_obj("guns", "active"), say("lb_in"), say("guns"), spawn(1, BREAKER, 3, "a_ridge_w", "guns_w", "hold"), spawn(1, STORM, 1, "a_ridge_w", "guns_w", "guard", "a_ridge_w"),
            spawn(1, BREAKER, 2, "a_ridge_e", "guns_e", "hold"), spawn(1, RANGER, 2, "a_ridge_e", "guns_e", "guard", "a_ridge_e"), timer_start("hold_b"), music("combat")])
    m.trig("t11_lb_done", all_(active("lb"), timer("hold_b"), bravo_in, wave("guns_w", "cleared"), wave("guns_e", "cleared")),
           [set_obj("lb", "completed"), set_obj("guns", "completed"), say("lb_done"), say("guns_out"), music("tense")])
    m.trig("t11b_open_c", all_(done("lb"), time_s(420)), [set_obj("lc", "active")])
    charlie_in = count(0, 6, tag="combat", area="a_lc")
    m.trig("t12_lc_in", all_(active("lc"), charlie_in),
           [say("lc_in"), spawn(1, RANGER, 3, "a_flank", "marines", "attack_move", "a_base"), spawn(1, TIDE, 1, "a_beach", "marines", "attack_move", "a_base"),
            spawn(1, SKIM, 1, "a_beach", "marines", "attack_move", "a_base"), say("landing"), timer_start("hold_c"), cam("a_base", seconds=4), music("combat")])
    m.trig("t12b_lc_done", all_(active("lc"), timer("hold_c"), charlie_in), [set_obj("lc", "completed"), set_obj("advance", "completed"), say("lc_done"), music("tense")])
    m.trig("t12c_open_post", all_(done("lc"), time_s(660)), [set_obj("post", "active")])
    m.trig("t13_post_down", all_(active("post"), struct("destroyed", placed="hall")), [set_obj("post", "completed")])
    m.trig("t14_more_marines", time_s(900), [spawn(1, RANGER, 3, "a_flank", "marines2", "attack_move", "a_base"), spawn(1, TIDE, 2, "a_beach", "marines2", "attack_move", "a_base")])
    m.trig("t20_tower", all_(active("trident"), struct("destroyed", placed="trident")), [set_obj("trident", "failed"), say("tower_lost")])
    m.trig("t21_layers", all_(active("layers"), count(0, 4, of="structure", tag="defense")), [set_obj("layers", "completed")])
    m.trig("t90_win", all_(done("lb"), done("lc"), done("post")), [set_obj("base", "completed"), say("win"), say("debrief_win"), win(0), music("victory")])
    m.trig("t91_lose_hq", count(0, 0, "<=", def_=HQ), [set_obj("base", "failed"), say("lose_hq"), say("debrief_lose"), lose(0), music("defeat")])
    m.trig("t92_lose_time", time_s(1320), [say("lose_time"), say("debrief_lose"), lose(0), music("defeat")])
    return m
