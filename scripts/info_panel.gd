extends PanelContainer
## Colony at a glance: species, age, who is doing what, brood, food, how much of the
## nest is dug, and a graph of the population over time. Also where a player can
## start over with a brand-new colony (after confirming).

signal new_colony_requested
signal keep_screen_on_changed(on: bool)
signal speed_changed(speed: float)

const SPEEDS := [1.0, 2.0, 4.0]

const TEXT := Color("#f0dcb4")
const DIM := Color("#c8b494")
const GRAPH_LINE := Color("#e0a050")
const GRAPH_FILL := Color(0.88, 0.63, 0.31, 0.18)

var _stats: Callable  # returns a Dictionary of current figures
var _history: Callable  # returns Array of population samples
var _rows: Dictionary = {}
var _graph: Control
var _refresh := 0.0
var _confirm: ConfirmationDialog
var _keep_on: CheckButton
var _speed_buttons: Array[Button] = []
var _notes_label: Label
var notes: Callable  # returns recent field-note entries, newest first


func setup(stats: Callable, history: Callable, keep_on: bool, speed: float) -> void:
	_stats = stats
	_history = history
	_keep_on.set_pressed_no_signal(keep_on)
	for i in SPEEDS.size():
		_speed_buttons[i].set_pressed_no_signal(is_equal_approx(SPEEDS[i], speed))


