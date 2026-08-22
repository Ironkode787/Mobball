class_name Switches
extends RefCounted
## Table switch id → economy group (specs/ledger-data.md `value_mult` targets).
##
## Hardware ids are the table lane's vocabulary (`bumper_2`, `sling_l`, `rollover_3`,
## `wire_bank_1`…); value groups are the economy's. This is the one place the two meet, so
## a renamed target never has to be chased through the flow code.

## Groups whose Jobs need "hit every one of them" — the count of distinct switches that
## make the set (rollover lanes, wire payphones, storefront banks).
const COVER_SIZE := {
	&"rollovers": 3,
	&"wire": 3,
	&"storefronts": 3,
}

const _PREFIXES: Array[Array] = [
	["bumper", &"bumpers"],
	["sling", &"slings"],
	["spinner", &"spinner"],
	["rollover", &"rollovers"],
	["wire", &"wire"],
	["storefront", &"storefronts"],
	["orbit", &"orbit"],
	["laundromat", &"laundry"],
	["kickback", &"kickback"],
	["bribe", &"bribe"],
	["cop", &"cop"],
]


## The value group a switch pays into. Unknown hardware pays as &"other" — it still earns,
## it just misses group-specific multipliers, which is the right failure for new hardware
## that lands before its upgrade data does.
static func group_for(id: StringName) -> StringName:
	var s := String(id)
	for row: Array in _PREFIXES:
		if s.begins_with(String(row[0])):
			return row[1]
	return &"other"


## True for the "whole bank went down" switch a drop bank fires on completion.
static func is_bank_complete(id: StringName) -> bool:
	return String(id).ends_with("_complete")


## Trailing index of an indexed switch (`rollover_2` → 2), or -1. The skill shot needs it
## to know which lane the ball actually took.
static func index_of(id: StringName) -> int:
	var s := String(id)
	var cut := s.rfind("_")
	if cut < 0 or cut >= s.length() - 1:
		return -1
	var tail := s.substr(cut + 1)
	if not tail.is_valid_int():
		return -1
	return tail.to_int()
