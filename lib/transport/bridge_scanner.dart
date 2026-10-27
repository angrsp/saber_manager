import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import '../models/saber_device.dart';
import 'bridge_uuids.dart';

// Ricerca dei bridge
abstract class BridgeScanner {
  static const Duration defaultDuration = Duration(seconds: 10);

  // Lista dei bridge trovati, aggiornata a ogni novità (ordinata per segnale);
  // si chiude dopo [duration] o quando chi ascolta annulla la sottoscrizione
  Stream<List<SaberDevice>> scan({Duration duration = defaultDuration});
}

// Scansione BLE filtrata per UUID del NUS
class BleScanner implements BridgeScanner {
  BleScanner(this._ble, {this.requireLocationServices = false});

  final FlutterReactiveBle _ble;

  // Solo fino ad Android 11 la scansione richiede la localizzazione attiva
  bool requireLocationServices;

  @override
  Stream<List<SaberDevice>> scan({Duration duration = BridgeScanner.defaultDuration}) {
    final found = <String, SaberDevice>{};
    late StreamController<List<SaberDevice>> controller;
    StreamSubscription<DiscoveredDevice>? subscription;
    Timer? timer;

    Future<void> stop() async {
      timer?.cancel();
      await subscription?.cancel();
      subscription = null;
      if (!controller.isClosed) await controller.close();
    }

    controller = StreamController<List<SaberDevice>>(
      onListen: () {
        controller.add(const []);
        subscription = _ble
            .scanForDevices(
              withServices: [BridgeUuids.nus],
              scanMode: ScanMode.lowLatency,
              requireLocationServicesEnabled: requireLocationServices,
            )
            .listen(
          (d) {
            found[d.id] = SaberDevice(
              id: d.id,
              name: d.name.isNotEmpty ? d.name : 'SaberBridge',
              rssi: d.rssi,
              type: SaberType.unknown,
            );
            final list = found.values.toList()..sort((a, b) => (b.rssi ?? -999).compareTo(a.rssi ?? -999));
            if (!controller.isClosed) controller.add(list);
          },
          onError: (Object e) {
            debugPrint('BLE: errore di scansione $e');
            if (!controller.isClosed) controller.addError(e);
            stop();
          },
        );
        timer = Timer(duration, stop);
      },
      onCancel: stop,
    );
    return controller.stream;
  }
}
