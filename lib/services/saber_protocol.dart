import 'dart:typed_data';
import 'package:usb_serial/usb_serial.dart';
import '../models/color_config.dart';  
import 'usb_service.dart';

class SaberProtocolService {
  USBService? _usbService;
  
  // Imposta il servizio USB
  void setUSBService(USBService usbService) {
    _usbService = usbService;
  }

  // Verifica se la connessione è attiva
  bool get isConnected => _usbService?.isConnected ?? false;

  // ============ COMANDI COLORI ============
  
  /// Preview di un colore sulla lightsaber
  /// Comando: P=r,g,b,w
  Future<bool> previewColor(RGBWColor color) async {
    if (_usbService == null || !_usbService!.isConnected) return false;
    
    try {
      final command = 'P=${color.red},${color.green},${color.blue},${color.white}';
      
      await _usbService!.sendRawCommand(command);
      
      // Leggi la risposta
      final response = await _usbService!.readRawResponse();
      return response.startsWith('OK');
      
    } catch (e) {
      print('Error previewing color: $e');
      return false;
    }
  }

  /// Imposta il colore per un specifico bank ed effetto
  /// Comandi: C{bank}=r,g,b,w (main), F{bank}=r,g,b,w (clash), W{bank}=r,g,b,w (swing)
  Future<bool> setColor(int bank, ColorEffect effect, RGBWColor color) async {
    if (_usbService == null || !_usbService!.isConnected) return false;
    
    try {
      String commandPrefix;
      switch (effect) {
        case ColorEffect.main:
          commandPrefix = 'C';
          break;
        case ColorEffect.clash:
          commandPrefix = 'F';
          break;
        case ColorEffect.swing:
          commandPrefix = 'W';
          break;
      }
      
      final command = '$commandPrefix$bank=${color.red},${color.green},${color.blue},${color.white}';
      
      await _usbService!.sendRawCommand(command);
      
      // Leggi la risposta
      final response = await _usbService!.readRawResponse();
      if (response.startsWith('OK')) {
        // Salva la configurazione
        await _saveConfig();
        return true;
      }
      return false;
      
    } catch (e) {
      print('Error setting color: $e');
      return false;
    }
  }

  /// Imposta il bank attivo
  /// Comando: B=bank
  Future<bool> setActiveBank(int bank) async {
    if (_usbService == null || !_usbService!.isConnected) return false;
    
    try {
      final command = 'B=$bank';
      
      await _usbService!.sendRawCommand(command);
      
      // Leggi la risposta
      final response = await _usbService!.readRawResponse();
      if (response.startsWith('OK')) {
        // Salva la configurazione
        await _saveConfig();
        return true;
      }
      return false;
      
    } catch (e) {
      print('Error setting active bank: $e');
      return false;
    }
  }

  /// Salva l'intero bank di colori
  Future<bool> saveColorBank(int bankIndex, ColorBank bank, {bool setActive = true}) async {
    if (_usbService == null || !_usbService!.isConnected) return false;
    
    try {
      // Imposta tutti e tre i colori del bank
      bool success = true;
      
      success &= await setColor(bankIndex, ColorEffect.main, bank.mainColor);
      success &= await setColor(bankIndex, ColorEffect.clash, bank.clashColor);
      success &= await setColor(bankIndex, ColorEffect.swing, bank.swingColor);
      
      // Opzionalmente imposta come bank attivo
      if (setActive && success) {
        success &= await setActiveBank(bankIndex);
      }
      
      return success;
      
    } catch (e) {
      print('Error saving color bank: $e');
      return false;
    }
  }

  /// Salva tutti i color banks
  Future<bool> saveAllColorBanks(ColorConfiguration config) async {
    if (_usbService == null || !_usbService!.isConnected) return false;
    
    try {
      bool success = true;
      
      // Salva tutti i banks (senza impostare come attivo)
      for (int i = 0; i < config.banks.length; i++) {
        success &= await saveColorBank(i, config.banks[i], setActive: false);
        
        // Piccola pausa tra i banks per non sovraccaricare la saber
        await Future.delayed(const Duration(milliseconds: 500));
      }
      
      // Imposta il bank attivo alla fine
      if (success) {
        success &= await setActiveBank(config.activeBank);
      }
      
      return success;
      
    } catch (e) {
      print('Error saving all color banks: $e');
      return false;
    }
  }

  // ============ LETTURA CONFIGURAZIONE ============
  
