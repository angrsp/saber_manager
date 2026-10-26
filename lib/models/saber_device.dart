// Modello dati per dispositivi saber, indipendente dal trasporto
class SaberDevice {
  // Identificativo del dispositivo: remoteId BLE (oggi deviceId USB)
  final String id;
  final String name;
  final int? rssi;
  final SaberType type;
  final String? firmwareVersion;
  final String? serialNumber;
  final bool isConnected;

  SaberDevice({
    required this.id,
    required this.name,
    this.rssi,
    required this.type,
    this.firmwareVersion,
    this.serialNumber,
    this.isConnected = false,
  });

  SaberDevice copyWith({
    String? id,
    String? name,
    int? rssi,
    SaberType? type,
    String? firmwareVersion,
    String? serialNumber,
    bool? isConnected,
  }) {
    return SaberDevice(
      id: id ?? this.id,
      name: name ?? this.name,
      rssi: rssi ?? this.rssi,
      type: type ?? this.type,
      firmwareVersion: firmwareVersion ?? this.firmwareVersion,
      serialNumber: serialNumber ?? this.serialNumber,
      isConnected: isConnected ?? this.isConnected,
    );
  }

  @override
  String toString() {
    return 'SaberDevice(id: $id, name: $name, type: $type, fw: $firmwareVersion, connected: $isConnected)';
  }
}

enum SaberType {
  animaEVO,
  animaNXT,
  unknown,
}
