import 'dart:async';
import 'dart:typed_data';
import 'package:usb_serial/usb_serial.dart';
import 'package:permission_handler/permission_handler.dart';

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
  static const int BAUD_RATE = 1152000;
  static const int CHUNK_SIZE = 128;
  static const Duration READ_TIMEOUT = Duration(seconds: 3);
  static const Duration CHUNK_DELAY = Duration(milliseconds: 500);

  // OpenCore Device IDs (convertiti da hex a decimale)
  static const List<Map<String, int>> ANIMA_DEVICES = [
    {'vid': 0x16C0, 'pid': 0x0483}, // Anima EVO
    {'vid': 0x0483, 'pid': 0x5740}, // Anima NXT
  ];

  UsbPort? _port;
  StreamSubscription<Uint8List>? _subscription; // Corretto: Uint8List invece di String
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
      print('❌ Scan error: $e');
      return [];
    }
  }

  // Connetti a un saber specifico
  Future<SaberDevice?> connectToSaber(SaberDevice saber) async {
    try {
      _updateStatus('Connecting to ${saber.name}...');
      
      // Disconnetti se già connesso
      if (isConnected) {
        await disconnect();
      }

      // Crea connessione USB
      _port = await saber.usbDevice.create();
      if (_port == null) {
        throw SaberException('Failed to create USB port');
      }

      // Apri la porta
      bool opened = await _port!.open();
      if (!opened) {
        throw SaberException('Failed to open USB port');
      }

      // Configura parametri seriali
      await _port!.setDTR(true);
      await _port!.setRTS(true);
      await _port!.setPortParameters(
        BAUD_RATE,
        UsbPort.DATABITS_8,
        UsbPort.STOPBITS_1,
        UsbPort.PARITY_NONE,
      );

      print('🔧 USB port configured: $BAUD_RATE baud');

      // Test connessione con comando ready
      if (await _isReady()) {
        _updateStatus('Testing saber communication...');
        
        // Ottieni info dal saber
        Map<String, String> info = await _getSaberInfo();
        
        _connectedDevice = saber.copyWith(
          isConnected: true,
          firmwareVersion: info['version'],
          serialNumber: info['serial'],
        );

        _updateStatus('Connected to ${saber.name}');
        
        print('🎉 Successfully connected to ${saber.name}');
        print('   Firmware: ${info['version']}');
        print('   Serial: ${info['serial']}');
        
        return _connectedDevice;
      } else {
        await disconnect();
        throw SaberException('Saber not responding - try restarting it');
      }
    } catch (e) {
      _updateStatus('Connection failed: $e');
      print('❌ Connection error: $e');
      await disconnect();
      return null;
    }
  }

  // Disconnetti
  Future<void> disconnect() async {
    try {
      _subscription?.cancel();
      await _port?.close();
      _port = null;
      _connectedDevice = null;
      _updateStatus('Disconnected');
      print('🔌 Disconnected from saber');
    } catch (e) {
      print('❌ Disconnect error: $e');
    }
  }

  // Test se il saber è pronto a ricevere comandi
  Future<bool> _isReady() async {
    try {
      await _sendCommand('WR?');
      String response = await _readLine();
      print('📡 Ready check response: $response');
      return response.trim() == 'OK, Write Ready';
    } catch (e) {
      print('❌ Ready check failed: $e');
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
      if (versionResponse.startsWith('V=')) {
        info['version'] = versionResponse.substring(2).trim();
      }

      // Numero seriale
      await _sendCommand('S?');
      String serialResponse = await _readLine();
      if (serialResponse.startsWith('S=')) {
        info['serial'] = serialResponse.substring(2).trim();
      }
    } catch (e) {
      print('❌ Error getting saber info: $e');
    }

    return info;
  }

  // Invia comando al saber
  Future<void> _sendCommand(String cmd) async {
    if (_port == null) throw SaberException('Not connected');

    List<int> data = '$cmd\n'.codeUnits;
    print('📤 Sending: $cmd');

    if (data.length <= CHUNK_SIZE) {
      await _port!.write(Uint8List.fromList(data));
    } else {
      // Invia a chunk per evitare buffer overflow
      for (int i = 0; i < data.length; i += CHUNK_SIZE) {
        int end = (i + CHUNK_SIZE > data.length) ? data.length : i + CHUNK_SIZE;
        await _port!.write(Uint8List.fromList(data.sublist(i, end)));

        if (end < data.length) {
          await Future.delayed(CHUNK_DELAY);
        }
      }
    }
  }

  // Leggi risposta dal saber
  Future<String> _readLine() async {
    if (_port == null) throw SaberException('Not connected');

    String response = '';
    Completer<String> completer = Completer();
    Timer? timeout;

    timeout = Timer(READ_TIMEOUT, () {
      if (!completer.isCompleted) {
        completer.completeError(ConnectionTimeoutException());
      }
    });

    // CORRETTO: Usa Uint8List e converti a String
    _subscription = _port!.inputStream?.listen((Uint8List data) {
      String dataString = String.fromCharCodes(data); // Conversione Uint8List -> String
      response += dataString;
      
      if (response.contains('\n')) {
        timeout?.cancel();
        _subscription?.cancel();
        
        // Filtra messaggi di debug che iniziano con '#'
        List<String> lines = response.split('\n');
        for (String line in lines) {
          line = line.trim();
          if (line.isNotEmpty && !line.startsWith('#')) {
            if (!completer.isCompleted) {
              print('📥 Received: $line');
              completer.complete(line);
            }
            return;
          }
        }
      }
    });

    return completer.future;
  }

  // Utility methods
  bool _isAnimaDevice(UsbDevice device) {
    return ANIMA_DEVICES.any((anima) =>
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