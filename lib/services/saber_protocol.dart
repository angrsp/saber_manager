import 'package:flutter/foundation.dart';
import '../models/color_config.dart';
import '../models/saber_device.dart';
import '../models/saber_exceptions.dart';
import 'saber_link.dart';

// Protocollo OpenCore della spada (COMMS-PROTOCOL.md di polaris-opencore), sopra SaberLink.
// Le scritture di colori e bank non salvano: ogni operazione pubblica manda un solo SAVE alla fine.
class SaberProtocolService {
  SaberProtocolService(this._link, {this.timeout = SaberLink.defaultTimeout});

  final SaberLink _link;

  // Timeout di ogni richiesta (SAVE risponde in circa 300 ms, gli altri comandi in pochi ms)
  final Duration timeout;

  static const int bankCount = 8;

  // Verifica se la connessione è attiva
  bool get isConnected => _link.isConnected;

  // ============ CONNESSIONE ============

  /// Verifica che la spada risponda
  /// Comando: WR? → OK, Write Ready (un secondo tentativo dopo un timeout)
  Future<void> handshake() async {
    for (int attempt = 1; attempt <= 2; attempt++) {
      try {
        await _link.request('WR?', match: 'OK, Write Ready', timeout: timeout);
        return;
      } on ResponseTimeoutException {
        debugPrint('Handshake attempt $attempt: no response');
      }
    }
    throw SaberException('Saber not responding');
  }

  /// Legge la versione del firmware
  /// Comando: V? → V=NXT_1.1.0
  Future<String?> getFirmwareVersion() async {
    try {
      final response = await _link.request('V?', match: 'V=', timeout: timeout);
      return response.substring(2).trim();
    } catch (e) {
      debugPrint('Error getting firmware version: $e');
      return null;
    }
  }

  /// Legge il numero seriale
  /// Comando: S? → S=5f00303931501920383758
  Future<String?> getSerialNumber() async {
    try {
      final response = await _link.request('S?', match: 'S=', timeout: timeout);
      return response.substring(2).trim();
    } catch (e) {
      debugPrint('Error getting serial number: $e');
      return null;
    }
  }

  /// Tipo di spada dalla versione del firmware, come py2saber e Tintallë
  static SaberType typeFromVersion(String? version) {
    if (version != null && version.startsWith('NXT_')) return SaberType.animaNXT;
    return SaberType.unknown;
  }

  // ============ COMANDI COLORI ============

  /// Preview di un colore sulla lightsaber
  /// Comando: P=r,g,b,w → OK, P=r,g,b,w
  Future<bool> previewColor(RGBWColor color) async {
    try {
      await _expectEcho('P=${_formatColor(color)}', 'OK, ');
      return true;
    } catch (e) {
      debugPrint('Error previewing color: $e');
      return false;
    }
  }

  /// Spegne l'anteprima
  /// Comando: P=0 → OK, P=0
  Future<bool> stopPreview() async {
    try {
      await _expectEcho('P=0', 'OK, ');
      return true;
    } catch (e) {
      debugPrint('Error stopping preview: $e');
      return false;
    }
  }

  /// Imposta e salva il colore per un specifico bank ed effetto
  /// Comandi: C{bank}=r,g,b,w (main), F{bank}=r,g,b,w (clash), W{bank}=r,g,b,w (swing), poi SAVE
  Future<bool> setColor(int bank, ColorEffect effect, RGBWColor color) async {
    try {
      await _writeColor(bank, effect, color);
      await _saveConfig();
      return true;
    } catch (e) {
      debugPrint('Error setting color: $e');
      return false;
    }
  }

  /// Imposta e salva il bank attivo
  /// Comandi: B=bank, poi SAVE
  Future<bool> setActiveBank(int bank) async {
    try {
      await _writeActiveBank(bank);
      await _saveConfig();
      return true;
    } catch (e) {
      debugPrint('Error setting active bank: $e');
      return false;
    }
  }

  /// Salva l'intero bank di colori, con un solo SAVE
  Future<bool> saveColorBank(int bankIndex, ColorBank bank, {bool setActive = true}) async {
    try {
      for (final effect in ColorEffect.values) {
        await _writeColor(bankIndex, effect, bank.getColorForEffect(effect));
      }
      if (setActive) {
        await _writeActiveBank(bankIndex);
      }
      await _saveConfig();
      return true;
    } catch (e) {
      debugPrint('Error saving color bank: $e');
      return false;
    }
  }

  /// Salva tutti i color banks e il bank attivo, con un solo SAVE
  Future<bool> saveAllColorBanks(ColorConfiguration config) => saveAllColorBanksWithProgress(config, (_) {});

