import 'dart:async';
import 'dart:typed_data';

import 'package:saber_manager/transport/saber_transport.dart';

// Trasporto controllato dal test: registra le scritture e manda all'app
// esattamente i frammenti passati a push().
class ManualTransport implements SaberTransport {
  ManualTransport({TransportState initialState = TransportState.connected}) : _state = initialState;

  final StreamController<Uint8List> _dataController = StreamController<Uint8List>.broadcast();
  final StreamController<TransportState> _stateController = StreamController<TransportState>.broadcast();
  TransportState _state;

  // Testo di ogni scrittura, terminatore compreso
  final List<String> written = [];

  // Chiamata a ogni comando scritto (senza terminatore), per rispondere dal test
  void Function(String command)? onCommand;

  // Durata di ogni write, come una write BLE con risposta
  Duration writeDelay = Duration.zero;

  // Se impostato, write fallisce con questo errore
  Object? writeError;

  @override
  Stream<Uint8List> get onData => _dataController.stream;

  @override
  Stream<TransportState> get state => _stateController.stream;

  @override
  TransportState get currentState => _state;

  @override
  Future<void> connect(String deviceId) async => setState(TransportState.connected);

  @override
  Future<void> write(Uint8List data) async {
    if (writeDelay > Duration.zero) await Future<void>.delayed(writeDelay);
    final error = writeError;
    if (error != null) throw error;
    final text = String.fromCharCodes(data);
    written.add(text);
    onCommand?.call(text.replaceAll('\n', ''));
  }

  @override
  Future<void> disconnect() async => setState(TransportState.disconnected);

  @override
  void dispose() {
    _dataController.close();
    _stateController.close();
  }

  void push(String text) => _dataController.add(Uint8List.fromList(text.codeUnits));

  void setState(TransportState state) {
    _state = state;
    _stateController.add(state);
  }
}
