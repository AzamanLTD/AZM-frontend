// Test support: ApiClient reads the auth token from secure storage on every
// authenticated call. Under `flutter test` that plugin channel does not exist,
// so the read throws and EVERY request fails before it is built — which makes
// a contract test silently measure the harness instead of the contract.
// Stubbing the channel with a null token makes the read behave like a
// signed-out device, which is the state these unit tests want.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

void stubSecureStorage({String? token}) {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, (call) async {
        switch (call.method) {
          case 'read':
            return token;
          case 'readAll':
            return token == null ? <String, String>{} : {'auth_token': token};
          case 'containsKey':
            return token != null;
          default:
            return null;
        }
      });
}
