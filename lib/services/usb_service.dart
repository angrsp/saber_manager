import 'dart:async';
import 'dart:typed_data';
import 'package:usb_serial/usb_serial.dart';

// Modello dati per dispositivi saber
class SaberDevice {
  final UsbDevice usbDevice;
  final String name;
  final SaberType type;
  final String? firmwareVersion;
  final String? serialNumber;
  final bool isConnected;

  SaberDevice({
    required this.usbDevice,
    required this.name,
    required this.type,
    this.firmwareVersion,
    this.serialNumber,
    this.isConnected = false,
  });

  SaberDevice copyWith({
    UsbDevice? usbDevice,
    String? name,
    SaberType? type,
    String? firmwareVersion,
    String? serialNumber,
    bool? isConnected,
  }) {
    return SaberDevice(
      usbDevice: usbDevice ?? this.usbDevice,
      name: name ?? this.name,
      type: type ?? this.type,
      firmwareVersion: firmwareVersion ?? this.firmwareVersion,
      serialNumber: serialNumber ?? this.serialNumber,
      isConnected: isConnected ?? this.isConnected,
    );
  }

  @override
  String toString() {
    return 'SaberDevice(name: $name, type: $type, fw: $firmwareVersion, connected: $isConnected)';
  }
}

enum SaberType {
  animaEVO,
  animaNXT,
  unknown,
}

// Exception personalizzate
class SaberException implements Exception {
  final String message;
  SaberException(this.message);
  
  @override
  String toString() => 'SaberException: $message';
}

class NoSaberFoundException extends SaberException {
  NoSaberFoundException() : super('No compatible saber found');
}

class ConnectionTimeoutException extends SaberException {
  ConnectionTimeoutException() : super('Connection timeout');
}

class PermissionDeniedException extends SaberException {
  PermissionDeniedException() : super('USB permission denied');
}

// Servizio principale USB
class USBService {
  static const int baudRate = 1152000;
  static const int chunkSize = 128;
  static const Duration readTimeout = Duration(seconds: 5);
  static const Duration chunkDelay = Duration(milliseconds: 500);
  static const Duration connectionStabilizationDelay = Duration(seconds: 2);

  // OpenCore Device IDs (convertiti da hex a decimale)
  static const List<Map<String, int>> animaDevices = [
    {'vid': 0x16C0, 'pid': 0x0483}, // Anima EVO
    {'vid': 0x0483, 'pid': 0x5740}, // Anima NXT
  ];

  UsbPort? _port;
  StreamSubscription<Uint8List>? _subscription;
  SaberDevice? _connectedDevice;

  // Stream controllers per eventi
  final StreamController<List<SaberDevice>> _devicesController = 
      StreamController<List<SaberDevice>>.broadcast();
  final StreamController<String> _statusController = 
      StreamController<String>.broadcast();

  // Streams pubblici
  Stream<List<SaberDevice>> get devicesStream => _devicesController.stream;
  Stream<String> get statusStream => _statusController.stream;

  // Getters
  bool get isConnected => _port != null && _connectedDevice != null;
  SaberDevice? get connectedDevice => _connectedDevice;
  
  // NUOVO: Esponi la porta USB per il SaberProtocolService
  UsbPort? get connectedPort => _port;

  // Richiedi permessi USB
  Future<bool> requestPermissions() async {
    try {
      _updateStatus('Requesting USB permissions...');
      
      // Verifica se il dispositivo supporta USB host
      List<UsbDevice> devices = await UsbSerial.listDevices();
      if (devices.isEmpty) {
        _updateStatus('No USB devices found - check USB OTG support');
        return false;
      }

      _updateStatus('USB permissions granted');
      return true;
    } catch (e) {
      _updateStatus('Permission error: $e');
      return false;
    }
  }

  // Scan per dispositivi saber
  Future<List<SaberDevice>> scanForSabers() async {
    try {
      _updateStatus('Scanning for sabers...');
      
      List<UsbDevice> devices = await UsbSerial.listDevices();
      List<SaberDevice> sabers = [];

      print('📱 Found ${devices.length} USB devices');
      
      for (UsbDevice device in devices) {
        print('🔍 Checking device: VID=${device.vid?.toRadixString(16)}, PID=${device.pid?.toRadixString(16)}');
        
        if (_isAnimaDevice(device)) {
          SaberType type = _getSaberType(device);
          String name = _generateSaberName(device, type);
          
          SaberDevice saber = SaberDevice(
            usbDevice: device,
            name: name,
            type: type,
          );
          
          sabers.add(saber);
          print('✅ Found saber: $name');
        }
      }

      if (sabers.isEmpty) {
        _updateStatus('No sabers found - connect your OpenCore lightsaber');
      } else {
        _updateStatus('Found ${sabers.length} saber(s)');
        print('🎉 Found ${sabers.length} saber(s)!');
      }

      _devicesController.add(sabers);
      return sabers;
    } catch (e) {
      _updateStatus('Scan error: $e');
      throw SaberException('Scan failed: $e');
    }
  }

