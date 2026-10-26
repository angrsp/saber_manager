# Piano di sviluppo: app Saber Manager su BLE

Ultimo aggiornamento: 2026-10-25.
File collegati: `saber_manager-note-app-BLE.md` (analisi del codice di `dev`), `ESP32-bridge-note.md`, `piano-FW-bridge.md` (piano del firmware e **contratto BLE**, sezione 3: questo piano lo richiama senza ripeterlo).

## 1. Punto di partenza

- Repository `saber_manager`, ramo `dev` (`608896e`), working tree pulito e allineato a `origin/dev`: non ci sono modifiche locali non pushate. Storia lineare `c772cbc` → `2b85034` (`main`) → `608896e` (`dev`). Nessun tag. `pubspec.yaml` ha `version: 1.0.0+1`, il valore di default di `flutter create`: nessuna versione è mai stata rilasciata.
- Flutter non è nel PATH: va verificato con `flutter doctor` prima di A1.
- Spada: **Anima NXT**. Hardware del bridge ancora da ordinare: fino al suo arrivo si lavora con il trasporto finto.
- La caratteristica di stato del bridge è nella v1 (`piano-FW-bridge.md`, 3.3).

### 1.1 Fatti verificati che correggono le note

Fonti: protocollo ufficiale `LamaDiLuce/polaris-opencore/Documentation/COMMS-PROTOCOL.md` e `angrsp/py2saber`. Tabella completa in `piano-FW-bridge.md`, 1.1; qui le conseguenze per l'app.

1. **Il salvataggio è `SAVE` → `OK SAVE`, non `S`.** `S` non esiste e i comandi sconosciuti non ricevono risposta: oggi ogni `_saveConfig()` va in timeout (5 s), `setColor` lo ignora e restituisce `true`, e la spada non salva mai. È il bug principale di `dev`, non solo un problema di lentezza (note 2.2.1).
2. **Handshake: `WR?` → `OK, Write Ready`.** Il tentativo a quattro comandi di `_checkSaberReadyMultiple` si sostituisce con questo solo (note 2.1 e 2.3).
3. **Bank 0–7.** `C0=...` è corretto: nessun off-by-one (note 2.2.2).
4. **I colori si possono leggere**: `B?` → `B=x`; `c?`, `f?`, `w?` → 8 righe `cN=r,g,b,w`. Così si risolve "si parte sempre dal bianco" (note 2.2.3). `w?` richiede la build ≥ 1.9.15.
5. **Ogni risposta ha un prefisso che ne indica il contenuto** (`V=`, `S=`, `OK C0=...`, `OK SAVE`, `B=`): le risposte si attribuiscono alla richiesta per prefisso, non per ordine di arrivo.
6. **Tipo di spada**: NXT se la versione inizia con `NXT_` (come py2saber e Tintallë); in aggiunta VID/PID dal servizio di stato del bridge.
7. Timeout di lettura di py2saber: 3 s.

Restano da confermare sulla NXT reale con la fase F0 del firmware (risultati in `piano-FW-bridge.md`, sezione 6): maiuscole/minuscole nelle risposte di `c?/f?/w?`, persistenza dopo `SAVE` senza VBUS, comportamento di `P=`.

## 2. Flusso di lavoro: gitflow

### 2.1 Rami

| Ramo | Da dove nasce | Dove confluisce | Contenuto |
|---|---|---|---|
| `main` | — | — | solo versioni rilasciate, ognuna con un tag `vX.Y.Z` |
| `dev` | — | — | ramo di integrazione (il "develop" di gitflow). Si tiene il nome esistente invece di rinominarlo in `develop`, per non toccare il remoto |
| `feature/<nome>` | `dev` | `dev` (`--no-ff`) | una fase o parte di fase (sezione 3) |
| `release/X.Y.Z` | `dev` | `main` + tag, poi `dev` | numero di versione, correzioni, testi |
| `hotfix/X.Y.Z` | `main` | `main` + tag, poi `dev` | correzione urgente su una versione rilasciata |

Il ramo unico `ble` proposto nelle note (sezione 4, passo 1) è sostituito da un ramo `feature/` per fase.

Regole:
- Nessun commit diretto su `main` né su `dev`.
- Un ramo `feature/` si chiude solo con `flutter analyze` senza errori e `flutter test` verde.
- La versione in `pubspec.yaml` si cambia solo nei rami `release/` e `hotfix/`: `X.Y.Z+N`, con `N` (versionCode Android) che cresce a ogni rilascio.
- Push dei rami `feature/` su `origin` quando servono backup o revisione; `main` e `dev` si pushano dopo ogni chiusura di feature o release.

