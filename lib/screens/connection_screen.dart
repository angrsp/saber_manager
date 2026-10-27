import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/saber_device.dart';
import '../services/bluetooth_access.dart';
import '../services/saber_connection_service.dart';

// Ricerca e connessione del bridge. Stati: cerco, bridge trovati, connesso senza spada, pronto.
// Quando la spada è pronta torna alla home.
class ConnectionScreen extends StatefulWidget {
  const ConnectionScreen({super.key});

  @override
  State<ConnectionScreen> createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends State<ConnectionScreen> {
  late final SaberConnectionService _service;
  String? _selectedId;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _service = context.read<SaberConnectionService>();
    _service.addListener(_onServiceChanged);
    if (_service.phase == ConnectionPhase.idle) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _service.scan();
      });
    }
  }

  @override
  void dispose() {
    _service.removeListener(_onServiceChanged);
    // Uscendo durante la ricerca la si ferma; dopo, perché l'albero dei widget qui è bloccato
    Future.microtask(_service.stopScan);
    super.dispose();
  }

  void _onServiceChanged() {
    if (_service.isConnected && !_closing && mounted) {
      _closing = true;
      Navigator.of(context).pop();
    }
  }

  Future<void> _connect(SaberDevice bridge) async {
    setState(() => _selectedId = bridge.id);
    await _service.connect(bridge);
    if (mounted) setState(() => _selectedId = null);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<SaberConnectionService>(
      builder: (context, service, child) {
        final phase = service.phase;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Connect Saber'),
            backgroundColor: Colors.deepPurple,
            foregroundColor: Colors.white,
            actions: [
              if (phase == ConnectionPhase.scanning)
                IconButton(
                  icon: const Icon(Icons.stop),
                  tooltip: 'Stop',
                  onPressed: service.stopScan,
                )
              else
                IconButton(
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Scan',
                  onPressed: phase == ConnectionPhase.idle ? service.scan : null,
                ),
            ],
            bottom: phase == ConnectionPhase.scanning || phase == ConnectionPhase.connecting
                ? const PreferredSize(
                    preferredSize: Size.fromHeight(4),
                    child: LinearProgressIndicator(),
                  )
                : null,
          ),
          body: service.isBridgeConnected ? _buildBridgeConnected(service) : _buildSearch(service),
        );
      },
    );
  }

  // Ricerca e lista dei bridge
  Widget _buildSearch(SaberConnectionService service) {
    final phase = service.phase;
    final error = service.error;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (error != null && phase == ConnectionPhase.idle) _buildErrorBanner(service, error),
        Expanded(
          child: service.devices.isEmpty
              ? _buildEmpty(service)
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: service.devices.length,
                  itemBuilder: (context, index) => _buildDeviceTile(service, service.devices[index]),
                ),
        ),
      ],
    );
  }

  Widget _buildDeviceTile(SaberConnectionService service, SaberDevice bridge) {
    final connecting = service.phase == ConnectionPhase.connecting && _selectedId == bridge.id;
    final canConnect = service.phase == ConnectionPhase.idle || service.phase == ConnectionPhase.scanning;
    return Card(
      child: ListTile(
        leading: Icon(_signalIcon(bridge.rssi), color: Colors.deepPurple, size: 32),
        title: Text(bridge.name),
        subtitle: Text(bridge.rssi != null ? '${bridge.rssi} dBm · ${bridge.id}' : bridge.id),
        trailing: connecting
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.arrow_forward_ios),
        onTap: canConnect ? () => _connect(bridge) : null,
      ),
    );
  }

  Widget _buildEmpty(SaberConnectionService service) {
    final scanning = service.phase == ConnectionPhase.scanning;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              scanning ? Icons.bluetooth_searching : Icons.bluetooth_disabled,
              size: 64,
              color: Colors.grey,
            ),
            const SizedBox(height: 16),
            Text(
              scanning ? 'Scanning for SaberBridge...' : 'No SaberBridge found',
              style: const TextStyle(fontSize: 18),
            ),
            const SizedBox(height: 8),
            Text(
              'Make sure the SaberBridge is powered on and close to the phone',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[600]),
            ),
            if (!scanning) ...[
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: service.phase == ConnectionPhase.idle ? service.scan : null,
                icon: const Icon(Icons.refresh),
                label: const Text('Scan Again'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildErrorBanner(SaberConnectionService service, String error) {
    final needsSettings = service.readiness == BluetoothReadiness.permissionPermanentlyDenied;
    return MaterialBanner(
      content: Text(error),
      leading: const Icon(Icons.error_outline, color: Colors.red),
      actions: [
        if (needsSettings)
          TextButton(
            onPressed: service.openSettings,
            child: const Text('Settings'),
          ),
        TextButton(
          onPressed: service.clearError,
          child: const Text('Dismiss'),
        ),
      ],
    );
  }

  // Bridge connesso: si aspetta la spada o si legge
  Widget _buildBridgeConnected(SaberConnectionService service) {
    final handshaking = service.phase == ConnectionPhase.handshaking || service.phase == ConnectionPhase.ready;
    final error = service.error;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.bluetooth_connected, size: 64, color: Colors.deepPurple),
            const SizedBox(height: 16),
            Text(
              '${service.bridge?.name ?? 'Bridge'} connected',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            if (handshaking) ...[
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              const Text('Saber found, reading info...'),
            ] else ...[
              Icon(
                error != null ? Icons.error_outline : Icons.power_settings_new,
                size: 40,
                color: error != null ? Colors.red : Colors.orange,
              ),
              const SizedBox(height: 12),
              Text(
                error ?? 'Turn on the saber',
                style: const TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 8),
              Text(
                error != null
                    ? 'Check that the saber is on and plugged into the bridge'
                    : 'The connection starts by itself when the saber is on',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[600]),
              ),
              if (error != null) ...[
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: service.retryHandshake,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              ],
            ],
            const SizedBox(height: 32),
            OutlinedButton.icon(
              onPressed: service.disconnect,
              icon: const Icon(Icons.bluetooth_disabled),
              label: const Text('Disconnect bridge'),
            ),
          ],
        ),
      ),
    );
  }

  static IconData _signalIcon(int? rssi) {
    if (rssi == null) return Icons.bluetooth;
    if (rssi >= -60) return Icons.signal_cellular_alt;
    if (rssi >= -80) return Icons.signal_cellular_alt_2_bar;
    return Icons.signal_cellular_alt_1_bar;
  }
}
