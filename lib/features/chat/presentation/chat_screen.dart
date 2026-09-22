import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_theme.dart';
import '../../../core/storage/database_service.dart';
import '../../../shared/utils/formatters.dart';
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
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  final FocusNode _enterNode = FocusNode();

  MessageModel? _replyingTo;
  bool _searching = false;
  String _query = '';

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
      setState(() {
        _replyingTo = null;
        _query = '';
      });
      ref.read(chatProvider.notifier).loadConversation(widget.peer.id);
      _scrollToBottom();
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    _searchController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    _enterNode.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _sendText() {
    final text = _textController.text;
    if (text.trim().isEmpty) return;
    ref.read(chatProvider.notifier).sendTextMessage(text, replyTo: _replyingTo);
    _textController.clear();
    setState(() => _replyingTo = null);
    _scrollToBottom();
  }

  Future<void> _pickAndSendFile({FileType type = FileType.any}) async {
    final result = await FilePicker.pickFiles(type: type);
    if (result.isEmpty) return;

    for (final file in result) {
      if (!kIsWeb && file.path != null) {
        await ref.read(chatProvider.notifier).sendFile(file.path!);
      } else {
        final bytes = await file.xFile.readAsBytes();
        await ref.read(chatProvider.notifier).sendFileBytes(fileName: file.name, bytes: bytes);
      }
    }
    _scrollToBottom();
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

  IconData _platformIcon(String platform) {
    switch (platform.toLowerCase()) {
      case 'windows':
        return Icons.laptop_windows_rounded;
      case 'macos':
        return Icons.laptop_mac_rounded;
      case 'linux':
        return Icons.laptop_rounded;
      case 'android':
        return Icons.phone_android_rounded;
      case 'ios':
        return Icons.phone_iphone_rounded;
      default:
        return Icons.devices_rounded;
    }
  }

  String _presence(DeviceModel peer) {
    if (peer.isLanAvailable || peer.isOnline) return 'online';
    return Formatters.formatLastSeen(peer.lastSeen);
  }

  @override
  Widget build(BuildContext context) {
    final messages = ref.watch(chatProvider);
    ref.listen(chatProvider, (_, _) => _scrollToBottom());

    final visible = messages.where((m) {
      if (_query.isEmpty) return true;
      final q = _query.toLowerCase();
      return m.content.toLowerCase().contains(q) ||
          (m.fileMetadata?.fileName.toLowerCase().contains(q) ?? false);
    }).toList();

    final entries = <Object>[];
    DateTime? lastDay;
    for (final message in visible) {
      final day = DateTime(message.timestamp.year, message.timestamp.month, message.timestamp.day);
      if (lastDay == null || day != lastDay) {
        entries.add(day);
        lastDay = day;
      }
      entries.add(message);
    }

    return Scaffold(
      backgroundColor: DevSyncColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (_searching) {
              setState(() {
                _searching = false;
                _query = '';
                _searchController.clear();
              });
              return;
            }
            ref.read(selectedPeerProvider.notifier).state = null;
          },
        ),
        title: _searching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Search in chat',
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                ),
                onChanged: (value) => setState(() => _query = value),
              )
            : InkWell(
                onTap: () => _openInfo(messages),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: DevSyncColors.surfaceVariant,
                      child: Icon(_platformIcon(widget.peer.platform), size: 18, color: DevSyncColors.primary),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(widget.peer.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                          Text(
                            _presence(widget.peer),
                            style: const TextStyle(fontSize: 12, color: DevSyncColors.textMuted, fontWeight: FontWeight.w400),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
        actions: [
          IconButton(
            icon: Icon(_searching ? Icons.close : Icons.search),
            onPressed: () {
              setState(() {
                _searching = !_searching;
                if (!_searching) {
                  _query = '';
                  _searchController.clear();
                }
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.attach_file_rounded),
            onPressed: _openAttachSheet,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: visible.isEmpty
                ? Center(
                    child: Text(
                      messages.isEmpty
                          ? 'Send a file or a note to ${widget.peer.name}'
                          : 'No messages match',
                      style: const TextStyle(color: DevSyncColors.textMuted),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: entries.length + 1,
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        return const Padding(
                          padding: EdgeInsets.fromLTRB(28, 8, 28, 12),
                          child: Text(
                            'Messages and files on this chat are encrypted between your devices.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 12, color: DevSyncColors.textMuted, height: 1.35),
                          ),
                        );
                      }
                      final entry = entries[index - 1];
                      if (entry is DateTime) {
                        return Center(
                          child: Container(
                            margin: const EdgeInsets.symmetric(vertical: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: DevSyncColors.surfaceVariant,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              Formatters.formatDayChip(entry),
                              style: const TextStyle(fontSize: 12, color: DevSyncColors.textSecondary),
                            ),
                          ),
                        );
                      }
                      final msg = entry as MessageModel;
                      return _bubble(msg);
                    },
                  ),
          ),
          if (_replyingTo != null) _replyBar(),
          _composer(),
        ],
      ),
    );
  }

  Widget _bubble(MessageModel msg) {
    void openMenu() => _openMessageMenu(msg);
    switch (msg.type) {
      case MessageType.code:
        return CodeMessageBubble(key: ValueKey(msg.id), message: msg, onLongPress: openMenu);
      case MessageType.file:
        return FileMessageBubble(key: ValueKey(msg.id), message: msg, onLongPress: openMenu);
      case MessageType.text:
      default:
        return TextMessageBubble(key: ValueKey(msg.id), message: msg, onLongPress: openMenu);
    }
  }

  Widget _replyBar() {
    return Container(
      color: DevSyncColors.surface,
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 0),
      child: Row(
        children: [
          Container(width: 3, height: 36, color: DevSyncColors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _replyingTo!.isDeleted ? 'This message was deleted' : (_replyingTo!.replyPreview ?? _replyingTo!.content),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: DevSyncColors.textSecondary, fontSize: 13),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            onPressed: () => setState(() => _replyingTo = null),
          ),
        ],
      ),
    );
  }

  Widget _composer() {
    return Container(
      color: DevSyncColors.surface,
      padding: const EdgeInsets.fromLTRB(4, 6, 8, 6),
      child: SafeArea(
        top: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            IconButton(
              icon: const Icon(Icons.add_rounded, color: DevSyncColors.textSecondary),
              onPressed: _openAttachSheet,
            ),
            Expanded(
              child: KeyboardListener(
                focusNode: _enterNode,
                onKeyEvent: (event) {
                  if (event is KeyDownEvent &&
                      event.logicalKey == LogicalKeyboardKey.enter &&
                      !HardwareKeyboard.instance.isShiftPressed) {
                    _sendText();
                  }
                },
                child: TextField(
                  controller: _textController,
                  focusNode: _focusNode,
                  minLines: 1,
                  maxLines: 5,
                  textCapitalization: TextCapitalization.sentences,
                  style: const TextStyle(fontSize: 15, color: DevSyncColors.textPrimary),
                  decoration: const InputDecoration(
                    hintText: 'Message',
                    contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            IconButton(
              style: IconButton.styleFrom(
                backgroundColor: DevSyncColors.primary,
                foregroundColor: DevSyncColors.onPrimary,
              ),
              icon: const Icon(Icons.send_rounded, size: 18),
              onPressed: _sendText,
            ),
          ],
        ),
      ),
    );
  }

  void _openAttachSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: DevSyncColors.surface,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.insert_drive_file_outlined, color: DevSyncColors.primary),
                title: const Text('Document'),
                subtitle: const Text('Any file from this laptop'),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickAndSendFile();
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_outlined, color: DevSyncColors.primary),
                title: const Text('Photos and videos'),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickAndSendFile(type: FileType.media);
                },
              ),
              ListTile(
                leading: const Icon(Icons.code_rounded, color: DevSyncColors.primary),
                title: const Text('Code snippet'),
                onTap: () {
                  Navigator.pop(ctx);
                  _openCodeSnippetDialog();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _openMessageMenu(MessageModel message) {
    showModalBottomSheet(
      context: context,
      backgroundColor: DevSyncColors.surface,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!message.isDeleted)
                ListTile(
                  leading: const Icon(Icons.reply_rounded),
                  title: const Text('Reply'),
                  onTap: () {
                    Navigator.pop(ctx);
                    setState(() => _replyingTo = message);
                    _focusNode.requestFocus();
                  },
                ),
              if (!message.isDeleted && message.type != MessageType.file)
                ListTile(
                  leading: const Icon(Icons.copy_rounded),
                  title: const Text('Copy'),
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: message.content));
                    Navigator.pop(ctx);
                  },
                ),
              ListTile(
                leading: Icon(message.isStarred ? Icons.star_rounded : Icons.star_outline_rounded),
                title: Text(message.isStarred ? 'Unstar' : 'Star'),
                onTap: () {
                  Navigator.pop(ctx);
                  ref.read(chatProvider.notifier).toggleStar(message);
                },
              ),
              if (!message.isDeleted)
                ListTile(
                  leading: const Icon(Icons.forward_rounded),
                  title: const Text('Forward'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _forward(message);
                  },
                ),
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded, color: DevSyncColors.error),
                title: const Text('Delete'),
                onTap: () {
                  Navigator.pop(ctx);
                  _confirmDelete(message);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _forward(MessageModel message) async {
    final peers = ref.read(peersProvider).where((p) => p.id != widget.peer.id).toList();
    if (peers.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Link another device before forwarding')),
      );
      return;
    }
    final target = await showModalBottomSheet<DeviceModel>(
      context: context,
      backgroundColor: DevSyncColors.surface,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('Forward to', style: TextStyle(fontWeight: FontWeight.w600)),
              ),
              for (final peer in peers)
                ListTile(
                  leading: Icon(_platformIcon(peer.platform)),
                  title: Text(peer.name),
                  onTap: () => Navigator.pop(ctx, peer),
                ),
            ],
          ),
        );
      },
    );
    if (target == null) return;
    final text = message.type == MessageType.file
        ? 'File: ${message.fileMetadata?.fileName ?? 'attachment'}'
        : message.content;
    await ref.read(chatProvider.notifier).sendTextToPeer(target, text);
  }

  Future<void> _confirmDelete(MessageModel message) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: DevSyncColors.surface,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: const Text('Delete for me'),
                onTap: () => Navigator.pop(ctx, 'me'),
              ),
              if (message.isOutgoing && !message.isDeleted)
                ListTile(
                  title: const Text('Delete for everyone'),
                  onTap: () => Navigator.pop(ctx, 'all'),
                ),
            ],
          ),
        );
      },
    );
    if (choice == 'me') {
      await ref.read(chatProvider.notifier).deleteForMe(message);
    } else if (choice == 'all') {
      await ref.read(chatProvider.notifier).deleteForEveryone(message);
    }
  }

  void _openInfo(List<MessageModel> messages) {
    final files = messages.where((m) => m.type == MessageType.file && !m.isDeleted).toList();
    final muted = DatabaseService.instance.isMuted(widget.peer.id);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _ChatInfoPage(
          peer: widget.peer,
          files: files,
          initiallyMuted: muted,
          platformIcon: _platformIcon(widget.peer.platform),
        ),
      ),
    );
  }
}

