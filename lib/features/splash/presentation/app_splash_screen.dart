import 'dart:async';
import 'package:flutter/material.dart';
import '../../../app.dart';
import '../../auth/presentation/auth_screen.dart';
import '../../../core/constants/app_theme.dart';
import '../../../core/storage/database_service.dart';
import '../../../core/network/persistent_ws_client.dart';

class AppSplashScreen extends StatefulWidget {
  const AppSplashScreen({super.key});

  @override
  State<AppSplashScreen> createState() => _AppSplashScreenState();
}

class _AppSplashScreenState extends State<AppSplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;
  bool _hasNavigated = false;

  @override
  void initState() {
    super.initState();

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOut,
    );

    _scaleAnimation = Tween<double>(begin: 0.92, end: 1.0).animate(
      CurvedAnimation(
        parent: _animController,
        curve: Curves.easeOutCubic,
      ),
    );

    _animController.forward();

    // Check authentication and navigate smoothly after short delay (800ms)
    Timer(const Duration(milliseconds: 800), _evaluateDestination);
  }

  void _evaluateDestination() {
    if (_hasNavigated || !mounted) return;
    _hasNavigated = true;

    final isAuth = DatabaseService.instance.isAuthenticated();
    final hasCode = DatabaseService.instance.getConnectionCode() != null;
    final token = DatabaseService.instance.getAuthToken();

    if (isAuth || hasCode) {
      // Proactively initiate persistent WebSocket connection if credentials exist
      if (token != null && token.isNotEmpty) {
        PersistentWsClient.instance.connect(token: token);
      }
    }

    final targetScreen = (isAuth || hasCode)
        ? const DevSyncHomeScaffold()
        : const AuthScreen();

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 400),
        pageBuilder: (context, animation, secondaryAnimation) => targetScreen,
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DevSyncColors.lightBackground,
      body: Center(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: ScaleTransition(
            scale: _scaleAnimation,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: DevSyncColors.lightSurface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: DevSyncColors.lightBorder, width: 1.2),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.sync_alt_rounded,
                      size: 34,
                      color: DevSyncColors.primary,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'DEVSYNC',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2.5,
                    color: DevSyncColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Private Personal Device Mesh',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    color: DevSyncColors.textSecondary,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
