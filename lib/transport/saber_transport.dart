import 'dart:typed_data';
import '../models/bridge_status.dart';

enum TransportState {
  disconnected,
  connecting,
  connected,
}

// Trasporto dei byte fra app e spada (BLE, oppure finto per sviluppo e test).
// Non interpreta i dati: righe e protocollo stanno in SaberLink.
abstract class SaberTransport {
  // Byte in arrivo dalla spada, in frammenti di lunghezza qualsiasi
  Stream<Uint8List> get onData;

  Stream<TransportState> get state;
  TransportState get currentState;

  Future<void> connect(String deviceId);

  // Fallisce con SaberNotConnectedException se il bridge è connesso ma la spada no
  Future<void> write(Uint8List data);

  Future<void> disconnect();

  void dispose();
}

// Trasporto attraverso il bridge BLE: oltre ai byte espone lo stato del bridge
abstract class BridgeTransport implements SaberTransport {
  // Aggiornamenti dalla caratteristica di stato (a ogni cambio e a ogni lettura)
  Stream<BridgeStatus> get bridgeStatus;

  // Ultimo stato noto; null se il bridge non ha il servizio di stato o non è connesso
  BridgeStatus? get currentBridgeStatus;

  // Versione firmware del bridge dal DIS (0x2A26), se letta
  String? get bridgeFirmware;
}
