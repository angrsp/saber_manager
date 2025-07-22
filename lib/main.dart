import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/usb_service.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppState()),
        Provider(create: (_) => USBService()),
      ],
      child: MaterialApp(
        title: 'Saber Manager',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          primarySwatch: Colors.deepPurple,
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.deepPurple,
            brightness: Brightness.light,
          ),
        ),
        home: HomeScreen(),
      ),
    );
  }
}

class AppState extends ChangeNotifier {
  SaberDevice? _connectedSaber;
  List<SaberDevice> _availableSabers = [];
  bool _isScanning = false;
  bool _isConnecting = false;
  String _statusMessage = 'Ready to scan for sabers';

  // Getters
  SaberDevice? get connectedSaber => _connectedSaber;
  List<SaberDevice> get availableSabers => _availableSabers;
  bool get isScanning => _isScanning;
  bool get isConnecting => _isConnecting;
  String get statusMessage => _statusMessage;
  bool get isConnected => _connectedSaber?.isConnected ?? false;

  // Setters
  void setConnectedSaber(SaberDevice? saber) {
    _connectedSaber = saber;
    notifyListeners();
  }

  void setAvailableSabers(List<SaberDevice> sabers) {
    _availableSabers = sabers;
    notifyListeners();
  }

  void setScanning(bool scanning) {
    _isScanning = scanning;
    notifyListeners();
  }

  void setConnecting(bool connecting) {
    _isConnecting = connecting;
    notifyListeners();
  }

  void setStatusMessage(String message) {
    _statusMessage = message;
    notifyListeners();
  }

  void disconnect() {
    _connectedSaber = null;
    setStatusMessage('Disconnected');
    notifyListeners();
  }
}

class HomeScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Saber Manager'),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
      ),
      body: Consumer<AppState>(
        builder: (context, appState, child) {
          return Column(
            children: [
              // Status Card
              Container(
                margin: EdgeInsets.all(16),
                child: Card(
                  elevation: 4,
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Icon(
                              appState.isConnected ? Icons.flash_on : Icons.flash_off,
                              color: appState.isConnected ? Colors.green : Colors.grey,
                              size: 32,
                            ),
                            SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    appState.isConnected ? 'Connected' : 'Not Connected',
                                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: appState.isConnected ? Colors.green : Colors.grey,
                                    ),
                                  ),
                                  if (appState.connectedSaber != null)
                                    Text(
                                      appState.connectedSaber!.name,
                                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  Text(
                                    appState.statusMessage,
                                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (appState.isScanning || appState.isConnecting)
                              SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                          ],
                        ),
                        
                        // Device Info
                        if (appState.connectedSaber != null) ...[
                          SizedBox(height: 12),
                          Divider(),
                          SizedBox(height: 8),
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
                  padding: EdgeInsets.all(16),
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
                        onTap: () => _showFeatureDialog(context, 'Manage Colors'),
                      ),
                      _buildActionCard(
                        context,
                        appState,
                        title: 'Update Firmware',
                        icon: Icons.system_update,
                        color: Colors.red,
                        enabled: appState.isConnected,
                        onTap: () => _showFeatureDialog(context, 'Update Firmware'),
                      ),
                    ],
                  ),
                ),
              ),
              
              // Info Message
              Container(
                width: double.infinity,
                padding: EdgeInsets.all(16),
                child: Text(
                  '🚀 Sprint 1: USB Communication\n\n'
                  '✅ Real USB OTG scanning\n'
                  '✅ OpenCore device detection\n'
                  '✅ Serial communication protocol\n'
                  '⏳ Next: File upload & management',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.grey[600],
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
      padding: EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.grey[600]),
          SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w500,
              color: Colors.grey[600],
            ),
          ),
          SizedBox(width: 4),
          Expanded(
            child: Text(
              value,
              style: TextStyle(fontWeight: FontWeight.bold),
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
    bool enabled = true,
  }) {
    return Card(
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 48,
                color: enabled ? color : Colors.grey,
              ),
              SizedBox(height: 12),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: enabled ? null : Colors.grey,
                  fontWeight: FontWeight.bold,
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
      _disconnect(context, appState);
    } else {
      _showConnectionScreen(context);
    }
  }

  void _disconnect(BuildContext context, AppState appState) async {
    USBService usbService = Provider.of<USBService>(context, listen: false);
    await usbService.disconnect();
    appState.disconnect();
  }

  void _showConnectionScreen(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ConnectionScreen()),
    );
  }

  void _showFeatureDialog(BuildContext context, String feature) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.construction, color: Colors.orange),
            SizedBox(width: 8),
            Text(feature),
          ],
        ),
        content: Text(
          'This feature will be implemented in Sprint 2-4!\n\n'
          '🎯 Current: USB Communication ✅\n'
          '🔜 Next Sprint: File Management\n'
          '🔜 Sprint 3: Color Management\n'
          '🔜 Sprint 4: Firmware Updates',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Got it!'),
          ),
        ],
      ),
    );
  }
}

