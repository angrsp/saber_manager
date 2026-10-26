import 'package:flutter_test/flutter_test.dart';

import 'package:saber_manager/models/saber_device.dart';

void main() {
  test('copyWith aggiorna solo i campi passati', () {
    final saber = SaberDevice(id: 'AA:BB', name: 'Bridge', rssi: -60, type: SaberType.unknown);

    final connected = saber.copyWith(
      isConnected: true,
      type: SaberType.animaNXT,
      firmwareVersion: 'NXT_1.9.15',
    );

    expect(connected.id, 'AA:BB');
    expect(connected.name, 'Bridge');
    expect(connected.rssi, -60);
    expect(connected.type, SaberType.animaNXT);
    expect(connected.firmwareVersion, 'NXT_1.9.15');
    expect(connected.serialNumber, isNull);
    expect(connected.isConnected, isTrue);
    expect(saber.isConnected, isFalse);
  });
}
