import 'package:flutter/material.dart';

class RGBWColor {
  final int red;
  final int green;
  final int blue;
  final int white;

  const RGBWColor({
    required this.red,
    required this.green,
    required this.blue,
    required this.white,
  });

  // Costruttore di default (bianco)
  const RGBWColor.white() : red = 255, green = 255, blue = 255, white = 255;
  
  // Costruttore da mappa
  factory RGBWColor.fromMap(Map<String, dynamic> map) {
    return RGBWColor(
      red: map['red'] ?? 0,
      green: map['green'] ?? 0,
      blue: map['blue'] ?? 0,
      white: map['white'] ?? 0,
    );
  }

  // Conversione a mappa
  Map<String, dynamic> toMap() {
    return {
      'red': red,
      'green': green,
      'blue': blue,
      'white': white,
    };
  }

  // Copia con modifiche
  RGBWColor copyWith({
    int? red,
    int? green,
    int? blue,
    int? white,
  }) {
    return RGBWColor(
      red: red ?? this.red,
      green: green ?? this.green,
      blue: blue ?? this.blue,
      white: white ?? this.white,
    );
  }

  // Conversione approssimativa a RGB per anteprima
  // Implementazione semplificata della logica di color.py
  Color toRGBColor() {
    // Fattori di luminanza per ogni LED (da color.py)
    const luminanceFactors = {
      'r': 1.3,
      'g': 1.9,
      'b': 0.4,
      'w': 2.3,
    };

    // Calcolo semplificato senza conversione XYZ
    double redComponent = (red / 255.0) * luminanceFactors['r']!;
    double greenComponent = (green / 255.0) * luminanceFactors['g']!;
    double blueComponent = (blue / 255.0) * luminanceFactors['b']!;
    double whiteComponent = (white / 255.0) * luminanceFactors['w']!;

    // Aggiungi il contributo del bianco a tutti i componenti
    int finalRed = ((redComponent + whiteComponent * 0.33).clamp(0.0, 1.0) * 255).round();
    int finalGreen = ((greenComponent + whiteComponent * 0.33).clamp(0.0, 1.0) * 255).round();
    int finalBlue = ((blueComponent + whiteComponent * 0.33).clamp(0.0, 1.0) * 255).round();

    return Color.fromARGB(255, finalRed, finalGreen, finalBlue);
  }

  @override
  String toString() {
    return 'RGBW($red, $green, $blue, $white)';
  }

  @override
  bool operator ==(Object other) {
    return other is RGBWColor &&
        other.red == red &&
        other.green == green &&
        other.blue == blue &&
        other.white == white;
  }

  @override
  int get hashCode => Object.hash(red, green, blue, white);
}

class ColorBank {
  RGBWColor mainColor;
  RGBWColor clashColor;
  RGBWColor swingColor;

  ColorBank({
    RGBWColor? mainColor,
    RGBWColor? clashColor,
    RGBWColor? swingColor,
  })  : mainColor = mainColor ?? const RGBWColor.white(),
        clashColor = clashColor ?? const RGBWColor.white(),
        swingColor = swingColor ?? const RGBWColor.white();

  // Costruttore da mappa
  factory ColorBank.fromMap(Map<String, dynamic> map) {
    return ColorBank(
      mainColor: map['color'] != null ? RGBWColor.fromMap(map['color']) : null,
      clashColor: map['clash'] != null ? RGBWColor.fromMap(map['clash']) : null,
      swingColor: map['swing'] != null ? RGBWColor.fromMap(map['swing']) : null,
    );
  }

  // Conversione a mappa (compatible con formato Tintalle)
  Map<String, dynamic> toMap() {
    return {
      'color': mainColor.toMap(),
      'clash': clashColor.toMap(),
      'swing': swingColor.toMap(),
    };
  }

  // Ottieni colore per effetto
  RGBWColor getColorForEffect(ColorEffect effect) {
    switch (effect) {
      case ColorEffect.main:
        return mainColor;
      case ColorEffect.clash:
        return clashColor;
      case ColorEffect.swing:
        return swingColor;
    }
  }

  // Imposta colore per effetto
  void setColorForEffect(ColorEffect effect, RGBWColor color) {
    switch (effect) {
      case ColorEffect.main:
        mainColor = color;
        break;
      case ColorEffect.clash:
        clashColor = color;
        break;
      case ColorEffect.swing:
        swingColor = color;
        break;
    }
  }

  ColorBank copyWith({
    RGBWColor? mainColor,
    RGBWColor? clashColor,
    RGBWColor? swingColor,
  }) {
    return ColorBank(
      mainColor: mainColor ?? this.mainColor,
      clashColor: clashColor ?? this.clashColor,
      swingColor: swingColor ?? this.swingColor,
    );
  }
}

enum ColorEffect {
  main('Main', 'color'),
  clash('Clash', 'clash'),
  swing('Swing', 'swing');

  const ColorEffect(this.displayName, this.protocolName);
  
  final String displayName;
  final String protocolName; // Nome usato nel protocollo OpenCore
}

class ColorConfiguration {
  List<ColorBank> banks;
  int activeBank;

  ColorConfiguration({
    List<ColorBank>? banks,
    this.activeBank = 0,
  }) : banks = banks ?? List.generate(8, (_) => ColorBank());

  // Costruttore da mappa (compatible con formato Tintalle)
  factory ColorConfiguration.fromMap(Map<String, dynamic> map) {
    final banksData = map['bank'] as List<dynamic>? ?? [];
    final banks = banksData.take(8).map((bankData) => 
        ColorBank.fromMap(bankData as Map<String, dynamic>)
    ).toList();
    
    // Assicurati di avere sempre 8 banks
    while (banks.length < 8) {
      banks.add(ColorBank());
    }

    return ColorConfiguration(
      banks: banks,
      activeBank: (map['activeBank'] ?? 1) - 1, // Tintalle usa 1-based indexing
    );
  }

  // Conversione a mappa (compatible con formato Tintalle)
  Map<String, dynamic> toMap() {
    return {
      'activeBank': activeBank + 1, // Tintalle usa 1-based indexing
      'bank': banks.map((bank) => bank.toMap()).toList(),
    };
  }

  // Ottieni bank attivo
  ColorBank get currentBank => banks[activeBank];

  // Imposta bank attivo
  void setActiveBank(int index) {
    if (index >= 0 && index < banks.length) {
      activeBank = index;
    }
  }

  // Ottieni colore per bank ed effetto
  RGBWColor getColor(int bankIndex, ColorEffect effect) {
    if (bankIndex >= 0 && bankIndex < banks.length) {
      return banks[bankIndex].getColorForEffect(effect);
    }
    return const RGBWColor.white();
  }

  // Imposta colore per bank ed effetto
  void setColor(int bankIndex, ColorEffect effect, RGBWColor color) {
    if (bankIndex >= 0 && bankIndex < banks.length) {
      banks[bankIndex].setColorForEffect(effect, color);
    }
  }

  ColorConfiguration copyWith({
    List<ColorBank>? banks,
    int? activeBank,
  }) {
    return ColorConfiguration(
      banks: banks ?? this.banks.map((bank) => ColorBank.fromMap(bank.toMap())).toList(),
      activeBank: activeBank ?? this.activeBank,
    );
  }
}