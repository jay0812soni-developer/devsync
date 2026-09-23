import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart' as dart_crypto;
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../storage/local_file_manager.dart';
import '../storage/file_categorizer.dart';

class TransferCheckpoint {
  final String transferId;
  final String fileName;
  final int fileSize;
  final int chunkSize;
  final int totalChunks;
  final String expectedSha256;
  final Set<int> verifiedChunks;
  int lastUpdated;

  TransferCheckpoint({
    required this.transferId,
    required this.fileName,
    required this.fileSize,
    required this.chunkSize,
    required this.totalChunks,
    required this.expectedSha256,
    required this.verifiedChunks,
    required this.lastUpdated,
  });

  Map<String, dynamic> toJson() => {
    'transferId': transferId,
    'fileName': fileName,
    'fileSize': fileSize,
    'chunkSize': chunkSize,
    'totalChunks': totalChunks,
    'expectedSha256': expectedSha256,
    'verifiedChunks': verifiedChunks.toList(),
    'lastUpdated': lastUpdated,
  };

  factory TransferCheckpoint.fromJson(Map<String, dynamic> json) {
    return TransferCheckpoint(
      transferId: json['transferId'] as String,
      fileName: json['fileName'] as String,
      fileSize: json['fileSize'] as int,
      chunkSize: json['chunkSize'] as int? ?? 65536,
      totalChunks: json['totalChunks'] as int,
      expectedSha256: json['expectedSha256'] as String,
      verifiedChunks: Set<int>.from(json['verifiedChunks'] as List? ?? []),
      lastUpdated: json['lastUpdated'] as int? ?? DateTime.now().millisecondsSinceEpoch,
    );
  }
}

class FileTransferProgress {
  final String transferId;
  final String fileName;
  final int totalBytes;
  final int transferredBytes;
  final double fraction;
  final bool isCompleted;
  final String? savedFilePath;
  final String? error;

  FileTransferProgress({
    required this.transferId,
    required this.fileName,
    required this.totalBytes,
    required this.transferredBytes,
    required this.fraction,
    this.isCompleted = false,
    this.savedFilePath,
    this.error,
  });
}

/// Standard IEEE 802.3 CRC-32 calculation for per-chunk verification
int calculateCrc32(Uint8List data) {
  var crc = 0xFFFFFFFF;
  for (final byte in data) {
    crc ^= byte;
    for (var i = 0; i < 8; i++) {
      if ((crc & 1) != 0) {
        crc = (crc >> 1) ^ 0xEDB88320;
      } else {
        crc >>= 1;
      }
    }
  }
  return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}

/// Robust, disk-backed, chunk-verified file transfer engine with resume support
class FileTransferEngine {
  static FileTransferEngine? _instance;
  static FileTransferEngine get instance => _instance ??= FileTransferEngine._();

  FileTransferEngine._();

  static const int standardChunkSize = 64 * 1024; // 64 KB standard chunks

  final _progressController = StreamController<FileTransferProgress>.broadcast();
  Stream<FileTransferProgress> get progressStream => _progressController.stream;

  // Active receiver state: transferId -> RandomAccessFile
  final Map<String, RandomAccessFile> _activePartFiles = {};
  final Map<String, TransferCheckpoint> _activeCheckpoints = {};

  final Set<String> _pausedTransfers = {};
  Directory? stagingDirOverride;

  Future<Directory> _getStagingDirectory() async {
    if (stagingDirOverride != null) {
      if (!await stagingDirOverride!.exists()) {
        await stagingDirOverride!.create(recursive: true);
      }
      return stagingDirOverride!;
    }

    Directory base;
    if (kIsWeb) {
      return Directory('');
    }
    try {
      if (Platform.isAndroid || Platform.isIOS) {
        base = await getApplicationDocumentsDirectory();
      } else {
        base = await getTemporaryDirectory();
      }
    } catch (_) {
      base = Directory.systemTemp;
    }

    final staging = Directory(p.join(base.path, '.devsync_staging'));
    if (!await staging.exists()) {
      await staging.create(recursive: true);
    }
    return staging;
  }

