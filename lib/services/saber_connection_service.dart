import '../models/saber_device.dart';
import 'saber_link.dart';
import 'saber_protocol.dart';

// Scansione, connessione, handshake e info della spada.
// Per ora c'è solo il trasporto finto; scansione BLE e permessi arrivano con A4.
class SaberConnectionService {
  SaberConnectionService(this._link, this._protocol);

  static const String fakeDeviceId = 'fake';

  final SaberLink _link;
  final SaberProtocolService _protocol;

  bool get isConnected => _link.isConnected;

  Future<List<SaberDevice>> scan() async {
    return [
      SaberDevice(id: fakeDeviceId, name: 'Fake Saber (demo)', type: SaberType.unknown),
    ];
  }

  // Connette, fa l'handshake e legge versione e seriale
  Future<SaberDevice> connect(SaberDevice device) async {
    await _link.connect(device.id);
    try {
      await _protocol.handshake();
      final version = await _protocol.getFirmwareVersion();
      final serial = await _protocol.getSerialNumber();
      return device.copyWith(
        type: SaberProtocolService.typeFromVersion(version),
        firmwareVersion: version,
        serialNumber: serial,
        isConnected: true,
      );
    } catch (_) {
      await _link.disconnect();
      rethrow;
    }
  }

  Future<void> disconnect() => _link.disconnect();
}
