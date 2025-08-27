import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/color_config.dart';

class ColorPickerCard extends StatefulWidget {
  final RGBWColor color;
  final String title;
  final Function(RGBWColor) onColorChanged;
  final bool enabled;

  const ColorPickerCard({
    super.key,
    required this.color,
    required this.title,
    required this.onColorChanged,
    this.enabled = true,
  });

  @override
  State<ColorPickerCard> createState() => _ColorPickerCardState();
}

class _ColorPickerCardState extends State<ColorPickerCard> {
  late RGBWColor _currentColor;
  
  // Controllers per i TextFormField
  late TextEditingController _redController;
  late TextEditingController _greenController;
  late TextEditingController _blueController;
  late TextEditingController _whiteController;

  @override
  void initState() {
    super.initState();
    _currentColor = widget.color;
    
    // Inizializza i controllers
    _redController = TextEditingController(text: _currentColor.red.toString());
    _greenController = TextEditingController(text: _currentColor.green.toString());
    _blueController = TextEditingController(text: _currentColor.blue.toString());
    _whiteController = TextEditingController(text: _currentColor.white.toString());
  }

  @override
  void didUpdateWidget(ColorPickerCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.color != widget.color) {
      _currentColor = widget.color;
      _updateControllers();
    }
  }

  @override
  void dispose() {
    _redController.dispose();
    _greenController.dispose();
    _blueController.dispose();
    _whiteController.dispose();
    super.dispose();
  }

  void _updateControllers() {
    _redController.text = _currentColor.red.toString();
    _greenController.text = _currentColor.green.toString();
    _blueController.text = _currentColor.blue.toString();
    _whiteController.text = _currentColor.white.toString();
  }

  void _updateColor({int? red, int? green, int? blue, int? white}) {
    final newColor = _currentColor.copyWith(
      red: red,
      green: green,
      blue: blue,
      white: white,
    );
    
    setState(() {
      _currentColor = newColor;
    });
    
    widget.onColorChanged(newColor);
  }

  Widget _buildColorSlider({
    required String label,
    required int value,
    required Color color,
    required Function(int) onChanged,
    required TextEditingController controller,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Label e valore
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: 14,
              ),
            ),
            SizedBox(
              width: 60,
              height: 32,
              child: TextFormField(
                controller: controller,
                enabled: widget.enabled,
                textAlign: TextAlign.center,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                ],
                decoration: const InputDecoration(
                  contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (value) {
                  final intValue = int.tryParse(value);
                  if (intValue != null && intValue >= 0 && intValue <= 255) {
                    onChanged(intValue);
                  }
                },
                onFieldSubmitted: (value) {
                  final intValue = int.tryParse(value) ?? 0;
                  final clampedValue = intValue.clamp(0, 255);
                  controller.text = clampedValue.toString();
                  onChanged(clampedValue);
                },
              ),
            ),
          ],
        ),
        
        const SizedBox(height: 8),
        
        // Slider
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: color.withValues(alpha: 0.8),
            inactiveTrackColor: color.withValues(alpha: 0.3),
            thumbColor: color,
            overlayColor: color.withValues(alpha: 0.1),
          ),
          child: Slider(
            value: value.toDouble(),
            min: 0,
            max: 255,
            divisions: 255,
            onChanged: widget.enabled ? (value) {
              final intValue = value.round();
              controller.text = intValue.toString();
              onChanged(intValue);
            } : null,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header con titolo e anteprima colore
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                // Anteprima del colore
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: _currentColor.toRGBColor(),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Colors.grey.shade300,
                      width: 1,
                    ),
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 20),
            
            // Sliders per RGBW
            _buildColorSlider(
              label: 'Red',
              value: _currentColor.red,
              color: Colors.red,
              controller: _redController,
              onChanged: (value) => _updateColor(red: value),
            ),
            
            const SizedBox(height: 16),
            
            _buildColorSlider(
              label: 'Green',
              value: _currentColor.green,
              color: Colors.green,
              controller: _greenController,
              onChanged: (value) => _updateColor(green: value),
            ),
            
            const SizedBox(height: 16),
            
            _buildColorSlider(
              label: 'Blue',
              value: _currentColor.blue,
              color: Colors.blue,
              controller: _blueController,
              onChanged: (value) => _updateColor(blue: value),
            ),
            
            const SizedBox(height: 16),
            
            _buildColorSlider(
              label: 'White',
              value: _currentColor.white,
              color: Colors.grey.shade600,
              controller: _whiteController,
              onChanged: (value) => _updateColor(white: value),
            ),
          ],
        ),
      ),
    );
  }
}

