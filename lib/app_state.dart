import 'package:flutter/material.dart';
import 'models/saber_device.dart';

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