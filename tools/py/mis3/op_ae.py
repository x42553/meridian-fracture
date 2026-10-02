"""MIS3: OPERATION 7, AE 'Second Harvest' (op_ae): salvage-driven recovery after a battle. Fault line: African Empire / Protectorate (+ every bloc / its own members)."""
from .lib import *

BUF = "unit.ae.buffalo_tank"
GUARD = "unit.ae.union_guard"
PIKE = "unit.ae.pike_team"
RECL = "unit.ae.reclaimer"
MAMBA = "unit.ae.mamba_apc"
ENG = "unit.shared.engineer"
BUL = "unit.sap.bulwark_tank"
SHIELD = "unit.sap.shield_rifle_squad"
KAV = "unit.sap.kavach_team"
MON = "unit.sap.monsoon_howitzer"
JACK = "unit.sap.jackal_apc"
ARJ = "unit.sap.arjun_assault_tank"
GEN = "structure.shared.generator"
BAR = "structure.shared.barracks"
REF = "structure.shared.refinery"
FAC = "structure.shared.factory"
RAD = "structure.shared.radar"
HQ = "structure.shared.headquarters"
SP = "Steward's Office"
PR = "Protectorate Claims Board"


def build():
    m = Mission("op_ae", "Operation Second Harvest", "operation", 7,
                {"family": "open", "size": 128, "seed": 41, "params": {"biome": 1, "resources": 60}}, rules={"start_credits": 2200, "fog": 1}, sim_seed=7101)
    m.brief("Situation",
            "The Battle of Kasai Ford ended at dawn. Nobody won it: two columns met on the old causeway, burned each other's armour and "
            "withdrew behind their own lines. What they left behind is a field of wrecks and a ruined Union Works that was supposed to be "
            "the Empire's forward yard. The Steward has ordered it rebuilt before the rains.", "faction.ae")
    m.brief("The Protectorate Claim",
            "The Protectorate's Claims Board has filed a notice that every wreck on the causeway belongs to the 'ownership of the dead': "
            "to whoever buried them. The Empire says whoever pulls a hull out of the mud owns it. Both sides have engineers on the way. "
            "The Empire and the Protectorate share an interest in independent reconstruction technology and quarrel over contracts and "
            "eastern shipping lanes. Today that quarrel has a causeway.", "faction.sap")
    m.brief("Orders",
            "Salvage first, then build: your engineers and the Reclaimer can strip a freshly destroyed enemy vehicle for a fifth of its "
            "price, but a wreck lasts only a minute, so hold the field while they work. Rebuild a second Refinery, a Factory and a Radar, "
            "field fourteen combat units, and hold the Works for fourteen minutes. The Steward will levy a share of your treasury when "
            "the accounts are audited; spend it before then.")
    m.player(0, "human", "roster.ae.vanilla", 1, "Union Works", "hq", credits=2200,
             units=[{"def": ENG, "count": 3, "dx": -5, "dy": 0}, {"def": RECL, "count": 1, "dx": -4, "dy": 3}, {"def": BUF, "count": 2, "dx": -7, "dy": -3},
                    {"def": GUARD, "count": 3, "dx": -6, "dy": 4}, {"def": PIKE, "count": 2, "dx": -8, "dy": 1}],
             structures=[{"def": GEN, "dx": 5, "dy": 3}, {"def": BAR, "dx": -2, "dy": 8}, {"def": REF, "dx": 6, "dy": -3}])
    m.player(1, "ai", "roster.ae.vanilla", 1, "Fallen Column", "none", start_slot=1, ai={"level": 0, "style": 0, "active": False})
    m.player(2, "ai", "roster.sap.vanilla", 2, "Protectorate Claims", "hq", start_slot=2, ai={"level": 0, "style": 0, "active": False})

    m.circle("a_works", 0, 0, 12, "start:0")
    m.circle("a_clash", -22, -10, 5, "start:0")
    m.circle("a_ae_start", -14, -2, 4, "start:0")
    m.circle("a_sap_start", -32, -18, 4, "start:0")
    m.circle("a_n", -20, -40, 6, "start:0")
    m.circle("a_w", -48, -6, 6, "start:0")
    m.circle("a_front", -12, -7, 6, "start:0")

    m.msg("intro", "Union Works, Steward's Office. The causeway is yours if you can hold it. Dawn is breaking. Salvage the hulls before they sink.", SP, "match_start_ae")
    m.msg("hint_salvage", "Select an Engineer or the Reclaimer and right-click a wreck to strip it. A wreck pays one fifth of the vehicle's price and lasts about a minute, so work while your tanks cover the field.", SP)
    m.msg("hint_build", "A second Refinery, a Factory and a Radar. Salvage pays for the first, the rest should follow from your Collectors.", SP)
    m.msg("w1", "Protectorate vanguard on the causeway. They want the wrecks.", SP, "base_under_attack")
    m.msg("w2", "A second Protectorate group, with howitzers. They are laying the field under fire.", SP, "base_under_attack")
    m.msg("w3", "Claims force from the west: armour, shield squads and a reclamation column. They intend to take the field by force.", SP, "base_under_attack")
    m.msg("w4", "Everything the Claims Board has is on the causeway.", SP, "base_under_attack")
    m.msg("pr_notice", "Notice to the Empire's yard: all salvage on the causeway is held in trust for the next of kin. Cease and desist. A Claims officer will visit to inventory it.", PR)
    m.msg("levy", "AUDIT: the Steward's Office has levied a quarter of the Works' treasury for the capital. You were warned. The yard's workers have noted who signed the order.", SP, "insufficient_funds")
    m.msg("recovered", "The Fallen Column's command vehicle is back inside the Works. The crew is alive.", SP)
    m.msg("convoy", "The Steward's supply convoy is on the road and will reach the Works shortly. Hold on!", SP, "ally_under_attack")
    m.msg("lose_hq", "The Works' headquarters has fallen. The yard is lost.", SP, "defeat")
    m.msg("win", "The convoy is through and the Works are running. Fourteen minutes: a yard rebuilt out of the enemy's wrecks.", SP, "victory")
    m.msg("debrief_win", "DEBRIEF: the Union Works is running again and half its first output was built from Protectorate hulls. The Claims Board will protest at the next corridor conference; the Steward's levy will be a bigger scandal in the yard than the battle was.", "Debrief")
    m.msg("debrief_lose", "DEBRIEF: the Works fell. The Protectorate holds the causeway and the wrecks, and the Steward's Office is looking for someone to explain why the levy was collected.", "Debrief")

    m.objective("rebuild", "primary", "Rebuild the Works: a second Refinery, a Factory and a Radar", "active")
    m.objective("army", "primary", "Field at least 14 combat units", "active")
    m.objective("hold", "primary", "Hold the Union Works until the convoy arrives (14:00)", "active")
    m.objective("engineers", "secondary", "Keep all three Engineers alive", "active")
    m.objective("recover", "secondary", "Tow the Fallen Column's command vehicle into the Works", "hidden")
    m.timer("conv_t", 840, "Supply convoy")

    # the prelude battle: the Fallen Column (ally) against a Protectorate column; the wrecks that stay are the engineers' work
    prelude = [spawn(1, BUF, 6, "a_ae_start", "ae_col", "attack_move", "a_clash"), spawn(1, GUARD, 4, "a_ae_start", "ae_col", "attack_move", "a_clash"),
               spawn(2, BUL, 6, "a_sap_start", "sap_col", "attack_move", "a_clash"), spawn(2, SHIELD, 4, "a_sap_start", "sap_col", "attack_move", "a_clash")]
    m.trig("t00_start", time_t(0), [say("intro"), timer_start("conv_t"), music("tense")] + prelude)
    m.trig("t01_hint", time_s(25), [say("hint_salvage")])
    m.trig("t02_hint2", time_s(90), [say("hint_build")])
    m.trig("t03_cmd", time_s(35), [spawn(0, MAMBA, 1, "a_clash", None, "hold"), set_obj("recover", "active")])
    m.trig("t04_recovered", all_(active("recover"), count(0, 1, def_=MAMBA, area="a_works")), [set_obj("recover", "completed"), say("recovered")])
    m.trig("t05_ai_on", time_s(300), [change_ai(2, active=True)])
    m.trig("t06_notice", time_s(200), [say("pr_notice")])
    waves = [(290, "w1", [(BUL, 2, "a_n"), (SHIELD, 2, "a_n")]),
             (440, "w2", [(MON, 1, "a_n"), (BUL, 2, "a_w"), (KAV, 1, "a_w")]),
             (600, "w3", [(ARJ, 1, "a_w"), (BUL, 2, "a_w"), (SHIELD, 2, "a_n")]),
             (760, "w4", [(ARJ, 2, "a_n"), (BUL, 3, "a_w"), (MON, 1, "a_w"), (SHIELD, 2, "a_n")])]
    for i, (t, msg, groups) in enumerate(waves):
        m.trig("t1%d_wave" % i, time_s(t), [spawn(2, u, n, a, "wave%d" % (i + 1), "attack_move", "a_works") for (u, n, a) in groups] + [say(msg), music("combat")])
    # the twist: the Steward's audit takes a quarter of the treasury
    m.trig("t20_levy", time_s(540), [give(0, -1500), say("levy"), music("tense")])
    m.trig("t30_rebuild", all_(active("rebuild"), count(0, 2, def_=REF), struct("exists", 0, FAC), struct("exists", 0, RAD)), [set_obj("rebuild", "completed")])
    m.trig("t31_army", all_(active("army"), count(0, 14, tag="combat")), [set_obj("army", "completed")])
    m.trig("t32_eng", all_(active("engineers"), count(0, 3, "<", def_=ENG)), [set_obj("engineers", "failed")])
    m.trig("t33_convoy", time_s(780), [say("convoy")])
    m.trig("t90_win", all_(timer("conv_t"), done("rebuild"), done("army"), count(0, 1, def_=HQ)),
           [set_obj("hold", "completed"), say("win"), say("debrief_win"), win(0), music("victory")])
    m.trig("t91_lose_hq", count(0, 0, "<=", def_=HQ), [set_obj("hold", "failed"), say("lose_hq"), say("debrief_lose"), lose(0), music("defeat")])
    m.trig("t92_lose_time", all_(time_s(1260)), [set_obj("hold", "failed"), say("debrief_lose"), lose(0), music("defeat")])
    return m
