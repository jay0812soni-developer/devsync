import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../../core/constants/app_theme.dart';
import '../domain/device_model.dart';

/// Structured result parsed from any DevSync pairing QR code or token
class PairingScanResult {
  final String? code;
  final DeviceModel? peer;
  final Map<String, dynamic>? rawJson;
  final String rawText;

  const PairingScanResult({
    this.code,
    this.peer,
    this.rawJson,
    required this.rawText,
  });

  /// Flexible parser supporting pure 6-digit codes, JSON payloads, and devsync URLs
  factory PairingScanResult.parse(String raw) {
    final trimmed = raw.trim();

    // 1. Exact 6-digit code (e.g. "849201")
    if (RegExp(r'^\d{6}$').hasMatch(trimmed)) {
      return PairingScanResult(code: trimmed, rawText: trimmed);
    }

    // 2. JSON Device / Pairing payload (from QrPairSheet or Web)
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map<String, dynamic>) {
        final codeVal = (decoded['code'] ?? decoded['connectionCode'])?.toString().trim();
        final cleanCode = (codeVal != null && RegExp(r'^\d{6}$').hasMatch(codeVal)) ? codeVal : null;

        DeviceModel? peer;
        final id = decoded['id']?.toString();
        if (id != null && id.isNotEmpty) {
          peer = DeviceModel(
            id: id,
            name: decoded['name']?.toString() ?? 'DevSync Peer',
            platform: decoded['platform']?.toString() ?? 'unknown',
            signingPublicKey: decoded['signingPublicKey']?.toString() ?? '',
            exchangePublicKey: decoded['exchangePublicKey']?.toString() ?? '',
            lanIp: decoded['lanIp']?.toString(),
            lanPort: decoded['lanPort'] is int ? decoded['lanPort'] as int : null,
            isOnline: true,
            isLanAvailable: decoded['lanIp'] != null,
            lastSeen: DateTime.now(),
            isPaired: true,
          );
        }

        return PairingScanResult(
          code: cleanCode,
          peer: peer,
          rawJson: decoded,
          rawText: trimmed,
        );
      }
    } catch (_) {
      // Not JSON, continue to next parser
    }

    // 3. Deep link / URL format (e.g. devsync://pair?code=849201)
    try {
      final uri = Uri.parse(trimmed);
      final codeParam = uri.queryParameters['code'] ?? uri.queryParameters['connectionCode'];
      if (codeParam != null && RegExp(r'^\d{6}$').hasMatch(codeParam.trim())) {
        return PairingScanResult(code: codeParam.trim(), rawText: trimmed);
      }
    } catch (_) {}

    // 4. Fallback: extract any 6 consecutive digits from the text
    final match = RegExp(r'\b\d{6}\b').firstMatch(trimmed);
    if (match != null) {
      return PairingScanResult(code: match.group(0), rawText: trimmed);
    }

    return PairingScanResult(rawText: trimmed);
  }

  bool get hasValidData => (code != null && code!.length == 6) || peer != null;
}

/// A modern, cyber-styled QR code scanner modal with camera feed,
/// scanning laser animation, photo picker, and manual token input.
class QrScannerSheet extends ConsumerStatefulWidget {
  const QrScannerSheet({super.key});

  /// Helper static method to show the scanner bottom sheet
  static Future<PairingScanResult?> show(BuildContext context) {
    return showModalBottomSheet<PairingScanResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const QrScannerSheet(),
    );
  }

  @override
  ConsumerState<QrScannerSheet> createState() => _QrScannerSheetState();
}

class _QrScannerSheetState extends ConsumerState<QrScannerSheet> with SingleTickerProviderStateMixin {
  late final MobileScannerController _controller;
  late final AnimationController _animController;
  late final Animation<double> _scanAnimation;

