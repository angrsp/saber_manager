import 'package:flutter_test/flutter_test.dart';

import 'package:saber_manager/models/saber_device.dart';
import 'package:saber_manager/models/saber_exceptions.dart';
import 'package:saber_manager/services/saber_connection_service.dart';
import 'package:saber_manager/services/saber_link.dart';
import 'package:saber_manager/services/saber_protocol.dart';
import 'package:saber_manager/transport/fake_transport.dart';

void main() {
  late FakeTransport transport;
  late SaberLink link;
  late SaberConnectionService service;

  setUp(() {
    transport = FakeTransport();
    link = SaberLink(transport);
    service = SaberConnectionService(
      link,
      SaberProtocolService(link, timeout: const Duration(milliseconds: 50)),
    );
  });

  tearDown(() => link.dispose());

  test('scansione e connessione alla spada finta', () async {
    final devices = await service.scan();
    expect(devices.single.id, SaberConnectionService.fakeDeviceId);

    final saber = await service.connect(devices.single);

    expect(transport.commands, ['WR?', 'V?', 'S?']);
    expect(saber.isConnected, isTrue);
    expect(saber.type, SaberType.animaNXT);
    expect(saber.firmwareVersion, 'NXT_fake');
    expect(saber.serialNumber, FakeSaber.serial);
    expect(service.isConnected, isTrue);

    await service.disconnect();
    expect(service.isConnected, isFalse);
  });

  test('handshake fallito: il link viene disconnesso', () async {
    transport.mutedCommands.add('WR?');
    final devices = await service.scan();

    await expectLater(service.connect(devices.single), throwsA(isA<SaberException>()));
    expect(service.isConnected, isFalse);
  });
}
