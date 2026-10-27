import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/bridge_status.dart';
import '../models/saber_device.dart';
import '../services/saber_connection_service.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  static const String notViaBle = 'Not available via BLE';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Saber Manager'),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
      ),
      body: Consumer<SaberConnectionService>(
        builder: (context, service, child) {
          final saber = service.saber;
          return Column(
            children: [
              // Status Card
              Container(
                margin: const EdgeInsets.all(16),
                child: Card(
                  elevation: 4,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Icon(
                              _statusIcon(service),
                              color: _statusColor(service),
                              size: 32,
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Status',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                  Text(
                                    _statusTitle(service),
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: _statusColor(service),
                                    ),
                                  ),
                                  Text(
                                    service.statusMessage,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),

                        // Informazioni su bridge e spada
                        if (service.isBridgeConnected) ...[
                          const Divider(height: 32),
                          _buildInfoRow(
                            'Bridge:',
                            [
                              service.bridge?.name ?? 'SaberBridge',
                              if (service.bridgeFirmware != null) service.bridgeFirmware!,
                            ].join(' '),
                            Icons.bluetooth_connected,
                          ),
                          if (_batteryText(service.bridgeStatus) != null)
                            _buildInfoRow(
                              'Battery:',
                              _batteryText(service.bridgeStatus)!,
                              service.bridgeStatus!.batteryLow ? Icons.battery_alert : Icons.battery_std,
                            ),
                        ],
                        if (saber != null) ...[
                          _buildInfoRow(
                            'Type:',
                            _typeName(saber.type),
                            Icons.category,
                          ),
                          if (saber.firmwareVersion != null)
                            _buildInfoRow(
                              'Firmware:',
                              saber.firmwareVersion!,
                              Icons.memory,
                            ),
                          if (saber.serialNumber != null)
                            _buildInfoRow(
                              'Serial:',
                              saber.serialNumber!,
                              Icons.tag,
                            ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),

              // Action Grid
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: GridView.count(
                    crossAxisCount: 2,
                    mainAxisSpacing: 16,
                    crossAxisSpacing: 16,
                    children: [
                      _buildActionCard(
                        context,
                        title: service.isBridgeConnected ? 'Disconnect' : 'Connect Saber',
                        icon: service.isBridgeConnected ? Icons.bluetooth_disabled : Icons.bluetooth_searching,
                        color: service.isBridgeConnected ? Colors.orange : Colors.blue,
                        onTap: () => _handleConnection(context, service),
                        enabled: service.phase != ConnectionPhase.connecting,
                      ),
                      // File, suoni e firmware passano dal disco USB della spada: non via BLE
                      _buildActionCard(
                        context,
                        title: 'Upload Files',
                        subtitle: notViaBle,
                        icon: Icons.audiotrack,
                        color: Colors.green,
                        enabled: false,
                        onTap: () {},
                      ),
                      _buildActionCard(
                        context,
                        title: 'Manage Colors',
                        icon: Icons.palette,
                        color: Colors.purple,
                        enabled: service.isConnected,
                        onTap: () => Navigator.pushNamed(context, '/colors'),
                      ),
                      _buildActionCard(
                        context,
                        title: 'Sound Effects',
                        subtitle: notViaBle,
                        icon: Icons.music_note,
                        color: Colors.indigo,
                        enabled: false,
                        onTap: () {},
                      ),
                      _buildActionCard(
                        context,
                        title: 'Firmware Update',
                        subtitle: notViaBle,
                        icon: Icons.system_update,
                        color: Colors.red,
                        enabled: false,
                        onTap: () {},
                      ),
                      _buildActionCard(
                        context,
                        title: 'Settings',
                        icon: Icons.settings,
                        color: Colors.grey,
                        enabled: true,
                        onTap: () => _showFeatureDialog(context, 'Settings'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.grey[600]),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionCard(
    BuildContext context, {
    required String title,
    String? subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    required bool enabled,
  }) {
    return Card(
      elevation: enabled ? 4 : 2,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: enabled ? null : Colors.grey[100],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 40,
                color: enabled ? color : Colors.grey,
              ),
              const SizedBox(height: 12),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: enabled ? Colors.black87 : Colors.grey,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _handleConnection(BuildContext context, SaberConnectionService service) {
    if (service.isBridgeConnected) {
      service.disconnect();
    } else {
      Navigator.pushNamed(context, '/connection');
    }
  }

  static IconData _statusIcon(SaberConnectionService service) {
    if (service.isConnected) return Icons.flash_on;
    if (service.isBridgeConnected) return Icons.bluetooth_connected;
    return Icons.flash_off;
  }

  static Color _statusColor(SaberConnectionService service) {
    if (service.isConnected) return Colors.green;
    if (service.isBridgeConnected) return Colors.orange;
    return Colors.red;
  }

  static String _statusTitle(SaberConnectionService service) {
    switch (service.phase) {
      case ConnectionPhase.ready:
        return 'Connected';
      case ConnectionPhase.waitingForSaber:
        return 'Saber not connected';
      case ConnectionPhase.connecting:
      case ConnectionPhase.handshaking:
        return 'Connecting...';
      case ConnectionPhase.idle:
      case ConnectionPhase.scanning:
        return 'Disconnected';
    }
  }

  // Tensione della batteria del bridge; null se non misurata
  static String? _batteryText(BridgeStatus? status) {
    if (status == null || status.batteryMv == 0) return null;
    final volts = (status.batteryMv / 1000).toStringAsFixed(2);
    return status.batteryLow ? '$volts V (low)' : '$volts V';
  }

  String _typeName(SaberType type) {
    switch (type) {
      case SaberType.animaEVO:
        return 'Anima EVO';
      case SaberType.animaNXT:
        return 'Anima NXT';
      case SaberType.unknown:
        return 'Unknown';
    }
  }

  void _showFeatureDialog(BuildContext context, String feature) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(feature),
        content: Text('$feature feature will be implemented in future versions.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}
