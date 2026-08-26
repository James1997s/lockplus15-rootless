# White Framed Motion asset provenance

The `themes/assets/framed-parking/parking-animation.gif` asset is derived from the animation URL provided directly by the repository owner: <https://i.giphy.com/4HmjzyjzUkXpHmEG5i.webp>.

The user requested that the animation be used unchanged inside a photo-style frame. Its visual composition was therefore neither cropped nor semantically edited. It was converted from animated WebP to GIF because the LockPlus 15 remote-asset contract supports GIF rather than WebP. The resulting GIF preserves the full 500 × 333 frame, loops indefinitely, and uses 15 sampled frames at 80 ms each to remain below the client’s 2 MiB download cap.

The asset is hosted in this repository solely for Theme Manager’s on-demand download flow and is not bundled into the Debian package.
