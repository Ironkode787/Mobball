extends Node
## AudioDirector autoload. Gameplay calls AudioDirector.play(&"event") and never touches
## files. Event → asset mapping is owned by the audio workstream (specs/audio-pipeline.md).
## Missing assets fail silent (logged once) so gameplay never depends on audio being built.

var _missing_logged: Dictionary = {}


func play(event: StringName, _opts: Dictionary = {}) -> void:
	var path := "res://assets/audio/sfx/%s.wav" % event
	if not ResourceLoader.exists(path):
		if not _missing_logged.has(event):
			_missing_logged[event] = true
			print("[audio] no asset yet for event: ", event)
		return
	var stream: AudioStream = load(path)
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.finished.connect(p.queue_free)
	add_child(p)
	p.play()
