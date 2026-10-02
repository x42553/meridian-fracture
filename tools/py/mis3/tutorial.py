"""MIS3: TUTORIAL 'Field Training' (tut_field_training). NAPC vanilla, open 96 map, ~15 min, 22 hand-holding steps."""
from .lib import *

GEN = "structure.shared.generator"
REF = "structure.shared.refinery"
BAR = "structure.shared.barracks"
FAC = "structure.shared.factory"
RAD = "structure.shared.radar"
TUR = "structure.shared.anti_tank_turret"
WT = "structure.shared.watchtower"
LAB = "structure.shared.laboratory"
TANK = "unit.napc.guardian_tank"
RIFLE = "unit.napc.rifle_squad"
JAGER = "unit.nec.jager_squad"
SPIKE = "unit.nec.spike_team"
LEO = "unit.nec.leopard_tank"
AURORA = "structure.nec.aurora_microwave_array"
SP = "Field Instructor"


RIVAL = [spawn_s(2, GEN, "a_rival", id="rival_gen1"), spawn_s(2, GEN, "a_rival", id="rival_gen2"), spawn_s(2, GEN, "a_rival", id="rival_gen3"),
         spawn_s(2, RAD, "a_rival", id="rival_radar"), spawn_s(2, LAB, "a_rival", id="rival_lab"), spawn_s(2, AURORA, "a_rival", id="rival_array"),
         change_ai(2, active=True, level=2)]