  final TextEditingController _manualController = TextEditingController();
  bool _isProcessing = false;
  bool _torchOn = false;
  bool _showManualInput = false;
  bool _cameraHasError = false;
  String? _cameraErrorMessage;

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController(
      detectionSpeed: DetectionSpeed.noDuplicates,
      formats: const [BarcodeFormat.qrCode],
    );

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _scanAnimation = Tween<double>(begin: 0.05, end: 0.95).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _animController.dispose();
    _controller.dispose();
    _manualController.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_isProcessing) return;
    final barcode = capture.barcodes.firstOrNull;
    if (barcode == null) return;

    final raw = barcode.rawValue ?? barcode.displayValue;
    if (raw == null || raw.trim().isEmpty) return;

    final result = PairingScanResult.parse(raw);
    if (result.hasValidData) {
      _isProcessing = true;
      HapticFeedback.mediumImpact();
      Navigator.of(context).pop(result);
    }
  }

  Future<void> _handlePickImage() async {
    try {
      final res = await FilePicker.pickFiles(type: FileType.image);
      if (res.isEmpty || res.first.path == null) return;

      final path = res.first.path!;
      final capture = await _controller.analyzeImage(path);

      if (capture != null && capture.barcodes.isNotEmpty) {
        _onDetect(capture);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No QR code found in selected image. Try another image or paste code directly.'),
              backgroundColor: DevSyncColors.error,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not scan image: $e'),
            backgroundColor: DevSyncColors.error,
          ),
        );
      }
    }
  }

  void _handleManualSubmit() {
    final text = _manualController.text.trim();
    if (text.isEmpty) return;

    final result = PairingScanResult.parse(text);
    if (result.hasValidData) {
      Navigator.of(context).pop(result);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Invalid pairing code or token format. Please check and try again.'),
          backgroundColor: DevSyncColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.88,
      ),
      margin: EdgeInsets.only(bottom: bottomInset),
      decoration: const BoxDecoration(
        color: DevSyncColors.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(
          top: BorderSide(color: DevSyncColors.primary, width: 2),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Top Drag Handle
            const SizedBox(height: 10),
            Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: DevSyncColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // Modal Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: DevSyncColors.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.qr_code_scanner_rounded, color: DevSyncColors.primary, size: 20),
                  ),
                  const SizedBox(width: 12),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Scan QR Code to Pair',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      Text(
                        'Scan the QR displayed on your registered device',
                        style: TextStyle(fontSize: 11, color: DevSyncColors.textSecondary),
                      ),
                    ],
                  ),
                  const Spacer(),

                  // Flash Torch Button
                  if (!_cameraHasError && !_showManualInput) ...[
                    IconButton(
                      icon: Icon(
                        _torchOn ? Icons.flash_on_rounded : Icons.flash_off_rounded,
                        color: _torchOn ? DevSyncColors.primary : DevSyncColors.textSecondary,
                        size: 20,
                      ),
                      tooltip: 'Toggle Flash',
                      onPressed: () async {
                        await _controller.toggleTorch();
                        setState(() => _torchOn = !_torchOn);
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.flip_camera_ios_rounded, color: DevSyncColors.textSecondary, size: 20),
                      tooltip: 'Switch Camera',
                      onPressed: () => _controller.switchCamera(),
                    ),
                  ],

                  // Close Button
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: DevSyncColors.textSecondary, size: 22),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            const Divider(color: DevSyncColors.surfaceVariant, height: 1),

            // Content Body: Scanner Viewport or Manual Input
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    if (!_showManualInput) ...[
                      // Camera Viewfinder Box
                      Container(
                        width: double.infinity,
                        height: 280,
                        decoration: BoxDecoration(
                          color: Colors.black,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: DevSyncColors.border),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            // Live Camera Feed
                            MobileScanner(
                              controller: _controller,
                              onDetect: _onDetect,
                              errorBuilder: (context, error) {
                                WidgetsBinding.instance.addPostFrameCallback((_) {
                                  if (!_cameraHasError) {
                                    setState(() {
                                      _cameraHasError = true;
                                      _cameraErrorMessage = error.errorDetails?.message ?? 'Camera preview unavailable';
                                    });
                                  }
                                });

                                return _buildCameraErrorView();
                              },
                            ),

                            // Corner Target Markers Overlay
                            if (!_cameraHasError) ...[
                              _buildScannerOverlay(),
                              // Animated Laser Scan Line
                              AnimatedBuilder(
                                animation: _scanAnimation,
                                builder: (context, child) {
                                  return Positioned(
                                    top: 280 * _scanAnimation.value,
                                    left: 40,
                                    right: 40,
                                    child: Container(
                                      height: 2,
                                      decoration: BoxDecoration(
                                        color: DevSyncColors.primary,
                                        boxShadow: [
                                          BoxShadow(
                                            color: DevSyncColors.primary.withValues(alpha: 0.8),
                                            blurRadius: 8,
                                            spreadRadius: 2,
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Align the QR code within the frame to pair automatically.',
                        style: TextStyle(fontSize: 12, color: DevSyncColors.textMuted),
                        textAlign: TextAlign.center,
                      ),
                    ] else ...[
                      // Manual Input / Paste Section
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: DevSyncColors.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: DevSyncColors.border),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text(
                              'Paste Pairing Token or Enter Code',
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'Paste the full JSON pairing token or enter the 6-digit connection code.',
                              style: TextStyle(fontSize: 12, color: DevSyncColors.textSecondary),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _manualController,
                              maxLines: 4,
                              style: const TextStyle(fontFamily: 'monospace', fontSize: 13, color: Colors.white),
                              decoration: InputDecoration(
                                hintText: 'e.g. 849201 or {"id": "...", "code": "..."}',
                                suffixIcon: IconButton(
                                  icon: const Icon(Icons.paste_rounded, color: DevSyncColors.primary, size: 20),
                                  onPressed: () async {
                                    final data = await Clipboard.getData(Clipboard.kTextPlain);
                                    if (data?.text != null) {
                                      _manualController.text = data!.text!;
                                    }
                                  },
                                ),
                              ),
                            ),
                            const SizedBox(height: 14),
                            ElevatedButton.icon(
                              onPressed: _handleManualSubmit,
                              icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
                              label: const Text('Confirm & Pair', style: TextStyle(fontWeight: FontWeight.bold)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: DevSyncColors.primary,
                                foregroundColor: DevSyncColors.onPrimary,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 16),

                    // Bottom Action Row (Pick Image / Toggle Manual Input)
                    Row(
                      children: [
                        // Upload Image Button
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _handlePickImage,
                            icon: const Icon(Icons.photo_library_outlined, size: 16),
                            label: const Text('Upload QR Image', style: TextStyle(fontSize: 12)),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: DevSyncColors.textSecondary,
                              side: const BorderSide(color: DevSyncColors.border),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),

                        // Toggle Paste / Code Button
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              setState(() => _showManualInput = !_showManualInput);
                            },
                            icon: Icon(
                              _showManualInput ? Icons.camera_alt_outlined : Icons.paste_rounded,
                              size: 16,
                            ),
                            label: Text(
                              _showManualInput ? 'Use Camera' : 'Paste Token',
                              style: const TextStyle(fontSize: 12),
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: DevSyncColors.secondary,
                              side: const BorderSide(color: DevSyncColors.border),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCameraErrorView() {
    return Container(
      color: DevSyncColors.background,
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.videocam_off_rounded, color: DevSyncColors.textMuted, size: 42),
          const SizedBox(height: 10),
          const Text(
            'Camera Not Available',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white),
          ),
          const SizedBox(height: 4),
          Text(
            _cameraErrorMessage ?? 'Camera permission denied or camera device not found.',
            style: const TextStyle(fontSize: 11, color: DevSyncColors.textMuted),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 14),
          ElevatedButton.icon(
            onPressed: () => setState(() => _showManualInput = true),
            icon: const Icon(Icons.edit_note_rounded, size: 16),
            label: const Text('Enter Code / Paste Token', style: TextStyle(fontSize: 12)),
            style: ElevatedButton.styleFrom(
              backgroundColor: DevSyncColors.primary,
              foregroundColor: DevSyncColors.onPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScannerOverlay() {
    return IgnorePointer(
      child: Padding(
        padding: const EdgeInsets.all(36),
        child: Stack(
          children: [
            // Top-left corner
            Align(
              alignment: Alignment.topLeft,
              child: Container(
                width: 24,
                height: 24,
                decoration: const BoxDecoration(
                  border: Border(
                    top: BorderSide(color: DevSyncColors.primary, width: 3),
                    left: BorderSide(color: DevSyncColors.primary, width: 3),
                  ),
                ),
              ),
            ),
            // Top-right corner
            Align(
              alignment: Alignment.topRight,
              child: Container(
                width: 24,
                height: 24,
                decoration: const BoxDecoration(
                  border: Border(
                    top: BorderSide(color: DevSyncColors.primary, width: 3),
                    left: BorderSide.none,
                    right: BorderSide(color: DevSyncColors.primary, width: 3),
                  ),
                ),
              ),
            ),
            // Bottom-left corner
            Align(
              alignment: Alignment.bottomLeft,
              child: Container(
                width: 24,
                height: 24,
                decoration: const BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: DevSyncColors.primary, width: 3),
                    left: BorderSide(color: DevSyncColors.primary, width: 3),
                  ),
                ),
              ),
            ),
            // Bottom-right corner
            Align(
              alignment: Alignment.bottomRight,
              child: Container(
                width: 24,
                height: 24,
                decoration: const BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: DevSyncColors.primary, width: 3),
                    right: BorderSide(color: DevSyncColors.primary, width: 3),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
