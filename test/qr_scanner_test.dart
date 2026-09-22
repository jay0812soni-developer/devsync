import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:devsync/features/devices/presentation/qr_scanner_sheet.dart';

void main() {
  group('PairingScanResult Tests', () {
    test('Parses direct 6-digit connection code', () {
      final res = PairingScanResult.parse('849201');
      expect(res.code, equals('849201'));
      expect(res.hasValidData, isTrue);
      expect(res.peer, isNull);
    });

    test('Parses trimmed 6-digit code with whitespace', () {
      final res = PairingScanResult.parse('  519302 \n');
      expect(res.code, equals('519302'));
      expect(res.hasValidData, isTrue);
    });

    test('Parses full DevSync JSON pairing payload with code and peer', () {
      final jsonPayload = jsonEncode({
        'type': 'devsync_pair',
        'code': '123456',
        'connectionCode': '123456',
        'id': 'device-alpha-100',
        'name': "Jay's MacBook Pro",
        'platform': 'macos',
        'signingPublicKey': 'base64-sign-key',
        'exchangePublicKey': 'base64-exchange-key',
        'lanIp': '192.168.1.50',
        'lanPort': 52140,
      });

      final res = PairingScanResult.parse(jsonPayload);
      expect(res.code, equals('123456'));
      expect(res.hasValidData, isTrue);
      expect(res.peer, isNotNull);
      expect(res.peer!.id, equals('device-alpha-100'));
      expect(res.peer!.name, equals("Jay's MacBook Pro"));
      expect(res.peer!.platform, equals('macos'));
      expect(res.peer!.lanIp, equals('192.168.1.50'));
      expect(res.peer!.lanPort, equals(52140));
    });

    test('Parses deep-link URL with code parameter', () {
      final res = PairingScanResult.parse('devsync://pair?code=654321');
      expect(res.code, equals('654321'));
      expect(res.hasValidData, isTrue);
    });

    test('Parses embedded 6-digit code from arbitrary text', () {
      final res = PairingScanResult.parse('Your pairing connection token is 789123. Enjoy DevSync!');
      expect(res.code, equals('789123'));
      expect(res.hasValidData, isTrue);
    });

    test('Identifies invalid scan text', () {
      final res = PairingScanResult.parse('Hello world! No valid code here.');
      expect(res.code, isNull);
      expect(res.peer, isNull);
      expect(res.hasValidData, isFalse);
    });
  });
}