### 2.2 Inizializzazione (una volta)

git-flow AVH 1.12.3 è già installato. Configurazione per usare `dev` come ramo di sviluppo:

```
cd saber_manager
git config gitflow.branch.master main
git config gitflow.branch.develop dev
git config gitflow.prefix.feature feature/
git config gitflow.prefix.bugfix bugfix/
git config gitflow.prefix.release release/
git config gitflow.prefix.hotfix hotfix/
git config gitflow.prefix.support support/
git config gitflow.prefix.versiontag v
git flow init -d
```

Uso tipico:

```
git flow feature start ble-base          # crea feature/ble-base da dev
# ...commit...
git flow feature finish ble-base         # merge --no-ff in dev, cancella il ramo
git flow release start 0.1.0
git flow release finish 0.1.0            # merge in main, tag v0.1.0, merge in dev
```

Equivalente senza git-flow: `git switch -c feature/ble-base dev` … `git switch dev && git merge --no-ff feature/ble-base`.

### 2.3 Rilasci previsti

| Versione | Quando | Contenuto |
|---|---|---|
| `v0.1.0` | dopo A6, con il bridge `v0.1.0` | connessione BLE, info, lettura e scrittura colori sulla NXT |
| `v0.2.0` | dopo A7 | pairing con bonding (insieme al bridge `v1.0.0`) e pulizia |

Nel ramo `release/0.1.0`: `pubspec.yaml` → `version: 0.1.0+1`, README, prova manuale completa (sezione 4).

## 3. Fasi

Per ogni fase: ramo, lavoro, criterio di uscita. Le fasi A1–A5 non richiedono hardware.

### A0 – Protocollo
Nessun ramo. Dipende dalla fase F0 del firmware (verifiche su PC con la NXT). Fino ad allora i fatti di 1.1 sono l'ipotesi di lavoro; se F0 li smentisce, si corregge il `FakeSaber` (A3) e i test prima di proseguire.

### A1 – Base (`feature/ble-base`)
- `flutter doctor`; `flutter analyze` e `flutter build apk --debug` sullo stato di `dev`, annotando gli errori trovati.
- Inizializzazione gitflow (2.2).
- Eliminare la `HomeScreen` duplicata in `lib/main.dart` e usare `lib/screens/home_screen.dart`.
- `.idea/` in `.gitignore`, poi `git rm -r --cached .idea`.
- Sostituire `test/widget_test.dart` (test del contatore) con uno smoke test dell'app.
- `print` → `debugPrint` (senza emoji).
- Uscita: `flutter analyze` pulito, `flutter test` verde, l'app si avvia.

