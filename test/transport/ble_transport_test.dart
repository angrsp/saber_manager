import 'package:flutter_test/flutter_test.dart';

import 'package:saber_manager/transport/ble_transport.dart';

void main() {
  group('codice ATT dagli errori di scrittura', () {
    test('messaggio di RxAndroidBle in GenericFailure', () {
      final error = Exception(
        'GenericFailure<WriteCharacteristicFailure>(code: WriteCharacteristicFailure.unknown, message: '
        '"GATT exception from MAC address XX:XX:XX:XX:XX:XX, with type BleGattOperation{description=\'CHARACTERISTIC_WRITE\'}, '
        'status 128 (UNKNOWN). (Look up status 0x80 here https://cs.android.com/...)")',
      );
      expect(BleTransport.attStatusOf(error), BleTransport.attSaberNotConnected);
    });

    test('buffer pieno', () {
      expect(BleTransport.attStatusOf(Exception('... status 129 (UNKNOWN) ...')), BleTransport.attBufferFull);
    });

    test('formato esadecimale', () {
      expect(BleTransport.attStatusOf('write failed, status: 0x81'), BleTransport.attBufferFull);
    });

    test('nessun codice', () {
      expect(BleTransport.attStatusOf(Exception('Writechar timed-out')), isNull);
    });
  });
}
