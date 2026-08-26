# Brushstroke Time rotating painting studies — research notes

The planned extended Brushstroke Time sequence would use small **public-domain historical painting studies** after the live time is painted. The device would download compact local assets only when this theme is selected; the renderer would not load external artwork at runtime.

## Verified source finding

- **Mona Lisa — Leonardo da Vinci.** Wikimedia Commons describes the referenced `Mona Lisa.jpg` file as a faithful photographic reproduction of a two-dimensional public-domain work. The page states that Leonardo died in 1519 and identifies the work as public domain in jurisdictions with a life-plus-100-years term; it also applies the Creative Commons Public Domain Mark 1.0 to the file. Source: <https://commons.wikimedia.org/wiki/File:Mona_Lisa.jpg>.

## Candidate historical study

- **The Great Wave — Katsushika Hokusai.** The British Museum collection search result identifies its relevant collection record as a colour woodblock print called *The Great Wave*, depicting fishermen in skiffs and a wave about to crash. The website’s text extraction did not expose a reuse license; do not use or redistribute a British Museum image file until an asset-specific reusable source has been verified. Collection record: <https://www.britishmuseum.org/collection/object/A_1906-1220-0-533>.

## Implementation boundary

The theme should use only source files whose reuse status is explicitly verified. It should attribute source pages in a provenance note and should not make a broader licensing claim about third-party digitizations. A compact asset would be SHA-256-verified during the existing on-demand theme download and then displayed from the local SpecialLock cache.
