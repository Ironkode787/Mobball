class_name TableAPI
extends RefCounted
## The flow lane's defensive doorway to the table root (`res://game/table/table_main.tscn`).
##
## The table workstream is rebuilding that scene in parallel with this code, and the M1
## additions (`set_raid_active`, `set_lit_rollover`, `pays_through_game`, storefront arming)
## land at their own pace. Every call from flow into the table goes through here so a
## missing API is a shrug, never a crash — and so there is exactly one list of the things
## flow expects the table to grow.

## True if `obj` really has that property. `Object.get()` on a missing name is a silent
## null, which is indistinguishable from a property that is legitimately null.
static func has_property(obj: Object, property: String) -> bool:
	if obj == null or not is_instance_valid(obj):
		return false
	for p: Dictionary in obj.get_property_list():
		if String(p.get("name", "")) == property:
			return true
	return false


static func prop(obj: Object, property: String, fallback: Variant = null) -> Variant:
	if not has_property(obj, property):
		return fallback
	var v: Variant = obj.get(property)
	return fallback if v == null else v


## Call `method` if the table has it. Returns the result, or `fallback` if it does not.
static func call_if(obj: Object, method: String, args: Array = [], fallback: Variant = null) -> Variant:
	if obj == null or not is_instance_valid(obj) or not obj.has_method(method):
		return fallback
	return obj.callv(method, args)


## The ball currently in play, or null.
static func ball(table: Object) -> Ball:
	var b: Variant = prop(table, "ball", null)
	if b is Ball and is_instance_valid(b as Ball):
		return b
	return null


static func bounds(table: Object, fallback: Rect2) -> Rect2:
	var r: Variant = call_if(table, "bounds", [], fallback)
	if r is Rect2 and (r as Rect2).size.y > 0.0:
		return r
	return fallback
