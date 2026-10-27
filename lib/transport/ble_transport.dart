import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import '../models/bridge_status.dart';
import '../models/saber_exceptions.dart';
import 'bridge_uuids.dart';
import 'saber_transport.dart';

// Trasporto verso il bridge SaberBridge (contratto BLE v1, piano-FW-bridge.md sezione 3):
// scrittura con risposta su RX a pezzi da (MTU - 3), notifiche da TX, stato del bridge dal servizio 7A6F0001.
class BleTransport implements BridgeTransport {
  BleTransport(this._ble);

  static const int preferredMtu = 247;
  static const Duration connectionTimeout = Duration(seconds: 10);

  // Errori ATT applicativi della write su RX
  static const int attSaberNotConnected = 0x80;
  static const int attBufferFull = 0x81;
  static const int bufferFullRetries = 10;
  static const Duration bufferFullPause = Duration(milliseconds: 50);

  final FlutterReactiveBle _ble;

  final StreamController<Uint8List> _dataController = StreamController<Uint8List>.broadcast();
  final StreamController<TransportState> _stateController = StreamController<TransportState>.broadcast();
  final StreamController<BridgeStatus> _statusController = StreamController<BridgeStatus>.broadcast();

  TransportState _state = TransportState.disconnected;
  String? _deviceId;
  int _mtu = 23;
  BridgeStatus? _bridgeStatus;
  String? _bridgeFirmware;

  StreamSubscription<ConnectionStateUpdate>? _connection;
  StreamSubscription<List<int>>? _txSubscription;
  StreamSubscription<List<int>>? _statusSubscription;

  // Le scritture vanno una alla volta, perché i pezzi di un comando non si mescolino
  Future<void> _writeQueue = Future.value();

  @override
  Stream<Uint8List> get onData => _dataController.stream;

  @override
  Stream<TransportState> get state => _stateController.stream;

  @override
  TransportState get currentState => _state;

  @override
  Stream<BridgeStatus> get bridgeStatus => _statusController.stream;

  @override
  BridgeStatus? get currentBridgeStatus => _bridgeStatus;

  @override
  String? get bridgeFirmware => _bridgeFirmware;

  int get mtu => _mtu;

  @override
  Future<void> connect(String deviceId) async {
    if (_state != TransportState.disconnected) await disconnect();
    _deviceId = deviceId;
    _setState(TransportState.connecting);

    final connected = Completer<void>();
    _connection = _ble
        .connectToDevice(id: deviceId, connectionTimeout: connectionTimeout)
        .listen(
      (update) {
        debugPrint('BLE $deviceId: ${update.connectionState}${update.failure != null ? ' ${update.failure}' : ''}');
        switch (update.connectionState) {
          case DeviceConnectionState.connected:
            if (!connected.isCompleted) connected.complete();
          case DeviceConnectionState.disconnected:
            if (!connected.isCompleted) {
              connected.completeError(SaberException('Bridge connection failed'));
            } else {
              _onLinkLost();
            }
          case DeviceConnectionState.connecting:
          case DeviceConnectionState.disconnecting:
            break;
        }
      },
      onError: (Object e) {
        debugPrint('BLE $deviceId: errore di connessione $e');
        if (!connected.isCompleted) {
          connected.completeError(e is TimeoutException ? ConnectionTimeoutException() : SaberException('$e'));
        } else {
          _onLinkLost();
        }
      },
    );

    try {
      await connected.future;
      await _setUp(deviceId);
      // La connessione può essere caduta durante la preparazione
      if (_connection == null) throw SaberDisconnectedException();
      _setState(TransportState.connected);
    } catch (_) {
      await _close();
      rethrow;
    }
  }

