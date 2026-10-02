class_name AppViewPort
extends UiViewPortWorld
## The match's `UiViewPort`: `UiViewPortWorld` (camera, picking, selection) plus the pieces only the composed stage owns
## (`AppViewStage`): the baked minimap texture and its fog material, and the lobby's map preview bake. Everything the view has
## not delivered yet keeps the no-op defaults of `UiViewPort`.

var stage: AppViewStage = null


func _init(p_stage: AppViewStage = null) -> void:
	super._init(p_stage.view if p_stage != null else null)
	stage = p_stage


func minimap_texture() -> Texture2D:
	return stage.minimap_texture() if stage != null else null


func minimap_material() -> Material:
	return stage.minimap_material() if stage != null else null


func bake_map_preview(map: MapData) -> Texture2D:
	return AppViewStage.bake_preview(map)
