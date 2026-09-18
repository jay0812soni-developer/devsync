import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../app.dart';
import '../../auth/presentation/auth_screen.dart';
import '../../../core/storage/database_service.dart';

class NetflixSplashScreen extends StatefulWidget {
  const NetflixSplashScreen({super.key});

  @override
  State<NetflixSplashScreen> createState() => _NetflixSplashScreenState();
}

class _NetflixSplashScreenState extends State<NetflixSplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _ribbonAnim;
  late Animation<double> _logoScaleAnim;
  late Animation<double> _logoOpacityAnim;
  late Animation<double> _taglineOpacityAnim;
  late Animation<double> _glowRadiusAnim;

  bool _hasNavigated = false;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    );

    // 1. Ribbons shoot outward and sweep across (0.0 -> 0.6)
    _ribbonAnim = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.6, curve: Curves.easeOutCubic),
    );

    // 2. Logo scales from distant depth to crisp foreground (0.2 -> 0.75)
    _logoScaleAnim = Tween<double>(begin: 0.35, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.2, 0.75, curve: Curves.easeOutBack),
      ),
    );

    // 3. Logo fades in (0.15 -> 0.5)
    _logoOpacityAnim = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.15, 0.5, curve: Curves.easeIn),
    );

    // 4. Glowing aura blooms (0.4 -> 0.8)
    _glowRadiusAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.4, 0.8, curve: Curves.easeInOutQuad),
      ),
    );

    // 5. Tagline fades in (0.65 -> 0.95)
    _taglineOpacityAnim = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.65, 0.95, curve: Curves.easeIn),
    );

    _controller.forward();

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _navigateNext();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
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
        transitionDuration: const Duration(milliseconds: 600),
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
      backgroundColor: const Color(0xFF070A0F),
      body: Stack(
        children: [
          // Background subtle vignette
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.center,
                  radius: 1.2,
                  colors: [
                    Color(0xFF101622),
                    Color(0xFF070A0F),
                  ],
                ),
              ),
            ),
          ),

          // Cinematic Netflix-inspired Light Beams / Ribbons
          AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              return CustomPaint(
                size: Size.infinite,
                painter: _NetflixRibbonPainter(
                  progress: _ribbonAnim.value,
                  glowIntensity: _glowRadiusAnim.value,
                ),
              );
            },
          ),

          // Central Logo Reveal
          Center(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                return Opacity(
                  opacity: _logoOpacityAnim.value,
                  child: Transform.scale(
                    scale: _logoScaleAnim.value,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Stylized DevSync Emblem
                        Stack(
                          alignment: Alignment.center,
                          children: [
                            // Neon Radial Bloom
                            Container(
                              width: 140 * _glowRadiusAnim.value,
                              height: 140 * _glowRadiusAnim.value,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFF00F5D4).withValues(alpha: 0.35 * _glowRadiusAnim.value),
                                    blurRadius: 70,
                                    spreadRadius: 20,
                                  ),
                                  BoxShadow(
                                    color: const Color(0xFF7B2CBF).withValues(alpha: 0.35 * _glowRadiusAnim.value),
                                    blurRadius: 90,
                                    spreadRadius: 30,
                                  ),
                                ],
                              ),
                            ),

                            // Geometric Modern Icon
                            Container(
                              width: 88,
                              height: 88,
                              decoration: BoxDecoration(
                                color: const Color(0xFF0D1117),
                                borderRadius: BorderRadius.circular(22),
                                border: Border.all(
                                  color: const Color(0xFF00F5D4).withValues(alpha: 0.8),
                                  width: 2.5,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFF00F5D4).withValues(alpha: 0.3),
                                    blurRadius: 24,
                                    offset: const Offset(0, 8),
                                  ),
                                ],
                              ),
                              child: Center(
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Text(
                                      '<',
                                      style: TextStyle(
                                        color: Color(0xFF00F5D4),
                                        fontSize: 34,
                                        fontWeight: FontWeight.w900,
                                        fontFamily: 'monospace',
                                      ),
                                    ),
                                    const SizedBox(width: 2),
                                    Transform.rotate(
                                      angle: math.pi / 4,
                                      child: Container(
                                        width: 12,
                                        height: 12,
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF7B2CBF),
                                          borderRadius: BorderRadius.circular(3),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 2),
                                    const Text(
                                      '/>',
                                      style: TextStyle(
                                        color: Color(0xFF00F5D4),
                                        fontSize: 34,
                                        fontWeight: FontWeight.w900,
                                        fontFamily: 'monospace',
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 28),

                        // Bold Brand Wordmark
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'DEV',
                              style: TextStyle(
                                fontSize: 38,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 5.0,
                                color: const Color(0xFFFFFFFF),
                                shadows: [
                                  Shadow(
                                    color: const Color(0xFF00F5D4).withValues(alpha: 0.8),
                                    blurRadius: 18,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            ShaderMask(
                              shaderCallback: (bounds) => const LinearGradient(
                                colors: [Color(0xFF00F5D4), Color(0xFF9D4EDD)],
                              ).createShader(bounds),
                              child: const Text(
                                'SYNC',
                                style: TextStyle(
                                  fontSize: 38,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 5.0,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 14),

                        // Subtitle Tagline
                        Opacity(
                          opacity: _taglineOpacityAnim.value,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xFF161B22).withValues(alpha: 0.8),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: const Color(0xFF30363D),
                                width: 1,
                              ),
                            ),
                            child: const Text(
                              'SOVEREIGN MULTI-DEVICE MESH',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 2.5,
                                color: Color(0xFF8B949E),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          // Skip Button in Top Right
          Positioned(
            top: 48,
            right: 24,
            child: TextButton(
              onPressed: _navigateNext,
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF8B949E),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Skip', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                  SizedBox(width: 4),
                  Icon(Icons.arrow_forward_ios_rounded, size: 12),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Custom painter rendering dynamic cinema ribbon beams radiating outward
class _NetflixRibbonPainter extends CustomPainter {
  final double progress;
  final double glowIntensity;

  _NetflixRibbonPainter({
    required this.progress,
    required this.glowIntensity,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;

    final center = Offset(size.width / 2, size.height / 2);
    final maxDist = math.sqrt(size.width * size.width + size.height * size.height) * 0.7;

    // Beams of light projecting from the center
    final beamCount = 18;
    final rand = math.Random(42);

    for (int i = 0; i < beamCount; i++) {
      final angle = (i / beamCount) * 2 * math.pi + (progress * 0.4);
      final beamLength = maxDist * progress * (0.6 + rand.nextDouble() * 0.4);
      final beamWidth = (4.0 + rand.nextDouble() * 8.0) * progress;

      final colorIndex = i % 3;
      final Color beamColor = colorIndex == 0
          ? const Color(0xFF00F5D4)
          : colorIndex == 1
              ? const Color(0xFF7B2CBF)
              : const Color(0xFFE50914);

      final paint = Paint()
        ..color = beamColor.withValues(alpha: (0.18 + 0.12 * glowIntensity) * (1.0 - progress * 0.3))
        ..strokeWidth = beamWidth
        ..style = PaintingStyle.stroke
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);

      final endX = center.dx + math.cos(angle) * beamLength;
      final endY = center.dy + math.sin(angle) * beamLength;

      canvas.drawLine(center, Offset(endX, endY), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _NetflixRibbonPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.glowIntensity != glowIntensity;
  }
}