class _ChatInfoPage extends ConsumerStatefulWidget {
  final DeviceModel peer;
  final List<MessageModel> files;
  final bool initiallyMuted;
  final IconData platformIcon;

  const _ChatInfoPage({
    required this.peer,
    required this.files,
    required this.initiallyMuted,
    required this.platformIcon,
  });

  @override
  ConsumerState<_ChatInfoPage> createState() => _ChatInfoPageState();
}

class _ChatInfoPageState extends ConsumerState<_ChatInfoPage> {
  late bool _muted = widget.initiallyMuted;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Chat info')),
      body: ListView(
        children: [
          const SizedBox(height: 24),
          CircleAvatar(
            radius: 36,
            backgroundColor: DevSyncColors.surfaceVariant,
            child: Icon(widget.platformIcon, color: DevSyncColors.primary, size: 32),
          ),
          const SizedBox(height: 12),
          Text(widget.peer.name, textAlign: TextAlign.center, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(
            widget.peer.platform,
            textAlign: TextAlign.center,
            style: const TextStyle(color: DevSyncColors.textMuted),
          ),
          const SizedBox(height: 20),
          SwitchListTile(
            title: const Text('Mute notifications'),
            value: _muted,
            activeThumbColor: DevSyncColors.primary,
            onChanged: (value) async {
              await DatabaseService.instance.setMuted(widget.peer.id, value);
              setState(() => _muted = value);
              ref.read(conversationTickProvider.notifier).state++;
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: const Text('Clear chat'),
            onTap: () async {
              final myId = ref.read(myDeviceProvider).identity?.deviceId;
              if (myId == null) return;
              await DatabaseService.instance.clearConversation(myId, widget.peer.id);
              ref.read(chatProvider.notifier).loadConversation(widget.peer.id);
              if (context.mounted) Navigator.pop(context);
            },
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Text(
              'Shared files (${widget.files.length})',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          if (widget.files.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('No files in this chat yet', style: TextStyle(color: DevSyncColors.textMuted)),
            )
          else
            for (final file in widget.files.reversed)
              ListTile(
                leading: const Icon(Icons.insert_drive_file_outlined),
                title: Text(file.fileMetadata?.fileName ?? 'File'),
                subtitle: Text(Formatters.formatBytes(file.fileMetadata?.fileSize ?? 0)),
              ),
        ],
      ),
    );
  }
}
