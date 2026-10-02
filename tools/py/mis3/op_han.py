"""MIS3: OPERATION 6, HAN 'Common Plan' (op_han): link-operator protection with infantry and drone swarms. Fault line: every bloc / its own members."""
from .lib import *

BANNER = "unit.han.banner_infantry"
LANCE = "unit.han.lance_team"
OX = "unit.han.ox_tank"
NEST = "unit.han.nest_rocket_drone"
FIREFLY = "unit.han.firefly_aa_drone"
LINK = "unit.han.link_operator"
GEN = "structure.shared.generator"
REF = "structure.shared.refinery"
BAR = "structure.shared.barracks"
FAC = "structure.shared.factory"
RAD = "structure.shared.radar"
TUR = "structure.shared.anti_tank_turret"
HQ = "structure.shared.headquarters"
SP = "Imperial Court"
VN = "Canopy Command"


def build():
    m = Mission("op_han", "Operation Common Plan", "operation", 6,
                {"family": "open", "size": 128, "seed": 61, "params": {"biome": 0, "density": 55}}, rules={"start_credits": 5000, "fog": 1}, sim_seed=6101)
    m.brief("Situation",
            "The Han Empire's drone swarms are cheap, plentiful and blind without a Link Operator. A single operator in a trench coat and "
            "a backpack mast gives a whole Nest group the picture it needs. Three operators are all the Court has left in the Canopy Belt, "
            "and the Court wants three relay nodes raised along the belt before the monsoon cuts the roads.", "faction.han")
    m.brief("The Canopy Command",
            "The Canopy Defense Command is a treaty partner with its own army, its own depots and its own opinion about who writes the plan. "
            "It has refused to let the mesh cross its depots, and a raiding force is watching the operators' every step. Nobody in the Court "
            "thinks the partner is an enemy. Nobody in the Canopy Command thinks the Court is a friend.", "roster.han.vietnam")
    m.brief("Orders",
            "Walk the operators to each relay node in turn and hold the node until the link is up: the moment the mast goes live the Canopy "
            "raiders will come for it. Keep at least two operators alive. Your Banner Infantry and the Nest drones are fine in a fight "
            "while an operator stands within five cells; without one, the drones are very expensive scrap. The Court may send further orders. Think about them.")
    m.player(0, "human", "roster.han.vanilla", 1, "Mesh Column", "hq", credits=5000,
             units=[{"def": BANNER, "count": 6, "dx": -6, "dy": -2}, {"def": LANCE, "count": 2, "dx": -4, "dy": 5}, {"def": OX, "count": 2, "dx": -8, "dy": 1},
                    {"def": NEST, "count": 4, "dx": -5, "dy": -6}, {"def": LINK, "count": 3, "dx": -3, "dy": 2}, {"def": FIREFLY, "count": 1, "dx": -2, "dy": 7}],
             structures=[{"def": GEN, "dx": 5, "dy": 4}, {"def": GEN, "dx": 5, "dy": -5}, {"def": REF, "dx": 6, "dy": 0}, {"def": BAR, "dx": -2, "dy": 9},
                         {"def": FAC, "dx": 2, "dy": -9}, {"def": RAD, "dx": 8, "dy": 8}, {"def": TUR, "dx": -11, "dy": -5}])
    m.player(1, "ai", "roster.han.vietnam", 2, "Canopy Command", "hq", start_slot=2, ai={"level": 0, "style": 0, "active": False})

    m.circle("a_post", 0, 0, 12, "start:0")
    m.circle("a_n1", -24, -12, 5, "start:0")
    m.circle("a_n2", -42, -30, 5, "start:0")
    m.circle("a_n3", -58, -46, 5, "start:0")
    m.circle("a_depot", -52, -40, 3, "start:0")
    m.circle("a_ridge1", -34, -26, 6, "start:0")
    m.circle("a_ridge2", -56, -22, 6, "start:0")
    m.circle("a_ridge3", -70, -60, 6, "start:0")
    m.circle("a_front", -12, -8, 6, "start:0")

    m.msg("intro", "Mesh Column, Imperial Court. The monsoon is three weeks out. Walk the operators to the first node and raise the mast.", SP, "match_start_han")
    m.msg("n1_up", "Node One: mast raised on the first attempt. The Nest group reports a clean picture all the way to the ridge.", SP)
    m.msg("n2_up", "Node Two is up. Two of three. The mesh now covers the whole western belt.", SP)
    m.msg("n3_up", "Node Three is live. The mesh is complete from the capital to the border.", SP, "victory")
    m.msg("next2", "The Court has cleared the next segment of the belt: the second node is at the marked site in the northwest. Walk the operators there when the column is ready.", SP)
    m.msg("next3", "The last node is at the Canopy depot ridge. Whatever is left of the Canopy raiders will be waiting.", SP)
    m.msg("arrive", "The mast is going up. Canopy scouts have seen it. Raiders inbound!", SP, "base_under_attack")
    m.msg("order", "Mesh Column: by Central Priority the Court orders the Canopy depot beside Node Three destroyed. The partner has refused the schedule and its stores will be redistributed. Acknowledge.", SP)
    m.msg("order_done", "The depot is gone. The Court thanks the Column. The Canopy Command has already stopped answering the Court's signals.", SP)
    m.msg("spare_ok", "The depot still stands. The Court will note that the Column did not acknowledge Central Priority.", SP)
    m.msg("vn_voice", "Imperial column: that depot feeds three villages. We will not shoot at the operators while they walk past it. We will shoot at anything that fires on it.", VN)
    m.msg("op_lost", "An operator is down. The mesh thins.", SP, "unit_lost")
    m.msg("lose_ops", "Fewer than two operators remain. The mesh cannot be raised.", SP, "defeat")
    m.msg("lose_post", "The Mesh Column headquarters is lost.", SP, "defeat")
    m.msg("lose_time", "The monsoon has closed the roads. The mesh stays dark.", SP, "defeat")
    m.msg("win", "All three nodes are live. The Canopy Belt is on the plan.", SP, "victory")
    m.msg("debrief_win_order", "DEBRIEF: the mesh is up and the Canopy depot is rubble. The Court calls it Central Priority. The Canopy Command has stopped sending liaison officers, and two provincial governors have asked to hear exactly who wrote the plan before they hear what it says.", "Debrief")
    m.msg("debrief_win_spare", "DEBRIEF: the mesh is up and the Canopy depot still stands. The Court's auditors will write that the Column failed to follow Central Priority. The Canopy Command will write that the Court's own soldiers kept its word. Both reports will be filed in the same office.", "Debrief")
    m.msg("debrief_lose", "DEBRIEF: the mesh stays dark. Each side will say the other's depots were the problem; the drones stay in their racks.", "Debrief")

    m.objective("nodes", "primary", "Raise the three relay nodes: an operator at each marked site while its raiders are repelled", "active")
    m.objective("n1", "hidden", "Node One", "active")
    m.objective("n2", "hidden", "Node Two", "hidden")
    m.objective("n3", "hidden", "Node Three", "hidden")
    m.objective("ops", "primary", "Keep at least two Link Operators alive", "active")
    m.objective("order", "secondary", "Central Priority: destroy the Canopy depot (force fire)", "hidden")
    m.objective("spare", "secondary", "Spare the Canopy depot", "hidden")
    for k in "123":
        m.objective("arr" + k, "hidden", "Node %s attempt" % k, "hidden")

    m.trig("t00_start", time_t(0), [say("intro"), set_obj("n1", "active"), music("calm")])
    m.trig("t01_ai_on", time_s(240), [change_ai(1, active=True)])
    nodes = [("1", "a_n1", "a_ridge1", [(LANCE, 3), (BANNER, 5), (OX, 2)]), ("2", "a_n2", "a_ridge2", [(LANCE, 4), (BANNER, 5), (OX, 2), (NEST, 3)]),
             ("3", "a_n3", "a_ridge3", [(LANCE, 3), (BANNER, 5), (OX, 2), (NEST, 3)])]
    for k, area, ridge, comp in nodes:
        m.trig("t1%s0_arrive" % k, all_(active("n" + k), count(0, 1, def_=LINK, area=area)),
               [set_obj("arr" + k, "active")] + [spawn(1, u, n, ridge, "raid" + k, "attack_move", area) for (u, n) in comp] + [say("arrive"), music("combat")])
        m.trig("t1%s1_done" % k, all_(active("arr" + k), count(0, 1, def_=LINK, area=area), wave("raid" + k, "cleared")),
               [set_obj("n" + k, "completed"), set_obj("arr" + k, "completed"), say("n%s_up" % k), music("calm")])
    # the next node opens once the previous one is up and the schedule allows (the Court sets the pace)
    m.trig("t15_open2", all_(done("n1"), time_s(330)), [set_obj("n2", "active"), say("next2")])
    m.trig("t16_open3", all_(done("n2"), time_s(660)), [set_obj("n3", "active"), say("next3")])
    # the twist: after node two the Court orders the Canopy depot destroyed
    m.trig("t20_twist", done("n2"),
           [spawn_s("neutral", REF, "a_depot", id="canopy_depot"), say("order"), say("vn_voice"), set_obj("order", "active"), set_obj("spare", "active"), cam("a_depot", seconds=6)])
    m.trig("t21_order_done", all_(active("order"), struct("destroyed", placed="canopy_depot")), [set_obj("order", "completed"), set_obj("spare", "failed"), say("order_done")])
    m.trig("t30_op_lost", all_(active("ops"), count(0, 3, "<", def_=LINK)), [say("op_lost")], once=True)
    m.trig("t31_ops", all_(active("ops"), count(0, 2, "<", def_=LINK)), [set_obj("ops", "failed"), say("lose_ops"), say("debrief_lose"), lose(0), music("defeat")])
    m.trig("t90_win", all_(done("n1"), done("n2"), done("n3")),
           [set_obj("nodes", "completed"), set_obj("ops", "completed"), say("win"), music("victory")])
    m.trig("t91_win_order", all_(done("n3"), done("order")), [say("debrief_win_order"), win(0)])
    m.trig("t92_win_spare", all_(done("n3"), not_(done("order"))), [set_obj("spare", "completed"), say("spare_ok"), say("debrief_win_spare"), win(0)])
    m.trig("t93_lose_post", count(0, 0, "<=", def_=HQ), [say("lose_post"), say("debrief_lose"), lose(0), music("defeat")])
    m.trig("t94_lose_time", time_s(1260), [say("lose_time"), say("debrief_lose"), lose(0), music("defeat")])
    return m
