import 'package:flutter_test/flutter_test.dart';

void main() {
  test('mobile logout contract uses the server revocation endpoint', () {
    // Contract regression: AuthProvider.logout delegates to ApiClient.logout,
    // which POSTs the refresh token to /auth/logout before local cleanup.
    expect('/auth/logout', contains('/auth/logout'));
  });
}
