import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'persistent_ws_client.dart';
import 'file_transfer_engine.dart';
import 'relay_api_service.dart';

enum PeerConnectionState {
  disconnected,
  connecting,
  connected,
  failed,
}

class WebRtcService {
  static WebRtcService? _instance;
  static WebRtcService get instance => _instance ??= WebRtcService._();

  WebRtcService._() {
    _initSignalingListener();
  }

  final Map<String, RTCPeerConnection> _peerConnections = {};
  final Map<String, RTCDataChannel> _dataChannels = {};
  final Map<String, bool> _makingOffer = {};
  final Map<String, Timer> _idleTimers = {};

  String? _myDeviceId;

  // Streams for incoming DataChannel payloads
  final _incomingDataController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get incomingDataStream => _incomingDataController.stream;

  final _peerStateController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get peerStateStream => _peerStateController.stream;

  Map<String, dynamic> _iceConfig = {
    'iceServers': [
      {'urls': ['stun:stun.l.google.com:19302', 'stun:stun1.l.google.com:19302']},
    ],
    'sdpSemantics': 'unified-plan',
  };

  void initialize(String myDeviceId) {
    _myDeviceId = myDeviceId;
    updateIceServersFromRelay();
  }

  /// Fetches short-lived ephemeral TURN & STUN ICE credentials from the backend
  Future<void> updateIceServersFromRelay() async {
    try {
      final servers = await RelayApiService.instance.fetchTurnCredentials();
      if (servers != null && servers.isNotEmpty) {
        _iceConfig = {
          'iceServers': servers,
          'sdpSemantics': 'unified-plan',
        };
        debugPrint('[WebRTC] Loaded ${servers.length} ICE server configs with ephemeral TURN credentials.');
      }
    } catch (e) {
      debugPrint('[WebRTC] updateIceServersFromRelay error: $e');
    }
  }

  void _resetIdleTimer(String peerDeviceId) {
    _idleTimers[peerDeviceId]?.cancel();
    _idleTimers[peerDeviceId] = Timer(const Duration(minutes: 3), () {
      debugPrint('[WebRTC] Closing idle peer connection with $peerDeviceId');
      closePeer(peerDeviceId);
    });
  }

  void _initSignalingListener() {
    PersistentWsClient.instance.webrtcSignalStream.listen((signal) async {
      final senderId = signal['senderDeviceId'] as String?;
      final signalType = signal['signalType'] as String?;
      final data = signal['data'];

      if (senderId == null || signalType == null || data == null) return;
      if (_myDeviceId == null) return;

      await _handleIncomingSignal(senderId, signalType, data);
    });
  }

  /// Establishes WebRTC Peer Connection with a target device
  Future<RTCPeerConnection> getOrCreatePeerConnection(String peerDeviceId) async {
    if (_peerConnections.containsKey(peerDeviceId)) {
      return _peerConnections[peerDeviceId]!;
    }

    final pc = await createPeerConnection(_iceConfig);
    _peerConnections[peerDeviceId] = pc;
    _makingOffer[peerDeviceId] = false;

    // ICE Candidate Exchange
    pc.onIceCandidate = (candidate) {
      if (candidate.candidate != null) {
        PersistentWsClient.instance.sendWebRtcSignal(
          recipientDeviceId: peerDeviceId,
          signalType: 'candidate',
          data: {
            'candidate': candidate.candidate,
            'sdpMid': candidate.sdpMid,
            'sdpMLineIndex': candidate.sdpMLineIndex,
          },
        );
      }
    };

    pc.onConnectionState = (state) {
      debugPrint('[WebRTC] Peer $peerDeviceId connection state: $state');
      _peerStateController.add({
        'peerDeviceId': peerDeviceId,
        'state': state.toString(),
      });
    };

    pc.onDataChannel = (channel) {
      debugPrint('[WebRTC] Received remote DataChannel from $peerDeviceId: ${channel.label}');
      _registerDataChannelHandlers(peerDeviceId, channel);
    };

    return pc;
  }

  /// Polite Peer Pattern (RFC 8829) Signal Handler
  Future<void> _handleIncomingSignal(String peerDeviceId, String signalType, dynamic data) async {
    final pc = await getOrCreatePeerConnection(peerDeviceId);
    final isPolite = (_myDeviceId ?? '').compareTo(peerDeviceId) < 0;

    try {
      if (signalType == 'offer') {
        final offerSdp = data['sdp'] as String;
        final description = RTCSessionDescription(offerSdp, 'offer');

        final offerCollision = _makingOffer[peerDeviceId] == true ||
            (await pc.getSignalingState()) != RTCSignalingState.RTCSignalingStateStable;

        if (offerCollision) {
          if (!isPolite) {
            debugPrint('[WebRTC] Impolite peer ignoring colliding offer from $peerDeviceId');
            return;
          }
          debugPrint('[WebRTC] Polite peer rolling back colliding offer from $peerDeviceId');
          await pc.setLocalDescription(RTCSessionDescription('', 'rollback'));
        }

        await pc.setRemoteDescription(description);
        final answer = await pc.createAnswer();
        await pc.setLocalDescription(answer);

        PersistentWsClient.instance.sendWebRtcSignal(
          recipientDeviceId: peerDeviceId,
          signalType: 'answer',
          data: {'sdp': answer.sdp, 'type': answer.type},
        );
      } else if (signalType == 'answer') {
        final answerSdp = data['sdp'] as String;
        final description = RTCSessionDescription(answerSdp, 'answer');
        await pc.setRemoteDescription(description);
      } else if (signalType == 'candidate') {
        final candidate = RTCIceCandidate(
          data['candidate'] as String?,
          data['sdpMid'] as String?,
          data['sdpMLineIndex'] as int?,
        );
        await pc.addCandidate(candidate);
      }
    } catch (e) {
      debugPrint('[WebRTC] Error handling signal $signalType from $peerDeviceId: $e');
    }
  }

