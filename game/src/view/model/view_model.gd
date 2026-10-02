class_name ViewModel
extends RefCounted
## Product of a ViewModelBuilder build: the single-surface ArrayMesh, its metadata and the recipe meta.

var key: StringName = &""
var mesh: ArrayMesh = null
var info: ViewModelInfo = null
var meta: Dictionary = {}  ## archetype + recipe + `meta` op values (motion, wreck, role, icon, ...)
var recipe_id: StringName = &""
var style_id: StringName = &""
var placeholder: bool = false  ## true for the box that replaces a missing / failed recipe
var error: String = ""  ## op-path error of a failed build (placeholder models only)