  // Connetti a un dispositivo
  Future<SaberDevice?> connectToDevice(SaberDevice saber) async {
    try {
      _updateStatus('Connecting to ${saber.name}...');
      print('🔌 Attempting connection to ${saber.name}');

      // Crea la porta USB
      _port = await saber.usbDevice.create();
      if (_port == null) {
        throw SaberException('Failed to create USB port');
      }

      // Apri la connessione
      bool opened = await _port!.open();
      if (!opened) {
        _port = null;
        throw SaberException('Failed to open USB port');
      }

      // Configura i parametri della porta
      await _port!.setDTR(true);
      await _port!.setRTS(false);
      await _port!.setPortParameters(
        baudRate, 
        UsbPort.DATABITS_8, 
        UsbPort.STOPBITS_1, 
        UsbPort.PARITY_NONE
      );

      print('✅ USB port opened successfully');

      // Aspetta più tempo per la stabilizzazione
      print('⏳ Waiting for connection stabilization...');
      await Future.delayed(connectionStabilizationDelay);

      // Tenta diversi metodi per verificare la connessione
      bool isReady = await _checkSaberReadyMultiple();
      if (!isReady) {
        await disconnect();
        throw SaberException('Saber not responding');
      }

      // Ottieni informazioni dalla saber
      Map<String, String> info = await _getSaberInfo();
      
      // Crea il dispositivo connesso con le informazioni aggiornate
      _connectedDevice = saber.copyWith(
        isConnected: true,
        firmwareVersion: info['version'],
        serialNumber: info['serial'],
      );

      _updateStatus('Connected to ${_connectedDevice!.name}');
      print('🎉 Successfully connected to ${_connectedDevice!.name}');
      
      return _connectedDevice;
    } catch (e) {
      print('❌ Connection failed: $e');
      await disconnect();
      throw SaberException('Connection failed: $e');
    }
  }

  // Disconnetti
  Future<void> disconnect() async {
    try {
      _subscription?.cancel();
      _subscription = null;
      
      await _port?.close();
      _port = null;
      
      _connectedDevice = null;
      _updateStatus('Disconnected');
      print('🔌 Disconnected from saber');
    } catch (e) {
      print('❌ Error during disconnect: $e');
    }
  }

  // Verifica se la saber è pronta - metodi multipli
  Future<bool> _checkSaberReadyMultiple() async {
    print('🔍 Testing saber communication...');
    
    // Metodo 1: Comando backslash (originale)
    if (await _testCommand('\\', ['OK, Write Ready', 'OK', 'Write Ready'])) {
      print('✅ Saber responded to \\ command');
      return true;
    }
    
    // Metodo 2: Comando di versione
    if (await _testCommand('V?', ['V=', 'Version'])) {
      print('✅ Saber responded to V? command');
      return true;
    }
    
    // Metodo 3: Comando di help
    if (await _testCommand('?', ['Help', 'Commands', 'Available'])) {
      print('✅ Saber responded to ? command');
      return true;
    }
    
    // Metodo 4: Solo newline
    if (await _testCommand('', ['>', 'OK', 'Ready'])) {
      print('✅ Saber responded to newline');
      return true;
    }
    
    print('❌ Saber not responding to any test commands');
    return false;
  }

  // Testa un comando specifico
  Future<bool> _testCommand(String command, List<String> expectedResponses) async {
    try {
      print('📤 Testing command: "${command}"');
      
      await _sendCommand(command);
      String response = await _readLine();
      
      print('📥 Received: "$response"');
      
      // Verifica se la risposta contiene una delle stringhe attese
      for (String expected in expectedResponses) {
        if (response.contains(expected)) {
          return true;
        }
      }
      
      return false;
    } catch (e) {
      print('❌ Test command failed: $e');
      return false;
    }
  }

