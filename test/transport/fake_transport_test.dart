import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:saber_manager/models/saber_exceptions.dart';
import 'package:saber_manager/transport/fake_transport.dart';
import 'package:saber_manager/transport/saber_transport.dart';

void main() {
  group('FakeSaber, risposte come in F0', () {
    late FakeSaber saber;

    setUp(() => saber = FakeSaber());

    test('handshake, versione, seriale', () {
      expect(saber.process('WR?'), 'OK, Write Ready\n');
      expect(saber.process('V?'), 'V=NXT_fake\n');
      expect(saber.process('S?'), 'S=fa4e0046414b4510000001\n');
    });

    test('c?, f?, w?: 8 righe minuscole', () {
      expect(saber.process('c?').split('\n'), [
        'c0=255,0,0,0', 'c1=0,255,0,0', 'c2=0,0,255,0', 'c3=255,255,0,0',
        'c4=0,255,255,0', 'c5=255,0,255,0', 'c6=255,128,0,0', 'c7=0,0,0,255', '',
      ]);
      expect(saber.process('f?').split('\n').first, 'f0=255,255,255,255');
      expect(saber.process('w?').split('\n'), hasLength(9));
    });

    test('C<n>= risponde con l\'eco e cambia il colore', () {
      expect(saber.process('C0=255,0,0,0'), 'OK C0=255,0,0,0\n');
      expect(saber.process('F2=1,2,3,4'), 'OK F2=1,2,3,4\n');
      expect(saber.process('f2?'), 'f2=1,2,3,4\n');
      expect(saber.process('W5=0A0B0C0D'), 'OK W5=0A0B0C0D\n');
      expect(saber.process('w5?'), 'w5=10,11,12,13\n');
      expect(saber.process('W5?'), 'W5=0A0B0C0D\n');
    });

    test('bank 0-7: fuori intervallo nessuna risposta', () {
      expect(saber.process('C8=1,2,3,4'), '');
      expect(saber.process('B=8'), '');
      expect(saber.process('B=5'), 'OK B=5\n');
      expect(saber.process('B?'), 'B=5\n');
    });

    test('anteprima con la virgola', () {
      expect(saber.process('P=0,0,255,0'), 'OK, P=0,0,255,0\n');
      expect(saber.process('P=0'), 'OK, P=0\n');
    });

    test('SAVE, comandi sconosciuti, \\r e #', () {
      expect(saber.process('SAVE'), 'OK SAVE\n');
      expect(saber.process('S'), '');
      expect(saber.process('XYZ'), '');
      expect(saber.process('V?\r'), '');
      expect(saber.process('#ciao'), '#');
    });

    test('RESET riporta i colori di default', () {
      saber.process('C0=1,1,1,1');
      saber.process('B=3');
      expect(saber.process('RESET'), 'OK RESET\n');
      expect(saber.process('c0?'), 'c0=255,0,0,0\n');
      expect(saber.process('B?'), 'B=0\n');
    });
  });

  group('FakeTransport', () {
    late FakeTransport transport;
    late List<Uint8List> received;
    late StreamSubscription<Uint8List> subscription;

    setUp(() async {
      transport = FakeTransport();
      received = [];
      subscription = transport.onData.listen(received.add);
      await transport.connect('fake');
    });

    tearDown(() {
      subscription.cancel();
      transport.dispose();
    });

    Future<void> send(String text) => transport.write(Uint8List.fromList(text.codeUnits));
    String text() => received.map(String.fromCharCodes).join();

    test('stati della connessione', () async {
      final states = <TransportState>[];
      final other = FakeTransport();
      final sub = other.state.listen(states.add);
      await other.connect('fake');
      await other.disconnect();
      await Future<void>.delayed(Duration.zero);

      expect(states, [TransportState.connecting, TransportState.connected, TransportState.disconnected]);
      await sub.cancel();
      other.dispose();
    });

    test('risposte in frammenti da 20 byte al massimo', () async {
      await send('c?\n');
      await Future<void>.delayed(Duration.zero);

      expect(received.length, greaterThan(1));
      expect(received.every((f) => f.length <= 20), isTrue);
      expect(text(), FakeSaber().process('c?'));
    });

    test('comando spezzato su più scritture', () async {
      await send('WR');
      await send('?\nV?\n');
      await Future<void>.delayed(Duration.zero);

      expect(transport.commands, ['WR?', 'V?']);
      expect(text(), 'OK, Write Ready\nV=NXT_fake\n');
    });

    test('comandi silenziati e righe di log', () async {
      final noisy = FakeTransport(logLineEvery: 1)..mutedCommands.add('w?');
      final data = <Uint8List>[];
      final sub = noisy.onData.listen(data.add);
      await noisy.connect('fake');

      await noisy.write(Uint8List.fromList('w?\nB?\n'.codeUnits));
      await Future<void>.delayed(Duration.zero);

      expect(data.map(String.fromCharCodes).join(), '#FakeSaber: alive 1\n#FakeSaber: alive 2\nB=0\n');
      await sub.cancel();
      noisy.dispose();
    });

    test('write senza connessione o senza spada', () async {
      transport.saberPresent = false;
      await expectLater(send('V?\n'), throwsA(isA<SaberNotConnectedException>()));

      transport.simulateDisconnect();
      await expectLater(send('V?\n'), throwsA(isA<SaberDisconnectedException>()));
    });
  });
}
