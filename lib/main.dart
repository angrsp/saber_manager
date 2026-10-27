import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:provider/provider.dart';
import 'services/bluetooth_access.dart';
import 'services/saber_connection_service.dart';
import 'services/saber_link.dart';
import 'services/saber_protocol.dart';
import 'transport/ble_transport.dart';
import 'transport/bridge_scanner.dart';
import 'transport/fake_transport.dart';
import 'transport/saber_transport.dart';
import 'screens/home_screen.dart';
import 'screens/colors_screen.dart';
import 'screens/connection_screen.dart';

// flutter run --dart-define=FAKE_BRIDGE=true: spada finta al posto del bridge BLE (sviluppo, emulatore)
const bool fakeBridgeFromEnvironment = bool.fromEnvironment('FAKE_BRIDGE');

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, this.fakeBridge = fakeBridgeFromEnvironment});

  final bool fakeBridge;

  @override
  Widget build(BuildContext context) {
    final ble = fakeBridge ? null : FlutterReactiveBle();
    final platformBluetooth = ble == null ? null : PlatformBluetoothAccess(ble);

    return MultiProvider(
      providers: [
        // Il trasporto lo chiude SaberLink.dispose
        Provider<BridgeTransport>(
          create: (_) => ble == null
              ? FakeTransport(responseDelay: const Duration(milliseconds: 20), logLineEvery: 5)
              : BleTransport(ble),
        ),
        Provider<SaberLink>(
          create: (context) => SaberLink(context.read<BridgeTransport>()),
          dispose: (_, link) => link.dispose(),
        ),
        Provider<SaberProtocolService>(
          create: (context) => SaberProtocolService(context.read<SaberLink>()),
        ),
        ChangeNotifierProvider<SaberConnectionService>(
          create: (context) => SaberConnectionService(
            transport: context.read<BridgeTransport>(),
            link: context.read<SaberLink>(),
            protocol: context.read<SaberProtocolService>(),
            scanner: ble == null ? FakeScanner() : _bleScanner(ble, platformBluetooth!),
            bluetooth: platformBluetooth ?? AlwaysReadyBluetooth(),
          ),
        ),
      ],
      child: MaterialApp(
        title: 'Saber Manager',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          primarySwatch: Colors.deepPurple,
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.deepPurple,
            brightness: Brightness.light,
          ),
        ),
        home: const HomeScreen(),
        routes: {
          '/colors': (context) => const ColorsScreen(),
          '/connection': (context) => const ConnectionScreen(),
        },
      ),
    );
  }

  static BridgeScanner _bleScanner(FlutterReactiveBle ble, PlatformBluetoothAccess bluetooth) {
    final scanner = BleScanner(ble);
    // La versione di Android si conosce solo in modo asincrono; la scansione parte comunque dopo ensureReady
    bluetooth.needsLocationServices().then((needed) => scanner.requireLocationServices = needed);
    return scanner;
  }
}