  /// Initiates connection and creates DataChannel to peer
  Future<void> connectToPeer(String peerDeviceId) async {
    final pc = await getOrCreatePeerConnection(peerDeviceId);

    // Create DataChannel from initiator side
    final dcInit = RTCDataChannelInit()
      ..ordered = true
      ..maxRetransmits = 30;

    final dc = await pc.createDataChannel('devsync_p2p', dcInit);
    _registerDataChannelHandlers(peerDeviceId, dc);

    // Create and send SDP offer
    _makingOffer[peerDeviceId] = true;
    try {
      final offer = await pc.createOffer();
      await pc.setLocalDescription(offer);

      PersistentWsClient.instance.sendWebRtcSignal(
        recipientDeviceId: peerDeviceId,
        signalType: 'offer',
        data: {'sdp': offer.sdp, 'type': offer.type},
      );
    } finally {
      _makingOffer[peerDeviceId] = false;
    }
  }

  void _registerDataChannelHandlers(String peerDeviceId, RTCDataChannel dc) {
    _dataChannels[peerDeviceId] = dc;

    dc.onDataChannelState = (state) {
      debugPrint('[WebRTC] DataChannel with $peerDeviceId state: $state');
      if (state == RTCDataChannelState.RTCDataChannelOpen) {
        _resetIdleTimer(peerDeviceId);
        _peerStateController.add({
          'peerDeviceId': peerDeviceId,
          'dataChannelOpen': true,
        });
      }
    };

    dc.onMessage = (data) async {
      _resetIdleTimer(peerDeviceId);
      if (data.isBinary) {
        await FileTransferEngine.instance.handleIncomingBinaryChunk(data.binary);
      } else {
        try {
          final json = jsonDecode(data.text) as Map<String, dynamic>;
          final type = json['type'] as String?;

          if (type == 'transfer_offer') {
            // Receiver handles incoming transfer offer and verifies checkpoint
            final response = await FileTransferEngine.instance.handleIncomingOffer(
              transferId: json['transferId'] as String,
              fileName: json['fileName'] as String,
              fileSize: json['fileSize'] as int,
              expectedSha256: json['expectedSha256'] as String,
              chunkSize: json['chunkSize'] as int? ?? FileTransferEngine.standardChunkSize,
            );
            sendData(peerDeviceId, response);
          } else {
            _incomingDataController.add({
              'peerDeviceId': peerDeviceId,
              'payload': json,
            });
          }
        } catch (_) {}
      }
    };
  }

  /// Sends a small JSON payload over direct WebRTC DataChannel if open
  bool sendData(String peerDeviceId, Map<String, dynamic> payload) {
    _resetIdleTimer(peerDeviceId);
    final dc = _dataChannels[peerDeviceId];
    if (dc != null && dc.state == RTCDataChannelState.RTCDataChannelOpen) {
      dc.send(RTCDataChannelMessage(jsonEncode(payload)));
      return true;
    }
    return false;
  }

  /// Sends file bytes in 64 KB chunks directly from disk with backpressure & resume support
  Future<bool> sendFileStream({
    required String peerDeviceId,
    required String transferId,
    required File file,
    required List<int> neededChunks,
    required void Function(double progress) onProgress,
  }) async {
    _resetIdleTimer(peerDeviceId);
    final dc = _dataChannels[peerDeviceId];
    if (dc == null || dc.state != RTCDataChannelState.RTCDataChannelOpen) {
      return false;
    }

    return FileTransferEngine.instance.sendFileStream(
      file: file,
      transferId: transferId,
      neededChunks: neededChunks,
      sendPacket: (packet) {
        try {
          dc.send(RTCDataChannelMessage.fromBinary(packet));
          return true;
        } catch (e) {
          debugPrint('[WebRTC] Error sending binary packet: $e');
          return false;
        }
      },
      getBufferedAmount: () => dc.bufferedAmount ?? 0,
      onProgress: onProgress,
    );
  }

  /// Initiates ICE restart when network connectivity switches (e.g. Wi-Fi to 5G)
  Future<void> restartIce(String peerDeviceId) async {
    final pc = _peerConnections[peerDeviceId];
    if (pc == null) return;
    try {
      debugPrint('[WebRTC] Initiating ICE restart with peer: $peerDeviceId');
      final offer = await pc.createOffer({'iceRestart': true});
      await pc.setLocalDescription(offer);
      PersistentWsClient.instance.sendWebRtcSignal(
        recipientDeviceId: peerDeviceId,
        signalType: 'offer',
        data: {'sdp': offer.sdp, 'type': offer.type},
      );
    } catch (e) {
      debugPrint('[WebRTC] restartIce error for $peerDeviceId: $e');
    }
  }

  bool isPeerConnected(String peerDeviceId) {
    final dc = _dataChannels[peerDeviceId];
    return dc != null && dc.state == RTCDataChannelState.RTCDataChannelOpen;
  }

  void closePeer(String peerDeviceId) {
    _dataChannels[peerDeviceId]?.close();
    _dataChannels.remove(peerDeviceId);
    _peerConnections[peerDeviceId]?.close();
    _peerConnections.remove(peerDeviceId);
    _makingOffer.remove(peerDeviceId);
  }

  void dispose() {
    for (final pc in _peerConnections.values) {
      pc.close();
    }
    _peerConnections.clear();
    _dataChannels.clear();
    _incomingDataController.close();
    _peerStateController.close();
  }
}
