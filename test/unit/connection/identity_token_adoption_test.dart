// A socket authenticated with the exchanged websocket token (web) is echoed
// a token carrying that exchange's short `exp`. Persisting it replaced the
// long-lived identity token, so every reconnect after a minute minted with
// an expired bearer ("Invalid token: ExpiredSignature") and got 401.
import 'dart:convert';

import 'package:test/test.dart';
import 'package:spacetimedb/spacetimedb.dart';

String _jwt(Map<String, Object?> claims) {
  String enc(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${enc({'alg': 'ES256', 'typ': 'JWT'})}.${enc(claims)}.sig';
}

SpacetimeDbConnection _connection(String? token) {
  return SpacetimeDbConnection(
    host: '127.0.0.1:1',
    database: 'token-adoption-test',
    initialToken: token,
    config: const ConnectionConfig(autoReconnect: false, maxReconnectAttempts: 0),
  );
}

void main() {
  final longLived = _jwt({'hex_identity': 'c200', 'sub': 'a', 'iat': 1000});
  final shortLived = _jwt({'hex_identity': 'c200', 'sub': 'a', 'iat': 1000, 'exp': 1060});
  final later = _jwt({'hex_identity': 'c200', 'sub': 'a', 'iat': 1000, 'exp': 99999});

  test('jwtExpiry reads exp and tolerates non-JWT input', () {
    expect(SpacetimeDbConnection.jwtExpiry(longLived), isNull);
    expect(SpacetimeDbConnection.jwtExpiry(shortLived), 1060);
    expect(SpacetimeDbConnection.jwtExpiry('not-a-jwt'), isNull);
    expect(SpacetimeDbConnection.jwtExpiry('a.b.c'), isNull);
  });

  test('a short-lived echo never replaces a long-lived stored token', () {
    expect(_connection(longLived).shouldAdoptIdentityToken(shortLived), isFalse);
  });

  test('with no stored token the echo is adopted', () {
    expect(_connection(null).shouldAdoptIdentityToken(shortLived), isTrue);
    expect(_connection(null).shouldAdoptIdentityToken(longLived), isTrue);
  });

  test('an echo without exp, or with a later exp, is adopted', () {
    expect(_connection(shortLived).shouldAdoptIdentityToken(longLived), isTrue);
    expect(_connection(shortLived).shouldAdoptIdentityToken(later), isTrue);
    expect(_connection(later).shouldAdoptIdentityToken(shortLived), isFalse);
  });

  test('re-echoing the identical token is a no-op', () {
    expect(_connection(longLived).shouldAdoptIdentityToken(longLived), isFalse);
  });

  test('undecodable tokens fall back to adopting', () {
    expect(_connection(longLived).shouldAdoptIdentityToken('opaque'), isTrue);
    expect(_connection('opaque').shouldAdoptIdentityToken(shortLived), isTrue);
  });
}
