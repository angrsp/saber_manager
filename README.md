# Saber Manager

App Flutter per gestire le spade laser con firmware OpenCore (Anima NXT ed EVO) attraverso il **SaberBridge**, un dongle BLE collegato alla spada via USB.

Lo sviluppo segue [`piano-app-BLE.md`](piano-app-BLE.md); il firmware del bridge e il contratto BLE sono in `../saber_bridge/piano-FW-bridge.md` (sezione 3).

## Cosa fa

- Scansione e connessione al SaberBridge via BLE, con stato del bridge (spada collegata, batteria, versione del firmware).
- Attesa della spada: se è spenta, l'app aspetta che si accenda e fa l'handshake da sola.
- Info della spada: tipo, versione del firmware, numero di serie.
- Colori: lettura, modifica con anteprima, salvataggio sulla spada, esportazione e importazione su file.

Caricamento di file, suoni e aggiornamento del firmware passano dal disco USB della spada e non sono disponibili via BLE.

Piattaforme: Android 7 o successivo (API 24, il minimo di Flutter). iOS è configurato ma non ancora provato.

## Struttura

```
lib/
├── main.dart              # Provider e scelta tra bridge vero e finto
├── models/                # SaberDevice, BridgeStatus, colori, eccezioni
├── transport/             # Byte da e verso il bridge
│   ├── saber_transport.dart   # Interfacce SaberTransport e BridgeTransport
│   ├── ble_transport.dart     # flutter_reactive_ble: NUS, stato, MTU, codici ATT
│   ├── bridge_scanner.dart    # Scansione dei bridge
│   └── fake_transport.dart    # Bridge e spada finti (FakeSaber)
├── services/
│   ├── saber_link.dart              # Righe di testo, richieste e risposte per prefisso
│   ├── saber_protocol.dart          # Comandi OpenCore (WR?, V?, c?, SAVE, ...)
│   ├── saber_connection_service.dart # Stato della connessione per tutta l'app
│   └── bluetooth_access.dart        # Permessi e accensione del Bluetooth
├── screens/               # Home, connessione, colori
└── widgets/
```

## Sviluppo

Requisiti: Flutter 3.47 (stable), JDK 17, Android SDK 36.

```sh
flutter pub get
flutter analyze
flutter test
flutter run                                  # con il SaberBridge vero
flutter run --dart-define=FAKE_BRIDGE=true   # con bridge e spada finti, anche sull'emulatore
```

Note sulla build Android:
- `reactive_ble_mobile` chiede `compileSdk 37`, che AGP 8.13 non trova: `android/build.gradle` lo forza a 36 fino al passaggio ad AGP 9.
- Il plugin Kotlin è alla 2.4.x perché `flutter_reactive_ble` usa `kotlin-stdlib` 2.4.
- La localizzazione è dichiarata solo fino ad Android 11, dove serve alla scansione BLE; da Android 12 bastano `BLUETOOTH_SCAN` e `BLUETOOTH_CONNECT`.

## Rami

Gitflow: `main` per i rilasci, `dev` per lo sviluppo, `feature/<nome>` per ogni fase del piano.
