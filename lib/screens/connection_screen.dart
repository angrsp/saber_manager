import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app_state.dart';
import '../models/saber_device.dart';
import '../services/usb_service.dart';

class ConnectionScreen extends StatefulWidget {
  const ConnectionScreen({super.key});

  @override
  State<ConnectionScreen> createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends State<ConnectionScreen> {
  @override
  void initState() {
    super.initState();
    _scanForSabers();
  }

  Future<void> _scanForSabers() async {
    AppState appState = Provider.of<AppState>(context, listen: false);
    USBService usbService = Provider.of<USBService>(context, listen: false);
    
    appState.setScanning(true);
    
    try {
      // Richiedi permessi prima
      bool permissionsGranted = await usbService.requestPermissions();
      if (!permissionsGranted) {
        throw Exception('USB permissions denied');
      }

      // Scan per dispositivi
      List<SaberDevice> sabers = await usbService.scanForSabers();
      appState.setAvailableSabers(sabers);
      
    } catch (e) {
      appState.setStatusMessage('Scan error: $e');
      _showErrorDialog('Scan failed: $e');
    } finally {
      appState.setScanning(false);
    }
  }

  Future<void> _connectToSaber(SaberDevice saber) async {
    AppState appState = Provider.of<AppState>(context, listen: false);
    USBService usbService = Provider.of<USBService>(context, listen: false);
    
    appState.setConnecting(true);
    
    try {
      SaberDevice? connectedSaber = await usbService.connectToDevice(saber);
      if (connectedSaber != null) {
        appState.setConnectedSaber(connectedSaber);
        appState.setStatusMessage('Connected to ${connectedSaber.name}');
        if (!mounted) return;
        Navigator.of(context).pop(); // Torna alla home
      } else {
        throw Exception('Failed to connect');
      }
    } catch (e) {
      appState.setStatusMessage('Connection error: $e');
      _showErrorDialog('Connection failed: $e');
    } finally {
      appState.setConnecting(false);
    }
  }

  void _showErrorDialog(String error) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Error'),
        content: Text(error),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Connect Saber'),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _scanForSabers,
          ),
        ],
      ),
      body: Consumer<AppState>(
        builder: (context, appState, child) {
          if (appState.isScanning) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Scanning for sabers...'),
                ],
              ),
            );
          }

          if (appState.availableSabers.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.device_unknown,
                    size: 64,
                    color: Colors.grey,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'No sabers found',
                    style: TextStyle(fontSize: 18),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Make sure your OpenCore lightsaber is connected via USB OTG',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: _scanForSabers,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Scan Again'),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: appState.availableSabers.length,
            itemBuilder: (context, index) {
              final saber = appState.availableSabers[index];
              return Card(
                child: ListTile(
                  leading: const Icon(
                    Icons.flash_on,
                    color: Colors.deepPurple,
                    size: 32,
                  ),
                  title: Text(saber.name),
                  subtitle: Text(saber.type.toString().split('.').last),
                  trailing: appState.isConnecting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.arrow_forward_ios),
                  onTap: appState.isConnecting ? null : () => _connectToSaber(saber),
                ),
              );
            },
          );
        },
      ),
    );
  }
}