  /// Come saveAllColorBanks, con il progresso: 3 colori per bank, il bank attivo e SAVE
  Future<bool> saveAllColorBanksWithProgress(
    ColorConfiguration config,
    void Function(ColorOperationProgress) onProgress,
  ) async {
    final progress = ColorOperationProgress(
      totalOperations: config.banks.length * ColorEffect.values.length + 2,
    );
    onProgress(progress);

    try {
      for (int i = 0; i < config.banks.length; i++) {
        for (final effect in ColorEffect.values) {
          await _writeColor(i, effect, config.banks[i].getColorForEffect(effect));
          progress.updateProgress('Saving bank ${i + 1} ${effect.displayName.toLowerCase()} color');
          onProgress(progress);
        }
      }

      await _writeActiveBank(config.activeBank);
      progress.updateProgress('Setting active bank');
      onProgress(progress);

      await _saveConfig();
      progress.updateProgress('Saved');
      onProgress(progress);
      return true;
    } catch (e) {
      debugPrint('Error saving all color banks: $e');
      return false;
    }
  }

  // ============ LETTURA CONFIGURAZIONE ============

  /// Legge la configurazione corrente dalla saber
  /// Comandi: B? → B=x; c?, f?, w? → 8 righe cN=r,g,b,w ciascuno.
  /// Un comando che tace (firmware vecchio) lascia i suoi campi al default e finisce in unread.
  /// Restituisce null se la lettura fallisce per altri motivi (per esempio una disconnessione).
  Future<ConfigurationReadResult?> readConfiguration() async {
    final config = ColorConfiguration();
    final unread = <String>[];

    try {
      try {
        final response = await _link.request('B?', match: 'B=', timeout: timeout);
        config.setActiveBank(int.parse(response.substring(2).trim()));
      } on ResponseTimeoutException {
        unread.add('B?');
      }

      for (final effect in ColorEffect.values) {
        final command = '${_readLetter(effect)}?';
        try {
          final lines = await _link.requestLines(
            command,
            match: _readLetter(effect),
            lines: bankCount,
            timeout: timeout,
          );
          for (final line in lines) {
            final parsed = _parseColorLine(line);
            config.setColor(parsed.bank, effect, parsed.color);
          }
        } on ResponseTimeoutException {
          unread.add(command);
        }
      }

      return ConfigurationReadResult(config, unread);
    } catch (e) {
      debugPrint('Error reading configuration: $e');
      return null;
    }
  }

  // ============ METODI PRIVATI ============

  /// Scrive un colore senza salvare
  Future<void> _writeColor(int bank, ColorEffect effect, RGBWColor color) async {
    await _expectEcho('${_writeLetter(effect)}$bank=${_formatColor(color)}', 'OK ');
  }

  /// Imposta il bank attivo senza salvare
  Future<void> _writeActiveBank(int bank) async {
    await _expectEcho('B=$bank', 'OK ');
  }

  /// Salva la configurazione sulla saber
  /// Comando: SAVE → OK SAVE
  Future<void> _saveConfig() async {
    await _link.request('SAVE', match: 'OK SAVE', timeout: timeout);
  }

  /// Manda un comando e verifica che la spada risponda con l'eco: [prefix] seguito dal comando
  Future<void> _expectEcho(String command, String prefix) async {
    final expected = '$prefix$command';
    // Il prefisso dell'attesa si ferma all'"=": un'eco diversa arriva comunque e fallisce subito
    final match = expected.substring(0, expected.indexOf('=') + 1);
    final response = await _link.request(command, match: match, timeout: timeout);
    if (response != expected) {
      throw SaberException('Unexpected response to "$command": "$response"');
    }
  }

  static String _formatColor(RGBWColor color) => '${color.red},${color.green},${color.blue},${color.white}';

  static String _writeLetter(ColorEffect effect) {
    switch (effect) {
      case ColorEffect.main:
        return 'C';
      case ColorEffect.clash:
        return 'F';
      case ColorEffect.swing:
        return 'W';
    }
  }

  static String _readLetter(ColorEffect effect) => _writeLetter(effect).toLowerCase();

  static final RegExp _colorLine = RegExp(r'^[cfw]([0-7])=(\d+),(\d+),(\d+),(\d+)$', caseSensitive: false);

  static ({int bank, RGBWColor color}) _parseColorLine(String line) {
    final m = _colorLine.firstMatch(line.trim());
    if (m == null) throw SaberException('Unexpected color line: "$line"');
    int value(int group) => int.parse(m.group(group)!).clamp(0, 255);
    return (
      bank: int.parse(m.group(1)!),
      color: RGBWColor(red: value(2), green: value(3), blue: value(4), white: value(5)),
    );
  }
}

/// Risultato di readConfiguration
class ConfigurationReadResult {
  ConfigurationReadResult(this.configuration, this.unread);

  final ColorConfiguration configuration;

  // Comandi a cui la spada non ha risposto: i loro campi sono rimasti al default
  final List<String> unread;

  bool get isComplete => unread.isEmpty;
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