  File _getMetaFile(Directory stagingDir, String transferId) {
    return File(p.join(stagingDir.path, '$transferId.meta.json'));
  }

  File _getPartFile(Directory stagingDir, String transferId) {
    return File(p.join(stagingDir.path, '$transferId.part'));
  }

  /// Receiver: Evaluates an incoming transfer offer and verifies checkpoint match
  Future<Map<String, dynamic>> handleIncomingOffer({
    required String transferId,
    required String fileName,
    required int fileSize,
    required String expectedSha256,
    int chunkSize = standardChunkSize,
  }) async {
    final staging = await _getStagingDirectory();
    final metaFile = _getMetaFile(staging, transferId);
    final partFile = _getPartFile(staging, transferId);

    final totalChunks = (fileSize + chunkSize - 1) ~/ chunkSize;

    // Check if previous checkpoint exists
    if (await metaFile.exists() && await partFile.exists()) {
      try {
        final content = await metaFile.readAsString();
        final existingCheckpoint = TransferCheckpoint.fromJson(jsonDecode(content));

        // Strict metadata match validation (Correction 4)
        if (existingCheckpoint.expectedSha256 == expectedSha256 &&
            existingCheckpoint.fileSize == fileSize &&
            existingCheckpoint.totalChunks == totalChunks) {
          
          debugPrint('[FileTransferEngine] Found valid checkpoint for $transferId. Resuming from ${existingCheckpoint.verifiedChunks.length}/$totalChunks chunks.');
          
          _activeCheckpoints[transferId] = existingCheckpoint;
          _activePartFiles[transferId] ??= await partFile.open(mode: FileMode.append);

          final needed = <int>[];
          for (var i = 0; i < totalChunks; i++) {
            if (!existingCheckpoint.verifiedChunks.contains(i)) {
              needed.add(i);
            }
          }

          return {
            'type': 'transfer_resume_ack',
            'transferId': transferId,
            'canResume': true,
            'verifiedChunksCount': existingCheckpoint.verifiedChunks.length,
            'neededChunks': needed,
          };
        } else {
          debugPrint('[FileTransferEngine] Checkpoint collision or mismatch for $transferId. Resetting staging files.');
          await metaFile.delete();
          await partFile.delete();
        }
      } catch (e) {
        debugPrint('[FileTransferEngine] Error reading checkpoint: $e');
      }
    }

    // Initialize fresh checkpoint
    final checkpoint = TransferCheckpoint(
      transferId: transferId,
      fileName: fileName,
      fileSize: fileSize,
      chunkSize: chunkSize,
      totalChunks: totalChunks,
      expectedSha256: expectedSha256,
      verifiedChunks: {},
      lastUpdated: DateTime.now().millisecondsSinceEpoch,
    );

    _activeCheckpoints[transferId] = checkpoint;
    await metaFile.writeAsString(jsonEncode(checkpoint.toJson()));
    _activePartFiles[transferId] = await partFile.open(mode: FileMode.write);

    final allNeeded = List<int>.generate(totalChunks, (i) => i);

    return {
      'type': 'transfer_resume_ack',
      'transferId': transferId,
      'canResume': false,
      'verifiedChunksCount': 0,
      'neededChunks': allNeeded,
    };
  }


