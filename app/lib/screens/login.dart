import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../api.dart';
import '../auth_store.dart';
import '../theme.dart';
import '../widgets/tesseract.dart';
import 'library.dart';

// OAuth client IDs from Google Cloud Console (project: pdf-summary-iiith).
// On Android, `serverClientId` must be a Web-type OAuth client.
// On iOS, the iOS-type client ID is passed as `clientId`.
const _googleWebServerClientId =
    '589108857546-io7ik50blkfml1kkt84s2b2k9id36i5o.apps.googleusercontent.com';
const _googleIosClientId =
    '589108857546-g33o1df9tp4qtjdvvconuc162496q5ne.apps.googleusercontent.com';

GoogleSignIn _buildGoogleSignIn() {
  if (defaultTargetPlatform == TargetPlatform.iOS) {
    return GoogleSignIn(
      scopes: const ['email', 'profile', 'openid'],
      clientId: _googleIosClientId,
      serverClientId: _googleWebServerClientId,
    );
  }
  return GoogleSignIn(
    scopes: const ['email', 'profile', 'openid'],
    serverClientId: _googleWebServerClientId,
  );
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _google = _buildGoogleSignIn();

  bool _isSignup = false;
  bool _busy = false;
  String? _error;

  Future<void> _submit() async {
    final email = _email.text.trim();
    final pwd = _password.text;
    if (email.isEmpty || pwd.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final res = _isSignup
          ? await Api.signup(email, pwd)
          : await Api.login(email, pwd);
      await AuthStore.save(res['access_token'] as String, res['user_email'] as String);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const LibraryScreen()),
      );
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Unable to reach the server. Is the backend running?');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _google.signOut();
      final account = await _google.signIn();
      if (account == null) {
        if (mounted) setState(() => _busy = false);
        return; // user cancelled
      }
      final auth = await account.authentication;
      final idToken = auth.idToken;
      if (idToken == null) {
        throw Exception('Google did not return an ID token. '
            'Make sure a Web OAuth client is configured and used as serverClientId.');
      }
      final res = await Api.google(idToken);
      await AuthStore.save(res['access_token'] as String, res['user_email'] as String);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const LibraryScreen()),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Google sign-in failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 96,
                      height: 96,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: oxfordBlue,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const TesseractMark(size: 80, animate: false),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'PDF Summary',
                    style: Theme.of(context).textTheme.displayMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _isSignup ? 'Create an account to upload your first PDF.' : 'Welcome back.',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: inkSoft),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _signInWithGoogle,
                    icon: const Icon(Icons.account_circle_outlined, size: 20),
                    label: const Text('Continue with Google'),
                  ),
                  const SizedBox(height: 20),
                  const _OrDivider(),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _email,
                    decoration: const InputDecoration(labelText: 'Email'),
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _password,
                    decoration: const InputDecoration(labelText: 'Password'),
                    obscureText: true,
                    onSubmitted: (_) => _submit(),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: const TextStyle(color: Colors.redAccent)),
                  ],
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: _busy ? null : _submit,
                    child: _busy
                        ? const SizedBox(
                            width: 18, height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : Text(_isSignup ? 'Create account' : 'Sign in'),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () => setState(() => _isSignup = !_isSignup),
                    child: Text(_isSignup ? 'I already have an account' : 'Create an account'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OrDivider extends StatelessWidget {
  const _OrDivider();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(child: Divider()),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            'or',
            style: Theme.of(context).textTheme.labelMedium,
          ),
        ),
        const Expanded(child: Divider()),
      ],
    );
  }
}
