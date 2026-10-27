import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/bridge_status.dart';
import '../models/saber_device.dart';
import '../transport/bridge_scanner.dart';
import '../transport/saber_transport.dart';
import 'bluetooth_access.dart';
import 'saber_link.dart';
import 'saber_protocol.dart';

enum ConnectionPhase {
  idle,
  scanning,
  connecting,
  // Bridge connesso, spada non collegata o non ancora pronta
  waitingForSaber,
  handshaking,
  ready,
}

// Stato della connessione per tutta l'app: permessi, scansione, connessione al bridge,
// attesa della spada, handshake e info. Se la spada si scollega torna in waitingForSaber
// senza chiudere il bridge; se cade il bridge torna in idle.
class SaberConnectionService extends ChangeNotifier {
  SaberConnectionService({
    required BridgeTransport transport,
    required SaberLink link,
    required SaberProtocolService protocol,
    required BridgeScanner scanner,
    required BluetoothAccess bluetooth,
  })  : _transport = transport,
        _link = link,
        _protocol = protocol,
        _scanner = scanner,
        _bluetooth = bluetooth {
    _stateSubscription = _transport.state.listen(_onTransportState);
    _statusSubscription = _transport.bridgeStatus.listen(_onBridgeStatus);
  }

  final BridgeTransport _transport;
  final SaberLink _link;
  final SaberProtocolService _protocol;
  final BridgeScanner _scanner;
  final BluetoothAccess _bluetooth;
  late final StreamSubscription<TransportState> _stateSubscription;
  late final StreamSubscription<BridgeStatus> _statusSubscription;
  StreamSubscription<List<SaberDevice>>? _scanSubscription;

  ConnectionPhase _phase = ConnectionPhase.idle;
  List<SaberDevice> _devices = const [];
  SaberDevice? _bridge;
  SaberDevice? _saber;
  BridgeStatus? _bridgeStatus;
  BluetoothReadiness? _readiness;
  String? _error;
  bool _disconnecting = false;
  bool _disposed = false;
  // Cresce a ogni sessione con la spada: i risultati di un handshake superato vengono scartati
  int _session = 0;

  ConnectionPhase get phase => _phase;
  List<SaberDevice> get devices => _devices;
  SaberDevice? get bridge => _bridge;
  SaberDevice? get saber => _saber;
  BridgeStatus? get bridgeStatus => _bridgeStatus;
  String? get bridgeFirmware => _transport.bridgeFirmware;
  BluetoothReadiness? get readiness => _readiness;
  String? get error => _error;

  bool get isScanning => _phase == ConnectionPhase.scanning;
  bool get isBridgeConnected =>
      _phase == ConnectionPhase.waitingForSaber ||
      _phase == ConnectionPhase.handshaking ||
      _phase == ConnectionPhase.ready;
  // Spada pronta per i comandi
  bool get isConnected => _phase == ConnectionPhase.ready;

  String get statusMessage {
    switch (_phase) {
      case ConnectionPhase.idle:
        return _error ?? 'Ready to scan for SaberBridge';
      case ConnectionPhase.scanning:
        return 'Scanning for SaberBridge...';
      case ConnectionPhase.connecting:
        return 'Connecting to ${_bridge?.name ?? 'bridge'}...';
      case ConnectionPhase.waitingForSaber:
        return _error ?? 'Bridge connected – turn on the saber';
      case ConnectionPhase.handshaking:
        return 'Saber found, reading info...';
      case ConnectionPhase.ready:
        return 'Connected to ${_saber?.name ?? 'saber'}';
    }
  }

  // Chiede permessi e Bluetooth acceso, poi cerca i bridge per [duration]
  Future<void> scan({Duration duration = BridgeScanner.defaultDuration}) async {
    if (_phase != ConnectionPhase.idle) return;
    _error = null;
    _readiness = await _bluetooth.ensureReady();
    if (_readiness != BluetoothReadiness.ready) {
      _error = _readinessMessage(_readiness!);
      _notify();
      return;
    }

    _devices = const [];
    _setPhase(ConnectionPhase.scanning);
    final done = Completer<void>();
    _scanSubscription = _scanner.scan(duration: duration).listen(
      (devices) {
        _devices = devices;
        _notify();
      },
      onError: (Object e) {
        _error = 'Scan failed: ${_describe(e)}';
        if (!done.isCompleted) done.complete();
      },
      onDone: () {
        if (!done.isCompleted) done.complete();
      },
    );
    await done.future;
    _scanSubscription = null;
    if (_phase == ConnectionPhase.scanning) _setPhase(ConnectionPhase.idle);
  }

  Future<void> stopScan() async {
    final subscription = _scanSubscription;
    _scanSubscription = null;
    await subscription?.cancel();
    if (_phase == ConnectionPhase.scanning) _setPhase(ConnectionPhase.idle);
  }

