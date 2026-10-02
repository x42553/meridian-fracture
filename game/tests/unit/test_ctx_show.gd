extends RefCounted
## HARD1: a failed assertion about an Object must never serialise the object. `var_to_str(Object)` walks every property, so a RefCounted cycle
## (AI brain <-> context) overflowed the native stack and killed the whole test runner (SIGBUS / SIGABRT) instead of reporting a failure.


class Node1:
	extends RefCounted
	var other: RefCounted = null
	var payload: Array = []


func _cycle() -> Node1:
	var a: Node1 = Node1.new()
	var b: Node1 = Node1.new()
	a.other = b
	b.other = a  # RefCounted cycle (leaks on purpose: the point is that the failure text survives it)
	a.payload = [a, b, {"self": a}]
	return a


func test_failed_assertions_on_cyclic_objects_report_instead_of_crashing(t: TestCtx) -> void:
	var inner: TestCtx = TestCtx.new()
	var a: Node1 = _cycle()
	inner.is_null(a, "cyclic object")
	inner.eq(a, null, "cyclic object vs null")
	inner.ne(a, a.other)
	inner.eq([a, a.other], [], "objects inside a container")
	inner.eq({"k": a}, {}, "objects inside a dictionary")
	t.gt(inner.failures.size(), 3, "the failures were recorded")
	var text: String = str(inner.failures[0]["msg"])
	t.check(text.contains("Node1") or text.contains("RefCounted"), "the text names the class: " + text)
	t.check(text.contains("#"), "and carries the instance id")
	a.payload = []
	a.other = null  # break the cycles: this test must not leak


func test_show_keeps_plain_values_readable(t: TestCtx) -> void:
	var inner: TestCtx = TestCtx.new()
	inner.eq(3, 4)
	inner.eq("a", "b")
	inner.eq([1, 2], [1, 3])
	t.eq(inner.failures.size(), 3)
	t.check(str(inner.failures[0]["msg"]).contains("got 3, expected 4"), str(inner.failures[0]["msg"]))
	t.check(str(inner.failures[2]["msg"]).contains("[1, 2]"), str(inner.failures[2]["msg"]))


func test_a_freed_object_is_named_as_such(t: TestCtx) -> void:
	var inner: TestCtx = TestCtx.new()
	var n: Node = Node.new()
	var ref: WeakRef = weakref(n)
	n.free()
	inner.is_null(n, "freed")
	t.is_null(ref.get_ref())
	t.eq(inner.failures.size(), 0, "a freed instance compares equal to null")
