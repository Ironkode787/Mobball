class_name SensoryAudit
extends RefCounted
## Runtime evidence for the M4 sensory budget. This observes the live scene; it never changes
## LOD, pauses nodes, or touches gameplay in response to a failure.


static func snapshot(root: Node, budget: PresentationBudget) -> Dictionary:
	var measured := {
		&"draw_calls": RenderingServer.get_rendering_info(
				RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		&"lights": 0,
		&"emitters": budget.count(&"emitters") if budget != null else 0,
		&"audio_voices": 0,
	}
	_count_live(root, measured)
	var violations := {}
	for kind: StringName in PresentationBudget.LIMITS:
		var count := int(measured.get(kind, 0))
		var limit := int(PresentationBudget.LIMITS[kind])
		if count > limit:
			violations[kind] = {"count": count, "limit": limit}
	return {"measured": measured, "violations": violations, "ok": violations.is_empty()}


static func _count_live(node: Node, measured: Dictionary) -> void:
	if node == null:
		return
	if node is Light2D and (node as Light2D).enabled and (node as Light2D).is_visible_in_tree():
		measured[&"lights"] = int(measured[&"lights"]) + 1
	elif node is GPUParticles2D and (node as GPUParticles2D).emitting \
			and (node as GPUParticles2D).is_visible_in_tree():
		# Presentation-budget emitters already count the Phase 3 pooled renderer. Real particle
		# nodes add to that same ceiling rather than opening a second allowance.
		measured[&"emitters"] = int(measured[&"emitters"]) + 1
	elif node is AudioStreamPlayer and (node as AudioStreamPlayer).playing:
		measured[&"audio_voices"] = int(measured[&"audio_voices"]) + 1
	for child: Node in node.get_children():
		_count_live(child, measured)
