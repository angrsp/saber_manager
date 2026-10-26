import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app_state.dart';
import '../models/saber_device.dart';
import '../services/usb_service.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Saber Manager'),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
      ),
      body: Consumer<AppState>(
        builder: (context, appState, child) {
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
                              appState.isConnected ? Icons.flash_on : Icons.flash_off,
                              color: appState.isConnected ? Colors.green : Colors.grey,
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
                                    appState.isConnected ? 'Connected' : 'Disconnected',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: appState.isConnected ? Colors.green : Colors.red,
                                    ),
                                  ),
                                  Text(
                                    appState.statusMessage,
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
                        
                        // Informazioni saber se connesso
                        if (appState.isConnected && appState.connectedSaber != null) ...[
                          const Divider(height: 32),
                          _buildInfoRow(
                            'Device:', 
                            appState.connectedSaber!.name,
                            Icons.device_hub,
                          ),
                          _buildInfoRow(
                            'Type:', 
                            appState.connectedSaber!.type == SaberType.animaEVO ? 'Anima EVO' : 'Anima NXT',
                            Icons.category,
                          ),
                          if (appState.connectedSaber!.firmwareVersion != null)
                            _buildInfoRow(
                              'Firmware:', 
                              appState.connectedSaber!.firmwareVersion!,
                              Icons.memory,
                            ),
                          if (appState.connectedSaber!.serialNumber != null)
                            _buildInfoRow(
                              'Serial:', 
                              appState.connectedSaber!.serialNumber!,
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
                        appState,
                        title: appState.isConnected ? 'Disconnect' : 'Connect Saber',
                        icon: appState.isConnected ? Icons.usb_off : Icons.usb,
                        color: appState.isConnected ? Colors.orange : Colors.blue,
                        onTap: () => _handleConnection(context, appState),
                        enabled: !appState.isScanning && !appState.isConnecting,
                      ),
                      _buildActionCard(
                        context,
                        appState,
                        title: 'Upload Files',
                        icon: Icons.audiotrack,
                        color: Colors.green,
                        enabled: appState.isConnected,
                        onTap: () => _showFeatureDialog(context, 'Upload Files'),
                      ),
                      _buildActionCard(
                        context,
                        appState,
                        title: 'Manage Colors',
                        icon: Icons.palette,
                        color: Colors.purple,
                        enabled: appState.isConnected,
                        onTap: () => Navigator.pushNamed(context, '/colors'),
                      ),
                      _buildActionCard(
                        context,
                        appState,
                        title: 'Sound Effects',
                        icon: Icons.music_note,
                        color: Colors.indigo,
                        enabled: appState.isConnected,
                        onTap: () => _showFeatureDialog(context, 'Sound Effects'),
                      ),
                      _buildActionCard(
                        context,
                        appState,
                        title: 'Firmware Update',
                        icon: Icons.system_update,
                        color: Colors.red,
                        enabled: appState.isConnected,
                        onTap: () => _showFeatureDialog(context, 'Firmware Update'),
                      ),
                      _buildActionCard(
                        context,
                        appState,
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
    BuildContext context,
    AppState appState, {
    required String title,
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
            ],
          ),
        ),
      ),
    );
  }

  void _handleConnection(BuildContext context, AppState appState) {
    if (appState.isConnected) {
      _disconnectSaber(context, appState);
    } else {
      Navigator.pushNamed(context, '/connection');
    }
  }

  void _disconnectSaber(BuildContext context, AppState appState) {
    final usbService = Provider.of<USBService>(context, listen: false);
    usbService.disconnect();
    appState.disconnect();
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