# Azaman liquid launch — dark

This mark-only splash prototype uses one 3-second Rive animation: a strong refractive emergence, a calmer centered hold, and a returning fluid swell that distorts and dissolves the mark for the screen handoff. The wordmark, rounded glass tile, and outward rings are not part of the rendered composition.

`liquid.luau` refracts the supplied silver SVG mark through a deforming image mesh. Dispersion fringes rise and settle with the same liquid wave instead of running as separate effects. The Rive timeline scales and translates together to keep the mark centered during the full sequence.

Run `rive .` from this folder to open the live preview. Key phase captures are in `build/azaman-liquid-arrival.png`, `build/azaman-liquid-stable.png`, and `build/azaman-liquid-departure.png`. The signed `.riv` in `build/` carries the current workspace's Rive watermark, so Flutter uses the compact MP4 render of this scene at `assets/experience/launch/azaman_launch_dark.mp4` instead. The light theme uses the matching render from `../azaman-liquid-light`.

The app selects the matching render from the active theme through `AzamanIntroPlayer`. Both assets are 932 × 1460, H.264/yuv420p, silent, and three seconds long. Reduced-motion and playback-error cases show the centered mark in the active theme without the wordmark.