  // Connette il bridge; true se il bridge è connesso (la spada può essere ancora assente).
  // Se la spada c'è già, l'handshake parte subito.
  Future<bool> connect(SaberDevice bridge) async {
    await stopScan();
    if (_phase != ConnectionPhase.idle) return false;
    _error = null;
    _bridge = bridge;
    _setPhase(ConnectionPhase.connecting);
    try {
      await _link.connect(bridge.id);
    } catch (e) {
      debugPrint('Connessione al bridge fallita: $e');
      _bridge = null;
      _error = 'Connection failed: ${_describe(e)}';
      _setPhase(ConnectionPhase.idle);
      return false;
    }

    _bridgeStatus = _transport.currentBridgeStatus;
    // Senza servizio di stato non si sa se la spada c'è: si prova l'handshake
    if (_bridgeStatus?.saberConnected ?? true) {
      unawaited(_startSession());
    } else {
      _setPhase(ConnectionPhase.waitingForSaber);
    }
    return true;
  }

  // Nuovo tentativo dopo un handshake fallito
  Future<void> retryHandshake() async {
    if (_phase != ConnectionPhase.waitingForSaber) return;
    await _startSession();
  }

  Future<void> _startSession() async {
    final session = ++_session;
    _error = null;
    _setPhase(ConnectionPhase.handshaking);
    try {
      await _protocol.handshake();
      final version = await _protocol.getFirmwareVersion();
      final serial = await _protocol.getSerialNumber();
      if (session != _session) return;
      var type = SaberProtocolService.typeFromVersion(version);
      if (type == SaberType.unknown) type = _bridgeStatus?.saberType ?? SaberType.unknown;
      _saber = SaberDevice(
        id: _bridge!.id,
        name: _bridge!.name,
        rssi: _bridge!.rssi,
        type: type,
        firmwareVersion: version,
        serialNumber: serial,
        isConnected: true,
      );
      _setPhase(ConnectionPhase.ready);
    } catch (e) {
      if (session != _session || _transport.currentState != TransportState.connected) return;
      debugPrint('Handshake fallito: $e');
      _error = 'Saber not responding';
      _setPhase(ConnectionPhase.waitingForSaber);
    }
  }

  void _onBridgeStatus(BridgeStatus status) {
    final wasConnected = _bridgeStatus?.saberConnected ?? false;
    _bridgeStatus = status;
    if (status.saberConnected && !wasConnected && _phase == ConnectionPhase.waitingForSaber) {
      unawaited(_startSession());
    } else if (!status.saberConnected &&
        (_phase == ConnectionPhase.ready || _phase == ConnectionPhase.handshaking)) {
      _session++;
      _saber = null;
      _error = null;
      _setPhase(ConnectionPhase.waitingForSaber);
    } else {
      _notify();
    }
  }

  void _onTransportState(TransportState state) {
    if (state != TransportState.disconnected || !isBridgeConnected) return;
    _session++;
    _saber = null;
    _bridge = null;
    _bridgeStatus = null;
    _error = _disconnecting ? null : 'Bridge connection lost';
    _setPhase(ConnectionPhase.idle);
  }

  Future<void> disconnect() async {
    _disconnecting = true;
    _session++;
    try {
      await _link.disconnect();
    } finally {
      _disconnecting = false;
    }
    _saber = null;
    _bridge = null;
    _bridgeStatus = null;
    _error = null;
    _setPhase(ConnectionPhase.idle);
  }

  void clearError() {
    _error = null;
    _notify();
  }

  Future<void> openSettings() => _bluetooth.openSettings();

  static String _readinessMessage(BluetoothReadiness readiness) {
    switch (readiness) {
      case BluetoothReadiness.ready:
        return '';
      case BluetoothReadiness.unsupported:
        return 'Bluetooth LE is not available on this device';
      case BluetoothReadiness.poweredOff:
        return 'Turn on Bluetooth to find the SaberBridge';
      case BluetoothReadiness.permissionDenied:
        return 'Bluetooth permission is needed to find the SaberBridge';
      case BluetoothReadiness.permissionPermanentlyDenied:
        return 'Bluetooth permission denied: enable it in the app settings';
      case BluetoothReadiness.locationServicesDisabled:
        return 'Turn on location services to scan for Bluetooth devices';
    }
  }

  // Testo leggibile di un errore: senza "SaberException: " e, per gli errori di flutter_reactive_ble
  // (GenericFailure(code: ..., message: "...")), solo il messaggio
  static String _describe(Object e) {
    final text = e.toString();
    if (text.startsWith('SaberException: ')) return text.substring(16);
    final failure = RegExp(r'message: "(.*)"\)').firstMatch(text);
    return failure?.group(1) ?? text;
  }

  void _setPhase(ConnectionPhase phase) {
    _phase = phase;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _scanSubscription?.cancel();
    _stateSubscription.cancel();
    _statusSubscription.cancel();
    super.dispose();
  }
}
