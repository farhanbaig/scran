# Bundled fonts

Scran uses three OFL-licensed families. The app registers them at runtime
(`AppFonts.register()` in `DesignSystem/ScranFont.swift`) — **no `Info.plist`
`UIAppFonts` array is required**. If these files are missing the app still
builds and runs, falling back to the matching system font.

Drop these exact files into this folder (they are auto-included by the
file-system-synchronized Xcode group). Filenames must match the PostScript /
resource names referenced in `ScranFont.swift`:

- `ArchivoBlack-Regular.ttf`
- `InterTight-Regular.ttf`
- `InterTight-Medium.ttf`
- `InterTight-SemiBold.ttf`
- `InterTight-Bold.ttf`
- `SpaceMono-Regular.ttf`
- `SpaceMono-Bold.ttf`

Sources (all OFL, free to bundle):
- Archivo Black — https://fonts.google.com/specimen/Archivo+Black
- Inter Tight — https://fonts.google.com/specimen/Inter+Tight
- Space Mono — https://fonts.google.com/specimen/Space+Mono

Or via the Google Fonts repo: https://github.com/google/fonts/tree/main/ofl
(`archivoblack`, `intertight`, `spacemono`).

After adding them, confirm the PostScript names in Font Book match the strings
in `ScranFont.swift`; adjust if a foundry ships different internal names.

## Status: bundled ✅

All seven `.ttf` files are present and verified — their internal PostScript
names match the `.custom(...)` strings in `ScranFont.swift` exactly, and they're
auto-included via the file-system-synchronized Xcode group (confirmed present in
the built `.app` and rendering in the running app).

`ArchivoBlack-Regular`, `SpaceMono-Regular`, `SpaceMono-Bold` come straight from
`ofl/archivoblack` and `ofl/spacemono` in the google/fonts repo.

Inter Tight ships there **only as a variable font** (`InterTight[wght].ttf`), so
the four static weights were instanced from it with fontTools:

```sh
python3 -m venv venv && ./venv/bin/pip install fonttools
for w in 400:Regular 500:Medium 600:SemiBold 700:Bold; do
  ./venv/bin/fonttools varLib.instancer "InterTight[wght].ttf" \
    wght=${w%%:*} --update-name-table -o "InterTight-${w##*:}.ttf"
done
```

`--update-name-table` rebuilds the name table from the font's STAT axis values,
yielding the exact PostScript names (`InterTight-Regular`, `-Medium`,
`-SemiBold`, `-Bold`) that `ScranFont.swift` registers.
