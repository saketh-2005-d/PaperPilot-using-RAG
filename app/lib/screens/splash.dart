import 'package:flutter/material.dart';

import '../auth_store.dart';
import '../theme.dart';
import '../widgets/tesseract.dart';
import 'library.dart';
import 'login.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  bool _animationDone = false;
  bool _authReady = false;
  bool _hasToken = false;

  @override
  void initState() {
    super.initState();
    _loadAuth();
  }

  Future<void> _loadAuth() async {
    final auth = await AuthStore.load();
    if (!mounted) return;
    setState(() {
      _authReady = true;
      _hasToken = auth.token != null;
    });
    _maybeNavigate();
  }

  void _onAnimationDone() {
    if (!mounted) return;
    setState(() => _animationDone = true);
    _maybeNavigate();
  }

  void _maybeNavigate() {
    if (!mounted || !_animationDone || !_authReady) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, _, _) =>
            _hasToken ? const LibraryScreen() : const LoginScreen(),
        transitionsBuilder: (_, anim, _, child) =>
            FadeTransition(opacity: anim, child: child),
        transitionDuration: const Duration(milliseconds: 350),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: oxfordBlue,
      body: Center(
        child: TesseractMark(
          size: 240,
          onComplete: _onAnimationDone,
        ),
      ),
    );
  }
}