  Future<void> _setUp(String deviceId) async {
    try {
      _mtu = await _ble.requestMtu(deviceId: deviceId, mtu: preferredMtu);
    } catch (e) {
      debugPrint('BLE: requestMtu fallita ($e), resta $_mtu');
    }
    if (Platform.isAndroid) {
      try {
        await _ble.requestConnectionPriority(deviceId: deviceId, priority: ConnectionPriority.highPerformance);
      } catch (e) {
        debugPrint('BLE: priorità di connessione non impostata ($e)');
      }
    }

    await _ble.discoverAllServices(deviceId);
    final services = await _ble.getDiscoveredServices(deviceId);
    bool has(Uuid id) => services.any((s) => s.id.expanded == id.expanded);

    if (!has(BridgeUuids.nus)) throw SaberException('Not a SaberBridge (no UART service)');

    _txSubscription = _ble.subscribeToCharacteristic(_characteristic(BridgeUuids.nus, BridgeUuids.nusTx)).listen(
          (data) => _dataController.add(Uint8List.fromList(data)),
          onError: (Object e) => debugPrint('BLE: notifiche TX interrotte ($e)'),
        );

    if (has(BridgeUuids.status)) {
      final statusChar = _characteristic(BridgeUuids.status, BridgeUuids.statusChar);
      // Il bridge manda una notifica con lo stato corrente appena ci si iscrive; la lettura copre il caso in cui arrivi prima
      _statusSubscription = _ble.subscribeToCharacteristic(statusChar).listen(
            _onStatus,
            onError: (Object e) => debugPrint('BLE: notifiche di stato interrotte ($e)'),
          );
      try {
        _onStatus(await _ble.readCharacteristic(statusChar));
      } catch (e) {
        debugPrint('BLE: lettura dello stato fallita ($e)');
      }
    } else {
      debugPrint('BLE: il bridge non ha il servizio di stato');
    }

    if (has(BridgeUuids.dis)) {
      try {
        final raw = await _ble.readCharacteristic(_characteristic(BridgeUuids.dis, BridgeUuids.disFirmware));
        _bridgeFirmware = utf8.decode(raw, allowMalformed: true).trim();
      } catch (e) {
        debugPrint('BLE: versione del bridge non letta ($e)');
      }
    }
    debugPrint('BLE: pronto, MTU $_mtu, bridge $_bridgeFirmware, $_bridgeStatus');
  }

  QualifiedCharacteristic _characteristic(Uuid service, Uuid characteristic) =>
      QualifiedCharacteristic(serviceId: service, characteristicId: characteristic, deviceId: _deviceId!);

  void _onStatus(List<int> data) {
    final status = BridgeStatus.parse(data);
    if (status == null) {
      debugPrint('BLE: stato del bridge non valido ($data)');
      return;
    }
    if (status.bytesLost) debugPrint('BLE: il bridge ha perso dei byte');
    _bridgeStatus = status;
    if (!_statusController.isClosed) _statusController.add(status);
  }

  @override
  Future<void> write(Uint8List data) {
    final result = _writeQueue.then((_) => _write(data));
    _writeQueue = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<void> _write(Uint8List data) async {
    final chunkSize = max(1, _mtu - 3);
    for (int i = 0; i < data.length; i += chunkSize) {
      if (_state != TransportState.connected) throw SaberDisconnectedException();
      await _writeChunk(data.sublist(i, min(i + chunkSize, data.length)));
    }
  }

  Future<void> _writeChunk(Uint8List chunk) async {
    final rx = _characteristic(BridgeUuids.nus, BridgeUuids.nusRx);
    for (int attempt = 1;; attempt++) {
      try {
        await _ble.writeCharacteristicWithResponse(rx, value: chunk);
        return;
      } catch (e) {
        final status = attStatusOf(e);
        if (status == attSaberNotConnected) throw SaberNotConnectedException();
        if (status == attBufferFull && attempt < bufferFullRetries) {
          await Future<void>.delayed(bufferFullPause);
          continue;
        }
        if (_state != TransportState.connected) throw SaberDisconnectedException();
        throw SaberException(status == attBufferFull ? 'Bridge buffer full' : 'Write failed: $e');
      }
    }
  }

  // Codice ATT da un errore di scrittura. Su Android RxAndroidBle scrive "... status 128 (...) ..."
  // nel messaggio; flutter_reactive_ble non lo espone in altro modo.
  static int? attStatusOf(Object error) {
    final text = error.toString();
    final decimal = RegExp(r'status[ =:]+(\d+)(?![x\d])', caseSensitive: false).firstMatch(text);
    if (decimal != null) return int.parse(decimal.group(1)!);
    final hex = RegExp(r'status[ =:]+0x([0-9a-f]+)', caseSensitive: false).firstMatch(text);
    if (hex != null) return int.parse(hex.group(1)!, radix: 16);
    return null;
  }

  // Connessione caduta senza che l'app l'abbia chiesto (bridge spento o fuori portata)
  void _onLinkLost() {
    if (_state == TransportState.disconnected) return;
    debugPrint('BLE: connessione persa');
    _close();
  }

  @override
  Future<void> disconnect() => _close();

  // Annullare la sottoscrizione di connectToDevice chiude la connessione
  Future<void> _close() async {
    final subscriptions = [_txSubscription, _statusSubscription, _connection];
    _txSubscription = null;
    _statusSubscription = null;
    _connection = null;
    _bridgeStatus = null;
    _bridgeFirmware = null;
    _mtu = 23;
    _setState(TransportState.disconnected);
    for (final s in subscriptions) {
      await s?.cancel();
    }
  }

  @override
  void dispose() {
    _close();
    _dataController.close();
    _stateController.close();
    _statusController.close();
  }

  void _setState(TransportState state) {
    if (_state == state) return;
    _state = state;
    if (!_stateController.isClosed) _stateController.add(state);
  }
}