  /// Receiver: Writes incoming binary chunk directly to disk via RandomAccessFile
  Future<void> handleIncomingBinaryChunk(Uint8List packet) async {
    // 32-byte standard binary header:
    // 0..15:  transferId (16 bytes UTF-8)
    // 16..19: chunkIndex (uint32)
    // 20..23: totalChunks (uint32)
    // 24..27: chunkDataLength (uint32)
    // 28..31: chunkChecksum (uint32 CRC32)
    // 32..N:  raw chunk payload
    if (packet.length < 32) return;

    final transferId = utf8.decode(packet.sublist(0, 16).takeWhile((b) => b != 0).toList());
    final byteData = ByteData.sublistView(packet);
    final chunkIndex = byteData.getUint32(16);
    final totalChunks = byteData.getUint32(20);
    final chunkDataLength = byteData.getUint32(24);
    final expectedChecksum = byteData.getUint32(28);
    final chunkBytes = packet.sublist(32);

    if (chunkBytes.length != chunkDataLength) {
      debugPrint('[FileTransferEngine] Chunk $chunkIndex truncated: expected $chunkDataLength bytes, got ${chunkBytes.length}');
      return;
    }

    // Verify per-chunk CRC-32 integrity
    final actualChecksum = calculateCrc32(chunkBytes);
    if (actualChecksum != expectedChecksum) {
      debugPrint('[FileTransferEngine] Chunk $chunkIndex CRC32 mismatch! Expected $expectedChecksum, got $actualChecksum. Dropping corrupted chunk.');
      return;
    }

    final checkpoint = _activeCheckpoints[transferId];
    if (checkpoint == null || chunkIndex >= totalChunks) return;

    var raf = _activePartFiles[transferId];
    if (raf == null) {
      final staging = await _getStagingDirectory();
      final partFile = _getPartFile(staging, transferId);
      raf = await partFile.open(mode: FileMode.append);
      _activePartFiles[transferId] = raf;
    }

    // Seek to exact byte offset and write chunk directly to disk
    final byteOffset = chunkIndex * checkpoint.chunkSize;
    await raf.setPosition(byteOffset);
    await raf.writeFrom(chunkBytes);

    checkpoint.verifiedChunks.add(chunkIndex);
    checkpoint.lastUpdated = DateTime.now().millisecondsSinceEpoch;

    final transferredBytes = (checkpoint.verifiedChunks.length * checkpoint.chunkSize).clamp(0, checkpoint.fileSize);
    final progressFraction = checkpoint.verifiedChunks.length / checkpoint.totalChunks;

    _progressController.add(FileTransferProgress(
      transferId: transferId,
      fileName: checkpoint.fileName,
      totalBytes: checkpoint.fileSize,
      transferredBytes: transferredBytes,
      fraction: progressFraction,
    ));

    // Save metadata periodically
    if (checkpoint.verifiedChunks.length % 20 == 0 || checkpoint.verifiedChunks.length == checkpoint.totalChunks) {
      final staging = await _getStagingDirectory();
      final metaFile = _getMetaFile(staging, transferId);
      await metaFile.writeAsString(jsonEncode(checkpoint.toJson()));
    }

    // Transfer Complete Check
    if (checkpoint.verifiedChunks.length == checkpoint.totalChunks) {
      await _finalizeReceivedFile(transferId, checkpoint, raf);
    }
  }

