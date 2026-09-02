/// Configuration for connection behavior
///
/// Allows customization of reconnection strategy, heartbeat intervals,
/// and other connection parameters.
/// Which compression the client asks the server to apply to subscription
/// and transaction frames (the `compression` query parameter of the
/// `/subscribe` endpoint).
enum MessageCompression {
  /// Send no parameter; SpacetimeDB then picks its own default (Brotli).
  serverDefault(null),

  /// Uncompressed frames. The only option every platform can decode: the
  /// pure-Dart brotli decoder mis-decodes larger frames under dart2js
  /// ("Corrupted Huffman code histogram") and gzip has no web decoder.
  none('None'),
  gzip('Gzip'),
  brotli('Brotli');

  const MessageCompression(this.wireValue);

  /// Value sent on the wire, or null for [serverDefault].
  final String? wireValue;
}

class ConnectionConfig {
  /// Maximum number of reconnection attempts before giving up
  final int maxReconnectAttempts;

  /// Base delay for exponential backoff (first retry)
  final Duration baseReconnectDelay;

  /// Maximum delay between reconnection attempts
  final Duration maxReconnectDelay;

  /// How often to send ping messages
  final Duration pingInterval;

  /// How long to wait for pong before declaring connection stale
  final Duration pongTimeout;

  /// Enable/disable automatic reconnection
  final bool autoReconnect;

  /// Timeout for initial WebSocket connection
  final Duration connectTimeout;

  /// Compression requested from the server. `null` picks a per-platform
  /// default: [MessageCompression.none] on web (see the enum docs) and
  /// [MessageCompression.serverDefault] everywhere else.
  final MessageCompression? compression;

  const ConnectionConfig({
    this.maxReconnectAttempts = 10,
    this.baseReconnectDelay = const Duration(seconds: 1),
    this.maxReconnectDelay = const Duration(seconds: 30),
    this.pingInterval = const Duration(seconds: 30),
    this.pongTimeout = const Duration(seconds: 10),
    this.autoReconnect = true,
    this.connectTimeout = const Duration(seconds: 10),
    this.compression,
  });

  /// Preset for mobile networks (more aggressive reconnection)
  ///
  /// Uses shorter intervals and more attempts to handle
  /// unstable mobile network connections.
  static const mobile = ConnectionConfig(
    maxReconnectAttempts: 20,
    baseReconnectDelay: Duration(milliseconds: 500),
    maxReconnectDelay: Duration(seconds: 15),
    pingInterval: Duration(seconds: 15),
    pongTimeout: Duration(seconds: 5),
    connectTimeout: Duration(seconds: 15),
  );

  /// Preset for stable connections (less aggressive)
  ///
  /// Uses longer intervals appropriate for stable
  /// network connections like WiFi or Ethernet.
  static const stable = ConnectionConfig(
    maxReconnectAttempts: 5,
    baseReconnectDelay: Duration(seconds: 2),
    maxReconnectDelay: Duration(minutes: 1),
    pingInterval: Duration(minutes: 1),
    pongTimeout: Duration(seconds: 15),
    connectTimeout: Duration(seconds: 10),
  );

  /// Preset for development (no reconnection, immediate feedback)
  ///
  /// Disables automatic reconnection for faster feedback
  /// during development and debugging.
  static const development = ConnectionConfig(
    maxReconnectAttempts: 0,
    autoReconnect: false,
    pingInterval: Duration(seconds: 30),
    pongTimeout: Duration(seconds: 10),
    connectTimeout: Duration(seconds: 10),
  );

  @override
  String toString() {
    return 'ConnectionConfig(maxReconnectAttempts: $maxReconnectAttempts, '
        'baseReconnectDelay: $baseReconnectDelay, '
        'maxReconnectDelay: $maxReconnectDelay, '
        'pingInterval: $pingInterval, '
        'pongTimeout: $pongTimeout, '
        'autoReconnect: $autoReconnect, '
        'connectTimeout: $connectTimeout, '
        'compression: $compression)';
  }
}
