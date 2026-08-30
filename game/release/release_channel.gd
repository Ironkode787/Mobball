class_name ReleaseChannel
extends RefCounted
## One policy seam for environment-driven previews and QA overrides.


static func allow_development_hooks(is_debug: bool = OS.is_debug_build(),
		is_beta: bool = OS.has_feature("beta")) -> bool:
	return is_debug and not is_beta
