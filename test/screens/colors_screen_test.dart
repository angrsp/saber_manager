import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:saber_manager/screens/colors_screen.dart';
import 'package:saber_manager/services/saber_link.dart';
import 'package:saber_manager/services/saber_protocol.dart';
import 'package:saber_manager/transport/fake_transport.dart';

void main() {
  // Trasporto e link vanno creati dentro il test, nella zona a tempo simulato di testWidgets:
  // creati in setUp, le loro risposte passerebbero per il tempo reale, fermo durante pump.
  Future<FakeTransport> pumpScreen(WidgetTester tester, {Set<String> muted = const {}}) async {
    final transport = FakeTransport()..mutedCommands.addAll(muted);
    final link = SaberLink(transport);
    addTearDown(link.dispose);
    await link.connect('fake');

    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      Provider<SaberProtocolService>(
        create: (_) => SaberProtocolService(link, timeout: const Duration(milliseconds: 100)),
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ColorsScreen())),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return transport;
  }

  testWidgets('legge i colori all\'apertura', (tester) async {
    final transport = await pumpScreen(tester);

    expect(transport.commands, ['B?', 'c?', 'f?', 'w?']);
    expect(find.text('Saber not connected'), findsNothing);
    expect(find.textContaining('could not be read'), findsNothing);
  });

  testWidgets('lettura incompleta: avviso', (tester) async {
    await pumpScreen(tester, muted: {'f?'});

    expect(find.textContaining('could not be read (f?)'), findsOneWidget);
  });

  testWidgets('P=0 all\'uscita solo dopo un\'anteprima', (tester) async {
    final transport = await pumpScreen(tester);
    await tester.tap(find.text('Preview'));
    await tester.pumpAndSettle();
    expect(transport.commands.last, startsWith('P='));

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(transport.commands.last, 'P=0');
  });

  testWidgets('nessun P=0 all\'uscita senza anteprima', (tester) async {
    final transport = await pumpScreen(tester);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(transport.commands, isNot(contains('P=0')));
  });
}
