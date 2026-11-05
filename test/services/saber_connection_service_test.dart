import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:saber_manager/models/saber_device.dart';
import 'package:saber_manager/services/bluetooth_access.dart';
import 'package:saber_manager/services/saber_connection_service.dart';
import 'package:saber_manager/services/saber_link.dart';
import 'package:saber_manager/services/saber_protocol.dart';
import 'package:saber_manager/transport/fake_transport.dart';

class _FixedBluetooth implements BluetoothAccess {
  _FixedBluetooth(this.readiness);
  final BluetoothReadiness readiness;

  @override
  Future<BluetoothReadiness> ensureReady() async => readiness;

  @override
  Future<void> openSettings() async {}
}

// Richiesta dei permessi ancora aperta finché il test non completa [answer]
class _PendingBluetooth implements BluetoothAccess {
  final answer = Completer<BluetoothReadiness>();

  @override
  Future<BluetoothReadiness> ensureReady() => answer.future;

  @override
  Future<void> openSettings() async {}
}

void main() {
  late FakeTransport transport;
  late SaberLink link;
  late SaberConnectionService service;

  SaberConnectionService build({BluetoothAccess? bluetooth}) => SaberConnectionService(
        transport: transport,
        link: link,
        protocol: SaberProtocolService(link, timeout: const Duration(milliseconds: 50)),
        scanner: FakeScanner(),
        bluetooth: bluetooth ?? AlwaysReadyBluetooth(),
      );

  // Attende che il servizio arrivi in [phase]
  Future<void> reach(ConnectionPhase phase) async {
    if (service.phase == phase) return;
    final reached = Completer<void>();
    void listener() {
      if (service.phase == phase && !reached.isCompleted) reached.complete();
    }

    service.addListener(listener);
    try {
      await reached.future.timeout(const Duration(seconds: 2));
    } finally {
      service.removeListener(listener);
    }
  }

  Future<void> connectBridge() async {
    await service.scan();
    expect(await service.connect(service.devices.single), isTrue);
  }

  setUp(() {
    transport = FakeTransport();
    link = SaberLink(transport);
    service = build();
  });

  tearDown(() {
    service.dispose();
    link.dispose();
  });

  test('scansione: trova il bridge e torna in idle', () async {
    await service.scan();

    expect(service.devices.single.id, FakeScanner.deviceId);
    expect(service.phase, ConnectionPhase.idle);
    expect(service.error, isNull);
  });

  test('Bluetooth spento: nessuna scansione e messaggio', () async {
    service.dispose();
    service = build(bluetooth: _FixedBluetooth(BluetoothReadiness.poweredOff));

    await service.scan();

    expect(service.devices, isEmpty);
    expect(service.readiness, BluetoothReadiness.poweredOff);
    expect(service.error, contains('Turn on Bluetooth'));
    expect(service.phase, ConnectionPhase.idle);
  });

  test('richiesta dei permessi: già in scanning; fermata in quel momento, nessuna scansione', () async {
    final bluetooth = _PendingBluetooth();
    service.dispose();
    service = build(bluetooth: bluetooth);

    final scan = service.scan();
    expect(service.phase, ConnectionPhase.scanning);

    await service.stopScan();
    expect(service.phase, ConnectionPhase.idle);
    bluetooth.answer.complete(BluetoothReadiness.ready);
    await scan;

    expect(service.phase, ConnectionPhase.idle);
    expect(service.devices, isEmpty);
  });

  test('spada presente: handshake e info subito', () async {
    await connectBridge();
    await reach(ConnectionPhase.ready);

    expect(transport.commands, ['WR?', 'V?', 'S?']);
    final saber = service.saber!;
    expect(saber.type, SaberType.animaNXT);
    expect(saber.firmwareVersion, 'NXT_fake');
    expect(saber.serialNumber, FakeSaber.serial);
    expect(service.isConnected, isTrue);
    expect(service.bridgeFirmware, FakeTransport.firmware);
    expect(service.bridgeStatus!.batteryMv, 3900);
  });

  test('spada assente: attesa, poi handshake quando si accende', () async {
    transport.saberPresent = false;
    await connectBridge();

    expect(service.phase, ConnectionPhase.waitingForSaber);
    expect(service.statusMessage, contains('turn on the saber'));
    expect(transport.commands, isEmpty);

    transport.saberPresent = true;
    await reach(ConnectionPhase.ready);
    expect(transport.commands, ['WR?', 'V?', 'S?']);
  });

  test('spada scollegata durante l\'uso: il bridge resta connesso', () async {
    await connectBridge();
    await reach(ConnectionPhase.ready);

    transport.saberPresent = false;
    await reach(ConnectionPhase.waitingForSaber);
    expect(service.saber, isNull);
    expect(service.isBridgeConnected, isTrue);
    expect(link.isConnected, isTrue);

    transport.saberPresent = true;
    await reach(ConnectionPhase.ready);
  });

  test('handshake fallito: errore, poi nuovo tentativo', () async {
    transport.mutedCommands.add('WR?');
    await connectBridge();
    await reach(ConnectionPhase.waitingForSaber);

    expect(service.error, 'Saber not responding');
    expect(service.isBridgeConnected, isTrue);

    transport.mutedCommands.clear();
    await service.retryHandshake();
    expect(service.phase, ConnectionPhase.ready);
    expect(service.error, isNull);
  });

  test('versione non letta: tipo dal VID/PID del bridge', () async {
    transport.mutedCommands.add('V?');
    await connectBridge();
    await reach(ConnectionPhase.ready);

    expect(service.saber!.firmwareVersion, isNull);
    expect(service.saber!.type, SaberType.animaNXT);
  });

  test('bridge perso: idle con messaggio', () async {
    await connectBridge();
    await reach(ConnectionPhase.ready);

    transport.simulateDisconnect();
    await reach(ConnectionPhase.idle);
    expect(service.error, 'Bridge connection lost');
    expect(service.saber, isNull);
    expect(service.bridge, isNull);
  });

  test('disconnessione chiesta: idle senza errore', () async {
    await connectBridge();
    await reach(ConnectionPhase.ready);

    await service.disconnect();
    expect(service.phase, ConnectionPhase.idle);
    expect(service.error, isNull);
    expect(link.isConnected, isFalse);
  });
}
