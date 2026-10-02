class_name AppSessionDriver
extends Node
## Frame driver of one `AppMatchContext` for processes without the `AppNet` autoload (unit tests, tools): polls the context once per
## rendered frame before every view / UI node (process priority -100). With `AppNet` present the autoload does this and no driver
## exists.

var ctx: AppMatchContext = null


func _init(p_ctx: AppMatchContext = null) -> void:
	ctx = p_ctx
	name = "SessionDriver"
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = -100


func _process(_delta: float) -> void:
	if ctx != null:
		ctx.frame()