### A2 – Estrazione dei modelli (`feature/extract-models`)
- Da `lib/services/usb_service.dart`:
  - `lib/models/saber_device.dart`: `SaberDevice` con `id` (`remoteId` BLE come `String`), nome, RSSI, `SaberType`, versione firmware, seriale, `isConnected`.
  - `lib/models/saber_exceptions.dart`: `SaberException`, `NoSaberFoundException`, `ConnectionTimeoutException`, `PermissionDeniedException` (messaggio non più legato all'USB), più `SaberDisconnectedException` e `SaberNotConnectedException` (bridge connesso, spada assente).
- `lib/app_state.dart` importa `models/saber_device.dart`.
- Nessun cambio di comportamento.
- Uscita: build e test verdi.

### A3 – `SaberLink`, trasporto finto e correzioni del protocollo
Si può dividere in due rami: `feature/saber-link` (trasporto, link, test) e poi `feature/protocol-fixes` (servizio del protocollo).

**Trasporto e link**
- `lib/transport/saber_transport.dart`: interfaccia come nelle note (sezione 3): `onData`, `state`, `connect`, `write`, `disconnect`.
- `lib/transport/fake_transport.dart` con un `FakeSaber` che emula la NXT come la variante fake del firmware (F4): `WR?`, `V?` (`V=NXT_fake`), `S?`, `B?`/`B=`, `c?/f?/w?`, `C/F/W<n>=`, `P=`, `SAVE`; silenzio sui comandi sconosciuti; risposte divise in frammenti da 20 byte; righe `#` intercalate; ritardo configurabile per provare i timeout.
- `lib/services/saber_link.dart`:
  - una sola sottoscrizione a `onData` per tutta la connessione;
  - buffer di testo → righe complete (`\n`, ignora `\r`); scarto e log delle righe `#`;
  - una richiesta alla volta (coda);
  - `request(cmd, {match, lines = 1, timeout = 3 s})`: `match` è il prefisso atteso; le righe che non corrispondono vengono scartate e loggate, così una risposta arrivata dopo un timeout non viene attribuita alla richiesta successiva;
  - con `lines > 1` raccoglie N righe corrispondenti (per `c?/f?/w?`);
  - alla disconnessione la richiesta in corso fallisce con `SaberDisconnectedException`.

**Servizio del protocollo** (`lib/services/saber_protocol.dart`)
- `SaberProtocolService(link)` con il link passato dal costruttore. L'API pubblica usata da `colors_screen.dart` resta invariata. Spariscono `setUSBService`, `disconnect` e il `ProxyProvider2` in `lib/main.dart`; `Provider` con `dispose:`.
- `_saveConfig` manda `SAVE` e si aspetta `OK SAVE`.
- Cadenza del salvataggio: `_writeColor` privata, senza salvataggio.
  - `setColor` e `setActiveBank` = scrittura + `SAVE`.
  - `saveColorBank` = 3 colori (+ `B=`) + un `SAVE`.
  - `saveAllColorBanks` e `saveAllColorBanksWithProgress` = 24 colori + `B=` + un `SAVE` (26 operazioni nel progresso, invece di 25 `S`).
- Via le pause fisse (100 ms dopo ogni invio, 300/500 ms fra i bank): il ciclo richiesta/risposta fa già da controllo di flusso. Si rimettono solo se F0 o F6 mostrano che la NXT ne ha bisogno.
- Controllo dell'eco: `C0=...` deve ricevere `OK C0=...`.
- Handshake: un solo `WR?` → `OK, Write Ready`, timeout 3 s, un secondo tentativo.
- Info: `V=` e `S=`; `SaberType.animaNXT` se la versione inizia con `NXT_`.
- `readConfiguration()`: `B?`, poi `c?`, `f?`, `w?` (8 righe ciascuno; prefisso senza distinzione fra maiuscole e minuscole; CSV decimale) → `ColorConfiguration`. Se un comando tace (firmware vecchio), quel campo resta al default ed è marcato "non letto".
- `lib/screens/colors_screen.dart`: carica la configurazione all'apertura, con un indicatore; se la lettura è incompleta, avvisa prima di "Save all banks". `P=0` all'uscita dalla schermata, per spegnere l'anteprima.
- `print` residui → `debugPrint`.

**Test** (`test/`)
- `SaberLink`: riga spezzata su più notifiche; due righe in un pacchetto; righe `#` in mezzo; timeout; risposta arrivata dopo il timeout (non va alla richiesta successiva); disconnessione a metà richiesta; risposta su più righe.
- `SaberProtocolService`: comandi prodotti (`P=`, `C/F/W<n>=`, `B=`); **un solo `SAVE`** per `saveColorBank` e per "salva tutto"; parsing di `B?`, `c?`, `f?`, `w?`; comando che tace.

Uscita: l'app funziona con il trasporto finto, la UI dei colori legge e scrive, test verdi.

### A4 – Trasporto BLE (`feature/ble-transport`)
- `flutter pub add flutter_blue_plus`; controllare la versione installata, **la licenza** (è cambiata nelle versioni recenti) e il `minSdk` richiesto.
- `lib/transport/ble_transport.dart`: connessione, `requestMtu(247)` e priorità di connessione alta su Android, `discoverServices`, ricerca del NUS e del servizio di stato, notifiche su TX, scrittura **con risposta** su RX a pezzi da (MTU − 3), listener sullo stato di connessione che chiude le sottoscrizioni. Errore ATT `0x80` → `SaberNotConnectedException`; `0x81` → nuovo tentativo dopo una breve pausa (contratto: `piano-FW-bridge.md`, 3.2).
- Lettura e notifiche della caratteristica di stato → `Stream<BridgeStatus>` (spada collegata, VID/PID, batteria in mV, byte persi); byte oltre l'ottavo ignorati (`piano-FW-bridge.md`, 3.3). Lettura del DIS per la versione del bridge.
- Scansione in una classe a parte, filtrata per UUID del NUS, 10 s.
- `lib/services/saber_connection_service.dart`: permessi a runtime, Bluetooth spento (richiesta di accensione su Android), scansione, connessione. Se lo stato dice "spada non collegata": mostra "Bridge connesso – accendi la spada", attende la notifica di stato e poi fa l'handshake. Quando la spada si scollega durante l'uso, torna in quello stato invece di disconnettere il bridge.
- Schermate:
  - `connection_screen.dart`: lista dei bridge con RSSI, stati distinti (cerco, bridge trovato, connesso senza spada, pronto), testi BLE al posto di "USB OTG", controllo di `mounted` dopo gli `await`.
  - `home_screen.dart`: icone Bluetooth, batteria del bridge e stato della spada; riquadri "Upload Files", "Sound Effects" e "Firmware Update" disabilitati con la dicitura "non disponibile via BLE".
- Configurazione Android secondo le note (2.6): permessi `BLUETOOTH_SCAN` (`neverForLocation`) e `BLUETOOTH_CONNECT`, `BLUETOOTH`/`BLUETOOTH_ADMIN`/`ACCESS_FINE_LOCATION` con `maxSdkVersion="30"`, `uses-feature android.hardware.bluetooth_le`; `minSdkVersion` compatibile con `flutter_blue_plus`; valutare se togliere `ndkVersion`.
- Uscita: build Android pulita; widget test di `ConnectionScreen` con un servizio finto; con il trasporto finto il flusso completo funziona ancora.

### A5 – Eliminazione dell'USB (`feature/remove-usb`)
- Eliminare `lib/services/usb_service.dart`, la dipendenza `usb_serial`, `android/app/src/main/res/xml/device_filter.xml`.
- Dal manifest: `USB_PERMISSION`, `uses-feature android.hardware.usb.host`, l'`intent-filter` `USB_DEVICE_ATTACHED` con il suo `meta-data`, `VIBRATE`, l'attributo `package=`.
- Togliere `path_provider` se resta inutilizzato.
- Uscita: nessun riferimento all'USB in `lib/` e nel manifest; build e test verdi.

### A6 – Prove su hardware (`feature/hw-tuning` per le correzioni)
1. Con il bridge in variante fake (fase F5 del firmware), senza spada: scansione, connessione, stato, handshake, lettura e scrittura dei colori, disconnessioni.
2. Con il bridge reale e la NXT (fase F6): lettura dei colori reali, scrittura + `SAVE`, verifica dopo lo spegnimento della spada, anteprima, spada spenta e riaccesa durante l'uso.
3. Correzioni di tempi, messaggi e casi limite emersi.
- Uscita: prova manuale completa (sezione 4) superata → **`release/0.1.0`**.

### A7 – Pairing e pulizia (`feature/ble-pairing`, `feature/cleanup`)
- Pairing con bonding quando il firmware ha la fase F9: dialog di pairing Android, gestione del bond perso o rifiutato.
- README (oggi vuoto), i due `.docx` in `docs/`, valutare la rimozione di `linux/`, `macos/`, `windows/`, `web/`.
- iOS facoltativo: `NSBluetoothAlwaysUsageDescription` in `ios/Runner/Info.plist`.
- Uscita: **`release/0.2.0`**.

## 4. Prova manuale prima di ogni rilascio

1. Prima installazione: richiesta dei permessi, Bluetooth spento e poi acceso.
2. Scansione: il bridge compare con RSSI; nessun altro dispositivo in lista.
3. Connessione con spada spenta: messaggio "accendi la spada"; all'accensione l'handshake parte da solo.
4. Info: versione `NXT_...` e seriale corretti.
5. Colori: lettura dei colori reali all'apertura; anteprima; salvataggio di un bank; "salva tutto" in pochi secondi, con un solo `SAVE`; i colori restano dopo aver spento e riacceso la spada.
6. Spada spenta durante l'uso: l'app torna in "bridge connesso, spada assente" senza bloccarsi.
7. Bridge spento o fuori portata: l'app torna alla schermata di connessione con un messaggio chiaro.

## 5. Sincronizzazione con il firmware

| Quando | Firmware (`piano-FW-bridge.md`) | App |
|---|---|---|
| Subito, senza hardware | F0, F1–F4 | A1–A5 (A3 conferma i fatti con F0) |
| Contratto fissato (fine F3) | UUID di stato definitivi | A4 legge il servizio di stato |
| Arriva la XIAO | F5 (variante fake) | A6, prima parte |
| Arrivano OTG e LiPo | F6–F7, `v0.1.0` | A6 con la NXT, poi `v0.1.0` |
| Prima della versione stabile | F8–F9, `v1.0.0` | A7, `v0.2.0` |