  // Ottieni informazioni dal saber
  Future<Map<String, String>> _getSaberInfo() async {
    Map<String, String> info = {};

    try {
      // Versione firmware
      await _sendCommand('V?');
      String versionResponse = await _readLine();
      print('📡 Version response: $versionResponse');
      
      if (versionResponse.contains('V=')) {
        info['version'] = versionResponse.substring(versionResponse.indexOf('V=') + 2).trim();
      } else if (versionResponse.isNotEmpty && !versionResponse.startsWith('#')) {
        // Se non è nel formato V=, prendi la risposta come versione
        info['version'] = versionResponse.trim();
      }

      // Numero seriale
      await _sendCommand('S?');
      String serialResponse = await _readLine();
      print('📡 Serial response: $serialResponse');
      
      if (serialResponse.contains('S=')) {
        info['serial'] = serialResponse.substring(serialResponse.indexOf('S=') + 2).trim();
      } else if (serialResponse.isNotEmpty && !serialResponse.startsWith('#')) {
        info['serial'] = serialResponse.trim();
      }
    } catch (e) {
      print('❌ Error getting saber info: $e');
      // Non è critico se non riusciamo a ottenere le info
    }

    return info;
  }

  // Invia comando al saber
  Future<void> _sendCommand(String cmd) async {
    if (_port == null) throw SaberException('Not connected');

    String fullCommand = cmd.isEmpty ? '\n' : '$cmd\n';
    List<int> data = fullCommand.codeUnits;
    print('📤 Sending: "${cmd}" (${data.length} bytes)');

    if (data.length <= chunkSize) {
      await _port!.write(Uint8List.fromList(data));
    } else {
      // Invia a chunk per evitare buffer overflow
      for (int i = 0; i < data.length; i += chunkSize) {
        int end = (i + chunkSize > data.length) ? data.length : i + chunkSize;
        await _port!.write(Uint8List.fromList(data.sublist(i, end)));

        if (end < data.length) {
          await Future.delayed(chunkDelay);
        }
      }
    }
    
    // Piccola pausa dopo l'invio
    await Future.delayed(const Duration(milliseconds: 100));
  }

  // Leggi risposta dal saber con timeout più lungo
  Future<String> _readLine() async {
    if (_port == null) throw SaberException('Not connected');

    String response = '';
    Completer<String> completer = Completer();
    Timer? timeout;

    timeout = Timer(readTimeout, () {
      if (!completer.isCompleted) {
        print('⏰ Read timeout after ${readTimeout.inSeconds}s');
        completer.completeError(ConnectionTimeoutException());
      }
    });

    _subscription = _port!.inputStream?.listen((Uint8List data) {
      String dataString = String.fromCharCodes(data);
      response += dataString;
      
      print('📨 Raw data received: ${data.map((e) => e.toRadixString(16)).join(' ')}');
      print('📨 String received: "$dataString"');
      
      if (response.contains('\n') || response.contains('\r')) {
        timeout?.cancel();
        _subscription?.cancel();
        
        // Pulisci la risposta
        List<String> lines = response.split(RegExp(r'[\r\n]'));
        for (String line in lines) {
          line = line.trim();
          if (line.isNotEmpty && !line.startsWith('#')) {
            if (!completer.isCompleted) {
              print('📥 Cleaned response: "$line"');
              completer.complete(line);
            }
            return;
          }
        }
        
        // Se non troviamo righe valide ma abbiamo dati, restituisci la risposta grezza
        if (!completer.isCompleted && response.trim().isNotEmpty) {
          String cleanResponse = response.trim().replaceAll(RegExp(r'[\r\n]'), '');
          print('📥 Fallback response: "$cleanResponse"');
          completer.complete(cleanResponse);
        }
      }
    });

    return completer.future;
  }

  // NUOVO: Metodo per inviare comandi raw (usato dal SaberProtocolService)
  Future<void> sendRawCommand(String command) async {
    await _sendCommand(command);
  }

  // NUOVO: Metodo per leggere risposta raw (usato dal SaberProtocolService)
  Future<String> readRawResponse() async {
    return await _readLine();
  }

  // Utility methods
  bool _isAnimaDevice(UsbDevice device) {
    return animaDevices.any((anima) =>
        device.vid == anima['vid'] && device.pid == anima['pid']);
  }

  SaberType _getSaberType(UsbDevice device) {
    if (device.vid == 0x16C0 && device.pid == 0x0483) {
      return SaberType.animaEVO;
    } else if (device.vid == 0x0483 && device.pid == 0x5740) {
      return SaberType.animaNXT;
    }
    return SaberType.unknown;
  }

  String _generateSaberName(UsbDevice device, SaberType type) {
    String baseName = type == SaberType.animaEVO ? 'Anima EVO' : 'Anima NXT';
    return '$baseName (${device.deviceId})';
  }

  void _updateStatus(String status) {
    print('📱 Status: $status');
    _statusController.add(status);
  }

  // Cleanup
  void dispose() {
    disconnect();
    _devicesController.close();
    _statusController.close();
  }
}