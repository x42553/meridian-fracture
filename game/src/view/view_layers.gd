class_name ViewLayers
extends RefCounted
## Render priorities, visual-layer bits and overlay y-offsets (render spec 4.8, 5.10).

# render_priority of transparent / overlay materials (opaque pass = 0)
const PRIO_OPAQUE: int = 0
const PRIO_WATER: int = -20
const PRIO_REFRACT_A: int = -10  ## shimmer, ring_distort, haze
const PRIO_REFRACT_B: int = -9
const PRIO_FX_MIN: int = -4
const PRIO_FX_MAX: int = 3
const PRIO_GHOST: int = 5
const PRIO_RINGS: int = 6
const PRIO_LINES: int = 7
const PRIO_GRID: int = 8
const PRIO_BARS: int = 9  ## health bars, status marks (depth_test_disabled)

# visual layer bit INDICES (0-based, for set_layer_mask_value(bit + 1, ...))
const BIT_WORLD: int = 0
const BIT_UNITS: int = 1
const BIT_FX: int = 2
const BIT_OVERLAYS: int = 3
const BIT_MINIMAP_ONLY: int = 4
const BIT_ICON_STUDIO: int = 19

# layer MASKS (for VisualInstance3D.layers / Camera3D.cull_mask)
const MASK_WORLD: int = 1 << BIT_WORLD
const MASK_UNITS: int = 1 << BIT_UNITS
const MASK_FX: int = 1 << BIT_FX
const MASK_OVERLAYS: int = 1 << BIT_OVERLAYS
const MASK_MINIMAP_ONLY: int = 1 << BIT_MINIMAP_ONLY
const MASK_ICON_STUDIO: int = 1 << BIT_ICON_STUDIO
## Main camera: everything except the minimap-only and icon studio layers.
const MASK_MAIN_CAMERA: int = MASK_WORLD | MASK_UNITS | MASK_FX | MASK_OVERLAYS

# overlay lifts (metres)
const RING_LIFT_M: float = 0.08  ## selection rings above the terrain
const RING_TOWARD_CAMERA_M: float = 0.15  ## vertex pull toward the camera against z-fighting
const LINE_LIFT_M: float = 0.15
const GRID_LIFT_M: float = 0.10
