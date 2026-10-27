import 'package:flutter_test/flutter_test.dart';

import 'package:saber_manager/models/bridge_status.dart';
import 'package:saber_manager/models/saber_device.dart';

void main() {
  test('payload di 8 byte little-endian', () {
    final status = BridgeStatus.parse([1, 0x05, 0x83, 0x04, 0x40, 0x57, 0x3C, 0x0F])!;

    expect(status.formatVersion, 1);
    expect(status.saberConnected, isTrue);
    expect(status.bytesLost, isFalse);
    expect(status.batteryLow, isTrue);
    expect(status.vid, 0x0483);
    expect(status.pid, 0x5740);
    expect(status.batteryMv, 3900);
    expect(status.saberType, SaberType.animaNXT);
  });

  test('spada non collegata', () {
    final status = BridgeStatus.parse([1, 0x02, 0, 0, 0, 0, 0, 0])!;

    expect(status.saberConnected, isFalse);
    expect(status.bytesLost, isTrue);
    expect(status.saberType, SaberType.unknown);
  });

  test('byte oltre l\'ottavo ignorati, payload corto rifiutato', () {
    expect(BridgeStatus.parse([1, 1, 0xC0, 0x16, 0x83, 0x04, 0, 0, 99, 99])!.saberType, SaberType.animaEVO);
    expect(BridgeStatus.parse([1, 1, 0, 0, 0, 0, 0]), isNull);
  });

  test('toBytes e parse sono simmetrici', () {
    const status = BridgeStatus(saberConnected: true, batteryLow: true, vid: 0x0483, pid: 0x5740, batteryMv: 3456);
    expect(BridgeStatus.parse(status.toBytes()), status);
  });
}
