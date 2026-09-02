// The subscribe URL's `compression` parameter. On web the pure-Dart brotli
// decoder mis-decodes larger frames under dart2js (a 2.6 KB transaction
// update failed with "Corrupted Huffman code histogram"), and gzip has no
// web decoder, so the client must be able to ask for uncompressed frames.
import 'package:test/test.dart';
import 'package:spacetimedb/spacetimedb.dart';

SpacetimeDbConnection _connection({
  required List<Uri> attempts,
  MessageCompression? compression,
  String? token,
  bool exchange = false,
}) {
  return SpacetimeDbConnection(
    host: '127.0.0.1:1',
    database: 'compression-param-test',
    initialToken: token,
    config: ConnectionConfig(
      autoReconnect: false,
      maxReconnectAttempts: 0,
      connectTimeout: const Duration(milliseconds: 200),
      compression: compression,
    ),
    socketFactory: (uri, protocols, headers, {connectTimeout = const Duration(seconds: 10)}) {
      attempts.add(uri);
      throw StateError('stub socket refused');
    },
    exchangeWebSocketToken: exchange,
  );
}

void main() {
  group('platform default', () {
    test('web resolves to None unless configured', () {
      expect(
        SpacetimeDbConnection.resolveCompression(null, isWeb: true),
        MessageCompression.none,
      );
      expect(
        SpacetimeDbConnection.resolveCompression(null, isWeb: false),
        MessageCompression.serverDefault,
      );
      for (final choice in MessageCompression.values) {
        expect(SpacetimeDbConnection.resolveCompression(choice, isWeb: true), choice);
        expect(SpacetimeDbConnection.resolveCompression(choice, isWeb: false), choice);
      }
    });

    test('the web default is the wire value the server accepts', () {
      expect(
        SpacetimeDbConnection.resolveCompression(null, isWeb: true).wireValue,
        'None',
      );
    });
  });

  group('compression query parameter', () {
    test('server default sends no parameter', () async {
      final attempts = <Uri>[];
      final connection = _connection(attempts: attempts);
      // Not on web here, so the resolved default is serverDefault.
      expect(connection.effectiveCompression, MessageCompression.serverDefault);
      await expectLater(connection.connect(), throwsA(isA<StateError>()));
      expect(attempts.single.queryParameters.containsKey('compression'), isFalse);
    });

    test('an explicit choice is sent with the SpacetimeDB spelling', () async {
      for (final (choice, wire) in [
        (MessageCompression.none, 'None'),
        (MessageCompression.gzip, 'Gzip'),
        (MessageCompression.brotli, 'Brotli'),
      ]) {
        final attempts = <Uri>[];
        final connection = _connection(attempts: attempts, compression: choice);
        await expectLater(connection.connect(), throwsA(isA<StateError>()));
        expect(attempts.single.queryParameters['compression'], wire);
        expect(attempts.single.path, '/v1/database/compression-param-test/subscribe');
      }
    });

    test('the compression parameter survives the web token exchange', () async {
      // The token is appended to the same query map, so neither parameter
      // clobbers the other. The mint is stubbed by pointing at a closed port;
      // no token means no mint, which is the case exercised here.
      final attempts = <Uri>[];
      final connection = _connection(
        attempts: attempts,
        compression: MessageCompression.none,
        exchange: true,
      );
      await expectLater(connection.connect(), throwsA(isA<StateError>()));
      expect(attempts.single.queryParameters['compression'], 'None');
    });
  });
}
