import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_theme.dart';
import '../../devices/domain/device_model.dart';
import '../../devices/presentation/device_providers.dart';
import '../domain/message_model.dart';
import 'chat_providers.dart';
import 'widgets/code_message_bubble.dart';
import 'widgets/code_snippet_dialog.dart';
import 'widgets/file_message_bubble.dart';
import 'widgets/text_message_bubble.dart';

class ChatScreen extends ConsumerStatefulWidget {
  final DeviceModel peer;

  const ChatScreen({super.key, required this.peer});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(chatProvider.notifier).loadConversation(widget.peer.id);
      _scrollToBottom();
    });
  }

  @override
  void didUpdateWidget(covariant ChatScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.peer.id != widget.peer.id) {
      ref.read(chatProvider.notifier).loadConversation(widget.peer.id);
      _scrollToBottom();
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _sendText() {
    final text = _textController.text;
    if (text.trim().isNotEmpty) {
      ref.read(chatProvider.notifier).sendTextMessage(text);
      _textController.clear();
      _scrollToBottom();
    }
  }

  Future<void> _pickAndSendFile() async {
    final result = await FilePicker.pickFiles(
      type: FileType.any,
    );

    if (result.isNotEmpty) {
      final file = result.first;
      if (!kIsWeb && file.path != null) {
        await ref.read(chatProvider.notifier).sendFile(file.path!);
      } else {
        final bytes = await file.xFile.readAsBytes();
        await ref.read(chatProvider.notifier).sendFileBytes(
              fileName: file.name,
              bytes: bytes,
            );
      }
      _scrollToBottom();
    }
  }

  void _openCodeSnippetDialog() {
    showDialog(
      context: context,
      builder: (ctx) => CodeSnippetDialog(
        onSend: (code, language) {
          ref.read(chatProvider.notifier).sendCodeSnippet(code: code, language: language);
          _scrollToBottom();
        },
      ),
    );
  }

  IconData _getPlatformIcon(String platform) {
    switch (platform.toLowerCase()) {
      case 'windows':
        return Icons.window_rounded;
      case 'macos':
        return Icons.apple_rounded;
      case 'linux':
        return Icons.terminal_rounded;
      case 'android':
        return Icons.android_rounded;
      case 'ios':
        return Icons.phone_iphone_rounded;
      default:
        return Icons.devices_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final messages = ref.watch(chatProvider);

    // Re-scroll on new message
    ref.listen(chatProvider, (_, _) => _scrollToBottom());

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            ref.read(selectedPeerProvider.notifier).state = null;
          },
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: DevSyncColors.surfaceVariant,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(_getPlatformIcon(widget.peer.platform), size: 18, color: DevSyncColors.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.peer.name,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: widget.peer.isLanAvailable
                              ? DevSyncColors.secondary
                              : (widget.peer.isOnline ? DevSyncColors.primary : DevSyncColors.textMuted),
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        widget.peer.isLanAvailable
                            ? 'LAN Direct (${widget.peer.lanIp}:${widget.peer.lanPort})'
                            : (widget.peer.isOnline ? 'Vercel Relay' : 'Offline (Queued)'),
                        style: TextStyle(
                          fontSize: 11,
                          color: widget.peer.isLanAvailable ? DevSyncColors.secondary : DevSyncColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline_rounded),
            tooltip: 'Device Details',
            onPressed: () => _showDeviceDetails(context),
          ),
        ],
      ),
      body: Column(
        children: [
          // Security / E2EE Banner
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            color: DevSyncColors.surfaceVariant.withValues(alpha: 0.5),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.lock_outline_rounded, size: 12, color: DevSyncColors.secondary),
                SizedBox(width: 6),
                Text(
                  'End-to-End Encrypted with X25519 + AES-256-GCM',
                  style: TextStyle(fontSize: 11, color: DevSyncColors.textSecondary),
                ),
              ],
            ),
          ),

          // Message List
          Expanded(
            child: messages.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.forum_outlined, size: 48, color: DevSyncColors.textMuted),
                        const SizedBox(height: 12),
                        Text(
                          'No messages with ${widget.peer.name} yet',
                          style: const TextStyle(color: DevSyncColors.textSecondary, fontSize: 14),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Send code snippets, files, or messages across your devices.',
                          style: TextStyle(color: DevSyncColors.textMuted, fontSize: 12),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final msg = messages[index];
                      switch (msg.type) {
                        case MessageType.code:
                          return CodeMessageBubble(key: ValueKey(msg.id), message: msg);
                        case MessageType.file:
                          return FileMessageBubble(key: ValueKey(msg.id), message: msg);
                        case MessageType.text:
                        default:
                          return TextMessageBubble(key: ValueKey(msg.id), message: msg);
                      }
                    },
                  ),
          ),

          // Input Bar
          _buildInputBar(),
        ],
      ),
    );
  }

  Widget _buildInputBar() {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: const BoxDecoration(
        color: DevSyncColors.surface,
        border: Border(top: BorderSide(color: DevSyncColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            // Attach File Button
            IconButton(
              icon: const Icon(Icons.attach_file_rounded, color: DevSyncColors.textSecondary),
              tooltip: 'Share File (Auto-categorized)',
              onPressed: _pickAndSendFile,
            ),

            // Share Code Button
            IconButton(
              icon: const Icon(Icons.code_rounded, color: DevSyncColors.accent),
              tooltip: 'Share Code Snippet',
              onPressed: _openCodeSnippetDialog,
            ),

            const SizedBox(width: 4),

            // Text Field
            Expanded(
              child: KeyboardListener(
                focusNode: FocusNode(),
                onKeyEvent: (event) {
                  // Desktop: Enter sends, Shift+Enter adds newline
                  if (event is KeyDownEvent &&
                      event.logicalKey == LogicalKeyboardKey.enter &&
                      !HardwareKeyboard.instance.isShiftPressed) {
                    _sendText();
                  }
                },
                child: TextField(
                  controller: _textController,
                  focusNode: _focusNode,
                  maxLines: 4,
                  minLines: 1,
                  style: const TextStyle(fontSize: 14, color: DevSyncColors.textPrimary),
                  decoration: const InputDecoration(
                    hintText: 'Type a message or paste code...',
                    contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  ),
                ),
              ),
            ),

            const SizedBox(width: 8),

            // Send Button
            Container(
              decoration: const BoxDecoration(
                color: DevSyncColors.primary,
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: const Icon(Icons.send_rounded, color: Colors.white, size: 18),
                onPressed: _sendText,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showDeviceDetails(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: DevSyncColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.peer.name,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: DevSyncColors.textPrimary),
              ),
              const SizedBox(height: 12),
              _detailRow('Device ID', widget.peer.id),
              _detailRow('Platform', widget.peer.platform.toUpperCase()),
              _detailRow('LAN IP', widget.peer.lanIp ?? 'Not detected'),
              _detailRow('LAN Port', '${widget.peer.lanPort ?? 42042}'),
              _detailRow('Status', widget.peer.isLanAvailable ? 'LAN Direct' : 'Remote Relay'),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 13, color: DevSyncColors.textMuted)),
          Text(value, style: const TextStyle(fontSize: 13, color: DevSyncColors.textPrimary, fontFamily: 'monospace')),
        ],
      ),
    );
  }
}
