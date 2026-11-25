# Azaman liquid launch — light

This is the light theme companion to `../azaman-liquid`: the silver mark appears alone over `#F4F4F7`, with no wordmark, tile, or outward rings. One continuous 3-second animation brings in a refractive liquid swell, settles into a clean centered hold, then returns the distortion to carry the mark away.

`liquid.luau` refracts the supplied silver SVG mark through a deforming image mesh. The colored edge dispersion follows the same wave and recedes during the calm hold. The Rive timeline scales and translates together to keep the mark centered throughout.

Run `rive .` from this folder to open the live preview. Key phase captures are in `build/azaman-liquid-light-arrival.png`, `build/azaman-liquid-light-stable.png`, and `build/azaman-liquid-light-departure.png`. The signed `.riv` in `build/` carries the current workspace's Rive watermark, so Flutter uses the compact MP4 render of this scene at `assets/experience/launch/azaman_launch_light.mp4` instead.

The app selects the matching render from the active theme through `AzamanIntroPlayer`. Both assets are 932 × 1460, H.264/yuv420p, silent, and three seconds long. Reduced-motion and playback-error cases show the centered mark in the active theme without the wordmark.
