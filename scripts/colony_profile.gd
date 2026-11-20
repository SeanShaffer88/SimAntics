extends RefCounted
## Who this player's colony is: a per-install seed picks the species and soil, and
## drives the nest layout. The seed is created once and saved, so every player gets
## their own colony and keeps it between launches.

const SETTINGS_PATH := "user://simantics.cfg"

## Species are modelled on real ants. Values that matter for behaviour and layout:
##   castes   - worker sizes (polymorphism): weight, size, head scale
##   workers  - colony size range shown on screen
##   depth    - nest depth as a fraction of the soil cross-section
##   chambers - chamber count range; shafts - vertical shaft count range
##   food     - what fills the food chambers ("seeds", "prey", "fungus")
##   granaries / fungus_gardens - how many chambers get those roles
##   refuse_deep - true for leafcutters, which keep waste in deep chambers
##   cocoons  - true where pupae spin cocoons (Formicinae); false = naked pupae
const SPECIES := [
	{
		"id": "harvester", "name": "Red Harvester Ant",
		"body": Color("#9c3c18"), "gaster": Color("#8a3014"), "dark": Color("#3e1206"), "light": Color("#e08a58"),
		"castes": [{"name": "worker", "weight": 1.0, "size": 1.0, "head": 1.1}],
		"workers": [16, 22], "depth": [0.85, 1.0], "chambers": [7, 10], "shafts": [1, 2],
		"food": "seeds", "granaries": 3, "fungus_gardens": 0, "refuse_deep": false, "cocoons": false,
		"speed": 1.0,
	},
	{
		"id": "bigheaded", "name": "Big-headed Ant",
		"body": Color("#7a4a22"), "gaster": Color("#5a3416"), "dark": Color("#2a160a"), "light": Color("#c08a50"),
		"castes": [
			{"name": "minor", "weight": 0.8, "size": 0.8, "head": 1.0},
			{"name": "major", "weight": 0.2, "size": 1.0, "head": 1.9},
		],
		"workers": [18, 26], "depth": [0.6, 0.85], "chambers": [6, 9], "shafts": [1, 2],
		"food": "seeds", "granaries": 2, "fungus_gardens": 0, "refuse_deep": false, "cocoons": false,
		"speed": 1.1,
	},
	{
		"id": "leafcutter", "name": "Leafcutter Ant",
		"body": Color("#a0461e"), "gaster": Color("#8c3c18"), "dark": Color("#3a1406"), "light": Color("#e0905a"),
		"castes": [
			{"name": "minima", "weight": 0.35, "size": 0.7, "head": 1.0},
			{"name": "media", "weight": 0.5, "size": 0.95, "head": 1.15},
			{"name": "soldier", "weight": 0.15, "size": 1.3, "head": 1.7},
		],
		"workers": [22, 28], "depth": [0.9, 1.0], "chambers": [8, 11], "shafts": [2, 2],
		"food": "fungus", "granaries": 0, "fungus_gardens": 3, "refuse_deep": true, "cocoons": false,
		"speed": 0.9,
	},
	{
		"id": "pavement", "name": "Pavement Ant",
		"body": Color("#4a3426"), "gaster": Color("#2e2018"), "dark": Color("#140c08"), "light": Color("#8a6a52"),
		"castes": [{"name": "worker", "weight": 1.0, "size": 0.85, "head": 1.05}],
		"workers": [20, 28], "depth": [0.5, 0.7], "chambers": [6, 9], "shafts": [1, 2],
		"food": "prey", "granaries": 1, "fungus_gardens": 0, "refuse_deep": false, "cocoons": false,
		"speed": 1.15,
	},
	{
		"id": "garden", "name": "Black Garden Ant",
		"body": Color("#3a2a22"), "gaster": Color("#241a16"), "dark": Color("#0e0806"), "light": Color("#7a6458"),
		"castes": [{"name": "worker", "weight": 1.0, "size": 0.9, "head": 1.0}],
		"workers": [18, 26], "depth": [0.65, 0.9], "chambers": [6, 9], "shafts": [1, 2],
		"food": "prey", "granaries": 1, "fungus_gardens": 0, "refuse_deep": false, "cocoons": true,
		"speed": 1.2,
	},
]

## Soil types: strata colours from the surface down.
const SOILS := [
	{"name": "loam", "strata": [Color("#5a3a24"), Color("#7e5432"), Color("#6a4630"), Color("#3e2a1e")]},
	{"name": "sandy", "strata": [Color("#7a5a3a"), Color("#b08a58"), Color("#9a7448"), Color("#6a4e34")]},
	{"name": "red clay", "strata": [Color("#5e3424"), Color("#9a5232"), Color("#82402a"), Color("#4a2a1e")]},
]

var seed_value := 0
var species: Dictionary
var soil: Dictionary
var worker_count := 0
var is_preview := false


## Loads this install's colony seed, creating and saving one on first launch.
static func load_or_create() -> RefCounted:
	for arg in OS.get_cmdline_user_args():  # dev preview: godot -- --colony-seed=123
		if arg.begins_with("--colony-seed="):
			var preview: RefCounted = from_seed(int(arg.get_slice("=", 1)))
			preview.is_preview = true  # never read or write the player's save
			return preview
	var config := ConfigFile.new()
	config.load(SETTINGS_PATH)
	var colony_seed := int(config.get_value("colony", "seed", 0))
	if colony_seed == 0:
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		colony_seed = rng.randi_range(1, 2147483646)
		config.set_value("colony", "seed", colony_seed)
		config.save(SETTINGS_PATH)
	return from_seed(colony_seed)


## Replaces this install's colony seed with a fresh one (a new species, soil and nest).
static func reset_seed() -> void:
	var config := ConfigFile.new()
	config.load(SETTINGS_PATH)
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	config.set_value("colony", "seed", rng.randi_range(1, 2147483646))
	config.save(SETTINGS_PATH)


static func from_seed(colony_seed: int) -> RefCounted:
	var profile: RefCounted = (load("res://scripts/colony_profile.gd") as GDScript).new()
	profile.seed_value = colony_seed
	var rng := RandomNumberGenerator.new()
	rng.seed = colony_seed
	profile.species = SPECIES[rng.randi() % SPECIES.size()]
	profile.soil = SOILS[rng.randi() % SOILS.size()]
	var range_workers: Array = profile.species["workers"]
	profile.worker_count = rng.randi_range(range_workers[0], range_workers[1])
	return profile


## Picks a caste for one worker, weighted by the species' caste mix.
func pick_caste(rng: RandomNumberGenerator) -> Dictionary:
	var castes: Array = species["castes"]
	var roll := rng.randf()
	for caste: Dictionary in castes:
		roll -= caste["weight"]
		if roll <= 0.0:
			return caste
	return castes[castes.size() - 1]
