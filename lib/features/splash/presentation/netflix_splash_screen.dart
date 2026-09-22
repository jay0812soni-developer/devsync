import 'package:flutter/material.dart';
import '../../../app.dart';
import '../../../core/constants/app_theme.dart';
import '../../auth/presentation/auth_screen.dart';
import '../../../core/storage/database_service.dart';

class NetflixSplashScreen extends StatefulWidget {
  const NetflixSplashScreen({super.key});

  @override
  State<NetflixSplashScreen> createState() => _NetflixSplashScreenState();
}

class _NetflixSplashScreenState extends State<NetflixSplashScreen> {
  bool _hasNavigated = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 700), _navigateNext);
  }

  void _navigateNext() {
    if (_hasNavigated || !mounted) return;
    _hasNavigated = true;

    final isAuth = DatabaseService.instance.isAuthenticated();
    final hasCode = DatabaseService.instance.getConnectionCode() != null;

    final targetScreen = (isAuth || hasCode)
        ? const DevSyncHomeScaffold()
        : const AuthScreen();

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (context, animation, secondaryAnimation) => targetScreen,
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DevSyncColors.background,
      body: GestureDetector(
        onTap: _navigateNext,
        behavior: HitTestBehavior.opaque,
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'DevSync',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.6,
                  color: DevSyncColors.textPrimary,
                ),
              ),
              SizedBox(height: 10),
              SizedBox(
                width: 36,
                child: Divider(color: DevSyncColors.primary, thickness: 2),
              ),
              SizedBox(height: 10),
              Text(
                'Messages between your devices',
                style: TextStyle(fontSize: 13, color: DevSyncColors.textMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
