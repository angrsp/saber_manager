import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:permission_handler/permission_handler.dart';

enum BluetoothReadiness {
  ready,
  unsupported,
  poweredOff,
  permissionDenied,
  // Negato con "non chiedere più": serve passare dalle impostazioni
  permissionPermanentlyDenied,
  // Fino ad Android 11 la scansione BLE richiede la localizzazione attiva
  locationServicesDisabled,
}

// Permessi a runtime e Bluetooth acceso, prima di scansione e connessione
abstract class BluetoothAccess {
  // Chiede i permessi mancanti e, se il Bluetooth è spento, di accenderlo
  Future<BluetoothReadiness> ensureReady();

  Future<void> openSettings();
}

// Per il trasporto finto e i test
class AlwaysReadyBluetooth implements BluetoothAccess {
  @override
  Future<BluetoothReadiness> ensureReady() async => BluetoothReadiness.ready;

  @override
  Future<void> openSettings() async {}
}

class PlatformBluetoothAccess implements BluetoothAccess {
  PlatformBluetoothAccess(this._ble);

  // Canale verso MainActivity.kt: versione di Android e richiesta di accensione del Bluetooth
  static const MethodChannel _channel = MethodChannel('saber_manager/bluetooth');
  static const Duration _statusTimeout = Duration(seconds: 5);
  static const Duration _powerOnTimeout = Duration(seconds: 15);
  static const Duration _refreshTimeout = Duration(seconds: 2);

  final FlutterReactiveBle _ble;
  int? _sdkInt;

  // Versione di Android (0 su altre piattaforme)
  Future<int> sdkInt() async {
    if (_sdkInt != null) return _sdkInt!;
    if (!Platform.isAndroid) return _sdkInt = 0;
    try {
      _sdkInt = await _channel.invokeMethod<int>('sdkInt') ?? 0;
    } on PlatformException catch (e) {
      debugPrint('Bluetooth: versione di Android non letta ($e)');
      _sdkInt = 0;
    }
    return _sdkInt!;
  }

  // Fino ad Android 11 serve la localizzazione attiva per la scansione
  Future<bool> needsLocationServices() async {
    final sdk = await sdkInt();
    return sdk > 0 && sdk <= 30;
  }

  @override
  Future<BluetoothReadiness> ensureReady() async {
    if (Platform.isAndroid) {
      final permissions = await needsLocationServices()
          ? [Permission.locationWhenInUse]
          : [Permission.bluetoothScan, Permission.bluetoothConnect];
      final results = await permissions.request();
      if (results.values.any((s) => s.isPermanentlyDenied)) return BluetoothReadiness.permissionPermanentlyDenied;
      if (results.values.any((s) => !s.isGranted)) return BluetoothReadiness.permissionDenied;
    }

    var status = await _currentStatus();
    // statusStream emette prima lo stato in cache, calcolato all'avvio dell'app (prima dei permessi),
    // e subito dopo quello ricalcolato dalla piattaforma: appena concessi i permessi il primo valore
    // è ancora "unauthorized", quindi si aspetta un attimo quello aggiornato.
    if (status == BleStatus.unauthorized && Platform.isAndroid) {
      status = await _waitStatus((s) => s != BleStatus.unknown && s != BleStatus.unauthorized, _refreshTimeout);
    }
    if (status == BleStatus.poweredOff && Platform.isAndroid) {
      await _requestEnable();
      status = await _waitStatus((s) => s != BleStatus.poweredOff, _powerOnTimeout);
    }

    switch (status) {
      case BleStatus.ready:
        return BluetoothReadiness.ready;
      case BleStatus.poweredOff:
        return BluetoothReadiness.poweredOff;
      case BleStatus.unauthorized:
        return BluetoothReadiness.permissionDenied;
      case BleStatus.locationServicesDisabled:
        return BluetoothReadiness.locationServicesDisabled;
      case BleStatus.unsupported:
      case BleStatus.unknown:
        return BluetoothReadiness.unsupported;
    }
  }

  // Il primo stato dopo l'inizializzazione può essere "unknown": si aspetta il primo valore utile
  Future<BleStatus> _currentStatus() => _waitStatus((s) => s != BleStatus.unknown, _statusTimeout);

  Future<BleStatus> _waitStatus(bool Function(BleStatus) test, Duration timeout) async {
    try {
      return await _ble.statusStream.firstWhere(test).timeout(timeout);
    } on TimeoutException {
      return _ble.status;
    }
  }

  Future<void> _requestEnable() async {
    try {
      await _channel.invokeMethod<bool>('requestEnable');
    } on PlatformException catch (e) {
      debugPrint('Bluetooth: richiesta di accensione fallita ($e)');
    }
  }

  @override
  Future<void> openSettings() => openAppSettings();
}