func _ready() -> void:
	custom_minimum_size = Vector2(330, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	add_child(box)
	var title := Label.new()
	title.name = "Title"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", TEXT)
	box.add_child(title)
	_rows["title"] = title
	for key in ["age", "workers", "roles", "brood", "food", "nest", "guide"]:
		var row := Label.new()
		row.add_theme_font_size_override("font_size", 14)
		row.add_theme_color_override("font_color", DIM)
		row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(row)
		_rows[key] = row
	var caption := Label.new()
	caption.text = "Population"
	caption.add_theme_font_size_override("font_size", 13)
	caption.add_theme_color_override("font_color", DIM)
	box.add_child(caption)
	_graph = Control.new()
	_graph.custom_minimum_size = Vector2(300, 64)
	_graph.draw.connect(_draw_graph)
	box.add_child(_graph)
	var notes_caption := Label.new()
	notes_caption.text = "Field notes"
	notes_caption.add_theme_font_size_override("font_size", 13)
	notes_caption.add_theme_color_override("font_color", DIM)
	box.add_child(notes_caption)
	_notes_label = Label.new()
	_notes_label.add_theme_font_size_override("font_size", 13)
	_notes_label.add_theme_color_override("font_color", TEXT)
	_notes_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_notes_label.custom_minimum_size = Vector2(300, 0)
	box.add_child(_notes_label)

	# settings: keep the phone awake on a desk, and how fast to watch
	_keep_on = CheckButton.new()
	_keep_on.text = "Keep screen on"
	_keep_on.focus_mode = Control.FOCUS_NONE
	_keep_on.add_theme_color_override("font_color", DIM)
	_keep_on.toggled.connect(func(on: bool): keep_screen_on_changed.emit(on))
	box.add_child(_keep_on)
	var speed_row := HBoxContainer.new()
	speed_row.add_theme_constant_override("separation", 6)
	var speed_label := Label.new()
	speed_label.text = "Watch speed"
	speed_label.add_theme_font_size_override("font_size", 14)
	speed_label.add_theme_color_override("font_color", DIM)
	speed_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	speed_row.add_child(speed_label)
	var group := ButtonGroup.new()
	for s: float in SPEEDS:
		var b := Button.new()
		b.text = "%d×" % int(s)
		b.toggle_mode = true
		b.button_group = group
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(44, 0)
		var chosen := StyleBoxFlat.new()  # the selected speed stands out clearly
		chosen.bg_color = Color("#8a5a2e")
		chosen.border_color = Color("#f0c080")
		chosen.set_border_width_all(2)
		chosen.set_content_margin_all(6)
		b.add_theme_stylebox_override("pressed", chosen)
		b.add_theme_stylebox_override("hover_pressed", chosen)
		b.add_theme_color_override("font_pressed_color", Color.WHITE)
		b.add_theme_color_override("font_hover_pressed_color", Color.WHITE)
		b.toggled.connect(func(on: bool):
			if on:
				speed_changed.emit(s))
		speed_row.add_child(b)
		_speed_buttons.append(b)
	box.add_child(speed_row)

	var restart := Button.new()
	restart.text = "Start a new colony…"
	restart.focus_mode = Control.FOCUS_NONE
	restart.pressed.connect(func(): _confirm.popup_centered())
	box.add_child(restart)

	_confirm = ConfirmationDialog.new()
	_confirm.title = "Start a new colony?"
	_confirm.dialog_text = "Your current colony will be gone for good, and a new founding queen\n" + \
			"of a randomly chosen species will start digging in fresh soil."
	_confirm.ok_button_text = "Start new colony"
	_confirm.cancel_button_text = "Keep this one"
	_confirm.confirmed.connect(func(): new_colony_requested.emit())
	add_child(_confirm)
	visible = false


func toggle() -> void:
	visible = not visible
	if visible:
		_update()


func _process(delta: float) -> void:
	if not visible:
		return
	_refresh -= delta
	if _refresh <= 0.0:
		_refresh = 1.0
		_update()


func _update() -> void:
	if not _stats.is_valid():
		return
	var s: Dictionary = _stats.call()
	_rows["title"].text = s["title"]
	_rows["age"].text = "Founded %s ago" % s["age"]
	_rows["workers"].text = "%d workers  ·  queen%s" % [s["workers"], s["alates"]]
	_rows["roles"].text = "%d nurses, %d nest workers, %d foragers, %d guards" % s["roles"]
	_rows["brood"].text = "Brood: %d eggs, %d larvae, %d pupae" % s["brood"]
	_rows["food"].text = "Food stored: %d  ·  %d sugary, %d with protein" % s["food"]
	_rows["nest"].text = "Nest dug: %d%%  ·  %d of %d chambers open" % s["nest"]
	_rows["guide"].text = "Behaviours observed: %d of %d  (tap ants to discover more)" % s["guide"]
	_graph.queue_redraw()
	if notes.is_valid():
		var lines: Array[String] = []
		var now := Time.get_unix_time_from_system()
		for e: Dictionary in notes.call():
			lines.append("%s  —  %s" % [_ago(now - float(e["time"])), e["text"]])
		_notes_label.text = "\n".join(lines) if not lines.is_empty() else "Nothing noted yet."


static func _ago(seconds: float) -> String:
	if seconds < 90.0:
		return "just now"
	var minutes := int(seconds / 60.0)
	if minutes < 60:
		return "%d min ago" % minutes
	if minutes < 60 * 48:
		return "%d h ago" % (minutes / 60)
	return "%d days ago" % (minutes / 1440)


func _draw_graph() -> void:
	var size := _graph.size
	_graph.draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.25))
	var samples: Array = _history.call() if _history.is_valid() else []
	if samples.size() < 2:
		_graph.draw_string(get_theme_default_font(), Vector2(8, size.y * 0.6), "Gathering data…",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 12, DIM)
		return
	var top := 1
	for v in samples:
		top = maxi(top, int(v))
	var points := PackedVector2Array()
	for i in samples.size():
		var x := size.x * i / (samples.size() - 1)
		var y := size.y - 4.0 - (size.y - 10.0) * float(samples[i]) / top
		points.append(Vector2(x, y))
	var fill := points.duplicate()
	fill.append(Vector2(size.x, size.y))
	fill.append(Vector2(0, size.y))
	_graph.draw_colored_polygon(fill, GRAPH_FILL)
	_graph.draw_polyline(points, GRAPH_LINE, 2.0)
	_graph.draw_string(get_theme_default_font(), Vector2(size.x - 34, 14), str(top),
			HORIZONTAL_ALIGNMENT_RIGHT, 30, 12, DIM)
