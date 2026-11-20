# SimAntics

A passive, observational ant-farm simulation for Android, built in Godot 4.7.2 (GDScript, Compatibility renderer, 1280x720 landscape). There is nothing to win or lose: you watch a self-sustaining colony live.

## What's in it

- **A unique colony per player.** A seed created on first launch picks the species (Red Harvester, Big-headed, Leafcutter, Pavement or Black Garden Ant), the soil type and the nest layout.
- **Ant-farm nest.** Rows of rounded, flat-floored chambers across the whole frame, joined by short openings, with several surface entrances. The central queen's chamber is surrounded by nurseries, with a separate pupa chamber, an alate chamber, food stores or fungus gardens, a refuse chamber and resting chambers.
- **A living colony.** The queen lays eggs, which hatch into larvae, then pupae, then pale callow workers. Nurses carry and feed the brood, workers haul waste, and foragers bring food home. Workers change job with age, and majors and soldiers guard.
- **Surface.** Five selectable presets with a cross-fade, a day/night cycle, and scent trails.
- **Watching tools.** Tap an ant or chamber to inspect it, and double-tap, pinch or scroll to zoom.
- **Generated sound.** Wind and crickets made in code, with a mute button.

All art and sound is generated in code: the project has no external assets.

## Running

Open the folder in Godot 4.7.2 and press F5. To preview a specific colony without touching your saved one, launch with `-- --colony-seed=123`.
