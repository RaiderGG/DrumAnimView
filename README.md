# DrumAnimView

A small Reaper visualization script that turns Rock Band style drummer animation MIDI notes into an animated drum kit view. It reads the notes from a track named `PART DRUMS`, maps them to the appropriate drum positions, and animates the hi-hat opening, kick pedal, and left/right hands in real time as playback or the cursor moves.

![Preview](screenshots/DrumAnimView.jpg)

## Features

- Animated drum kit visualization based on MIDI drum note data
- Adjustable timing offset, hand opacity, and display scale
- Hand labels with customizable color for visual clarity

## Requirements

- REAPER
- A MIDI drum track called `PART DRUMS`
- `ReaImGui` is optional; when Lua can find it, the script uses it, otherwise it uses REAPER's built-in `gfx` API.

## Installation - Windows

1. Download .zip from the **Releases** tab
2. Copy `DrumAnimView` folder to `%appdata%\REAPER\Scripts`
3. In REAPER, go to `Actions` **>** `Show action list...`
4. Click `New action...` and then `Load ReaScript`  
	4.1. Navigate to `%appdata%\REAPER\Scripts\DrumAnimView`  
	4.2. Select `DrumAnimView.lua` and click `Open`  
	4.3. Optionally, add a keybind, or use the Menu Editor to add the action to a toolbar

## Usage

1. Create or select a MIDI track named `PART DRUMS`.
2. Add MIDI drum animation notes to it.
3. Run `DrumAnimView.lua` in Reaper.
4. Use the on-screen controls to adjust:
   - **Timing offset**
   - **Hand opacity**
   - **Scale/zoom**
5. Play your project or move the edit cursor to preview the animation.

## Notes

- The script reads note data from `PART DRUMS` and maps MIDI pitches to visual targets.
- This is a visual aid for reviewing drum timing and feel, not a drum instrument or MIDI editor.
- The included assets in the `assets/` folder are used for the background, kick pedal animation, hi-hat animation, and hand sprites.

## License

This project is provided as-is for personal and creative use. If you plan to redistribute it, please keep the original script and asset files together.

Asset Credits
Lowpoly Drumstick

Author: Jiří Kuba (@kuba.jirka)
 Source: https://sketchfab.com/3d-models/lowpoly-drumstick-0cab2eab9d3a45aba4f68f72bfa5ae1e
 License: Sketchfab Free Standard License

LJAS - Alesis Crimson Mesh Kit

Author: La Jarre à Son (@la_jarre_a_son)
 Source: https://sketchfab.com/3d-models/ljas-alesis-crimson-mesh-kit-015965ea26c34902afdf7a843c9c03d4
 License: Creative Commons Attribution 4.0 International (CC BY 4.0)

Hand (low poly)

Author: scribbletoad (@scribbletoad)
 Source: https://sketchfab.com/3d-models/hand-low-poly-d6c802a74a174c8c805deb20186d1877
 License: Creative Commons Attribution 4.0 International (CC BY 4.0)
