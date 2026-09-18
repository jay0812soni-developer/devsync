import 'dart:math';
import 'package:intl/intl.dart';

class Formatters {
  Formatters._();

  static String formatBytes(int bytes, [int decimals = 1]) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    final i = (log(bytes) / log(1024)).floor();
    final clampedI = i < suffixes.length ? i : suffixes.length - 1;
    final size = bytes / pow(1024, clampedI);
    return '${size.toStringAsFixed(clampedI == 0 ? 0 : decimals)} ${suffixes[clampedI]}';
  }

  static String formatTimestamp(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final messageDay = DateTime(dt.year, dt.month, dt.day);

    if (messageDay == today) {
      return DateFormat('HH:mm').format(dt);
    } else if (today.difference(messageDay).inDays == 1) {
      return 'Yesterday ${DateFormat('HH:mm').format(dt)}';
    } else if (today.difference(messageDay).inDays < 7) {
      return DateFormat('EEE HH:mm').format(dt);
    } else {
      return DateFormat('MMM d, HH:mm').format(dt);
    }
  }

  static String formatSpeed(int bytesTransferred, Duration duration) {
    if (duration.inMilliseconds == 0) return '0 KB/s';
    final bytesPerSec = (bytesTransferred / (duration.inMilliseconds / 1000)).round();
    return '${formatBytes(bytesPerSec)}/s';
  }

  static String truncateMiddle(String text, int maxLength) {
    if (text.length <= maxLength) return text;
    final half = (maxLength / 2).floor() - 2;
    return '${text.substring(0, half)}...${text.substring(text.length - half)}';
  }
}
