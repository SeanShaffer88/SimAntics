extends PanelContainer
## Colony at a glance: species, age, who is doing what, brood, food, how much of the
## nest is dug, and a graph of the population over time. Also where a player can
## start over with a brand-new colony (after confirming).

signal new_colony_requested

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


func setup(stats: Callable, history: Callable) -> void:
	_stats = stats
	_history = history


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
	for key in ["age", "workers", "roles", "brood", "food", "nest"]:
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
	_rows["food"].text = "Food stored: %d" % s["food"]
	_rows["nest"].text = "Nest dug: %d%%  ·  %d of %d chambers open" % s["nest"]
	_graph.queue_redraw()


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
