# Saber Manager: stato dello sviluppo

Aggiornato al 2026-11-01. Ramo `dev` a `0ea9837`, allineato a `origin/dev`.
Piano di riferimento: [`piano-app-BLE.md`](piano-app-BLE.md).

## In breve

L'app è passata dall'USB al BLE, attraverso il SaberBridge.

| Fase | Contenuto | Stato |
|---|---|---|
| A0 | Protocollo verificato sulla NXT reale (fase F0 del firmware) | ✅ |
| A1 | Base: toolchain, gitflow, pulizia | ✅ |
| A2 | Estrazione dei modelli | ✅ |
| A3 | `SaberLink`, trasporto finto, correzioni del protocollo | ✅ |
| A4 | Trasporto BLE e nuove schermate | ✅ (manca la prova sul bridge vero) |
| A5 | Eliminazione dell'USB | ✅ |
| A6 | Prove su hardware | ⏳ in attesa della XIAO |
| A7 | Pulizia ✅ · pairing ⏳ in attesa della fase F9 del firmware | metà |

Lo stato attuale:
- `flutter analyze` non trova problemi;
- passano 78 test;
- l'APK di debug si compila;
- sull'emulatore l'app funziona, sia con il BLE (permessi e scansione) sia con il bridge finto (`--dart-define=FAKE_BRIDGE=true`).

## Sviluppi fatti

### A1 – Base (`6ba0d82`, `7529edd`)
- Flutter 3.47.8 installato in `C:\dev\flutter`, con JDK 17; build Android aggiornata (Gradle 8.14.3, AGP 8.13.0).
- Gitflow: `main` per i rilasci, `dev` per lo sviluppo, `feature/<nome>` per i lavori.
- Eliminata la `HomeScreen` duplicata in `main.dart`, `.idea/` tolta dal repository, `print` → `debugPrint`, smoke test al posto del test del contatore.

### A2 – Modelli (`ee6c725`)
- `SaberDevice` ed eccezioni spostate in `lib/models/`.
- Aggiunte `SaberDisconnectedException` e `SaberNotConnectedException`.

### A3 – Link, trasporto finto e protocollo (`1aeeea7`, `0d8cce8`)
- **`SaberTransport`**: l'interfaccia dei byte da e verso il bridge.
- **`FakeTransport`** con `FakeSaber`: emula la NXT come l'emulatore del firmware, comprese le risposte a frammenti e le righe `#`.
- **`SaberLink`**:
  - ricompone le righe;
  - manda una richiesta alla volta;
  - attribuisce le risposte per prefisso, così una risposta arrivata in ritardo non va alla richiesta successiva;
  - gestisce le risposte su più righe.
- **Correzioni del protocollo**:
  - il salvataggio è `SAVE` → `OK SAVE`, non `S`: prima la spada non salvava mai;
  - "Salva tutto" manda un solo `SAVE`;
  - via le pause fisse;
  - controllo dell'eco;
  - handshake con `WR?`.
- **Lettura dei colori reali**: `B?`, `c?`, `f?`, `w?` all'apertura della schermata colori. Prima si partiva sempre dal bianco.

### A4 – Trasporto BLE (`0426eed`)
- **Libreria**: `flutter_reactive_ble` 5.6.0 (BSD-3). `flutter_blue_plus` 2.x è stato scartato: per uso commerciale serve una licenza a pagamento e manda dati di telemetria durante la build.
- **`BleTransport`**:
  - MTU 247;
  - scrittura con risposta, a pezzi da MTU − 3;
  - codici ATT: `0x80` = spada non collegata; `0x81` = buffer pieno, si riprova;
  - stato del bridge e versione del firmware.
- **Scansione** filtrata per il servizio UART del bridge, 10 s, ordinata per segnale.
- **Permessi e Bluetooth**:
  - da Android 12 i permessi Bluetooth, senza localizzazione; fino ad Android 11 la localizzazione;
  - richiesta di accendere il Bluetooth;
  - pulsante per le impostazioni se il permesso è negato per sempre.
- **`SaberConnectionService`** tiene lo stato della connessione per tutta l'app, al posto di `AppState`:
  - attende la spada e fa l'handshake da solo quando si accende;
  - gestisce la spada scollegata durante l'uso e la perdita del bridge.
- **Schermate**:
  - home con bridge, batteria e icone Bluetooth;
  - nella connessione, stati separati;
  - la schermata colori torna alla home se la spada si scollega.
- **Problema risolto sull'emulatore**: subito dopo la concessione dei permessi la libreria restituiva ancora lo stato "non autorizzato" calcolato all'avvio.

### A5 – Eliminazione dell'USB (`577adfc`)
- Tolti `usb_service.dart`, la dipendenza `usb_serial`, `device_filter.xml` e le voci USB del manifest.
- La localizzazione che `flutter_reactive_ble` dichiara senza limiti è ora limitata ad Android 11.

### A7 – Pulizia (`0ea9837`)
- README scritto.
- Eliminati i due `.docx` superati e le piattaforme non supportate dal BLE: `linux/`, `macos/`, `windows/`, `web/`.
- Aggiunto il permesso Bluetooth per iOS.
- `.gitignore` sostituito con quello standard di un'app Flutter; `pubspec.lock` ora è versionato.

## Prossimi passi

### 1. A6 – Prove su hardware
**Prima parte**, appena arriva la XIAO con il firmware del bridge in variante fake (fase F5), senza spada:
- scansione, connessione, stato del bridge, handshake, lettura e scrittura dei colori, disconnessioni;
- **da verificare in particolare**:
  - che i codici ATT `0x80`/`0x81` si leggano davvero dal messaggio d'errore Android (`status 128`);
  - l'MTU negoziato e la scrittura a pezzi;
  - la cadenza delle notifiche di stato;
  - la richiesta di accensione del Bluetooth.

**Seconda parte**, con OTG, LiPo e la NXT (fasi F6–F7):
- colori reali, scrittura + `SAVE`, verifica dopo lo spegnimento della spada, anteprima, spada spenta e riaccesa durante l'uso.

**Su un telefono con Android 11 o precedente**: il percorso con la localizzazione.

**Correzioni** dei problemi emersi in `feature/hw-tuning`.

### 2. Rilascio `v0.1.0`
- Insieme al bridge `v0.1.0`.
- Nel ramo `release/0.1.0`: `version: 0.1.0+1` nel `pubspec.yaml` e la prova manuale completa (sezione 4 del piano).

### 3. A7 – Pairing (`feature/ble-pairing`)
- Quando il firmware ha la fase F9: bonding, dialog di pairing di Android, bond perso o rifiutato.
- Poi il rilascio `v0.2.0`, insieme al bridge `v1.0.0`.

### Si può fare anche subito
- **Passaggio ad AGP 9**: Flutter avvisa a ogni build che presto non supporterà più AGP 8.13. Il passaggio permette di togliere il compileSdk forzato a 36 per `reactive_ble_mobile`.
- **iOS** (facoltativo): serve un Mac. L'`IPHONEOS_DEPLOYMENT_TARGET` è ancora 12.0, mentre il modello di Flutter 3.47 usa 15.0.
