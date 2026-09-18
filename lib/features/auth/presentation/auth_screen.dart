import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinput/pinput.dart';
import '../../../core/network/relay_api_service.dart';
import '../../../core/constants/app_theme.dart';
import '../../../core/crypto/device_identity.dart';
import '../../../core/storage/database_service.dart';
import '../../devices/domain/device_model.dart';
import '../../devices/presentation/device_providers.dart';
import 'hurray_connection_dialog.dart';
import 'otp_verification_screen.dart';

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Registration Form Controllers
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  String _selectedCountryCode = '+91';
  final _regFormKey = GlobalKey<FormState>();
  bool _isSendingOtp = false;
  String? _regError;

  // Login / Connection Code Controllers
  final _codeController = TextEditingController();
  bool _isPairing = false;
  String? _loginError;

  // Optional Alternate Login by Email
  bool _showEmailLogin = false;
  final _loginEmailController = TextEditingController();

  final List<String> _countryCodes = [
    '+91 (IN)',
    '+1 (US)',
    '+44 (UK)',
    '+61 (AU)',
    '+49 (DE)',
    '+81 (JP)',
    '+65 (SG)',
    '+33 (FR)',
    '+86 (CN)',
    '+971 (AE)',
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _codeController.dispose();
    _loginEmailController.dispose();
    super.dispose();
  }

  // --- Registration Pipeline ---
  Future<void> _handleRegister() async {
    if (!_regFormKey.currentState!.validate()) return;

    setState(() {
      _isSendingOtp = true;
      _regError = null;
    });

    final fullPhone = '$_selectedCountryCode ${_phoneController.text.trim()}';
    final email = _emailController.text.trim();

    final result = await RelayApiService.instance.sendRegistrationOtp(
      email: email,
      phone: fullPhone,
    );

    if (!mounted) return;

    setState(() {
      _isSendingOtp = false;
    });

    if (result['success'] == true) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => OtpVerificationScreen(
            email: email,
            phone: fullPhone,
            debugOtp: result['debugOtp'] as String?,
          ),
        ),
      );
    } else {
      setState(() {
        _regError = result['error'] ?? 'Failed to send OTP. Please try again.';
      });
    }
  }

  // --- Login via 6-Digit Connection Code ---
  Future<void> _handlePairWithCode(String code) async {
    final cleanCode = code.replaceAll(RegExp(r'[^0-9]'), '').trim();
    if (cleanCode.length != 6) {
      setState(() {
        _loginError = 'Please enter a complete 6-digit Connection Code';
      });
      return;
    }

    setState(() {
      _isPairing = true;
      _loginError = null;
    });

    final myState = ref.read(myDeviceProvider);
    final identity = myState.identity ?? await DeviceIdentityManager().getOrCreateIdentity();

    final result = await RelayApiService.instance.pairWithConnectionCode(
      connectionCode: cleanCode,
      identity: identity,
    );

    if (!mounted) return;

    setState(() {
      _isPairing = false;
    });

    if (result['success'] == true) {
      final pairedDev = result['pairedDevice'] as DeviceModel?;
      final user = result['user'] as Map<String, dynamic>?;

      // Save credentials & connection status
      await DatabaseService.instance.setConnectionCode(cleanCode);
      await DatabaseService.instance.setAuthenticated(true);
      if (user != null && user['email'] != null) {
        await DatabaseService.instance.setUserEmail(user['email']);
      }

      // Add paired peer to local store
      if (pairedDev != null) {
        await DatabaseService.instance.savePeer(pairedDev);
      }

      if (mounted) {
        await HurrayConnectionDialog.show(
          context,
          pairedDevice: pairedDev,
          connectionCode: cleanCode,
          userEmail: user?['email'],
        );
      }
    } else {
      setState(() {
        _loginError = result['error'] ?? 'Invalid code or connection failed.';
      });
    }
  }

  // --- Email Login Fallback ---
  Future<void> _handleEmailLogin() async {
    final email = _loginEmailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() {
        _loginError = 'Please enter a valid registered email';
      });
      return;
    }

    setState(() {
      _isPairing = true;
      _loginError = null;
    });

    final result = await RelayApiService.instance.sendRegistrationOtp(
      email: email,
      phone: 'Existing Account',
    );

    if (!mounted) return;

    setState(() {
      _isPairing = false;
    });

    if (result['success'] == true) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => OtpVerificationScreen(
            email: email,
            phone: '',
            debugOtp: result['debugOtp'] as String?,
          ),
        ),
      );
    } else {
      setState(() {
        _loginError = result['error'] ?? 'Failed to send OTP';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF080B10),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // App Emblem & Brand Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0D1117),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: DevSyncColors.primary.withValues(alpha: 0.8), width: 1.5),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '<',
                              style: TextStyle(
                                color: DevSyncColors.primary,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'monospace',
                              ),
                            ),
                            Text(
                              '/>',
                              style: TextStyle(
                                color: DevSyncColors.secondary,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        'DEV',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 2,
                          color: Colors.white,
                        ),
                      ),
                      const Text(
                        'SYNC',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 2,
                          color: DevSyncColors.primary,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 10),

                  const Text(
                    'Worldwide Multi-Device Peer Network',
                    style: TextStyle(fontSize: 13, color: DevSyncColors.textSecondary),
                  ),

                  const SizedBox(height: 28),

                  // Segmented Tabs: [ Login ] / [ Register ]
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF161B22),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF30363D)),
                    ),
                    padding: const EdgeInsets.all(4),
                    child: TabBar(
                      controller: _tabController,
                      indicator: BoxDecoration(
                        color: DevSyncColors.primary,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      indicatorSize: TabBarIndicatorSize.tab,
                      labelColor: Colors.black,
                      unselectedLabelColor: Colors.white,
                      labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                      tabs: const [
                        Tab(text: 'Login'),
                        Tab(text: 'Register'),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Tab Views
                  SizedBox(
                    height: 400,
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        _buildLoginTab(),
                        _buildRegisterTab(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // --- 1. Login Tab View (Enter 6-Digit Connection Code) ---
  Widget _buildLoginTab() {
    final codeTheme = PinTheme(
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

    if (_showEmailLogin) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Restore Account with Email',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 6),
          const Text(
            'Enter your registered email to receive an OTP and restore this device.',
            style: TextStyle(fontSize: 12, color: DevSyncColors.textSecondary),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _loginEmailController,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'Registered Email',
              prefixIcon: Icon(Icons.email_outlined, color: DevSyncColors.primary),
            ),
          ),
          if (_loginError != null) ...[
            const SizedBox(height: 12),
            Text(_loginError!, style: const TextStyle(color: DevSyncColors.error, fontSize: 12)),
          ],
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: _isPairing ? null : _handleEmailLogin,
              style: ElevatedButton.styleFrom(backgroundColor: DevSyncColors.primary, foregroundColor: Colors.black),
              child: _isPairing
                  ? const CircularProgressIndicator(color: Colors.black, strokeWidth: 2.5)
                  : const Text('Send Login OTP', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: TextButton(
              onPressed: () => setState(() => _showEmailLogin = false),
              child: const Text('← Back to 6-Digit Connection Code', style: TextStyle(color: DevSyncColors.secondary)),
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Helper Explanation Card
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF161B22),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: DevSyncColors.primary.withValues(alpha: 0.3)),
          ),
          child: const Row(
            children: [
              Icon(Icons.qr_code_2_rounded, color: DevSyncColors.primary, size: 24),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Enter the 6-digit Connection Code displayed in the "Connections" section on your other device.',
                  style: TextStyle(fontSize: 12, color: DevSyncColors.textSecondary, height: 1.4),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 24),

        const Text(
          'Enter 6-Digit Connection Code',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white),
        ),

        const SizedBox(height: 14),

        // Pinput 6-digit input for pairing
        Pinput(
          length: 6,
          controller: _codeController,
          defaultPinTheme: codeTheme,
          focusedPinTheme: codeTheme.copyWith(
            decoration: codeTheme.decoration!.copyWith(
              border: Border.all(color: DevSyncColors.primary, width: 2),
            ),
          ),
          onCompleted: (code) => _handlePairWithCode(code),
        ),

        if (_loginError != null) ...[
          const SizedBox(height: 12),
          Text(_loginError!, style: const TextStyle(color: DevSyncColors.error, fontSize: 12)),
        ],

        const SizedBox(height: 24),

        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton(
            onPressed: _isPairing ? null : () => _handlePairWithCode(_codeController.text),
            style: ElevatedButton.styleFrom(
              backgroundColor: DevSyncColors.primary,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: _isPairing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2.5),
                  )
                : const Text('Pair Device & Sync', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          ),
        ),

        const Spacer(),

        TextButton(
          onPressed: () => setState(() => _showEmailLogin = true),
          child: const Text(
            'Already have an account? Login with Email',
            style: TextStyle(fontSize: 12, color: DevSyncColors.secondary),
          ),
        ),
      ],
    );
  }

  // --- 2. Register Tab View (Mobile Number + Email ID) ---
  Widget _buildRegisterTab() {
    return Form(
      key: _regFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Create Device Account',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 4),
          const Text(
            'Register one time to unlock your persistent 6-digit Connection Code.',
            style: TextStyle(fontSize: 12, color: DevSyncColors.textSecondary),
          ),

          const SizedBox(height: 20),

          // Email Field
          TextFormField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'Email Address',
              hintText: 'developer@example.com',
              prefixIcon: Icon(Icons.alternate_email_rounded, color: DevSyncColors.primary, size: 20),
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) return 'Email is required';
              final regex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
              if (!regex.hasMatch(value.trim())) return 'Enter a valid email address';
              return null;
            },
          ),

          const SizedBox(height: 16),

          // Mobile Number with Country Code Dropdown
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Country Code
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF161B22),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF30363D)),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedCountryCode,
                    dropdownColor: const Color(0xFF161B22),
                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                    items: _countryCodes.map((c) {
                      final codeOnly = c.split(' ')[0];
                      return DropdownMenuItem<String>(
                        value: codeOnly,
                        child: Text(c),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) setState(() => _selectedCountryCode = val);
                    },
                  ),
                ),
              ),

              const SizedBox(width: 10),

              // Phone Number Input
              Expanded(
                child: TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Mobile Number',
                    hintText: '9876543210',
                    prefixIcon: Icon(Icons.phone_rounded, color: DevSyncColors.primary, size: 20),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) return 'Mobile number is required';
                    if (value.trim().length < 7 || value.trim().length > 15) {
                      return 'Enter 7-15 digits';
                    }
                    return null;
                  },
                ),
              ),
            ],
          ),

          if (_regError != null) ...[
            const SizedBox(height: 12),
            Text(_regError!, style: const TextStyle(color: DevSyncColors.error, fontSize: 12)),
          ],

          const SizedBox(height: 24),

          // Submit & Send OTP Button
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: _isSendingOtp ? null : _handleRegister,
              style: ElevatedButton.styleFrom(
                backgroundColor: DevSyncColors.primary,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: _isSendingOtp
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2.5),
                    )
                  : const Text('Send 6-Digit OTP Email', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            ),
          ),

          const SizedBox(height: 14),

          const Center(
            child: Text(
              'A dark-mode styled verification code will be sent to your inbox.',
              style: TextStyle(fontSize: 11, color: DevSyncColors.textMuted),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}
