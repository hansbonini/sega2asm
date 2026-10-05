class_name ISSSound
extends Node
## ISS Deluxe sound. Uses, in order of preference:
## - res://assets/iss/music/song_NN.ogg: your own captures of the songs;
## - assets/iss/sound/rendered/: every song and effect rendered by running the
##   game's own sound driver (tools/render_sound.py, optional);
## - assets/iss/sound/sfx/: the PCM effects rendered by the extractor.
## Effects play on one player per hardware channel with the driver's rule: a
## new effect replaces the channel's current one unless that has a higher
## priority. say() queues commentary like speech_queue_update.

const DIR := "res://assets/iss/sound/"
const RENDERED := DIR + "rendered/rendered.json"
const MUSIC_DIR := "res://assets/iss/music/"
## speech_queue_update plays one queued line every $40 frames, 4 queued at most.
const SPEECH_GAP := 64.0 / 60.0
const SPEECH_QUEUE := 4

var _doc: Dictionary
var _rendered := {"songs": [], "sfx": []}
var _channels: Array[AudioStreamPlayer] = []
var _priority: Array[int] = []
var _speech: Array[int] = []
var _speech_wait := 0.0
var _music := AudioStreamPlayer.new()


func _ready() -> void:
	_load()
	for i in _doc["driver"]["channels"].size():
		var p := AudioStreamPlayer.new()
		p.finished.connect(func() -> void: _priority[i] = 0)
		add_child(p)
		_channels.append(p)
		_priority.append(0)
	add_child(_music)


## The sound index (also when asked for a stream before _ready).
func _load() -> void:
	if not _doc.is_empty():
		return
	_doc = JSON.parse_string(FileAccess.get_file_as_string(DIR + "sound.json"))
	if FileAccess.file_exists(RENDERED):
		_rendered = JSON.parse_string(FileAccess.get_file_as_string(RENDERED))


## The stream for effect id, or null (no audio for it in this ROM or export).
func sfx_stream(id: int) -> AudioStream:
	_load()
	if id < 0 or id >= _doc["sfx"].size():
		return null
	var s: Dictionary = _doc["sfx"][id]
	if s.get("missing_sample", false):
		return null # a commentary line whose sample is not in this ROM
	var r: Dictionary = _rendered["sfx"][id] if id < _rendered["sfx"].size() else {}
	var looped: bool = s.has("loop") or r.get("held", false)
	if s.has("wav") and (looped or not r.has("ogg")):
		return load(s["wav"]) # exact loop points
	if r.has("ogg"):
		var ogg: AudioStreamOggVorbis = load(r["ogg"])
		ogg.loop = looped
		return ogg
	return null


func has_sfx(id: int) -> bool:
	return sfx_stream(id) != null


## Plays effect id (sound_play_sfx).
func play_sfx(id: int) -> bool:
	var stream := sfx_stream(id)
	if stream == null or _channels.is_empty():
		return false
	var s: Dictionary = _doc["sfx"][id]
	var ch: int = maxi(0, _doc["driver"]["channels"].find(s.get("channel", "")))
	if _channels[ch].playing and int(s["priority"]) < _priority[ch]:
		return false
	_channels[ch].stream = stream
	_channels[ch].play()
	_priority[ch] = int(s["priority"])
	return true


func stop_sfx() -> void:
	for i in _channels.size():
		_channels[i].stop()
		_priority[i] = 0


## Queues commentary line id (speech_queue_push).
func say(id: int) -> void:
	if _speech.size() < SPEECH_QUEUE:
		_speech.append(id)


## speech_queue_reset: the commentary queue emptied.
func clear_speech() -> void:
	_speech.clear()
	_speech_wait = 0.0


## The event a commentary line belongs to ("goal", "corner kick", ...), or "".
func speech_context(id: int) -> String:
	return _doc["sfx"][id].get("speech", "")


func _process(delta: float) -> void:
	if _speech_wait > 0.0:
		_speech_wait -= delta
		return
	if not _speech.is_empty():
		play_sfx(_speech.pop_front())
		_speech_wait = SPEECH_GAP


## Plays song id (sound_play_music d0); false if there is no audio for it.
func play_music(id: int) -> bool:
	_load()
	var own := MUSIC_DIR + "song_%02d.ogg" % id
	if ResourceLoader.exists(own):
		_music.stream = load(own)
	elif id < _rendered["songs"].size() and _rendered["songs"][id].has("ogg"):
		var r: Dictionary = _rendered["songs"][id]
		var ogg: AudioStreamOggVorbis = load(r["ogg"])
		ogg.loop = r.has("loop_offset")
		ogg.loop_offset = r.get("loop_offset", 0.0)
		_music.stream = ogg
	elif id < _rendered["songs"].size() and bool(_rendered["songs"][id].get("silent", false)):
		# Song $19 is the driver's silence (the menus and the title stop the
		# music with it).
		_music.stop()
		return true
	else:
		return false
	_music.play()
	return true


func stop_music() -> void:
	_music.stop()
