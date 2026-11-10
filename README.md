# Saber Manager

Saber Manager is a Flutter app for managing lightsabers running the OpenCore firmware (Anima NXT and EVO boards). The phone talks over Bluetooth Low Energy to the **SaberBridge**, a small BLE dongle plugged into the saber's USB port, so blade colors and saber info can be read and changed without a cable.

Development follows [`piano-app-BLE.md`](piano-app-BLE.md) (in Italian); the bridge firmware and the BLE contract are described in `../saber_bridge/piano-FW-bridge.md` (section 3).

## Features

- Scan for and connect to the SaberBridge over BLE, with bridge status (saber attached, battery, firmware version).
- Saber wait: if the saber is off, the app waits for it to power on and performs the handshake automatically.
- Saber info: board type, firmware version, serial number.
- Colors: read, edit with live preview, save to the saber, export to and import from a file.

File uploads, sounds and firmware updates go through the saber's USB mass storage and are not available over BLE.

Platforms: Android 7 or later (API 24, Flutter's minimum). iOS is configured but not tested yet.

## Project structure

```
lib/
├── main.dart              # Providers and choice between real and fake bridge
├── models/                # SaberDevice, BridgeStatus, colors, exceptions
├── transport/             # Bytes to and from the bridge
│   ├── saber_transport.dart   # SaberTransport and BridgeTransport interfaces
│   ├── ble_transport.dart     # flutter_reactive_ble: NUS, status, MTU, ATT codes
│   ├── bridge_scanner.dart    # Bridge scanning
│   └── fake_transport.dart    # Fake bridge and saber (FakeSaber)
├── services/
│   ├── saber_link.dart              # Text lines, prefix-matched requests and responses
│   ├── saber_protocol.dart          # OpenCore commands (WR?, V?, c?, SAVE, ...)
│   ├── saber_connection_service.dart # App-wide connection state
│   └── bluetooth_access.dart        # Permissions and Bluetooth enabling
├── screens/               # Home, connection, colors
└── widgets/
```

## Development

Requirements: Flutter 3.47 (stable), JDK 17, Android SDK 37.

```sh
flutter pub get
flutter analyze
flutter test
flutter run                                  # with the real SaberBridge
flutter run --dart-define=FAKE_BRIDGE=true   # with a fake bridge and saber, works on the emulator too
```

Android build notes:
- AGP 9.2.1 with Gradle 9.4.1: `reactive_ble_mobile` asks for `compileSdk 37`, which AGP 9.1 (the version in the Flutter 3.47 template) only supports up to 36. For the same reason the app compiles with `compileSdk 37`; `targetSdk` stays at Flutter's default.
- Kotlin built into AGP (`android.builtInKotlin=true`): the app no longer applies the `kotlin-android` plugin. The Kotlin plugin declared in `settings.gradle.kts` is on 2.4.x because `flutter_reactive_ble` uses `kotlin-stdlib` 2.4.
- Location permission is declared only up to Android 11, where BLE scanning needs it; from Android 12 on, `BLUETOOTH_SCAN` and `BLUETOOTH_CONNECT` are enough.

## Branches

Gitflow: `main` for releases, `dev` for development, `feature/<name>` for each phase of the plan.
