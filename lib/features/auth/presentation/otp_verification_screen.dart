import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinput/pinput.dart';
import '../../../core/constants/app_theme.dart';
import '../../../core/crypto/device_identity.dart';
import '../../../core/network/relay_api_service.dart';
import '../../../core/storage/database_service.dart';
import '../../devices/presentation/device_providers.dart';
import 'hurray_connection_dialog.dart';

class OtpVerificationScreen extends ConsumerStatefulWidget {
  final String email;
  final String phone;

  const OtpVerificationScreen({
    super.key,
    required this.email,
    required this.phone,
  });

  @override
  ConsumerState<OtpVerificationScreen> createState() => _OtpVerificationScreenState();
}

class _OtpVerificationScreenState extends ConsumerState<OtpVerificationScreen> {
  final TextEditingController _pinController = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  bool _isVerifying = false;
  bool _isResending = false;
  String? _errorMessage;

  // Cooldown timer
  int _resendCooldown = 60;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startCooldownTimer();
  }

  void _startCooldownTimer() {
    _resendCooldown = 60;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        if (_resendCooldown > 0) {
          _resendCooldown--;
        } else {
          timer.cancel();
        }
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pinController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _verifyOtp(String otp) async {
    if (otp.length != 6) return;

    setState(() {
      _isVerifying = true;
      _errorMessage = null;
    });

    final myState = ref.read(myDeviceProvider);
    final identity = myState.identity ?? await DeviceIdentityManager().getOrCreateIdentity();

    final result = await RelayApiService.instance.verifyOtp(
      email: widget.email,
      otp: otp,
      phone: widget.phone,
      identity: identity,
    );

    if (!mounted) return;

    setState(() {
      _isVerifying = false;
    });

    if (result['success'] == true) {
      final code = result['connectionCode'] as String? ?? '';

      // Persist authentication state
      await DatabaseService.instance.setUserEmail(widget.email);
      await DatabaseService.instance.setUserPhone(widget.phone);
      await DatabaseService.instance.setConnectionCode(code);
      await DatabaseService.instance.setAuthenticated(true);

      if (mounted) {
        await HurrayConnectionDialog.show(
          context,
          pairedDevice: null,
          connectionCode: code,
          userEmail: widget.email,
        );
      }
    } else {
      setState(() {
        _errorMessage = result['error'] ?? 'Incorrect OTP code';
      });
      _pinController.clear();
      _focusNode.requestFocus();
    }
  }

  Future<void> _resendOtp() async {
    if (_resendCooldown > 0 || _isResending) return;

    setState(() {
      _isResending = true;
      _errorMessage = null;
    });

    final result = await RelayApiService.instance.sendRegistrationOtp(
      email: widget.email,
      phone: widget.phone,
    );

    if (!mounted) return;

    setState(() {
      _isResending = false;
    });

    if (result['success'] == true) {
      _startCooldownTimer();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('A new 6-digit verification code has been sent! Please check your Inbox and Spam folder.'),
          backgroundColor: DevSyncColors.success,
        ),
      );
    } else {
      setState(() {
        _errorMessage = result['error'] ?? 'Failed to resend OTP';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Custom Pinput themes matching DevSync dark-mode aesthetic
    final defaultPinTheme = PinTheme(
      width: 48,
      height: 56,
      textStyle: const TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.bold,
        color: Colors.white,
        fontFamily: 'monospace',
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF30363D), width: 1.5),
      ),
    );

    final focusedPinTheme = defaultPinTheme.copyWith(
      decoration: defaultPinTheme.decoration!.copyWith(
        border: Border.all(color: DevSyncColors.primary, width: 2),
        boxShadow: [
          BoxShadow(
            color: DevSyncColors.primary.withValues(alpha: 0.25),
            blurRadius: 10,
            spreadRadius: 2,
          ),
        ],
      ),
    );

    final submittedPinTheme = defaultPinTheme.copyWith(
      decoration: defaultPinTheme.decoration!.copyWith(
        color: const Color(0xFF0D1117),
        border: Border.all(color: DevSyncColors.primary.withValues(alpha: 0.6), width: 1.5),
      ),
    );

    final errorPinTheme = defaultPinTheme.copyWith(
      decoration: defaultPinTheme.decoration!.copyWith(
        border: Border.all(color: DevSyncColors.error, width: 2),
      ),
    );

    return Scaffold(
      backgroundColor: const Color(0xFF080B10),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Verification Icon
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: const Color(0xFF161B22),
                      shape: BoxShape.circle,
                      border: Border.all(color: DevSyncColors.primary.withValues(alpha: 0.5), width: 2),
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.mark_email_read_rounded,
                        color: DevSyncColors.primary,
                        size: 36,
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  const Text(
                    'Enter Verification Code',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),

                  const SizedBox(height: 10),

                  RichText(
                    textAlign: TextAlign.center,
                    text: TextSpan(
                      style: const TextStyle(fontSize: 14, color: DevSyncColors.textSecondary, height: 1.5),
                      children: [
                        const TextSpan(text: 'We sent a secure 6-digit code to\n'),
                        TextSpan(
                          text: widget.email,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 14),

                  // Spam / Junk folder reminder banner
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF161B22),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF30363D)),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.info_outline_rounded, size: 15, color: DevSyncColors.secondary),
                        SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            "Can't find the email? Please check your Spam or Junk folder.",
                            style: TextStyle(fontSize: 12, color: DevSyncColors.textSecondary),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Pinput 6-Digit Code Component
                  Pinput(
                    length: 6,
                    controller: _pinController,
                    focusNode: _focusNode,
                    defaultPinTheme: defaultPinTheme,
                    focusedPinTheme: focusedPinTheme,
                    submittedPinTheme: submittedPinTheme,
                    errorPinTheme: errorPinTheme,
                    pinputAutovalidateMode: PinputAutovalidateMode.onSubmit,
                    showCursor: true,
                    autofocus: true,
                    onCompleted: (pin) => _verifyOtp(pin),
                  ),

                  if (_errorMessage != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: DevSyncColors.error.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: DevSyncColors.error.withValues(alpha: 0.4)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.error_outline_rounded, color: DevSyncColors.error, size: 16),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              _errorMessage!,
                              style: const TextStyle(color: DevSyncColors.error, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 32),

                  // Verify Button
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _isVerifying ? null : () => _verifyOtp(_pinController.text),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: DevSyncColors.primary,
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: _isVerifying
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.black),
                            )
                          : const Text(
                              'Verify & Continue',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Resend Code Cooldown
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        "Didn't receive the email? ",
                        style: TextStyle(fontSize: 13, color: DevSyncColors.textMuted),
                      ),
                      TextButton(
                        onPressed: (_resendCooldown == 0 && !_isResending) ? _resendOtp : null,
                        child: _isResending
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2, color: DevSyncColors.primary),
                              )
                            : Text(
                                _resendCooldown > 0
                                    ? 'Resend in ${_resendCooldown}s'
                                    : 'Resend Code',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: _resendCooldown > 0 ? DevSyncColors.textMuted : DevSyncColors.primary,
                                ),
                              ),
                      ),
                    ],
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
