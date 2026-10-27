import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:saber_manager/screens/connection_screen.dart';
import 'package:saber_manager/services/bluetooth_access.dart';
import 'package:saber_manager/services/saber_connection_service.dart';
import 'package:saber_manager/services/saber_link.dart';
import 'package:saber_manager/services/saber_protocol.dart';
import 'package:saber_manager/transport/fake_transport.dart';

class _FixedBluetooth implements BluetoothAccess {
  _FixedBluetooth(this.readiness);
  final BluetoothReadiness readiness;
  int settingsOpened = 0;

  @override
  Future<BluetoothReadiness> ensureReady() async => readiness;

  @override
  Future<void> openSettings() async => settingsOpened++;
}

void main() {
  // Come in colors_screen_test: tutto creato dentro il test, nella zona a tempo simulato
  Future<(FakeTransport, SaberConnectionService)> pumpScreen(
    WidgetTester tester, {
    BluetoothAccess? bluetooth,
    bool saberPresent = true,
  }) async {
    final transport = FakeTransport()..saberPresent = saberPresent;
    final link = SaberLink(transport);
    final service = SaberConnectionService(
      transport: transport,
      link: link,
      protocol: SaberProtocolService(link, timeout: const Duration(milliseconds: 100)),
      scanner: FakeScanner(),
      bluetooth: bluetooth ?? AlwaysReadyBluetooth(),
    );
    addTearDown(() {
      service.dispose();
      link.dispose();
    });

    await tester.pumpWidget(
      ChangeNotifierProvider<SaberConnectionService>.value(
        value: service,
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ConnectionScreen())),
                child: const Text('home'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('home'));
    await tester.pumpAndSettle();
    return (transport, service);
  }

  testWidgets('cerca all\'apertura e mostra il bridge con RSSI', (tester) async {
    await pumpScreen(tester);

    expect(find.text('SaberBridge (demo)'), findsOneWidget);
    expect(find.textContaining('-50 dBm'), findsOneWidget);
  });

  testWidgets('connessione con la spada accesa: torna alla home', (tester) async {
    final (transport, service) = await pumpScreen(tester);

    await tester.tap(find.text('SaberBridge (demo)'));
    await tester.pumpAndSettle();

    expect(service.isConnected, isTrue);
    expect(transport.commands, ['WR?', 'V?', 'S?']);
    expect(find.byType(ConnectionScreen), findsNothing);
    expect(find.text('home'), findsOneWidget);
  });

  testWidgets('spada spenta: attesa, poi home quando si accende', (tester) async {
    final (transport, service) = await pumpScreen(tester, saberPresent: false);

    await tester.tap(find.text('SaberBridge (demo)'));
    await tester.pumpAndSettle();

    expect(find.text('SaberBridge (demo) connected'), findsOneWidget);
    expect(find.text('Turn on the saber'), findsOneWidget);
    expect(find.text('Disconnect bridge'), findsOneWidget);

    transport.saberPresent = true;
    await tester.pumpAndSettle();

    expect(service.isConnected, isTrue);
    expect(find.byType(ConnectionScreen), findsNothing);
  });

  testWidgets('spada che non risponde: errore e Retry', (tester) async {
    final (transport, service) = await pumpScreen(tester);
    transport.mutedCommands.add('WR?');

    await tester.tap(find.text('SaberBridge (demo)'));
    await tester.pumpAndSettle();

    expect(find.text('Saber not responding'), findsOneWidget);

    transport.mutedCommands.clear();
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(service.isConnected, isTrue);
    expect(find.byType(ConnectionScreen), findsNothing);
  });

  testWidgets('permesso negato per sempre: messaggio e Impostazioni', (tester) async {
    final bluetooth = _FixedBluetooth(BluetoothReadiness.permissionPermanentlyDenied);
    await pumpScreen(tester, bluetooth: bluetooth);

    expect(find.textContaining('enable it in the app settings'), findsOneWidget);
    expect(find.text('No SaberBridge found'), findsOneWidget);

    await tester.tap(find.text('Settings'));
    expect(bluetooth.settingsOpened, 1);
  });
}
