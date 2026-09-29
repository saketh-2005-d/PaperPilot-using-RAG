import 'package:shared_preferences/shared_preferences.dart';
import 'api.dart';

class AuthStore {
  static const _kToken = 'auth.token';
  static const _kEmail = 'auth.email';

  static Future<void> save(String token, String email) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kToken, token);
    await p.setString(_kEmail, email);
    Api.setToken(token);
  }

  static Future<({String? token, String? email})> load() async {
    final p = await SharedPreferences.getInstance();
    final t = p.getString(_kToken);
    final e = p.getString(_kEmail);
    if (t != null) Api.setToken(t);
    return (token: t, email: e);
  }

  static Future<void> clear() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_kToken);
    await p.remove(_kEmail);
    Api.setToken(null);
  }
}
