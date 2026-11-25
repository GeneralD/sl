# Third-party assets

## share/sl/models/loco.usdz — realistic 4-6-2 steam locomotive

- Source: "Steam Locomotive" v1 — tevy.dev
  <https://tevy.dev/models/steam-locomotive>
- License: CC0 1.0 Universal (public domain, no attribution required)
- Derivative: GLB converted to USDZ (Blender 5.3), textures decoded
  from KTX2 (basis_universal), re-oriented to X-forward/Y-up.
- Vendored file: `share/sl/models/loco.usdz`, selected by `--model loco`.

## Third-party audio assets

Vendored files live in `share/sl/audio/` and are installed to
`$(PREFIX)/share/sl/audio/` by `make install`. Every file is a trimmed /
converted derivative of the source below; licenses verified 2025-11-25.
All audio is mono 22050 Hz 16-bit PCM WAV.

## chuff.wav — steam locomotive chuff loop (~3.9 s, loop-crossfaded)

- Source: "Steam locomotive #1" — BigSoundBank
  <https://bigsoundbank.com/steam-locomotive-1-s3016.html>
  (direct file: <https://bigsoundbank.com/UPLOAD/mp3/3016.mp3>)
- License: CC0 1.0 Universal — <https://bigsoundbank.com/licenses.html>
- Derivative: 20.0–24.0 s excerpt, 150 ms loop crossfade, downmixed to
  mono 22050 Hz WAV.

## whistle.wav — steam whistle blast (~1.2 s)

- Source: `File:WWS SteamWhistle.ogg` — Wikimedia Commons
  <https://commons.wikimedia.org/wiki/File:WWS_SteamWhistle.ogg>
- Artist: Work With Sounds / Konrad Gutkowski
- License: CC BY 4.0 — <https://creativecommons.org/licenses/by/4.0>
- Attribution: "WWS SteamWhistle.ogg" by Work With Sounds /
  Konrad Gutkowski, licensed under CC BY 4.0.
- Derivative: ~5.30–6.55 s blast excerpt with short fades, downmixed to
  mono 22050 Hz WAV.

## scream.wav — short crowd scream (~2.5 s)

- Source: "Kids Scream #1" — BigSoundBank
  <https://bigsoundbank.com/kids-scream-1-s1148.html>
  (direct file: <https://bigsoundbank.com/UPLOAD/mp3/1148.mp3>)
- License: CC0 1.0 Universal — <https://bigsoundbank.com/licenses.html>
- Derivative: 1.2–3.7 s excerpt with short fades, downmixed to mono
  22050 Hz WAV.
