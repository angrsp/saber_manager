import 'dart:typed_data';

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
