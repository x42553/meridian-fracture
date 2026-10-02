class_name UiMetrics
extends RefCounted
## Every layout constant of ui.md 4.6.1 (logical px at `content_scale_factor` applied), the 4-px spacing scale,
## the type scale of 4.6.2 (`style.ui.type`; the JSON wins) and the widget sizes of the design system.

const DESIGN_H: int = 1080
const SIDEBAR_W: int = 348
const SIDEBAR_PAD := Vector2(14.0, 12.0)
const MINIMAP_MAX: int = 300
const MINIMAP_MIN: int = 180
const MINIMAP_PAD: int = 5
const TOOL_H: int = 32
const ECO_H: int = 56 + 42
const TAB_SIZE: int = 38
const TAB_GAP: int = 2
const CARD := Vector2(98.0, 104.0)
const CARD_ICON_H: int = 62
const GRID_COLS: int = 3
const GRID_GAP: int = 6
const GRID_SLOTS: int = 12
const QUEUE_SLOT := Vector2(56.0, 44.0)
const QUEUE_H: int = 66
const FOOTER_H: int = 16
const BOTTOM_W_MIN: int = 600
const BOTTOM_W_MAX: int = 900
const BOTTOM_W_MAX_LARGE: int = 1000
const BOTTOM_H: int = 160
const BOTTOM_MARGIN: int = 10
const GROUP_BADGE := Vector2(60.0, 30.0)
const GROUP_GAP: int = 4
const PORTRAIT := Vector2(152.0, 76.0)
const TILE: int = 46
const TILE_GAP: int = 4
const COMMAND_BTN: int = 48
const COMMAND_GAP: int = 5
const ABILITY_BTN: int = 40
const RIBBON := Vector2(480.0, 48.0)
const RIBBON_GAP: int = 6
const RIBBON_TOP: int = 12
const RIBBON_MAX: int = 4
const DOCK_BTN: int = 56
const DOCK_GAP: int = 6
const DOCK_POS := Vector2(12.0, 44.0)
const TOP_STRIP_POS := Vector2(12.0, 12.0)
const LOG_MAX: int = 6
const LOG_BOTTOM: int = 232
const BRACKET_MIN_HALF: int = 10
const BAR_W_MIN: int = 24
const BAR_W_MAX: int = 90
const BAR_H: int = 4
## Menus / lobby / browser margins (left, top, right, bottom).
const SCREEN_MARGIN := Vector4(56.0, 34.0, 56.0, 30.0)
const MENU_BTN := Vector2(420.0, 54.0)
const MENU_POS := Vector2(104.0, 470.0)
const LOBBY_ROW_H: int = 48
const LOBBY_COLS: PackedInt32Array = [76, 158, 232, 190, 118, 90]
const DRAG_THRESHOLD: int = 6
const EDGE_MARGIN: int = 6
const DOUBLE_CLICK_MS: int = 350
const DOUBLE_CLICK_PX: int = 8
const DOUBLE_TAP_MS: int = 350
const HOVER_HZ: int = 30
const MINIMAP_HZ: int = 30
const FEED_HZ: int = 10
const MIN_WINDOW := Vector2i(1024, 576)

# --- spacing scale (4-px grid, style.ui.chrome.grid_px) ---
const SP_1: int = 4
const SP_2: int = 8
const SP_3: int = 12
const SP_4: int = 16
const SP_5: int = 20
const SP_6: int = 24
const SP_8: int = 32

# --- type scale (4.6.2; no essential text below 14 logical px at 100 %) ---
const FS_CAPTION: int = 14
const FS_SMALL: int = 14
const FS_BODY: int = 15
const FS_SUB: int = 18
const FS_LIST: int = 15
const FS_HEAD: int = 14
const FS_NAME: int = 17
const FS_HERO: int = 20
const FS_TITLE: int = 40
const FS_LOGO: int = 56
const FS_NUM: int = 15
const FS_NUM_BIG: int = 34
const FS_NUM_COUNTDOWN: int = 25
const MIN_ESSENTIAL_PX: int = 14

# --- design-system widget sizes ---
const CUT_PANEL: int = 10
const CUT_BUTTON: int = 6
const CUT_INSET: int = 4
const CUT_SIDEBAR: int = 18
const CUT_RIBBON: int = 12
const CUT_TOOLTIP: int = 8
const BORDER: int = 1
const BRACKET_LEN: int = 12
const BRACKET_W: int = 2
const HIT_MIN: int = 32
const TOOLTIP_DELAY_MS: int = 500
const TOOLTIP_MAX_W: int = 340
const TOOLTIP_OFFSET: int = 16
const DIALOG_W_MIN: int = 420
const DIALOG_W_MAX: int = 640
const TOAST_W: int = 420
const LIST_ROW_H: int = 38
const CHIP_H: int = 30
const HEADER_H: int = 30
