import 'saber_device.dart';

// Stato del bridge dalla caratteristica 7A6F0002 (contratto BLE v1, piano-FW-bridge.md 3.3):
// 8 byte little-endian; i byte oltre l'ottavo sono estensioni future e si ignorano.
class BridgeStatus {
  const BridgeStatus({
    this.formatVersion = 1,
    required this.saberConnected,
    this.bytesLost = false,
    this.batteryLow = false,
    this.vid = 0,
    this.pid = 0,
    this.batteryMv = 0,
  });

  static const int length = 8;

  final int formatVersion;
  final bool saberConnected;
  // Byte persi dall'ultima lettura (si azzera quando lo stato arriva all'app)
  final bool bytesLost;
  final bool batteryLow;
  final int vid;
  final int pid;
  // 0 = non misurata
  final int batteryMv;

  // Tipo di spada dai descrittori USB (piano-FW-bridge.md 4, F2)
  SaberType get saberType {
    if (vid == 0x0483 && pid == 0x5740) return SaberType.animaNXT;
    if (vid == 0x16C0 && pid == 0x0483) return SaberType.animaEVO;
    return SaberType.unknown;
  }

  // null se il payload è troppo corto
  static BridgeStatus? parse(List<int> data) {
    if (data.length < length) return null;
    final flags = data[1];
    return BridgeStatus(
      formatVersion: data[0],
      saberConnected: flags & 0x01 != 0,
      bytesLost: flags & 0x02 != 0,
      batteryLow: flags & 0x04 != 0,
      vid: data[2] | (data[3] << 8),
      pid: data[4] | (data[5] << 8),
      batteryMv: data[6] | (data[7] << 8),
    );
  }

  List<int> toBytes() {
    final flags = (saberConnected ? 0x01 : 0) | (bytesLost ? 0x02 : 0) | (batteryLow ? 0x04 : 0);
    return [
      formatVersion, flags,
      vid & 0xFF, vid >> 8,
      pid & 0xFF, pid >> 8,
      batteryMv & 0xFF, batteryMv >> 8,
    ];
  }

  @override
  bool operator ==(Object other) =>
      other is BridgeStatus &&
      other.formatVersion == formatVersion &&
      other.saberConnected == saberConnected &&
      other.bytesLost == bytesLost &&
      other.batteryLow == batteryLow &&
      other.vid == vid &&
      other.pid == pid &&
      other.batteryMv == batteryMv;

  @override
  int get hashCode => Object.hash(formatVersion, saberConnected, bytesLost, batteryLow, vid, pid, batteryMv);

  @override
  String toString() =>
      'BridgeStatus(saber: $saberConnected, lost: $bytesLost, low: $batteryLow, '
      'vid: 0x${vid.toRadixString(16)}, pid: 0x${pid.toRadixString(16)}, ${batteryMv}mV)';
}
