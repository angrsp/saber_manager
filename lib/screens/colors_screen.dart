import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:path_provider/path_provider.dart';
import '../models/color_config.dart';
import '../services/saber_protocol.dart';
import '../widgets/color_picker_card.dart';

class ColorsScreen extends StatefulWidget {
  const ColorsScreen({super.key});

  @override
  State<ColorsScreen> createState() => _ColorsScreenState();
}

class _ColorsScreenState extends State<ColorsScreen> {
  late ColorConfiguration _config;
  late ColorConfiguration _originalConfig; // Per il reset
  ColorEffect _selectedEffect = ColorEffect.main;
  bool _isLoading = false;
  bool _hasUnsavedChanges = false;
  
  SaberProtocolService? _saberService;

  @override
  void initState() {
    super.initState();
    _config = ColorConfiguration(); // Configurazione di default
    _originalConfig = ColorConfiguration();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Ottieni il servizio dalla dependency injection
    _saberService = context.read<SaberProtocolService>();
  }

  // ============ GESTIONE STATO ============
  
  void _updateColor(RGBWColor color) {
    setState(() {
      _config.setColor(_config.activeBank, _selectedEffect, color);
      _hasUnsavedChanges = true;
    });
  }

  void _selectEffect(ColorEffect effect) {
    setState(() {
      _selectedEffect = effect;
    });
  }

  void _selectBank(int bankIndex) {
    setState(() {
      _config.setActiveBank(bankIndex);
    });
  }

  RGBWColor get _currentColor {
    return _config.getColor(_config.activeBank, _selectedEffect);
  }

  ColorBank get _currentBank {
    return _config.banks[_config.activeBank];
  }

  // ============ AZIONI SABER ============
  
