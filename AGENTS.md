# Godot toolchain

- Open, run, test and export this project with **Godot 4.7.2 stable Mono/.NET only**.
- Use `Open Game Editor.cmd` for the editor, `Build APK.cmd` for Android, and `tools/run_godot.ps1` with Godot arguments for command-line checks. These share a strict version check in `tools/godot_toolchain.ps1`.
- Do not use standard Godot, older 4.6.x installations, or a Godot executable resolved from PATH. Keep the complete matching `GodotSharp` bundle beside the pinned executable.
- Use matching `4.7.2.stable.mono` export templates. Do not rename standard/older templates to satisfy the version check.
- Gameplay currently uses GDScript. The Mono toolchain requirement does not authorize a C# rewrite.
- Run gameplay validation with `-- --shop-test` so tests do not change the player's real save.
