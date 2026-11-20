extends Node
## The year: days are counted from the day/night cycle (one per midnight) and every
## DAYS_PER_SEASON days the season turns. Ant colonies live by the year: they grow in
## spring, fly in summer, stock up in autumn and overwinter deep in the nest.

signal season_changed(season: int)

enum { SPRING, SUMMER, AUTUMN, WINTER }

const NAMES := ["Spring", "Summer", "Autumn", "Winter"]
const DAYS_PER_SEASON := 6

var day := 0  # days since the colony's first season began

var _day_night: Node
var _last_time := 0.0


func setup(day_night: Node, start_day: int) -> void:
	_day_night = day_night
	day = start_day
	_last_time = _day_night.time_of_day


func season() -> int:
	return int(day / float(DAYS_PER_SEASON)) % 4


func season_name() -> String:
	return NAMES[season()]


func day_of_season() -> int:
	return day % DAYS_PER_SEASON + 1


## How far through the current season (0 at its start, 1 at its end).
func progress() -> float:
	return (float(day % DAYS_PER_SEASON) + _day_night.time_of_day) / DAYS_PER_SEASON


func is_winter() -> bool:
	return season() == WINTER


## Moves the calendar on by whole days (time away, or tests).
func advance_days(days: int) -> void:
	if days <= 0:
		return
	var before := season()
	day += days
	if season() != before:
		season_changed.emit(season())


func _process(_delta: float) -> void:
	if _day_night == null:
		return
	var t: float = _day_night.time_of_day
	if t < _last_time - 0.5:  # the clock passed midnight
		advance_days(1)
	_last_time = t
