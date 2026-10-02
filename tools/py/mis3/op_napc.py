"""MIS3: OPERATION 1, NAPC 'Open Road' (op_napc): evacuation corridor hold with vehicle recovery. Fault line: North America / Europe."""
from .lib import *

APC = "unit.napc.pathfinder_apc"
TANK = "unit.napc.guardian_tank"
JAV = "unit.napc.javelin_team"
RIFLE = "unit.napc.rifle_squad"
LEO = "unit.nec.leopard_tank"
JAGER = "unit.nec.jager_squad"
SPIKE = "unit.nec.spike_team"
TUR = "structure.shared.anti_tank_turret"
WT = "structure.shared.watchtower"
SP = "Corps Command"
OV = "Oversight Mission"


def build():
    m = Mission("op_napc", "Operation Open Road", "operation", 1,
                {"family": "open", "size": 128, "seed": 14}, rules={"start_credits": 6000, "fog": 1}, sim_seed=1401)
    m.brief("Situation",
            "Two weeks after a grid collapse flooded the lower Dunmore district, the Peace Corps relief command is moving fifteen thousand people "
            "up the Dunmore Corridor, a single road along the southern escarpment. Your Corridor Post at the eastern end is the only place the "
            "convoys can unload. Three evacuation columns of four Pathfinder APCs are staged at the western depot.", "faction.napc")
    m.brief("The Oversight Mission",
            "The Confederation's Oversight Mission sits north of the road and has agreed to the relief on one condition: every column is "
            "inspected by a civilian board before it passes. The Assembly refuses to let a foreign board delay a rescue; the Confederation "
            "refuses to let a military command decide alone. Both are right about the other. Expect that argument to stop being polite.", "faction.nec")
    m.brief("Orders",
            "Hold the Post, keep the road open and get all three columns through, with at least three vehicles of each column arriving. "
            "Recover the vehicles stranded halfway along the road if you can; the Corps does not leave equipment behind. "
            "Doctrine: durable armour, repair at the factory apron, patience.")
    m.player(0, "human", "roster.napc.vanilla", 1, "Corridor Post", "hq", credits=6000,
             units=[{"def": TANK, "count": 4, "dx": 5, "dy": 3}, {"def": JAV, "count": 2, "dx": 3, "dy": 6}, {"def": RIFLE, "count": 2, "dx": 6, "dy": 6}])
    m.player(1, "ai", "roster.napc.vanilla", 1, "Relief Column", "none", start_slot=1, ai={"level": 0, "style": 0, "active": False})
    m.player(2, "ai", "roster.nec.vanilla", 2, "Oversight Mission", "hq", start_slot=2, ai={"level": 0, "style": 0, "active": False})

    m.circle("a_post", 0, 0, 10, "start:0")
    m.circle("a_exit", -5, 2, 6, "start:0")
    m.circle("a_wp1", -46, 2, 5, "start:0")
    m.circle("a_wp2", -24, 2, 5, "start:0")
    m.circle("a_depot", 4, 2, 5, "start:1")
    m.circle("a_strand", -17, -12, 4, "start:0")
    m.circle("a_chk", -22, -4, 5, "start:0")
    m.circle("a_ridge1", -30, -26, 5, "start:0")
    m.circle("a_ridge2", -50, -24, 5, "start:0")
    m.circle("a_ridge3", -12, -30, 5, "start:0")

    m.msg("intro", "Corridor Post, this is Corps Command. Column Alpha leaves the depot in two minutes. The Oversight Mission has not yet answered our last signal.", SP, "match_start_napc")
    m.msg("launch_a", "Column Alpha is rolling. Four APCs, west to east. Keep the road clear.", SP)
    m.msg("launch_b", "Column Bravo is rolling. The checkpoint is down, the road is ours. Four APCs, west to east.", SP)
    m.msg("launch_c", "Column Charlie, the last one, is rolling. Everything we have left on that road is in it.", SP)
    m.msg("hop", "The column is moving up the next stretch of the road.", SP)
    m.msg("strand", "Three of our APCs broke down on the ridge track north of the road and the crews walked on. Tow them back to the Post when the road is quiet: the factory apron will repair them.", SP)
    m.msg("arr_a", "Alpha is through. Fifty-odd families off the road. Good work, Post.", SP)
    m.msg("arr_b", "Bravo is through. Two columns down, one to go.", SP)
    m.msg("arr_c", "Charlie is through. That is everyone. Corridor Post, the road is yours.", SP)
    m.msg("twist", "Post, the Oversight Mission has just declared the corridor closed to unsupervised traffic and is raising a checkpoint at the halfway marker. They are reinforcing it. They will not let Bravo through. We cannot wait for another round of talks.", SP, "base_under_attack")
    m.msg("ov_warn", "Corps column, you will halt at the inspection point. This is the last notice. A civilian board answers for every vehicle on that road.", OV)
    m.msg("chk_down", "The checkpoint is down. Bravo can move. Whatever the Assembly decides about this, the road is open.", SP)
    m.msg("late", "The evacuation window is closing. If the columns are not through in the next two minutes the flood takes the lower road.", SP, "unit_under_attack")
    m.msg("lose_post", "The Corridor Post has fallen. The road is lost.", SP, "defeat")
    m.msg("lose_col", "The column was destroyed on the road. There is nothing more to bring through.", SP, "defeat")
    m.msg("lose_time", "The window has closed. The lower road is under water.", SP, "defeat")
    m.msg("win", "All three columns are through. The Assembly will call this a rescue and the Confederation will call it a breach. Both of them are going to ask who gave the order at the checkpoint.", SP, "victory")
    m.msg("debrief_win", "DEBRIEF: the relief reached its people. The Oversight Mission filed a protest within the hour; the Assembly's reply was one line long. In the capitals, the argument over who may command a shared relief operation has just become a real one.", "Debrief")
    m.msg("debrief_lose", "DEBRIEF: the corridor was lost. Both commands blame the other for the delay, and the people on the lower road blame both.", "Debrief")

    m.objective("evac", "primary", "Deliver all three evacuation columns (3 of 4 APCs each) to the Corridor Post", "active")
    m.objective("post", "primary", "Hold the Corridor Post", "active")
    m.objective("checkpoint", "primary", "Break the Oversight checkpoint at the halfway marker", "hidden")
    m.objective("recover", "secondary", "Recover the three stranded APCs to the Post", "hidden")
    m.objective("intact", "secondary", "Lose no evacuation APC", "active")
    for c in "abc":
        m.objective("live_" + c, "hidden", "Column %s on the road" % c.upper(), "hidden")
        m.objective("done_" + c, "hidden", "Column %s delivered" % c.upper(), "hidden")
    m.timer("hop_t", 40, "Column hop", repeat=True)

    m.trig("t00_start", time_t(0), [say("intro"), music("calm")])
    m.trig("t01_ai_on", time_s(240), [change_ai(2, active=True)])
    m.trig("t02_strand", time_s(270), [spawn(0, APC, 3, "a_strand", None, "hold"), say("strand"), set_obj("recover", "active")])
    m.trig("t03_recover", all_(active("recover"), count(0, 3, def_=APC, area="a_post")), [set_obj("recover", "completed")])

    def column(tag, launch_cond, msg, raid_units, nxt=None):
        t = "t1" + tag
        m.trig(t + "0_launch", launch_cond,
               [spawn(1, APC, 4, "a_depot", "col_" + tag, "move", "a_wp1"), say(msg), music("tense"), set_obj("live_" + tag, "active"),
                timer_start("hop_t"), enable(t + "1_hop1")] + raid_units)
        m.trig(t + "1_hop1", timer("hop_t"), [order(1, "move", order_area="a_wp2"), say("hop"), timer_start("hop_t"), enable(t + "2_hop2"), enable(t + "3a_loss"), enable(t + "4_fail")], enabled=False)
        m.trig(t + "2_hop2", timer("hop_t"), [order(1, "move", order_area="a_exit"), disable(t + "1_hop1")], enabled=False)
        m.trig(t + "3a_loss", all_(active("intact"), active("live_" + tag), count(1, 4, "<", def_=APC), count(1, 3, area="a_exit", def_=APC)),
               [set_obj("intact", "failed")], enabled=False)
        m.trig(t + "3b_arrive", all_(active("live_" + tag), count(1, 3, def_=APC, area="a_exit")),
               [set_obj("live_" + tag, "completed"), set_obj("done_" + tag, "completed"), say("arr_" + tag), destroy(owner=1, def_=APC), music("calm"),
                timer_stop("hop_t")])
        m.trig(t + "4_fail", all_(active("live_" + tag), count(1, 3, "<", def_=APC)),
               [say("lose_col"), say("debrief_lose"), set_obj("evac", "failed"), lose(0), music("defeat")], enabled=False)

    raid_a = [spawn(2, LEO, 2, "a_ridge1", "raid_a", "attack_move", "a_wp2"), spawn(2, JAGER, 1, "a_ridge1", "raid_a", "attack_move", "a_wp2")]
    raid_b = [spawn(2, LEO, 3, "a_ridge2", "raid_b", "attack_move", "a_wp2"), spawn(2, JAGER, 2, "a_ridge2", "raid_b", "attack_move", "a_wp2"),
              spawn(2, SPIKE, 1, "a_ridge3", "raid_b", "attack_move", "a_exit")]
    raid_c = [spawn(2, LEO, 3, "a_ridge2", "raid_c", "attack_move", "a_wp2"), spawn(2, JAGER, 2, "a_ridge1", "raid_c", "attack_move", "a_wp2"),
              spawn(2, SPIKE, 1, "a_ridge3", "raid_c", "attack_move", "a_exit"), spawn(2, LEO, 2, "a_ridge3", "raid_c", "attack_move", "a_exit")]
    column("a", time_s(120), "launch_a", raid_a)
    column("b", all_(done("checkpoint"), done("done_a"), time_s(420)), "launch_b", raid_b)
    column("c", all_(done("done_b"), time_s(720)), "launch_c", raid_c)

    # twist: the Oversight Mission closes the road behind column Alpha
    m.trig("t20_twist", all_(done("done_a")),
           [say("twist"), say("ov_warn"), set_obj("checkpoint", "active"),
            spawn_s(2, TUR, "a_chk", id="chk1"), spawn_s(2, TUR, "a_chk", id="chk2"), spawn_s(2, WT, "a_chk", id="chk3"),
            spawn(2, LEO, 3, "a_chk", "chk_guard", "guard", "a_chk"), spawn(2, SPIKE, 2, "a_chk", "chk_guard", "guard", "a_chk"),
            reveal(1, "a_chk", 20), cam("a_chk", seconds=6), enable("t21_reveal")])
    m.trig("t21_reveal", all_(active("checkpoint")), [reveal(0, "a_chk", 8)], once=False, cooldown=40, enabled=False)
    m.trig("t22_chk_down", all_(active("checkpoint"), struct("destroyed", placed="chk1"), struct("destroyed", placed="chk2"), struct("destroyed", placed="chk3")),
           [set_obj("checkpoint", "completed"), say("chk_down"), disable("t21_reveal")])

    m.trig("t80_late", time_s(1050), [say("late")])
    m.trig("t90_win", all_(done("done_a"), done("done_b"), done("done_c")),
           [set_obj("evac", "completed"), say("win"), say("debrief_win"), win(0), music("victory")])
    m.trig("t91_lose_post", count(0, 0, "<=", def_="structure.shared.headquarters"),
           [set_obj("post", "failed"), say("lose_post"), say("debrief_lose"), lose(0), music("defeat")])
    m.trig("t92_lose_time", time_s(1200), [set_obj("evac", "failed"), say("lose_time"), say("debrief_lose"), lose(0), music("defeat")])
    return m
