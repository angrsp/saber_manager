import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import '../models/saber_exceptions.dart';
import 'saber_transport.dart';

// Emulatore della Anima NXT, come main/nxt_emu.c del firmware del bridge
// (risposte uguali a quelle reali registrate in F0, piano-FW-bridge.md sezione 6).
class FakeSaber {
  static const String build = 'NXT_fake';
  static const String serial = 'fa4e0046414b4510000001';
  static const int banks = 8;

  static const List<List<int>> _mainDefaults = [
    [255, 0, 0, 0], [0, 255, 0, 0], [0, 0, 255, 0], [255, 255, 0, 0],
    [0, 255, 255, 0], [255, 0, 255, 0], [255, 128, 0, 0], [0, 0, 0, 255],
  ];

  // Colori r,g,b,w per bank: main (C), clash (F), swing (W)
  final List<List<int>> main = [];
  final List<List<int>> clash = [];
  final List<List<int>> swing = [];
  int bank = 0;

  FakeSaber() {
    reset();
  }

  void reset() {
    main
      ..clear()
      ..addAll(_mainDefaults.map((c) => List<int>.of(c)));
    clash
      ..clear()
      ..addAll(List.generate(banks, (_) => [255, 255, 255, 255]));
    swing
      ..clear()
      ..addAll(_mainDefaults.map((c) => List<int>.of(c)));
    bank = 0;
  }

  // Risposta a un comando senza terminatore, compreso il \n finale; '' = nessuna risposta
  String process(String m) {
    if (m.isEmpty) return '';
    final upper = m.toUpperCase();
    final c0 = m[0];
    final c1 = m.length > 1 ? m[1] : '';
    final c2 = m.length > 2 ? m[2] : '';

    if (upper == 'V') {
      return 'Build: $build\r\nSerial Number: $serial\r\nFiles on memory:\n\n';
    } else if (c0 == '#') {
      return '#'; // senza LF, come la spada
    } else if (upper == 'V?') {
      return 'V=$build\n';
    } else if (m == 'S?') {
      return 'S=$serial\n';
    } else if (upper == 'WR?') {
      return 'OK, Write Ready\n';
    } else if (c2 == '=') {
      final table = _table(c0);
      if (table != null && _isBank(c1)) {
        table[int.parse(c1)] = _parseColor(m.substring(3));
        return 'OK $m\n'; // eco del comando, non il colore normalizzato
      }
    } else if (c2 == '?') {
      final table = _table(c0);
      if (table != null && _isBank(c1)) {
        return '$c0$c1=${_formatColor(table[int.parse(c1)], _isUpper(c0))}\n';
      }
    } else if (m.length == 2 && c1 == '?' && _table(c0) != null) {
      final table = _table(c0)!;
      final lines = List.generate(banks, (i) => '$c0$i=${_formatColor(table[i], _isUpper(c0))}');
      return '${lines.join('\n')}\n';
    } else if (upper == 'P=0') {
      return 'OK, P=0\n';
    } else if (m.startsWith('P=') || m.startsWith('p=')) {
      return 'OK, $m\n';
    } else if (m.startsWith('B=')) {
      if (_isBank(c2)) {
        bank = int.parse(c2);
        return 'OK $m\n';
      }
    } else if (m == 'B?') {
      return 'B=$bank\n';
    } else if (m == 'RESET') {
      reset();
      return 'OK RESET\n';
    } else if (m == 'SAVE') {
      return 'OK SAVE\n';
    }
    // tutto il resto: nessuna risposta
    return '';
  }

  List<List<int>>? _table(String kind) {
    switch (kind) {
      case 'C':
      case 'c':
        return main;
      case 'F':
      case 'f':
        return clash;
      case 'W':
      case 'w':
        return swing;
    }
    return null;
  }

  bool _isBank(String c) => c.length == 1 && '01234567'.contains(c);

  bool _isUpper(String c) => c == c.toUpperCase();

