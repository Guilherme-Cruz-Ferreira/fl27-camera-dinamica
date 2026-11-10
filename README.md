# fl27-camera-dinamica — dynamic camera for SP Football Life 2027

A **Lua script for [Sider](https://github.com/juce/sider)** that adjusts the **Dynamic Wide** camera according to where the ball is:

- **midfield:** **open** camera (higher and farther away, so you can read the game);
- **near the penalty areas:** **closed** camera (closer, so it is easier to aim and see the action).

When the ball gets close to a **touchline** the camera also opens up a bit more, so the far side of the pitch is not cut off (more on the top touchline than the bottom one, configurable). The attacking end closes fully; **your own box** closes only a fraction of that (`def_strength`, configurable). Transitions are smooth.

> It does not modify any game file. While you play it only reads the ball position and writes two values (camera distance and height) to memory.
> Fan project, not affiliated with the SP Football Life creators or Konami. No game files are included.

## Requirements
- SP Football Life 2027 with Sider (it ships with the game) and the **`camera.lua`** module loaded (it patches the Dynamic Wide camera).
- Tested on **Linux (Wine)** with the `FL_2027.exe` from the 2026-11 build. The memory addresses are specific to that executable: if the game is updated they may need adjusting (see *How it works*).

## Installation

**Windows (manual)**
1. Copy `camera_dinamica.lua` to `SiderAddons\modules\` and `camera_dinamica.ini` to `SiderAddons\`.
2. In `SiderAddons\sider.ini`, right **below** the line `lua.module = "camera.lua"`, add:
   ```
   lua.module = "camera_dinamica.lua"
   ```
3. Start the game.

**Linux (Wine)**
```bash
./install-linux.sh "<path>/SP Football Life 2027/SiderAddons"
```
(close the game first; it backs up `sider.ini`). To remove: delete the line from `sider.ini` and the file in `modules\`.

## Usage
Open the Sider overlay (**Space**) and go to the **camera_dinamica** page. (The on-screen text is in Portuguese.)

| Key | Action |
|---|---|
| PageUp / PageDown | select a setting |
| Delete / Insert | decrease / increase (saved to the `.ini` automatically) |
| F6 | mode: dynamic → force closed → force open → off (only while the camera_dinamica overlay page is open, so it does not clash with other modules that use F6) |
| F7 / F8 | "I am attacking to the right / left" (flips by itself in the 2nd half) |
| Shift+R | reload Sider modules |

A **lower** distance/height value means a **closer** camera. Selecting an *ABERTA* (open) or *FECHADA* (closed) row previews that view. Without calibrating the side (F7/F8) it runs symmetrically (closes the same way at both goals).

## Configuration (`camera_dinamica.ini`)
| Key | Meaning |
|---|---|
| `near_start` / `near_end` | attack: distance to the goal (m) where it starts closing / is fully closed |
| `def_start` / `def_end` / `def_strength` | same for your own box; `def_strength` 0–1 is how much it closes (1 = same as attack) |
| `dist_open` / `height_open` | distance and height of the **open** view (midfield) |
| `dist_close` / `height_close` | distance and height of the **closed** view (the boxes) |
| `side_start` / `side_end` | distance from the centre line (m, pitch width axis) where the extra opening near a touchline starts / is maximal |
| `side_dist` / `side_height` | extra distance / height added near a touchline |
| `side_top` / `side_bottom` | gain (0–2) of that extra opening on the top / bottom touchline |
| `smooth` | per-frame smoothing (lower = slower transition) |
| `debug` | 1 logs the ball position to `sider.log` (diagnostics) |

## How it works
The Dynamic Wide camera reads its distance (`0x14260b8fc`, 28.7 by default) and height (`0x14260b900`, 35.4) from a table in the executable, and the game re-reads them every frame, so the script interpolates them between "open" and "closed". The ball position is read from the match structure (`*(base+0x36f3dc8)`, nodes 0xe3–0xf1, offset `+0xa80`; the node differs between a real match and training mode, so it looks for the one whose neighbour holds identical values). The attacking direction comes from a goalkeeper's position (|x| > 43) plus F7/F8.

`tools/camtune.lua` is a live tuner for discovering what each camera parameter does.

## Known issues
- **Master League:** reported as not working there while Exhibition works. The ball sits in different memory nodes depending on the mode (match vs. training already differ), so v1.2 widens the ball search. This is **not confirmed fixed**: if the overlay shows "bola nao encontrada" (ball not found), the module writes a `DIAGNOSTICO` list of memory nodes to `sider.log` after ~4 s — please open an issue and paste that block.

## Credits
- [Sider](https://github.com/juce/sider) by juce, and the `camera.lua` module that ships with SP Football Life.

## License
MIT — see [LICENSE](LICENSE).