def build():
    m = Mission("tut_field_training", "Field Training", "tutorial", 0,
                {"family": "open", "size": 128, "seed": 10}, rules={"start_credits": 4500, "fog": 0, "superweapons": 1}, sim_seed=10)
    m.brief("Welcome to the Academy",
            "The North American Peace Corps trains every new commander at the Reconstruction Academy before sending them to a corridor. "
            "This course takes about fifteen minutes and walks you through the whole game: camera, orders, economy, production, defence, "
            "support powers and the one thing every commander eventually meets, a superweapon warning.", "faction.napc")
    m.brief("How it works",
            "Each step appears in the objectives list with a short hint. Steps complete when you do the thing. If you get stuck the "
            "Instructor helps after a while (funds, a building or a squad), so you cannot lock yourself out. Nothing here is scored.")
    m.brief("Controls", "Every key can be changed in Options, Controls. The hints name the defaults. Press F1 at any time for the Field Manual.")

    m.player(0, "human", "roster.napc.vanilla", 1, "Cadet", "hq", units=[{"def": TANK, "count": 3, "dx": 4, "dy": 3}])
    m.player(1, "ai", "roster.nec.vanilla", 2, "Instructor Force", "none", credits=0,
             ai={"level": 0, "style": 0, "active": False}, start_slot=1)
    m.player(2, "ai", "roster.nec.vanilla", 2, "Rival Array", "none", credits=0,
             ai={"level": 2, "style": 0, "active": False}, start_slot=2)

    # ---- areas (all relative to the player start or the map so the course does not depend on the terrain)
    m.circle("a_base", 0, 0, 9, "start:0")
    m.circle("a_move1", -10, -10, 2, "start:0")
    m.circle("a_hostile1", -22, 2, 2, "start:0")
    m.circle("a_target", -13, 13, 2, "start:0")
    m.circle("a_gen", -5, 5, 2, "start:0")
    m.circle("a_ref", -6, 5, 2, "start:0")
    m.circle("a_field", -8, 8, 3, "start:0")
    m.circle("a_tower", 4, 6, 2, "start:0")
    m.circle("a_rally", -7, 12, 3, "start:0")
    m.circle("a_def", -7, -3, 3, "start:0")
    m.circle("a_radar", -2, 5, 2, "start:0")
    m.circle("a_w_north", -12, -26, 4, "start:0")
    m.circle("a_w_west", -30, 2, 4, "start:0")
    m.circle("a_rival", 0, 0, 8, "start:2")

    # ---- messages
    def hint(id, text, announcer=None):
        m.msg(id, text, SP, announcer)

    hint("h01", "Welcome to Field Training, Commander. First the camera. Scroll with the arrow keys or by pushing the mouse to the screen edge, rotate with Q and E, zoom with the mouse wheel. Home returns to your Headquarters.", "match_start_napc")
    hint("h02", "Selecting and moving. Click one of your three Guardian Tanks or drag a box around all of them (Shift adds or removes a unit). Then right-click the spot the camera has jumped to.")
    hint("h03", "Hostile practice squads ahead. Press A and click near them: attack-move fights everything on the way, while a plain right-click move ignores enemies. Destroy both squads.")
    hint("h04", "Three more orders. S stops your units, X scatters them (handy against area attacks), H holds position so they only fire from where they stand. Try each one now.")
    hint("h05", "That lone Watchtower is a practice target. Units never attack neutral buildings on their own. Hold Ctrl (Option on macOS) and right-click it, or press Y and click, to force fire. Destroy it.")
    hint("h06", "Time to build. Open the Structures tab in the sidebar, click the Generator card, and when it is ready click it again and place it inside the ring around your Headquarters (8 cells). Generators supply the power every building needs.")
    hint("h07", "Refineries turn deposits into credits. Build one close to the ore field the camera shows. It comes with a free Collector that starts working at once.")
    hint("h08", "Watch the Collector: it drives to the deposit, fills up with 600 credits, and returns to unload. C selects the next Collector. More Collectors means more income; the credits and income per minute are in the sidebar.")
    hint("h09", "Infantry come from the Barracks. Build one (500 credits) and place it inside the ring.")
    hint("h10", "Train two Rifle Squads: open the Infantry tab and click the Rifle Squad card. Left click queues one, right click removes one. Keep an eye on the power bar: a shortage slows production.")
    hint("h11", "Vehicles need a War Factory (2000 credits). Build and place it. Funds are tight, so wait for the Collector if you have to; the Instructor will top you up if you run dry.")
    hint("h12", "Queue two more Guardian Tanks in the Vehicles tab. Tanks are your main line, and the Factory's service apron slowly repairs idle ones nearby.")
    hint("h13", "Rally points. Select the Factory, press F, then click the ground at the spot the camera shows. New vehicles drive there by themselves. Queue one more tank to try it.")
    hint("h14", "Control groups. Select some tanks and press Ctrl+1 to store them, then 1 to recall them; pressing the number twice centres the camera on the group. Ctrl+A selects every combat unit.")
    hint("h15", "Base defence and placement. Build an Anti-Tank Turret (800) inside the ring on the western side, where the camera shows. A green ghost means a valid spot, red means blocked. Structures can only be placed within 8 cells of a Headquarters.")
    hint("h16", "Tech tiers. Build a Radar (1500). It unlocks tier 2 units (Combat Medic, Sentinel AA, Paladin Howitzer), shows the minimap and powers your support powers. Keep the power bar green.")
    hint("h17", "Support powers. With a powered Radar you can call a UAV Sweep (500 credits). Press F5 and click the map to reveal and detect in an area.")
    hint("h18", "Alert! A raiding party is coming from the north. Alerts appear as toasts and as pings on the minimap, and Space jumps the camera to the last one. Click the minimap to look, then defend the base.", "base_under_attack")
    hint("h19", "Repairing and selling. R then click a damaged structure repairs it for credits, Delete then click sells a structure for half its price. Sell the old Watchtower beside your Headquarters now.")
    hint("h20", "Final exercise: two raiding parties are coming, one after the other. Use everything you learned: attack-move, the turret, repairs, rally points, groups. Watch the minimap.", "base_under_attack")
    hint("h21", "Superweapon drill. The rival array in the far corner is charged or charging. When it fires you hear the warning and the minimap shows a ring for several seconds: move your units out of it. Or send tanks to destroy the array first. Either one finishes the drill.")
    hint("m_alert_sw", "Launch detected! In a real match you would now drag your units out of the ring. This one is an EMP: it only disables vehicles and powered buildings for a few seconds.", "sw_launch_detected")
    hint("m_rival", "Scouts report an unknown array being raised in the far corner of the map and powering up. Remember it: we will come back to it at the end of the course.", "enemy_sw_charging")
    hint("m_w3", "Second wave from the north! Keep your tanks together and fight near the turret.")
    hint("m_funds", "Command has wired you a funding advance. Spend it wisely.")
    hint("m_help", "Command has lent a hand so you can move on.")
    hint("m_done", "Course complete. You can command a base, an economy and an army, and you know how to read an alert. Report to your first corridor, Commander.", "victory")
    hint("m_lost", "Your Headquarters has fallen. Training is over for today. Try the course again.", "defeat")

    # ---- objectives: one per step, revealed in order
    O = [
        ("s01", "Look around: scroll, rotate and zoom the camera"),
        ("s02", "Select your tanks and move them to the marked spot"),
        ("s03", "Attack-move: destroy the two practice squads"),
        ("s04", "Try the stop, scatter and hold orders"),
        ("s05", "Force fire: destroy the practice Watchtower"),
        ("s06", "Build a Generator"),
        ("s07", "Build a Refinery near the ore field"),
        ("s08", "Watch the Collector harvest"),
        ("s09", "Build a Barracks"),
        ("s10", "Train two Rifle Squads"),
        ("s11", "Build a War Factory"),
        ("s12", "Train two more Guardian Tanks"),
        ("s13", "Set a rally point at the marked spot"),
        ("s14", "Try control groups (Ctrl+1, then 1)"),
        ("s15", "Build an Anti-Tank Turret at the marked spot"),
        ("s16", "Build a Radar (tier 2 tech)"),
        ("s17", "Use the UAV Sweep support power"),
        ("s18", "Defend the base against the raiding party"),
        ("s19", "Sell the old Watchtower"),
        ("s20", "Final exercise: defeat both raiding parties"),
        ("s21", "Superweapon drill: survive the rival's launch or destroy the array"),
    ]
    for oid, text in O:
        m.objective(oid, "primary", text)
    m.objective("keep_hq", "secondary", "Keep your Headquarters alive", "active")

    m.timer("step_to", 30, "Step")

    # ---- step machine: (objective, hint, timeout seconds, gate cond or None, fix actions, extra actions on open)
    steps = [
        ("s01", "h01", 30, None, [], []),
        ("s02", "h02", 75, count(0, 2, tag="tank", area="a_move1"), [order(0, "move", tag="tank", order_area="a_move1")], [cam("a_move1", seconds=6)]),
        ("s03", "h03", 120, wave("w_dummy", "cleared"), [order(0, "attack_move", tag="tank", order_area="a_hostile1")],
         [spawn(1, JAGER, 2, "a_hostile1", "w_dummy", "guard", "a_hostile1"), cam("a_hostile1", seconds=6)]),
        ("s04", "h04", 30, None, [], []),
        ("s05", "h05", 100, struct("destroyed", placed="practice_target"), [destroy(placed="practice_target")],
         [spawn_s("neutral", WT, "a_target", id="practice_target"), cam("a_target", seconds=6)]),
        ("s06", "h06", 150, struct("exists", 0, GEN), [spawn_s(0, GEN, "a_gen")], [cam("a_base", seconds=4)]),
        ("s07", "h07", 180, struct("exists", 0, REF), [spawn_s(0, REF, "a_ref")], [cam("a_field", seconds=6)]),
        ("s08", "h08", 35, None, [], [cam("a_field", seconds=8), say("m_rival")] + RIVAL),
        ("s09", "h09", 120, struct("exists", 0, BAR), [spawn_s(0, BAR, "a_base")], []),
        ("s10", "h10", 100, count(0, 2, def_=RIFLE), [spawn(0, RIFLE, 2, "a_base")], []),
        ("s11", "h11", 210, struct("exists", 0, FAC), [spawn_s(0, FAC, "a_base")], []),
        ("s12", "h12", 160, count(0, 5, tag="tank"), [spawn(0, TANK, 2, "a_base")], []),
        ("s13", "h13", 120, count(0, 1, area="a_rally", of="unit"), [order(0, "move", tag="tank", order_area="a_rally")], [cam("a_rally", seconds=6)]),
        ("s14", "h14", 35, None, [], []),
        ("s15", "h15", 150, count(0, 1, def_=TUR, area="a_def"), [spawn_s(0, TUR, "a_def")], [cam("a_def", seconds=5)]),
        ("s16", "h16", 180, struct("powered", 0, RAD), [spawn_s(0, RAD, "a_radar")], []),
        ("s17", "h17", 100, sp(0, 0, "used"), [], []),
        ("s18", "h18", 240, wave("w1", "cleared"), [],
         [spawn(1, JAGER, 2, "a_w_north", "w1", "attack_move", "a_base"), spawn(1, LEO, 1, "a_w_north", "w1", "attack_move", "a_base"),
          cam("a_w_north", seconds=5), music("combat")]),
        ("s19", "h19", 75, struct("destroyed", placed="old_tower"), [], [spawn_s(0, WT, "a_tower", id="old_tower"), music("calm")]),
        ("s20", "h20", 330, wave("w3", "cleared"), [],
         [spawn(1, JAGER, 2, "a_w_west", "w2", "attack_move", "a_base"), spawn(1, LEO, 1, "a_w_west", "w2", "attack_move", "a_base"), music("combat")]),
        ("s21", "h21", 240, any_(sw(2, "fired"), struct("destroyed", placed="rival_array")), [destroy(placed="rival_array")], [music("tense")]),
    ]
    n = 0
    prev = None
    for oid, hid, to, gate, fix, extra in steps:
        n += 1
        tid = "t%02d" % n
        open_cond = time_t(0) if prev is None else done(prev)
        m.trig(tid + "a_open", open_cond, [set_obj(oid, "active"), say(hid)] + extra + [timer_start("step_to", to)])
        if gate is not None:
            m.trig(tid + "b_gate", all_(active(oid), gate), [set_obj(oid, "completed")])
        m.trig(tid + "c_timeout", all_(active(oid), timer("step_to")), fix + [say("m_help"), set_obj(oid, "completed")] if fix else [set_obj(oid, "completed")])
        prev = oid
    # the second half of the final exercise: it follows the first when that is beaten
    m.trig("t20d_w3", all_(active("s20"), wave("w2", "cleared")),
           [spawn(1, JAGER, 3, "a_w_north", "w3", "attack_move", "a_base"), spawn(1, LEO, 1, "a_w_north", "w3", "attack_move", "a_base"),
            spawn(1, SPIKE, 1, "a_w_north", "w3", "attack_move", "a_base"), say("m_w3", "base_under_attack"), music("combat")])
    # the drill message whenever the rival array fires (also before its step)
    m.trig("t80_sw_fired", sw(2, "fired"), [say("m_alert_sw")])
    # win
    m.trig("t90_win", done("s21"), [say("m_done"), win(0), music("victory")])
    # funding safety net while a build step is active
    build_steps = [active(s) for s in ("s06", "s07", "s09", "s10", "s11", "s12", "s15", "s16", "s17")]
    m.trig("t91_funds", all_(credits(0, 450, "<="), any_(*build_steps), fired("t91_funds", 4, "<")), [give(0, 1500), say("m_funds")], once=False, cooldown=60)
    m.trig("t92_lose", count(0, 0, "<=", of="structure"), [set_obj("keep_hq", "failed"), say("m_lost"), lose(0), music("defeat")])
    return m