  // Senza separatori è esadecimale rrggbbww ("#" o "0x" davanti facoltativi),
  // altrimenti decimale separato da virgole, punti e virgola o spazi
  List<int> _parseColor(String src) {
    final s = src.trim();
    if (!s.contains(RegExp(r'[,; ]'))) {
      var hex = s;
      if (hex.startsWith('#')) {
        hex = hex.substring(1);
      } else if (hex.startsWith('0x')) {
        hex = hex.substring(2);
      }
      final v = int.tryParse(hex, radix: 16) ?? 0;
      return [(v >> 24) & 0xFF, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF];
    }
    final parts = s.split(RegExp(r'[,; ]'));
    return List.generate(4, (i) => i < parts.length ? (int.tryParse(parts[i].trim()) ?? 0) & 0xFF : 0);
  }

  String _formatColor(List<int> c, bool hex) {
    if (hex) {
      return c.map((v) => v.toRadixString(16).padLeft(2, '0').toUpperCase()).join();
    }
    return c.join(',');
  }
}

// Trasporto finto: collega l'app a un FakeSaber, con le risposte spezzate in notifiche
// come farebbe il bridge BLE.
class FakeTransport implements SaberTransport {
  FakeTransport({
    FakeSaber? saber,
    this.fragmentSize = 20,
    this.responseDelay = Duration.zero,
    this.logLineEvery = 0,
  }) : saber = saber ?? FakeSaber();

  final FakeSaber saber;

  // Lunghezza massima di ogni notifica (20 = MTU minima BLE meno 3)
  final int fragmentSize;

  // Ritardo prima di ogni risposta, per provare i timeout
  final Duration responseDelay;

  // Ogni quanti comandi inserire una riga di log "#..." prima della risposta (0 = mai)
  final int logLineEvery;

  // Comandi a cui la spada non risponde, per simulare un firmware più vecchio
  final Set<String> mutedCommands = {};

  // Comandi ricevuti, in ordine, senza terminatore
  final List<String> commands = [];

  // false = bridge connesso ma spada non collegata
  bool saberPresent = true;

  final StreamController<Uint8List> _dataController = StreamController<Uint8List>.broadcast();
  final StreamController<TransportState> _stateController = StreamController<TransportState>.broadcast();
  TransportState _state = TransportState.disconnected;
  String _rx = '';
  int _logLines = 0;

  @override
  Stream<Uint8List> get onData => _dataController.stream;

  @override
  Stream<TransportState> get state => _stateController.stream;

  @override
  TransportState get currentState => _state;

  @override
  Future<void> connect(String deviceId) async {
    if (_state == TransportState.connected) return;
    _setState(TransportState.connecting);
    await Future<void>.delayed(Duration.zero);
    _setState(TransportState.connected);
  }

  @override
  Future<void> write(Uint8List data) async {
    if (_state != TransportState.connected) throw SaberDisconnectedException();
    if (!saberPresent) throw SaberNotConnectedException();

    _rx += String.fromCharCodes(data);
    int end;
    while ((end = _rx.indexOf('\n')) >= 0) {
      final command = _rx.substring(0, end);
      _rx = _rx.substring(end + 1);
      commands.add(command);

      var response = mutedCommands.contains(command) ? '' : saber.process(command);
      if (logLineEvery > 0 && commands.length % logLineEvery == 0) {
        response = '#FakeSaber: alive ${++_logLines}\n$response';
      }
      if (response.isNotEmpty) {
        Future<void>.delayed(responseDelay, () {
          if (_state == TransportState.connected) inject(response);
        });
      }
    }
  }

  // Manda subito all'app dei byte arbitrari, spezzati in frammenti
  void inject(String text) {
    if (_dataController.isClosed) return;
    final bytes = text.codeUnits;
    for (int i = 0; i < bytes.length; i += fragmentSize) {
      _dataController.add(Uint8List.fromList(bytes.sublist(i, min(i + fragmentSize, bytes.length))));
    }
  }

  // Connessione persa (bridge spento o fuori portata)
  void simulateDisconnect() => _setState(TransportState.disconnected);

  @override
  Future<void> disconnect() async => _setState(TransportState.disconnected);

  @override
  void dispose() {
    _dataController.close();
    _stateController.close();
  }

  void _setState(TransportState state) {
    if (_state == state) return;
    _state = state;
    _rx = '';
    _stateController.add(state);
  }
}
