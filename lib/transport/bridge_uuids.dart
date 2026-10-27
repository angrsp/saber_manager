import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

// UUID del contratto BLE v1 (piano-FW-bridge.md, sezione 3)
class BridgeUuids {
  // Nordic UART Service: RX = scrittura app → spada, TX = notifiche spada → app
  static final Uuid nus = Uuid.parse('6E400001-B5A3-F393-E0A9-E50E24DCCA9E');
  static final Uuid nusRx = Uuid.parse('6E400002-B5A3-F393-E0A9-E50E24DCCA9E');
  static final Uuid nusTx = Uuid.parse('6E400003-B5A3-F393-E0A9-E50E24DCCA9E');

  // Servizio di stato del bridge
  static final Uuid status = Uuid.parse('7A6F0001-3C1D-4B8E-9F2A-6D5E4C3B2A10');
  static final Uuid statusChar = Uuid.parse('7A6F0002-3C1D-4B8E-9F2A-6D5E4C3B2A10');

  // Device Information Service: Firmware Revision String
  static final Uuid dis = Uuid.parse('180A');
  static final Uuid disFirmware = Uuid.parse('2A26');
}
