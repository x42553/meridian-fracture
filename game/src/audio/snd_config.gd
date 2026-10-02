class_name SndConfig
extends RefCounted
## Mechanism constants of the audio runtime (audio spec 4.7). Everything a sound designer tunes by ear lives in
## `game/data/audio/mix.json` (SndMixConfig); only limits that size arrays or fix formats are constants here.

const DATA_DIR: String = "res://data/audio"
const ASSET_DIR: String = "res://assets/audio"
const INDEX_PATH: String = "res://assets/audio/asset_index.json"

const M_PER_UNIT: float = 3.0 / 1024.0  ## sub-cell units to metres (1 cell = 3 m)
const UNITS_PER_CELL: int = 1024
const CELL_SHIFT: int = 10

const MAX_SLOTS: int = 128
const SLOT_BITS: int = 7
const POOL_3D_MAX: int = 88
const POOL_2D_MAX: int = 40
const MAX_EVENTS_SCANNED: int = 512
const MAX_CANDIDATES: int = 512
const SOURCE_THROTTLE_SLOTS: int = 1024
const MAX_GAIN_DB: float = 3.0
const SILENT_DB: float = -80.0
const LOOP_START_DB: float = -60.0
const RAMP_MAX_STEP_DB_PER_FRAME: float = 6.0
const BUILDUP_SECONDS: float = 1.5

## audio_warning codes
const W_DATA: int = 1
const W_MISSING_BANK: int = 2
const W_NO_CAMERA: int = 3
const W_DUMMY_DRIVER: int = 4
const W_TTS: int = 5

## Faction codes with their flavour banks.
const FACTIONS: PackedStringArray = ["napc", "nec", "olm", "def", "pd", "han", "ae", "sap"]

## Milliseconds since engine start; the injectable clock of every class takes a Callable with this shape.
static func now_ms() -> int:
	return Time.get_ticks_msec()
