import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_theme.dart';
import '../../../core/network/relay_api_service.dart';
import '../../../core/network/sse_relay_client.dart';
import '../../../core/storage/database_service.dart';
import '../../../shared/utils/formatters.dart';
import '../../chat/domain/message_model.dart';
import '../../chat/presentation/chat_providers.dart';
import '../../auth/presentation/auth_screen.dart';
import '../../auth/presentation/hurray_connection_dialog.dart';
import '../domain/device_model.dart';
import 'device_providers.dart';
import 'qr_pair_sheet.dart';

class DeviceListScreen extends ConsumerStatefulWidget {
  const DeviceListScreen({super.key});

  @override
  ConsumerState<DeviceListScreen> createState() => _DeviceListScreenState();
}

class _DeviceListScreenState extends ConsumerState<DeviceListScreen> {
  final TextEditingController _searchController = TextEditingController();
  StreamSubscription? _sseSubscription;
  bool _searchOpen = false;
  bool _showArchived = false;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _subscribeToPairingEvents();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(peersProvider.notifier).refreshMeshPeers();
    });
  }

  void _subscribeToPairingEvents() {
    _sseSubscription = SseRelayClient.instance.onMessageReceived.listen((rawMsg) {
      if (rawMsg['type'] == 'device_paired') {
        _handleDevicePairedEvent(rawMsg);
      }
    });
  }

  void _handleDevicePairedEvent(Map<String, dynamic> rawMsg) {
    try {
      final cipherText = rawMsg['cipherText'] as String?;
      if (cipherText != null) {
        final decoded = utf8.decode(base64Decode(cipherText));
        final data = jsonDecode(decoded) as Map<String, dynamic>;
        final pd = data['pairedDevice'] as Map<String, dynamic>?;
        if (pd != null) {
          final peerId = pd['deviceId'] as String?;
          final myId = DatabaseService.instance.readIdentityField('device_id');
          if (peerId == null || (myId != null && peerId == myId)) {
            return;
          }

          final newPeer = DeviceModel(
            id: peerId,
            name: pd['deviceName'] as String? ?? 'Remote Device',
            platform: pd['platform'] as String? ?? 'unknown',
            signingPublicKey: pd['signingPublicKey'] as String? ?? '',
            exchangePublicKey: pd['exchangePublicKey'] as String? ?? '',
            lanIp: pd['lanIp'] as String?,
            lanPort: pd['lanPort'] as int?,
            isOnline: true,
            isLanAvailable: false,
            lastSeen: DateTime.now(),
          );
          DatabaseService.instance.savePeer(newPeer);
          ref.read(peersProvider.notifier).addOrUpdatePeer(newPeer);
          ref.read(peersProvider.notifier).refreshMeshPeers();

          final code = DatabaseService.instance.getConnectionCode() ?? '------';
          HurrayConnectionDialog.show(
            context,
            pairedDevice: newPeer,
            connectionCode: code,
          );
        }
      }
    } catch (e) {
      debugPrint('Error in _handleDevicePairedEvent: $e');
    }
  }

  @override
  void dispose() {
    _sseSubscription?.cancel();
    _searchController.dispose();
    super.dispose();
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

  void _showRenameDialog(BuildContext context, String currentName) {
    final controller = TextEditingController(text: currentName);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: DevSyncColors.surface,
        title: const Text('Rename This Device'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'e.g. Workstation PC, M3 Mac...'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isEmpty) return;
              await ref.read(myDeviceProvider.notifier).renameDevice(name);
              if (ctx.mounted) Navigator.of(ctx).pop();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('This device is now $name')),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: DevSyncColors.primary),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showSettingsDialog(BuildContext context) {
    final relayController = TextEditingController(text: DatabaseService.instance.getRelayUrl());
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: DevSyncColors.surface,
        title: const Text('Network & Relay Settings'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Vercel Message Relay URL:',
              style: TextStyle(fontSize: 13, color: DevSyncColors.textSecondary),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: relayController,
              decoration: const InputDecoration(
                hintText: 'https://devsync-backend.vercel.app',
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Local LAN Direct transfers do not use bandwidth from this server.',
              style: TextStyle(fontSize: 11, color: DevSyncColors.textMuted),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final newUrl = relayController.text.trim();
              Navigator.of(ctx).pop();
              await DatabaseService.instance.setRelayUrl(newUrl);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Relay settings saved')),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: DevSyncColors.primary),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  String _preview(MessageModel? message) {
    if (message == null) return 'No messages yet';
    if (message.isDeleted) return 'This message was deleted';
    switch (message.type) {
      case MessageType.file:
        return message.fileMetadata?.fileName ?? 'File';
      case MessageType.code:
        return 'Code snippet';
      case MessageType.status:
        return '';
      case MessageType.text:
        return message.content.replaceAll('\n', ' ');
    }
  }

  void _openLinkSheet() {
    final myState = ref.read(myDeviceProvider);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: DevSyncColors.surface,
      builder: (ctx) {
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: _buildConnectionsCard(ctx, myState.identity?.deviceId ?? ''),
          ),
        );
      },
    );
  }

  void _openStarred() {
    final starred = DatabaseService.instance.getStarredMessages();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('Starred messages')),
          body: starred.isEmpty
              ? const Center(child: Text('No starred messages', style: TextStyle(color: DevSyncColors.textMuted)))
              : ListView(
                  children: [
                    for (final message in starred)
                      ListTile(
                        title: Text(_preview(message), maxLines: 2, overflow: TextOverflow.ellipsis),
                        subtitle: Text(Formatters.formatTimestamp(message.timestamp)),
                      ),
                  ],
                ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final myState = ref.watch(myDeviceProvider);
    final peers = ref.watch(peersProvider);
    ref.watch(conversationTickProvider);
    final myId = myState.identity?.deviceId;

    final archived = <DeviceModel>[];
    final chats = <DeviceModel>[];
    for (final peer in peers) {
      if (DatabaseService.instance.isArchived(peer.id)) {
        archived.add(peer);
      } else {
        chats.add(peer);
      }
    }

    int lastTime(DeviceModel peer) {
      if (myId == null) return peer.lastSeen.millisecondsSinceEpoch;
      return DatabaseService.instance.getLastMessage(myId, peer.id)?.timestamp.millisecondsSinceEpoch ??
          peer.lastSeen.millisecondsSinceEpoch;
    }

    void sortChats(List<DeviceModel> list) {
      list.sort((a, b) {
        final ap = DatabaseService.instance.isPinned(a.id);
        final bp = DatabaseService.instance.isPinned(b.id);
        if (ap != bp) return ap ? -1 : 1;
        return lastTime(b).compareTo(lastTime(a));
      });
    }

    sortChats(chats);
    sortChats(archived);

    final source = _showArchived ? archived : chats;
    final visible = source.where((peer) {
      if (_query.isEmpty) return true;
      final q = _query.toLowerCase();
      final preview = myId == null ? '' : _preview(DatabaseService.instance.getLastMessage(myId, peer.id)).toLowerCase();
      return peer.name.toLowerCase().contains(q) || preview.contains(q);
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: _searchOpen
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Search chats',
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                ),
                onChanged: (value) => setState(() => _query = value),
              )
            : InkWell(
                onTap: () {
                  final current = myState.identity?.deviceName ?? '';
                  _showRenameDialog(context, current.isEmpty ? 'This device' : current);
                },
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      myState.identity?.deviceName ?? 'This device',
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                    ),
                    const Text(
                      'Tap the name to rename',
                      style: TextStyle(fontSize: 11, color: DevSyncColors.textMuted, fontWeight: FontWeight.w400),
                    ),
                  ],
                ),
              ),
        leading: _showArchived
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() => _showArchived = false),
              )
            : null,
        actions: [
          IconButton(
            icon: Icon(_searchOpen ? Icons.close : Icons.search),
            onPressed: () {
              setState(() {
                _searchOpen = !_searchOpen;
                if (!_searchOpen) {
                  _query = '';
                  _searchController.clear();
                }
              });
            },
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'link':
                  _openLinkSheet();
                case 'starred':
                  _openStarred();
                case 'rename':
                  if (myState.identity != null) {
                    _showRenameDialog(context, myState.identity!.deviceName);
                  }
                case 'settings':
                  _showSettingsDialog(context);
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'link', child: Text('Link a device')),
              PopupMenuItem(value: 'starred', child: Text('Starred messages')),
              PopupMenuItem(value: 'rename', child: Text('Rename this device')),
              PopupMenuItem(value: 'settings', child: Text('Settings')),
            ],
          ),
        ],
      ),
      floatingActionButton: _showArchived
          ? null
          : FloatingActionButton(
              backgroundColor: DevSyncColors.primary,
              foregroundColor: DevSyncColors.onPrimary,
              onPressed: _openLinkSheet,
              child: const Icon(Icons.chat_rounded),
            ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(peersProvider.notifier).refreshMeshPeers(),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            if (!_showArchived && archived.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.archive_outlined, color: DevSyncColors.textSecondary),
                title: const Text('Archived'),
                trailing: Text('${archived.length}', style: const TextStyle(color: DevSyncColors.textMuted)),
                onTap: () => setState(() => _showArchived = true),
              ),
            if (visible.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(32, 72, 32, 24),
                child: Column(
                  children: [
                    const Icon(Icons.forum_outlined, size: 42, color: DevSyncColors.textMuted),
                    const SizedBox(height: 12),
                    Text(
                      peers.isEmpty ? 'No devices linked yet' : 'No chats match',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Link the other laptop, then send files the same way you would send a chat.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: DevSyncColors.textMuted, height: 1.4),
                    ),
                  ],
                ),
              )
            else
              for (final peer in visible) _buildPeerTile(context, peer, myId),
          ],
        ),
      ),
    );
  }

  Widget _buildPeerTile(BuildContext context, DeviceModel peer, String? myId) {
    final last = myId == null ? null : DatabaseService.instance.getLastMessage(myId, peer.id);
    final unread = DatabaseService.instance.unreadCount(peer.id);
    final pinned = DatabaseService.instance.isPinned(peer.id);
    final muted = DatabaseService.instance.isMuted(peer.id);
    final archived = DatabaseService.instance.isArchived(peer.id);

    return ListTile(
      onTap: () {
        ref.read(selectedPeerProvider.notifier).state = peer;
      },
      onLongPress: () async {
        final action = await showModalBottomSheet<String>(
          context: context,
          backgroundColor: DevSyncColors.surface,
          builder: (ctx) {
            return SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    title: Text(pinned ? 'Unpin' : 'Pin'),
                    onTap: () => Navigator.pop(ctx, 'pin'),
                  ),
                  ListTile(
                    title: Text(muted ? 'Unmute' : 'Mute'),
                    onTap: () => Navigator.pop(ctx, 'mute'),
                  ),
                  ListTile(
                    title: Text(archived ? 'Unarchive' : 'Archive'),
                    onTap: () => Navigator.pop(ctx, 'archive'),
                  ),
                ],
              ),
            );
          },
        );
        if (action == 'pin') await DatabaseService.instance.setPinned(peer.id, !pinned);
        if (action == 'mute') await DatabaseService.instance.setMuted(peer.id, !muted);
        if (action == 'archive') await DatabaseService.instance.setArchived(peer.id, !archived);
        if (mounted) setState(() {});
      },
      leading: Stack(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: DevSyncColors.surfaceVariant,
            child: Icon(_getPlatformIcon(peer.platform), color: DevSyncColors.primary, size: 22),
          ),
          if (peer.isOnline || peer.isLanAvailable)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: DevSyncColors.success,
                  border: Border.all(color: DevSyncColors.background, width: 2),
                ),
              ),
            ),
        ],
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              peer.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
            ),
          ),
          if (last != null)
            Text(
              Formatters.formatChatListTime(last.timestamp),
              style: TextStyle(
                fontSize: 12,
                color: unread > 0 ? DevSyncColors.primary : DevSyncColors.textMuted,
              ),
            ),
        ],
      ),
      subtitle: Row(
        children: [
          if (muted) ...[
            const Icon(Icons.volume_off_rounded, size: 14, color: DevSyncColors.textMuted),
            const SizedBox(width: 4),
          ],
          Expanded(
            child: Text(
              _preview(last),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: DevSyncColors.textSecondary, fontSize: 13),
            ),
          ),
          if (pinned) const Icon(Icons.push_pin_rounded, size: 14, color: DevSyncColors.textMuted),
          if (unread > 0) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: DevSyncColors.primary,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                unread > 99 ? '99+' : '$unread',
                style: const TextStyle(color: DevSyncColors.onPrimary, fontSize: 11, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // --- Connections & Cross-Device Pairing Card ---

  Widget _buildConnectionsCard(BuildContext context, String deviceId) {
    final connectionCode = DatabaseService.instance.getConnectionCode();
    final userEmail = DatabaseService.instance.getUserEmail();

    // Format code: e.g. 492817 -> 492 - 817
    String formattedCode = '------';
    if (connectionCode != null && connectionCode.length == 6) {
      formattedCode = '${connectionCode.substring(0, 3)} - ${connectionCode.substring(3)}';
    } else if (connectionCode != null) {
      formattedCode = connectionCode;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: DevSyncColors.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: DevSyncColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: DevSyncColors.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.hub_rounded,
                  color: DevSyncColors.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Pairing code',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: DevSyncColors.textPrimary,
                      ),
                    ),
                    Text(
                      'Same code on every device',
                      style: TextStyle(fontSize: 11, color: DevSyncColors.textSecondary),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: DevSyncColors.success.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: DevSyncColors.success.withValues(alpha: 0.4)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.circle, size: 6, color: DevSyncColors.success),
                    SizedBox(width: 4),
                    Text(
                      'ACTIVE',
                      style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: DevSyncColors.success),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          if (connectionCode != null) ...[
            // 6-Digit Code Presentation Box
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
              decoration: BoxDecoration(
                color: DevSyncColors.background,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: DevSyncColors.border),
              ),
              child: Column(
                children: [
                  const Text(
                    'Code',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                      color: DevSyncColors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 6),
                  SelectableText(
                    formattedCode,
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 3,
                      fontFamily: 'monospace',
                      color: DevSyncColors.textPrimary,
                    ),
                  ),
                  if (userEmail != null && userEmail.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Linked to: $userEmail',
                      style: const TextStyle(fontSize: 11, color: DevSyncColors.textSecondary),
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 12),

            // Action Buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: connectionCode));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Connection Code copied to clipboard!'),
                          backgroundColor: DevSyncColors.primary,
                        ),
                      );
                    },
                    icon: const Icon(Icons.copy_rounded, size: 16),
                    label: const Text('Copy Code', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: DevSyncColors.primary,
                      side: const BorderSide(color: DevSyncColors.primary),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.outlined(
                  onPressed: () => _regenerateCode(deviceId),
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  tooltip: 'Regenerate Code',
                ),
                const SizedBox(width: 8),
                IconButton.outlined(
                  onPressed: () {
                    showModalBottomSheet(
                      context: context,
                      backgroundColor: Colors.transparent,
                      isScrollControlled: true,
                      builder: (_) => const QrPairSheet(),
                    );
                  },
                  icon: const Icon(Icons.qr_code_2_rounded, size: 18),
                  tooltip: 'Show QR Code',
                ),
              ],
            ),

            const SizedBox(height: 10),

            const Text(
              'On your other devices, select "Login" and enter this 6-digit code to pair instantly.',
              style: TextStyle(fontSize: 11, color: DevSyncColors.textMuted, height: 1.4),
            ),
          ] else ...[
            // Prompt to Register / Create Connection Code
            const Text(
              'Register your device account once to generate your persistent 6-digit Connection Code for multi-device pairing.',
              style: TextStyle(fontSize: 12, color: DevSyncColors.textSecondary, height: 1.4),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const AuthScreen()),
                  );
                },
                icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                label: const Text('Register & Get Connection Code', style: TextStyle(fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: DevSyncColors.primary,
                  foregroundColor: DevSyncColors.onPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _regenerateCode(String deviceId) async {
    final email = DatabaseService.instance.getUserEmail() ?? '';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: DevSyncColors.surface,
        title: const Text('Regenerate Connection Code?'),
        content: const Text(
          'Existing paired devices will remain connected, but any new devices will need to enter the new 6-digit code.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: DevSyncColors.primary, foregroundColor: DevSyncColors.onPrimary),
            child: const Text('Regenerate'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final newCode = await RelayApiService.instance.regenerateConnectionCode(
        email: email.isNotEmpty ? email : null,
        deviceId: deviceId,
      );
      if (newCode != null) {
        await DatabaseService.instance.setConnectionCode(newCode);
        final myState = ref.read(myDeviceProvider);
        if (myState.identity != null) {
          await RelayApiService.instance.registerDevice(
            myState.identity!,
            lanIp: myState.localIp,
            lanPort: myState.lanPort,
            connectionCode: newCode,
          );
        }
        setState(() {});
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('New Connection Code generated: $newCode'),
              backgroundColor: DevSyncColors.success,
            ),
          );
        }
      }
    }
  }
}
