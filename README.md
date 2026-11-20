# SimAntics

A passive, observational ant-farm simulation for Android, built in Godot 4.7.2 (GDScript, Compatibility renderer, 1280x720 landscape). There is nothing to win or lose: you watch a self-sustaining colony live.

## What's in it

- **Every player's colony is unique.** A seed created on first launch picks the species (Red Harvester, Big-headed, Leafcutter, Pavement or Black Garden Ant), the soil type and the nest blueprint.
- **Founding and digging.** A new colony starts as a founding queen, her first brood and four workers in one small chamber. Workers dig the rest of the nest out over time:
  - Each soil pellet they carry out lands on a growing mound.
  - Chambers widen as they're dug.
  - New entrances break through to the surface.
  - The queen moves down into her deep chamber once it opens.
- **A living colony.**
  - The queen lays eggs, which become larvae, then pupae, then pale callow workers.
  - Nurses carry and feed the brood.
  - Workers haul waste and dig.
  - Foragers bring food home.
  - Workers change job with age, and majors and soldiers guard.
  - Mature colonies raise winged queens and males, which leave on a nuptial flight after rain.
- **Food, weather and visitors.**
  - Drag sugar, nectar, fruit, a dead ladybug or seeds onto the surface. Each food draws foragers differently, but the preferences are never shown.
  - Occasional rain sends everyone home.
  - A bird sometimes hunts surface ants. Tap it three times to scare it off.
- **Watching.**
  - Tap an ant or a chamber to inspect it.
  - Double-tap, pinch or scroll to zoom.
  - There's a day/night cycle and scent trails.
  - The info panel shows colony stats and a population graph, and can start a new colony.
- **Saved progress.** The colony saves itself and catches up on time away (up to 8 hours).

All art and sound is generated in code. The project has no external assets.

## Running

Open the folder in Godot 4.7.2 and press F5.

Developer launch options (after `--`):

- `--colony-seed=123` previews a specific colony without touching your saved one.
- `--mature` opens the whole nest at once instead of starting from a founding queen.

## Tests

```
godot --headless --path . -s res://tools/tests/test_nest_generator.gd
```

These check 300 seeds: every chamber is reachable, no chambers overlap, every node stays inside the frame, the chamber roles are valid, and the same seed always gives the same nest.

## Android

`export_presets.cfg` builds an arm64 APK. `tools/build_release.ps1` signs a release build with your own keystore; the script's header explains the one-time setup.
