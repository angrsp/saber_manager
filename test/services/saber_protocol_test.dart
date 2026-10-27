import 'package:flutter_test/flutter_test.dart';

import 'package:saber_manager/models/color_config.dart';
import 'package:saber_manager/models/saber_device.dart';
import 'package:saber_manager/models/saber_exceptions.dart';
import 'package:saber_manager/services/saber_link.dart';
import 'package:saber_manager/services/saber_protocol.dart';
import 'package:saber_manager/transport/fake_transport.dart';

import '../helpers/manual_transport.dart';

const short = Duration(milliseconds: 50);
const red = RGBWColor(red: 255, green: 0, blue: 0, white: 0);
const blue = RGBWColor(red: 0, green: 0, blue: 255, white: 10);

void main() {
  late FakeTransport transport;
  late SaberLink link;
  late SaberProtocolService protocol;

  setUp(() async {
    transport = FakeTransport(logLineEvery: 3);
    link = SaberLink(transport);
    protocol = SaberProtocolService(link, timeout: short);
    await link.connect('fake');
  });

  tearDown(() => link.dispose());

  int saves() => transport.commands.where((c) => c == 'SAVE').length;

  group('connessione', () {
    test('handshake con WR?', () async {
      await protocol.handshake();
      expect(transport.commands, ['WR?']);
    });

    test('handshake: secondo tentativo dopo un timeout', () async {
      final manual = ManualTransport();
      final manualLink = SaberLink(manual);
      var attempts = 0;
      manual.onCommand = (_) {
        if (++attempts == 2) manual.push('OK, Write Ready\n');
      };

      await SaberProtocolService(manualLink, timeout: short).handshake();
      expect(manual.written, ['WR?\n', 'WR?\n']);
      manualLink.dispose();
    });

    test('handshake fallito dopo due tentativi', () async {
      transport.mutedCommands.add('WR?');

      await expectLater(protocol.handshake(), throwsA(isA<SaberException>()));
      expect(transport.commands, ['WR?', 'WR?']);
    });

    test('versione, seriale e tipo di spada', () async {
      expect(await protocol.getFirmwareVersion(), 'NXT_fake');
      expect(await protocol.getSerialNumber(), FakeSaber.serial);
      expect(SaberProtocolService.typeFromVersion('NXT_1.1.0'), SaberType.animaNXT);
      expect(SaberProtocolService.typeFromVersion('1.9.15'), SaberType.unknown);
      expect(SaberProtocolService.typeFromVersion(null), SaberType.unknown);
    });
  });

  group('comandi', () {
    test('anteprima e spegnimento', () async {
      expect(await protocol.previewColor(blue), isTrue);
      expect(await protocol.stopPreview(), isTrue);
      expect(transport.commands, ['P=0,0,255,10', 'P=0']);
    });

    test('setColor: scrittura e un SAVE', () async {
      expect(await protocol.setColor(2, ColorEffect.main, red), isTrue);
      expect(await protocol.setColor(3, ColorEffect.clash, red), isTrue);
      expect(await protocol.setColor(4, ColorEffect.swing, blue), isTrue);

      expect(transport.commands, [
        'C2=255,0,0,0', 'SAVE',
        'F3=255,0,0,0', 'SAVE',
        'W4=0,0,255,10', 'SAVE',
      ]);
      expect(transport.saber.swing[4], [0, 0, 255, 10]);
    });

    test('setActiveBank: B= e un SAVE', () async {
      expect(await protocol.setActiveBank(5), isTrue);
      expect(transport.commands, ['B=5', 'SAVE']);
      expect(transport.saber.bank, 5);
    });

    test('saveColorBank: tre colori, B= e un solo SAVE', () async {
      final bank = ColorBank(mainColor: red, clashColor: blue, swingColor: red);

      expect(await protocol.saveColorBank(6, bank), isTrue);
      expect(transport.commands, ['C6=255,0,0,0', 'F6=0,0,255,10', 'W6=255,0,0,0', 'B=6', 'SAVE']);
    });

    test('saveColorBank senza bank attivo', () async {
      expect(await protocol.saveColorBank(1, ColorBank(), setActive: false), isTrue);
      expect(transport.commands.where((c) => c.startsWith('B=')), isEmpty);
      expect(saves(), 1);
    });

    test('salva tutto: 24 colori, B= e un solo SAVE, con il progresso', () async {
      final config = ColorConfiguration(activeBank: 3)..setColor(7, ColorEffect.swing, blue);
      final steps = <int>[];

      final ok = await protocol.saveAllColorBanksWithProgress(config, (p) => steps.add(p.completedOperations));

      expect(ok, isTrue);
      expect(transport.commands, hasLength(26));
      expect(transport.commands.where((c) => RegExp(r'^[CFW][0-7]=').hasMatch(c)), hasLength(24));
      expect(transport.commands[24], 'B=3');
      expect(transport.commands.last, 'SAVE');
      expect(saves(), 1);
      expect(transport.saber.swing[7], [0, 0, 255, 10]);
      expect(steps.first, 0);
      expect(steps.last, 26);
    });

    test('saveAllColorBanks', () async {
      expect(await protocol.saveAllColorBanks(ColorConfiguration()), isTrue);
      expect(saves(), 1);
    });

    test('nessun SAVE se una scrittura fallisce', () async {
      transport.mutedCommands.add('F0=255,255,255,255');

      expect(await protocol.saveAllColorBanks(ColorConfiguration()), isFalse);
      expect(saves(), 0);
    });

    test('eco diversa dal comando: errore', () async {
      final manual = ManualTransport();
      final manualLink = SaberLink(manual);
      manual.onCommand = (_) => manual.push('OK C0=0,0,0,0\n');

      expect(await SaberProtocolService(manualLink, timeout: short).setColor(0, ColorEffect.main, red), isFalse);
      expect(manual.written, ['C0=255,0,0,0\n']);
      manualLink.dispose();
    });

    test('senza connessione restituisce false', () async {
      await link.disconnect();

      expect(await protocol.setColor(0, ColorEffect.main, red), isFalse);
      expect(await protocol.previewColor(red), isFalse);
      expect(await protocol.getFirmwareVersion(), isNull);
    });
  });

  group('readConfiguration', () {
    test('legge bank attivo e 24 colori', () async {
      transport.saber
        ..bank = 4
        ..main[1] = [1, 2, 3, 4]
        ..clash[2] = [5, 6, 7, 8]
        ..swing[7] = [9, 10, 11, 12];

      final result = await protocol.readConfiguration();

      expect(result, isNotNull);
      expect(result!.isComplete, isTrue);
      expect(transport.commands, ['B?', 'c?', 'f?', 'w?']);
      final config = result.configuration;
      expect(config.activeBank, 4);
      expect(config.getColor(0, ColorEffect.main), red);
      expect(config.getColor(1, ColorEffect.main), const RGBWColor(red: 1, green: 2, blue: 3, white: 4));
      expect(config.getColor(2, ColorEffect.clash), const RGBWColor(red: 5, green: 6, blue: 7, white: 8));
      expect(config.getColor(7, ColorEffect.swing), const RGBWColor(red: 9, green: 10, blue: 11, white: 12));
    });

    test('comando che tace: campi al default e marcati come non letti', () async {
      transport.mutedCommands.add('w?');

      final result = await protocol.readConfiguration();

      expect(result!.isComplete, isFalse);
      expect(result.unread, ['w?']);
      expect(result.configuration.getColor(0, ColorEffect.main), red);
      expect(result.configuration.getColor(0, ColorEffect.swing), const RGBWColor.white());
    });

    test('senza connessione restituisce null', () async {
      await link.disconnect();
      expect(await protocol.readConfiguration(), isNull);
    });
  });
}