  /// Legge la configurazione corrente dalla saber
  /// Questo richiederà l'implementazione dei comandi di lettura
  Future<ColorConfiguration?> readConfiguration() async {
    if (_usbService == null || !_usbService!.isConnected) return null;
    
    try {
      // TODO: Implementare i comandi di lettura della configurazione
      // Per ora ritorna una configurazione di default
      // I comandi specifici dipendono dalla versione del firmware OpenCore
      
      return ColorConfiguration();
      
    } catch (e) {
      print('Error reading configuration: $e');
      return null;
    }
  }

  /// Legge le informazioni del firmware
  /// Comando: V? (versione)
  Future<String?> getFirmwareVersion() async {
    if (_usbService == null || !_usbService!.isConnected) return null;
    
    try {
      await _usbService!.sendRawCommand('V?');
      
      final response = await _usbService!.readRawResponse();
      if (response.isNotEmpty) {
        return response.trim();
      }
      return null;
      
    } catch (e) {
      print('Error getting firmware version: $e');
      return null;
    }
  }

  /// Legge il numero seriale
  /// Comando: S? (seriale)
  Future<String?> getSerialNumber() async {
    if (_usbService == null || !_usbService!.isConnected) return null;
    
    try {
      await _usbService!.sendRawCommand('S?');
      
      final response = await _usbService!.readRawResponse();
      if (response.isNotEmpty) {
        return response.trim();
      }
      return null;
      
    } catch (e) {
      print('Error getting serial number: $e');
      return null;
    }
  }

  // ============ METODI PRIVATI ============
  
  /// Salva la configurazione sulla saber
  /// Comando: S (save)
  Future<bool> _saveConfig() async {
    if (_usbService == null || !_usbService!.isConnected) return false;
    
    try {
      await _usbService!.sendRawCommand('S');
      
      final response = await _usbService!.readRawResponse();
      return response.startsWith('OK');
      
    } catch (e) {
      print('Error saving config: $e');
      return false;
    }
  }

  /// Invia un comando generico e legge la risposta
  Future<String> sendCommand(String command) async {
    if (_usbService == null || !_usbService!.isConnected) return '';
    
    try {
      await _usbService!.sendRawCommand(command);
      return await _usbService!.readRawResponse();
      
    } catch (e) {
      print('Error sending command: $e');
      return '';
    }
  }

  /// Chiude la connessione
  void disconnect() {
    _usbService = null;
  }
}

/// Classe per gestire le operazioni sui colori con progress tracking
class ColorOperationProgress {
  final int totalOperations;
  int completedOperations;
  String currentOperation;
  bool isCompleted;

  ColorOperationProgress({
    required this.totalOperations,
    this.completedOperations = 0,
    this.currentOperation = '',
    this.isCompleted = false,
  });

  double get progress => totalOperations > 0 ? completedOperations / totalOperations : 0.0;
  
  void updateProgress(String operation) {
    currentOperation = operation;
    completedOperations++;
    isCompleted = completedOperations >= totalOperations;
  }
}

/// Estensione del SaberProtocolService con progress tracking
extension SaberProtocolProgressExtension on SaberProtocolService {
  
  /// Salva tutti i color banks con progress tracking
  Future<bool> saveAllColorBanksWithProgress(
    ColorConfiguration config,
    void Function(ColorOperationProgress) onProgress,
  ) async {
    final progress = ColorOperationProgress(
      totalOperations: config.banks.length * 3 + 1, // 3 colori per bank + set active bank
    );
    
    onProgress(progress);
    
    try {
      bool success = true;
      
      // Salva tutti i banks
      for (int i = 0; i < config.banks.length; i++) {
        final bank = config.banks[i];
        
        // Main color
        progress.updateProgress('Saving bank ${i + 1} main color');
        onProgress(progress);
        success &= await setColor(i, ColorEffect.main, bank.mainColor);
        
        // Clash color
        progress.updateProgress('Saving bank ${i + 1} clash color');
        onProgress(progress);
        success &= await setColor(i, ColorEffect.clash, bank.clashColor);
        
        // Swing color
        progress.updateProgress('Saving bank ${i + 1} swing color');
        onProgress(progress);
        success &= await setColor(i, ColorEffect.swing, bank.swingColor);
        
        // Pausa tra i banks
        await Future.delayed(const Duration(milliseconds: 300));
      }
      
      // Imposta il bank attivo
      if (success) {
        progress.updateProgress('Setting active bank');
        onProgress(progress);
        success &= await setActiveBank(config.activeBank);
      }
      
      return success;
      
    } catch (e) {
      print('Error in saveAllColorBanksWithProgress: $e');
      return false;
    }
  }
}