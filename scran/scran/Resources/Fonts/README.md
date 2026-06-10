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
