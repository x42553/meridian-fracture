class_name SimPlayerEcon
extends SimComponent
## Slot `p.econ` (economy 4.2): the per-player economy record. Ints and packed int arrays only. The credits
## balance itself lives in the kernel ledger (`SimPlayer.credits`, changed only through SimEconomySystem.spend /
## earn -> world.try_spend / add_credits); handicap scaling, the unit count and the structure / rebuilder counters
## are kernel-owned too (SimPlayer). Everything else the spec puts here is in this record and hashed.

const HASH_EXEMPT: PackedStringArray = []

var pid: int = 0
var roster_idx: int = -1
var flags: int = 0  ## PF_*
# ledger statistics (credits paid / received by category)
var stat_harvested: int = 0
var stat_salvaged: int = 0
var stat_depot: int = 0
var stat_spent_construction: int = 0
var stat_spent_units: int = 0
var stat_spent_research: int = 0
var stat_spent_powers: int = 0
var stat_spent_repair: int = 0
var stat_refunded: int = 0
var stat_sold: int = 0
var income_ring: PackedInt32Array = PackedInt32Array()  ## 12 buckets x 100 ticks of HARVEST / SALVAGE / DEPOT income
var income_ring_idx: int = 0  ## bucket currently filled
var income_ring_epoch: int = 0  ## tick / 100 of that bucket
# unit cap
var unit_cap: int = 150
var cap_reserved: int = 0  ## sum of unit_cap_cost of unit-queue heads currently progressing
# counters: ACTIVE, non-temporary structures only; index = s_idx
var struct_count: PackedInt32Array = PackedInt32Array()
var active_hq_count: int = 0
# power
var power_supply: int = 0
var power_demand: int = 0
var power_state: int = SimEconConst.PW_NORMAL
var power_dirty: bool = false
var shortage_since: int = -1  ## tick the current shortage began, -1 if none
var reserve_left: int = 0
var reserve_max: int = 0
var adequate_streak: int = 0
var defenses_online: bool = true
var powers_online: bool = true
# player-wide queues (head at index 0); progress in bp-ticks
var cq_def: PackedInt32Array = PackedInt32Array()
var cq_cost: PackedInt32Array = PackedInt32Array()
var cq_ticks: PackedInt32Array = PackedInt32Array()
var cq_progress: int = 0
var cq_paid: int = 0
var cq_state: int = SimEconConst.QS_EMPTY
var cq_hold: bool = false
var rq_def: PackedInt32Array = PackedInt32Array()
var rq_cost: PackedInt32Array = PackedInt32Array()
var rq_ticks: PackedInt32Array = PackedInt32Array()
var rq_progress: int = 0
var rq_paid: int = 0
var rq_state: int = SimEconConst.QS_EMPTY
var rq_hold: bool = false
var researched: PackedByteArray = PackedByteArray()  ## index r_idx, 0 / 1
# rates and knobs
var rate_bp: PackedInt32Array = PackedInt32Array()  ## size 8 (PROD_*); 10000 = 1.0
var rates_dirty: bool = true
var knob_base: PackedInt32Array = PackedInt32Array()  ## size K_COUNT
var knob_temp: PackedInt32Array = PackedInt32Array()
var knob_until: PackedInt32Array = PackedInt32Array()
# strategic
var slots: Array[SimPowerSlot] = []  ## 4 entries (SLOT_P0 .. SLOT_SW)
# cached id lists (ascending entity id)
var refinery_ids: PackedInt32Array = PackedInt32Array()
var producer_ids: Array[PackedInt32Array] = []  ## index PROD_*; ACTIVE producers only
var producer_flat: PackedInt32Array = PackedInt32Array()  ## all ACTIVE producer ids ascending
var field_danger: PackedInt32Array = PackedInt32Array()  ## per deposit idx: tick until collectors avoid the field
var rr_offset: int = 0  ## round-robin start for payment fairness


func _init() -> void:
	income_ring.resize(SimEconConst.INCOME_BUCKETS)
	rate_bp.resize(SimEconConst.PROD_COUNT)
	rate_bp.fill(10000)
	knob_base = SimEconConst.KNOB_DEFAULT.duplicate()
	knob_temp.resize(SimEconConst.K_COUNT)
	knob_until.resize(SimEconConst.K_COUNT)
	for _i: int in SimEconConst.PROD_COUNT:
		producer_ids.append(PackedInt32Array())
	for i: int in SimEconConst.SLOT_COUNT:
		var s: SimPowerSlot = SimPowerSlot.new()
		s.kind = 1 if i == SimEconConst.SLOT_SW else 0
		slots.append(s)


func hash_into(buf: PackedInt32Array) -> void:
	buf.append(pid)
	buf.append(roster_idx)
	buf.append(flags)
	buf.append(stat_harvested)
	buf.append(stat_salvaged)
	buf.append(stat_depot)
	buf.append(stat_spent_construction)
	buf.append(stat_spent_units)
	buf.append(stat_spent_research)
	buf.append(stat_spent_powers)
	buf.append(stat_spent_repair)
	buf.append(stat_refunded)
	buf.append(stat_sold)
	_arr(buf, income_ring)
	buf.append(income_ring_idx)
	buf.append(income_ring_epoch)
	buf.append(unit_cap)
	buf.append(cap_reserved)
	_arr(buf, struct_count)
	buf.append(active_hq_count)
	buf.append(power_supply)
	buf.append(power_demand)
	buf.append(power_state)
	buf.append(1 if power_dirty else 0)
	buf.append(shortage_since)
	buf.append(reserve_left)
	buf.append(reserve_max)
	buf.append(adequate_streak)
	buf.append(1 if defenses_online else 0)
	buf.append(1 if powers_online else 0)
	_arr(buf, cq_def)
	_arr(buf, cq_cost)
	_arr(buf, cq_ticks)
	buf.append(cq_progress)
	buf.append(cq_paid)
	buf.append(cq_state)
	buf.append(1 if cq_hold else 0)
	_arr(buf, rq_def)
	_arr(buf, rq_cost)
	_arr(buf, rq_ticks)
	buf.append(rq_progress)
	buf.append(rq_paid)
	buf.append(rq_state)
	buf.append(1 if rq_hold else 0)
	buf.append(researched.size())
	for b: int in researched:
		buf.append(b)
	_arr(buf, rate_bp)
	buf.append(1 if rates_dirty else 0)
	_arr(buf, knob_base)
	_arr(buf, knob_temp)
	_arr(buf, knob_until)
	buf.append(slots.size())
	for s: SimPowerSlot in slots:
		s.hash_into(buf)
	_arr(buf, refinery_ids)
	buf.append(producer_ids.size())
	for a: PackedInt32Array in producer_ids:
		_arr(buf, a)
	_arr(buf, producer_flat)
	_arr(buf, field_danger)
	buf.append(rr_offset)


static func _arr(buf: PackedInt32Array, a: PackedInt32Array) -> void:
	buf.append(a.size())
	buf.append_array(a)
