# Agent Instructions

This project is managed by Dartloom.

1. Read `.dartloom/project.yaml` before changing infrastructure.
2. Dartloom packages are ordinary Dart dependencies. Feature code depends on
   contracts; application composition in `lib/app` creates implementations.
3. Do not add generated capability registries, runtime service locators, or
   adapter implementations to Dartloom-owned files.
4. Business code belongs in `lib/features`; shared app glue belongs in `lib/app`.
5. Dartloom owns only the selected project metadata and package sources. The
   application owns `lib/app`, `lib/features`, platform glue, and translations.

<!-- dartloom:begin -->
## Dartloom packages

Selected platforms: Android, iOS, Windows, macOS, Linux, Web

Selected Dartloom contracts and implementations are direct dependencies in
`pubspec.yaml`. Platform-specific implementations are selected through
conditional application composition in `lib/app`.
<!-- dartloom:end -->

## Capability platform support

Enabled project targets: android, ios, windows, macos, linux, web.

Implementations are platform-aware. Treat a capability as optional when the
current target cannot provide it, and use conditional application composition
instead of importing native-only adapters into Web code.

| Capability instance | Contract package | Implementation | Project targets |
| --- | --- | --- | --- |
| settings | `dartloom_settings` | shared preferences / secure storage | all targets |
| storage | `dartloom_storage` | file / IndexedDB | native / Web |
| logging | `dartloom_logging` | logger | all targets |
| pairing | `dartloom_pairing` | relay / LAN | all targets |
| messaging | `dartloom_messaging` | relay / LAN | all targets |
| singleton | `dartloom_singleton` | socket adapter | desktop only |
| resident | `dartloom_resident` | tray adapter | desktop only |


Before finishing, run `dart format .`, `flutter analyze`, and `flutter test`.
