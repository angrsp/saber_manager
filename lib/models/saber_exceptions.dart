// Exception personalizzate
class SaberException implements Exception {
  final String message;
  SaberException(this.message);

  @override
  String toString() => 'SaberException: $message';
}

class NoSaberFoundException extends SaberException {
  NoSaberFoundException() : super('No compatible saber found');
}

class ConnectionTimeoutException extends SaberException {
  ConnectionTimeoutException() : super('Connection timeout');
}

// La spada non ha risposto a un comando: per il protocollo vuol dire anche "comando non supportato"
class ResponseTimeoutException extends SaberException {
  final String command;
  ResponseTimeoutException(this.command) : super('No response to "$command"');
}

class PermissionDeniedException extends SaberException {
  PermissionDeniedException() : super('Permission denied');
}

// Connessione persa durante l'uso
class SaberDisconnectedException extends SaberException {
  SaberDisconnectedException() : super('Saber disconnected');
}

// Bridge connesso, ma la spada non è collegata
class SaberNotConnectedException extends SaberException {
  SaberNotConnectedException() : super('Bridge connected, saber not present');
}
