# PlayerWhile

Cross-platform character library and GitHub updater for Windows, Android, iOS, macOS and Linux.

The app has a floating GitHub updater panel. Paste a public GitHub repository or folder link, load the character list, then install or update any character with one button.

Supported discovery conventions include `characters/`, `character/`, `players/`, `sheets/`, `profiles/`, `персонажи/`, folders containing `character.json`, `sheet.json`, `profile.json` and standalone JSON, YAML, TOML, Markdown or text character files.

Downloaded character data is stored locally in the application's documents directory. Source repository, branch, path and update time are kept in a local index so the same character can be refreshed later.

Desktop builds open as an always-on-top utility window. Mobile builds use the same updater as a floating sheet inside the app. iOS does not permit arbitrary system-wide floating windows over other apps.

Builds are published by GitHub Actions to the `latest` GitHub Release. The iOS artifact is unsigned and must be signed with an Apple certificate before normal installation on a physical iPhone.