/// Widget per visualizzare l'anteprima dei colori degli effetti
class EffectColorPreview extends StatelessWidget {
  final RGBWColor mainColor;
  final RGBWColor clashColor;
  final RGBWColor swingColor;
  final ColorEffect selectedEffect;
  final Function(ColorEffect) onEffectSelected;
  final bool enabled;

  const EffectColorPreview({
    super.key,
    required this.mainColor,
    required this.clashColor,
    required this.swingColor,
    required this.selectedEffect,
    required this.onEffectSelected,
    this.enabled = true,
  });

  Widget _buildEffectButton({
    required ColorEffect effect,
    required RGBWColor color,
    required bool isSelected,
  }) {
    return GestureDetector(
      onTap: enabled ? () => onEffectSelected(effect) : null,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? Colors.blue.shade50 : Colors.transparent,
          border: Border.all(
            color: isSelected ? Colors.blue : Colors.grey.shade300,
            width: 2,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            // Anteprima colore
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: color.toRGBColor(),
                borderRadius: BorderRadius.circular(25),
                border: Border.all(
                  color: Colors.grey.shade300,
                  width: 1,
                ),
              ),
            ),
            
            const SizedBox(height: 8),
            
            // Nome effetto
            Text(
              effect.displayName,
              style: TextStyle(
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? Colors.blue : Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Effect Select',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            
            const SizedBox(height: 12),
            
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildEffectButton(
                  effect: ColorEffect.main,
                  color: mainColor,
                  isSelected: selectedEffect == ColorEffect.main,
                ),
                _buildEffectButton(
                  effect: ColorEffect.clash,
                  color: clashColor,
                  isSelected: selectedEffect == ColorEffect.clash,
                ),
                _buildEffectButton(
                  effect: ColorEffect.swing,
                  color: swingColor,
                  isSelected: selectedEffect == ColorEffect.swing,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Widget per la selezione del color bank
class ColorBankSelector extends StatelessWidget {
  final int selectedBank;
  final Function(int) onBankSelected;
  final bool enabled;
  final List<ColorBank> banks;

  const ColorBankSelector({
    super.key,
    required this.selectedBank,
    required this.onBankSelected,
    required this.banks,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Color Bank',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            
            const SizedBox(height: 12),
            
            DropdownButton<int>(
              value: selectedBank,
              isExpanded: true,
              onChanged: enabled ? (int? value) {
                if (value != null) {
                  onBankSelected(value);
                }
              } : null,
              items: List.generate(8, (index) {
                final bank = index < banks.length ? banks[index] : null;
                return DropdownMenuItem<int>(
                  value: index,
                  child: Row(
                    children: [
                      Text('Bank ${index + 1}'),
                      const SizedBox(width: 12),
                      if (bank != null) ...[
                        // Mini preview dei colori
                        _buildMiniColorPreview(bank.mainColor),
                        const SizedBox(width: 2),
                        _buildMiniColorPreview(bank.clashColor),
                        const SizedBox(width: 2),
                        _buildMiniColorPreview(bank.swingColor),
                      ],
                    ],
                  ),
                );
              }),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMiniColorPreview(RGBWColor color) {
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        color: color.toRGBColor(),
        border: Border.all(color: Colors.grey.shade400, width: 0.5),
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}