  Future<void> _previewColor() async {
    if (_saberService == null || !_saberService!.isConnected) {
      _showSnackBar('Saber not connected', isError: true);
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final success = await _saberService!.previewColor(_currentColor);
      if (success) {
        _showSnackBar('Color previewed on saber');
      } else {
        _showSnackBar('Failed to preview color', isError: true);
      }
    } catch (e) {
      _showSnackBar('Error: $e', isError: true);
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _saveCurrentBank() async {
    if (_saberService == null || !_saberService!.isConnected) {
      _showSnackBar('Saber not connected', isError: true);
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final success = await _saberService!.saveColorBank(
        _config.activeBank,
        _currentBank,
        setActive: true,
      );
      
      if (success) {
        setState(() {
          _hasUnsavedChanges = false;
          _originalConfig = ColorConfiguration.fromMap(_config.toMap());
        });
        _showSnackBar('Bank ${_config.activeBank + 1} saved to saber');
      } else {
        _showSnackBar('Failed to save bank', isError: true);
      }
    } catch (e) {
      _showSnackBar('Error: $e', isError: true);
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _saveAllBanks() async {
    if (_saberService == null || !_saberService!.isConnected) {
      _showSnackBar('Saber not connected', isError: true);
      return;
    }

    // Mostra dialog di conferma
    final confirmed = await _showConfirmDialog(
      'Save All Banks',
      'This will save all 8 color banks to the saber. This may take several minutes. Continue?',
    );

    if (!confirmed) return;

    setState(() {
      _isLoading = true;
    });

    try {
      // Mostra progress dialog
      final success = await _showProgressDialog();
      
      if (success) {
        setState(() {
          _hasUnsavedChanges = false;
          _originalConfig = ColorConfiguration.fromMap(_config.toMap());
        });
        _showSnackBar('All banks saved to saber');
      } else {
        _showSnackBar('Failed to save all banks', isError: true);
      }
    } catch (e) {
      _showSnackBar('Error: $e', isError: true);
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // ============ GESTIONE FILE ============
  
  Future<void> _saveToFile() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final fileName = 'saber_colors_${DateTime.now().millisecondsSinceEpoch}.json';
      final file = File('${directory.path}/$fileName');
      
      final jsonData = jsonEncode(_config.toMap());
      await file.writeAsString(jsonData);
      
      _showSnackBar('Colors saved to $fileName');
    } catch (e) {
      _showSnackBar('Error saving file: $e', isError: true);
    }
  }

  Future<void> _loadFromFile() async {
    // In una implementazione reale, qui useresti un file picker
    // Per ora simuliamo con un dialog
    _showSnackBar('File loading not implemented yet');
  }

  // ============ AZIONI UI ============
  
  void _resetChanges() {
    setState(() {
      _config = ColorConfiguration.fromMap(_originalConfig.toMap());
      _hasUnsavedChanges = false;
    });
    _showSnackBar('Changes reset');
  }

  // ============ UI HELPERS ============
  
  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : null,
        duration: Duration(seconds: isError ? 4 : 2),
      ),
    );
  }

  Future<bool> _showConfirmDialog(String title, String content) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<bool> _showProgressDialog() async {
    final completer = Completer<bool>();
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _ProgressDialog(
        onComplete: (success) {
          Navigator.of(context).pop();
          completer.complete(success);
        },
        config: _config,
        saberService: _saberService!,
      ),
    );
    
    return completer.future;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Color Management'),
        backgroundColor: Colors.blue.shade700,
        foregroundColor: Colors.white,
        actions: [
          if (_hasUnsavedChanges)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _resetChanges,
              tooltip: 'Reset Changes',
            ),
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'save_file':
                  _saveToFile();
                  break;
                case 'load_file':
                  _loadFromFile();
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'save_file',
                child: Row(
                  children: [
                    Icon(Icons.save_alt),
                    SizedBox(width: 8),
                    Text('Save to File'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'load_file',
                child: Row(
                  children: [
                    Icon(Icons.file_open),
                    SizedBox(width: 8),
                    Text('Load from File'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  // Selettore bank
                  ColorBankSelector(
                    selectedBank: _config.activeBank,
                    onBankSelected: _selectBank,
                    banks: _config.banks,
                    enabled: !_isLoading,
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // Selettore effetto
                  EffectColorPreview(
                    mainColor: _currentBank.mainColor,
                    clashColor: _currentBank.clashColor,
                    swingColor: _currentBank.swingColor,
                    selectedEffect: _selectedEffect,
                    onEffectSelected: _selectEffect,
                    enabled: !_isLoading,
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // Color picker
                  ColorPickerCard(
                    title: '${_selectedEffect.displayName} Color',
                    color: _currentColor,
                    onColorChanged: _updateColor,
                    enabled: !_isLoading,
                  ),
                  
                  const SizedBox(height: 24),
                  
                  // Pulsanti azioni
                  _buildActionButtons(),
                ],
              ),
            ),
    );
  }

  Widget _buildActionButtons() {
    final isConnected = _saberService?.isConnected ?? false;
    
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            const Text(
              'Actions',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            
            const SizedBox(height: 12),
            
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: isConnected && !_isLoading ? _previewColor : null,
                    icon: const Icon(Icons.visibility),
                    label: const Text('Preview'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 8),
            
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: isConnected && !_isLoading ? _saveCurrentBank : null,
                    icon: const Icon(Icons.save),
                    label: const Text('Save Bank'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
                
                const SizedBox(width: 8),
                
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: isConnected && !_isLoading ? _saveAllBanks : null,
                    icon: const Icon(Icons.save_alt),
                    label: const Text('Save All'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            
            if (!isConnected) ...[
              const SizedBox(height: 8),
              const Text(
                'Saber not connected',
                style: TextStyle(
                  color: Colors.red,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ============ PROGRESS DIALOG ============

class _ProgressDialog extends StatefulWidget {
  final Function(bool) onComplete;
  final ColorConfiguration config;
  final SaberProtocolService saberService;

  const _ProgressDialog({
    required this.onComplete,
    required this.config,
    required this.saberService,
  });

  @override
  State<_ProgressDialog> createState() => _ProgressDialogState();
}

class _ProgressDialogState extends State<_ProgressDialog> {
  ColorOperationProgress? _progress;

  @override
  void initState() {
    super.initState();
    _startSaving();
  }

  Future<void> _startSaving() async {
    try {
      final success = await widget.saberService.saveAllColorBanksWithProgress(
        widget.config,
        (progress) {
          setState(() {
            _progress = progress;
          });
        },
      );
      
      widget.onComplete(success);
    } catch (e) {
      widget.onComplete(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Saving Colors to Saber'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LinearProgressIndicator(
            value: _progress?.progress ?? 0.0,
          ),
          const SizedBox(height: 16),
          Text(
            _progress?.currentOperation ?? 'Starting...',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            '${_progress?.completedOperations ?? 0} of ${_progress?.totalOperations ?? 0}',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }
}