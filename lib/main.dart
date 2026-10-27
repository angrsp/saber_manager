import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'app_state.dart';
import 'services/saber_connection_service.dart';
import 'services/saber_link.dart';
import 'services/saber_protocol.dart';
import 'transport/fake_transport.dart';
import 'screens/home_screen.dart';
import 'screens/colors_screen.dart';
import 'screens/connection_screen.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppState()),
        // Trasporto finto finché non c'è il BLE (A4)
        Provider<SaberLink>(
          create: (_) => SaberLink(FakeTransport(responseDelay: const Duration(milliseconds: 20), logLineEvery: 5)),
          dispose: (_, link) => link.dispose(),
        ),
        Provider<SaberProtocolService>(
          create: (context) => SaberProtocolService(context.read<SaberLink>()),
        ),
        Provider<SaberConnectionService>(
          create: (context) => SaberConnectionService(
            context.read<SaberLink>(),
            context.read<SaberProtocolService>(),
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
}
