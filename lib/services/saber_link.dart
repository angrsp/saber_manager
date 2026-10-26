import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../models/saber_exceptions.dart';
import '../transport/saber_transport.dart';

// Collegamento a righe con la spada sopra un SaberTransport.
// Una sola sottoscrizione ai dati per tutta la vita del link, una richiesta alla volta,
// risposte attribuite per prefisso: una risposta arrivata dopo un timeout viene scartata
// invece di finire alla richiesta successiva.
class SaberLink {
  static const Duration defaultTimeout = Duration(seconds: 3);

  SaberLink(this._transport) {
    _dataSubscription = _transport.onData.listen(_onData);
    _stateSubscription = _transport.state.listen(_onState);
  }

  final SaberTransport _transport;
  late final StreamSubscription<Uint8List> _dataSubscription;
  late final StreamSubscription<TransportState> _stateSubscription;

  // Testo ricevuto non ancora terminato da \n
  String _buffer = '';
  _PendingRequest? _pending;

  // Coda delle richieste: ognuna parte quando la precedente è finita
  Future<void> _queue = Future.value();

  bool get isConnected => _transport.currentState == TransportState.connected;
  Stream<TransportState> get state => _transport.state;

  Future<void> connect(String deviceId) => _transport.connect(deviceId);
  Future<void> disconnect() => _transport.disconnect();

  // Manda un comando e restituisce la prima riga che inizia con [match]
  // (senza distinzione fra maiuscole e minuscole)
  Future<String> request(String command, {required String match, Duration timeout = defaultTimeout}) async {
    final lines = await requestLines(command, match: match, lines: 1, timeout: timeout);
    return lines.single;
  }

  // Come request, ma raccoglie [lines] righe che iniziano con [match] (per c?, f?, w?)
  Future<List<String>> requestLines(
    String command, {
    required String match,
    required int lines,
    Duration timeout = defaultTimeout,
  }) {
    final result = _queue.then((_) => _send(command, match, lines, timeout));
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<List<String>> _send(String command, String match, int lines, Duration timeout) async {
    if (!isConnected) throw SaberDisconnectedException();

    final pending = _PendingRequest(command, match.toLowerCase(), lines);
    // Il timeout può scadere mentre write è ancora in corso, prima che qualcuno attenda il future:
    // senza ignore() l'errore sarebbe segnalato come non gestito. Chi lo attende dopo lo riceve comunque.
    pending.completer.future.ignore();
    _pending = pending;
    pending.timer = Timer(timeout, () {
      debugPrint('Timeout waiting for "$match" after "$command"');
      _finish(pending, error: ResponseTimeoutException(command));
    });

    debugPrint('Sending: "$command"');
    try {
      // La spada vuole il solo LF: con \r\n il comando non viene riconosciuto
      await _transport.write(Uint8List.fromList(utf8.encode('$command\n')));
    } catch (_) {
      pending.timer?.cancel();
      if (_pending == pending) _pending = null;
      rethrow;
    }
    return pending.completer.future;
  }

  void _finish(_PendingRequest pending, {Object? error}) {
    if (pending.completer.isCompleted) return;
    pending.timer?.cancel();
    if (_pending == pending) _pending = null;
    if (error != null) {
      pending.completer.completeError(error);
    } else {
      pending.completer.complete(pending.lines);
    }
  }

  void _onData(Uint8List data) {
    _buffer += String.fromCharCodes(data);
    int end;
    while ((end = _buffer.indexOf('\n')) >= 0) {
      final line = _buffer.substring(0, end).replaceAll('\r', '');
      _buffer = _buffer.substring(end + 1);
      _onLine(line);
    }
  }

  void _onLine(String line) {
    if (line.isEmpty) return;
    if (line.startsWith('#')) {
      debugPrint('Saber log: $line');
      return;
    }

    final pending = _pending;
    if (pending == null || !line.toLowerCase().startsWith(pending.match)) {
      debugPrint('Discarded line: "$line"');
      return;
    }

    debugPrint('Received: "$line"');
    pending.lines.add(line);
    if (pending.lines.length == pending.expectedLines) _finish(pending);
  }

  void _onState(TransportState state) {
    // Come il bridge, a ogni cambio di stato si riparte da un buffer vuoto
    _buffer = '';
    final pending = _pending;
    if (state == TransportState.disconnected && pending != null) {
      _finish(pending, error: SaberDisconnectedException());
    }
  }

  void dispose() {
    _dataSubscription.cancel();
    _stateSubscription.cancel();
    final pending = _pending;
    if (pending != null) _finish(pending, error: SaberDisconnectedException());
    _transport.dispose();
  }
}

class _PendingRequest {
  _PendingRequest(this.command, this.match, this.expectedLines);

  final String command;
  final String match;
  final int expectedLines;
  final List<String> lines = [];
  final Completer<List<String>> completer = Completer<List<String>>();
  Timer? timer;
}