  /// Receiver: Computes full-file SHA-256 from disk and moves .part to destination
  Future<void> _finalizeReceivedFile(
    String transferId,
    TransferCheckpoint checkpoint,
    RandomAccessFile raf,
  ) async {
    await raf.flush();
    await raf.close();
    _activePartFiles.remove(transferId);

    final staging = await _getStagingDirectory();
    final partFile = _getPartFile(staging, transferId);
    final metaFile = _getMetaFile(staging, transferId);

    // Stream SHA-256 calculation directly from disk without loading full file into memory
    final stream = partFile.openRead();
    final digest = await dart_crypto.sha256.bind(stream).first;
    final calculatedSha = digest.toString().toLowerCase();

    if (calculatedSha == checkpoint.expectedSha256.toLowerCase()) {
      debugPrint('[FileTransferEngine] File hash verified successfully: $calculatedSha');

      final category = FileCategorizer.categorize(checkpoint.fileName);
      final destDir = await LocalFileManager.instance.getCategoryDirectory(category);
      final finalPath = await LocalFileManager.instance.resolveUniquePath(destDir, checkpoint.fileName);

      await partFile.rename(finalPath);
      if (await metaFile.exists()) {
        await metaFile.delete();
      }
      _activeCheckpoints.remove(transferId);

      _progressController.add(FileTransferProgress(
        transferId: transferId,
        fileName: checkpoint.fileName,
        totalBytes: checkpoint.fileSize,
        transferredBytes: checkpoint.fileSize,
        fraction: 1.0,
        isCompleted: true,
        savedFilePath: finalPath,
      ));
    } else {
      debugPrint('[FileTransferEngine] SHA-256 MISMATCH! Expected ${checkpoint.expectedSha256} but got $calculatedSha');
      _progressController.add(FileTransferProgress(
        transferId: transferId,
        fileName: checkpoint.fileName,
        totalBytes: checkpoint.fileSize,
        transferredBytes: 0,
        fraction: 0.0,
        error: 'File integrity check failed (SHA-256 mismatch)',
      ));
    }
  }

  /// Sender: Streams file chunks from disk over WebRTC DataChannel with backpressure
  Future<bool> sendFileStream({
    required File file,
    required String transferId,
    required List<int> neededChunks,
    required bool Function(Uint8List packet) sendPacket,
    required int Function() getBufferedAmount,
    required void Function(double progress) onProgress,
  }) async {
    if (!await file.exists()) return false;

    final fileSize = await file.length();
    const chunkSize = standardChunkSize;
    final totalChunks = (fileSize + chunkSize - 1) ~/ chunkSize;

    final raf = await file.open(mode: FileMode.read);
    _pausedTransfers.remove(transferId);

    try {
      var chunksSent = 0;
      final sortedNeeded = List<int>.from(neededChunks)..sort();

      for (final chunkIndex in sortedNeeded) {
        if (_pausedTransfers.contains(transferId)) {
          debugPrint('[FileTransferEngine] Transfer $transferId was paused.');
          break;
        }

        final byteOffset = chunkIndex * chunkSize;
        final currentChunkLength = (byteOffset + chunkSize <= fileSize)
            ? chunkSize
            : (fileSize - byteOffset);

        await raf.setPosition(byteOffset);
        final rawChunkData = await raf.read(currentChunkLength);

        // WebRTC backpressure: Pause reading when buffer exceeds 1 MB
        while (getBufferedAmount() > 1024 * 1024) {
          await Future.delayed(const Duration(milliseconds: 10));
        }

        final chunkDataLength = rawChunkData.length;
        final chunkChecksum = calculateCrc32(rawChunkData);

        // Build 32-byte packet header
        final header = Uint8List(32);
        final idBytes = utf8.encode(transferId.length > 16 ? transferId.substring(0, 16) : transferId);
        header.setRange(0, idBytes.length, idBytes);

        final byteData = ByteData.sublistView(header);
        byteData.setUint32(16, chunkIndex);
        byteData.setUint32(20, totalChunks);
        byteData.setUint32(24, chunkDataLength);
        byteData.setUint32(28, chunkChecksum);

        final packet = Uint8List(header.length + rawChunkData.length)
          ..setRange(0, header.length, header)
          ..setRange(header.length, header.length + rawChunkData.length, rawChunkData);

        final sent = sendPacket(packet);
        if (!sent) {
          debugPrint('[FileTransferEngine] Failed to send packet for chunk $chunkIndex');
          return false;
        }

        chunksSent++;
        onProgress(chunksSent / sortedNeeded.length);
      }
      return true;
    } finally {
      await raf.close();
    }
  }

  void pauseTransfer(String transferId) {
    _pausedTransfers.add(transferId);
  }

  void cancelTransfer(String transferId) {
    _pausedTransfers.add(transferId);
    final raf = _activePartFiles.remove(transferId);
    raf?.close();
  }
}