// Connection Screen per gestire scan e connessione
class ConnectionScreen extends StatefulWidget {
  @override
  _ConnectionScreenState createState() => _ConnectionScreenState();
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
      SaberDevice? connectedDevice = await usbService.connectToSaber(saber);
      
      if (connectedDevice != null) {
        appState.setConnectedSaber(connectedDevice);
        Navigator.pop(context);
      } else {
        throw Exception('Connection failed');
      }
    } catch (e) {
      appState.setStatusMessage('Connection failed: $e');
      _showErrorDialog('Failed to connect: $e');
    } finally {
      appState.setConnecting(false);
    }
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Error'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Connect Saber'),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            onPressed: _scanForSabers,
            icon: Icon(Icons.refresh),
          ),
        ],
      ),
      body: Consumer<AppState>(
        builder: (context, appState, child) {
          if (appState.isScanning || appState.isConnecting) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 24),
                  Text(
                    appState.isScanning ? 'Scanning for sabers...' : 'Connecting...',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  SizedBox(height: 8),
                  Text(
                    appState.statusMessage,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.grey[600],
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          }

          if (appState.availableSabers.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.search_off, size: 80, color: Colors.grey),
                  SizedBox(height: 24),
                  Text(
                    'No sabers found',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Make sure your OpenCore lightsaber is:\n• Connected via USB OTG cable\n• Powered on and fully booted\n• Compatible (Anima EVO/NXT)',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.grey[600],
                    ),
                  ),
                  SizedBox(height: 32),
                  ElevatedButton.icon(
                    onPressed: _scanForSabers,
                    icon: Icon(Icons.refresh),
                    label: Text('Scan Again'),
                  ),
                ],
              ),
            );
          }

          return Column(
            children: [
              Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Found ${appState.availableSabers.length} compatible saber(s)',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: EdgeInsets.all(16),
                  itemCount: appState.availableSabers.length,
                  itemBuilder: (context, index) {
                    SaberDevice saber = appState.availableSabers[index];
                    return Card(
                      child: ListTile(
                        leading: Icon(
                          Icons.flash_on,
                          color: saber.type == SaberType.animaEVO 
                              ? Colors.blue 
                              : Colors.green,
                          size: 32,
                        ),
                        title: Text(saber.name),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Type: ${saber.type == SaberType.animaEVO ? "Anima EVO" : "Anima NXT"}'),
                            Text('Device ID: ${saber.usbDevice.deviceId}'),
                            Text('VID/PID: ${saber.usbDevice.vid?.toRadixString(16).toUpperCase()}/${saber.usbDevice.pid?.toRadixString(16).toUpperCase()}'),
                          ],
                        ),
                        trailing: Icon(Icons.arrow_forward_ios),
                        onTap: () => _connectToSaber(saber),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}