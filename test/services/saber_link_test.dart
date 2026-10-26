import 'package:flutter_test/flutter_test.dart';

import 'package:saber_manager/models/saber_exceptions.dart';
import 'package:saber_manager/services/saber_link.dart';
import 'package:saber_manager/transport/fake_transport.dart';
import 'package:saber_manager/transport/saber_transport.dart';

import '../helpers/manual_transport.dart';

const short = Duration(milliseconds: 50);

// Lascia passare gli eventi degli stream e le scritture in coda
Future<void> flush() => Future<void>.delayed(Duration.zero);

void main() {
  late ManualTransport transport;
  late SaberLink link;

  setUp(() {
    transport = ManualTransport();
    link = SaberLink(transport);
  });

  tearDown(() => link.dispose());

  test('manda il comando terminato dal solo LF', () async {
    transport.onCommand = (_) => transport.push('OK, Write Ready\n');

    expect(await link.request('WR?', match: 'OK, Write Ready'), 'OK, Write Ready');
    expect(transport.written, ['WR?\n']);
  });

  test('riga spezzata su più notifiche', () async {
    transport.onCommand = (_) => transport
      ..push('OK, Wr')
      ..push('ite Re')
      ..push('ady\n');

    expect(await link.request('WR?', match: 'OK, Write Ready'), 'OK, Write Ready');
  });

  test('due righe nello stesso pacchetto', () async {
    transport.onCommand = (_) => transport.push('c0=255,0,0,0\nc1=0,255,0,0\n');

    expect(await link.requestLines('c?', match: 'c', lines: 2), ['c0=255,0,0,0', 'c1=0,255,0,0']);
  });

  test('ignora \\r e le righe vuote', () async {
    transport.onCommand = (_) => transport.push('\r\n\nB=3\r\n');

    expect(await link.request('B?', match: 'B='), 'B=3');
  });

  test('scarta le righe # in mezzo a una risposta su più righe', () async {
    transport.onCommand = (_) => transport
      ..push('c0=1,2,3,4\n#FakeSaber: ali')
      ..push('ve 1\nc1=5,6,7,8\n');

    expect(await link.requestLines('c?', match: 'c', lines: 2), ['c0=1,2,3,4', 'c1=5,6,7,8']);
  });

  test('confronta il prefisso senza distinguere maiuscole e minuscole', () async {
    transport.onCommand = (_) => transport.push('c0=1,2,3,4\n');

    expect(await link.request('c0?', match: 'C0='), 'c0=1,2,3,4');
  });

  test('scarta le righe che non corrispondono al prefisso atteso', () async {
    transport.onCommand = (_) => transport.push('OK SAVE\nV=NXT_1.1.0\n');

    expect(await link.request('V?', match: 'V='), 'V=NXT_1.1.0');
  });

  test('timeout se la spada non risponde', () async {
    await expectLater(
      link.request('XYZ', match: 'OK', timeout: short),
      throwsA(isA<ResponseTimeoutException>().having((e) => e.command, 'command', 'XYZ')),
    );
  });

  test('timeout scaduto durante una write lenta', () async {
    transport.writeDelay = const Duration(milliseconds: 100);

    await expectLater(link.request('B?', match: 'B=', timeout: short), throwsA(isA<ResponseTimeoutException>()));
  });

  test('una risposta arrivata dopo il timeout non va alla richiesta successiva', () async {
    transport.onCommand = (command) {
      if (command == 'B?') {
        transport
          ..push('V=late\n')
          ..push('B=1\n');
      }
    };

    await expectLater(link.request('V?', match: 'V=', timeout: short), throwsA(isA<ResponseTimeoutException>()));
    expect(await link.request('B?', match: 'B='), 'B=1');
  });

  test('timeout con una risposta su più righe incompleta', () async {
    transport.onCommand = (_) => transport.push('w0=0,0,0,0\nw1=0,0,0,0\n');

    await expectLater(
      link.requestLines('w?', match: 'w', lines: 8, timeout: short),
      throwsA(isA<ResponseTimeoutException>()),
    );
  });

  test('disconnessione a metà richiesta', () async {
    final result = link.request('SAVE', match: 'OK SAVE');
    await flush();
    transport.setState(TransportState.disconnected);

    await expectLater(result, throwsA(isA<SaberDisconnectedException>()));
  });

  test('richiesta senza connessione', () async {
    transport.setState(TransportState.disconnected);
    await flush();

    await expectLater(link.request('V?', match: 'V='), throwsA(isA<SaberDisconnectedException>()));
    expect(transport.written, isEmpty);
  });

  test('errore della write propagato alla richiesta', () async {
    transport.writeError = SaberNotConnectedException();

    await expectLater(link.request('V?', match: 'V='), throwsA(isA<SaberNotConnectedException>()));

    transport
      ..writeError = null
      ..onCommand = (_) => transport.push('V=NXT_1.1.0\n');
    expect(await link.request('V?', match: 'V='), 'V=NXT_1.1.0');
  });

  test('una richiesta alla volta', () async {
    final first = link.request('V?', match: 'V=');
    final second = link.request('S?', match: 'S=');
    await flush();
    expect(transport.written, ['V?\n']);

    transport.push('V=NXT_1.1.0\n');
    expect(await first, 'V=NXT_1.1.0');
    await flush();
    expect(transport.written, ['V?\n', 'S?\n']);

    transport.push('S=5f00303931501920383758\n');
    expect(await second, 'S=5f00303931501920383758');
  });

  test('la coda prosegue dopo una richiesta fallita', () async {
    final first = link.request('XYZ', match: 'OK', timeout: short);
    transport.onCommand = (command) {
      if (command == 'B?') transport.push('B=2\n');
    };
    final second = link.request('B?', match: 'B=');

    await expectLater(first, throwsA(isA<ResponseTimeoutException>()));
    expect(await second, 'B=2');
  });

  test('buffer svuotato a ogni cambio di stato', () async {
    transport.push('V=mez');
    await flush();
    transport
      ..setState(TransportState.disconnected)
      ..setState(TransportState.connected);
    await flush();
    transport.onCommand = (_) => transport.push('zo\nV=NXT_1.1.0\n');

    expect(await link.request('V?', match: 'V='), 'V=NXT_1.1.0');
  });

  group('con FakeTransport', () {
    late FakeTransport fake;
    late SaberLink fakeLink;

    setUp(() async {
      fake = FakeTransport(logLineEvery: 2);
      fakeLink = SaberLink(fake);
      await fakeLink.connect('fake');
    });

    tearDown(() => fakeLink.dispose());

    test('handshake, info e lettura degli 8 colori', () async {
      expect(await fakeLink.request('WR?', match: 'OK, Write Ready'), 'OK, Write Ready');
      expect(await fakeLink.request('V?', match: 'V='), 'V=NXT_fake');
      expect(await fakeLink.request('S?', match: 'S='), 'S=${FakeSaber.serial}');

      final colors = await fakeLink.requestLines('c?', match: 'c', lines: 8);
      expect(colors, hasLength(8));
      expect(colors.first, 'c0=255,0,0,0');
      expect(colors.last, 'c7=0,0,0,255');
    });

    test('scrittura di un colore e rilettura', () async {
      expect(await fakeLink.request('C3=1,2,3,4', match: 'OK C3='), 'OK C3=1,2,3,4');
      expect(await fakeLink.request('c3?', match: 'c3='), 'c3=1,2,3,4');
    });

    test('risposta in ritardo oltre il timeout', () async {
      final slow = FakeTransport(responseDelay: const Duration(milliseconds: 100));
      final slowLink = SaberLink(slow);
      await slowLink.connect('fake');

      await expectLater(slowLink.request('B?', match: 'B=', timeout: short), throwsA(isA<ResponseTimeoutException>()));
      slowLink.dispose();
    });
  });
}
