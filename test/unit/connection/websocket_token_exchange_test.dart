// Regression coverage for the web websocket-token exchange.
//
// Before this fix `_getWebSocketToken()` swallowed every non-200 response
// and exception and returned null, and `connect()` then opened the socket
// with no token at all. After an auto-reconnect the client silently became
// a brand-new anonymous identity while the status stream still said
// connected: pending mutations from the old identity never resolved and
// the new identity owned no rows.
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:spacetimedb/spacetimedb.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class _SocketAttempt {
  _SocketAttempt(this.uri, this.headers);
  final Uri uri;
  final Map<String, dynamic>? headers;
}

/// Records the socket the connection tried to open, then refuses it so the
/// test never needs a live server. `connect()` therefore always throws; the
/// assertions are about *which* socket was requested, and whether one was
/// requested at all.
WebSocketChannel _refusingSocket(
  List<_SocketAttempt> attempts,
  Uri uri,
  Iterable<String>? protocols,
  Map<String, dynamic>? headers, {
  Duration connectTimeout = const Duration(seconds: 10),
}) {
  attempts.add(_SocketAttempt(uri, headers));
  throw StateError('stub socket refused');
}

SpacetimeDbConnection _connection({
  required http.Client client,
  required List<_SocketAttempt> attempts,
  String? token = 'stored-identity-token',
  bool exchange = true,
}) {
  return SpacetimeDbConnection(
    host: '127.0.0.1:1',
    database: 'token-exchange-test',
    initialToken: token,
    config: const ConnectionConfig(
      autoReconnect: false,
      maxReconnectAttempts: 0,
      connectTimeout: Duration(milliseconds: 200),
    ),
    socketFactory: (uri, protocols, headers, {connectTimeout = const Duration(seconds: 10)}) =>
        _refusingSocket(attempts, uri, protocols, headers, connectTimeout: connectTimeout),
    httpClient: client,
    exchangeWebSocketToken: exchange,
    tokenExchangeRetryDelay: Duration.zero,
  );
}

void main() {
  group('websocket-token exchange', () {
    test('a persistent 401 never connects anonymously and reports authError',
        () async {
      final mints = <http.Request>[];
      final attempts = <_SocketAttempt>[];
      final client = MockClient((request) async {
        mints.add(request);
        return http.Response('unauthorized', 401);
      });
      final connection = _connection(client: client, attempts: attempts);
      final statuses = <ConnectionStatus>[];
      connection.connectionStatus.listen(statuses.add);

      await expectLater(
        connection.connect(),
        throwsA(isA<SpacetimeDbAuthException>()),
      );
      await Future<void>.delayed(Duration.zero);

      expect(mints, hasLength(SpacetimeDbConnection.tokenExchangeAttempts));
      expect(
        mints.map((r) => r.headers['Authorization']).toSet(),
        {'Bearer stored-identity-token'},
      );
      expect(attempts, isEmpty, reason: 'no socket may be opened without a token');
      expect(connection.status, ConnectionStatus.authError);
      expect(statuses, contains(ConnectionStatus.authError));
      expect(connection.token, 'stored-identity-token',
          reason: 'the stored token is kept for a later retry');
    });

    test('a transient mint failure is retried and the minted token is used',
        () async {
      var calls = 0;
      final attempts = <_SocketAttempt>[];
      final client = MockClient((request) async {
        calls++;
        if (calls == 1) return http.Response('unauthorized', 401);
        if (calls == 2) throw Exception('connection reset');
        return http.Response(jsonEncode({'token': 'minted-ws-token'}), 200);
      });
      final connection = _connection(client: client, attempts: attempts);

      await expectLater(connection.connect(), throwsA(isA<StateError>()));

      expect(calls, 3);
      expect(attempts, hasLength(1));
      expect(attempts.single.uri.queryParameters['token'], 'minted-ws-token');
      expect(connection.status, ConnectionStatus.disconnected);
    });

    test('without a stored token the socket opens anonymously, no mint',
        () async {
      final mints = <http.Request>[];
      final attempts = <_SocketAttempt>[];
      final client = MockClient((request) async {
        mints.add(request);
        return http.Response('unauthorized', 401);
      });
      final connection =
          _connection(client: client, attempts: attempts, token: null);

      await expectLater(connection.connect(), throwsA(isA<StateError>()));

      expect(mints, isEmpty);
      expect(attempts, hasLength(1));
      expect(attempts.single.uri.queryParameters.containsKey('token'), isFalse);
    });

    test('native path sends the bearer header and never mints', () async {
      final mints = <http.Request>[];
      final attempts = <_SocketAttempt>[];
      final client = MockClient((request) async {
        mints.add(request);
        return http.Response('unauthorized', 401);
      });
      final connection =
          _connection(client: client, attempts: attempts, exchange: false);

      await expectLater(connection.connect(), throwsA(isA<StateError>()));

      expect(mints, isEmpty);
      expect(attempts.single.headers?['Authorization'],
          'Bearer stored-identity-token');
      expect(attempts.single.uri.queryParameters.containsKey('token'), isFalse);
    });
  });
}
