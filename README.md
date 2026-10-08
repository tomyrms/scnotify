# SnapNotify (diagnostic build)

Sideload-only helper dylib for a personal Snapchat install:

- keeps the process alive in background (silent audio loop, same trick as WhatsApp mods),
- swizzles likely message/notification receive paths (runtime class scan, no substrate),
- mirrors hits to **local notifications** (`UNUserNotificationCenter`) and a log file,
- log is written to the app's Documents folder (`snapnotify.log`; enable "File Sharing" when signing to read it from the Files app).

Built via GitHub Actions (macOS runner + Theos). The dylib is injected into the IPA with an added `LC_LOAD_DYLIB` (`@loader_path/SnapNotify.dylib`).

Diagnostic intent: identify which runtime selector actually fires when a snap/chat arrives while backgrounded, then narrow v2 to exactly that hook.
