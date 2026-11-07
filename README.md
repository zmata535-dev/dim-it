# Dim It

`dim-it` dims the display after inactivity and restores the previous brightness when activity resumes. Its settings panel follows the existing `zm.auto-dim` interaction pattern.

While dimmed, Dim It temporarily changes the shared bar text and active foreground. Choose Gray, Dk Gray, or Black in its settings panel. On activity or restore, it returns to the prior user override or the live theme foreground. The settings panel keeps its regular popup colors.

The stock bar exposes its global foreground to third-party widgets as a read-only API. Dim It uses Omarchy's watched user `shell.toml` override to apply the temporary bar foreground without changing stock bar files, and restores the original `[bar] text` and `[bar] active` entries after activity.

Settings are stored in `~/.config/omarchy/dim-it.json`.
