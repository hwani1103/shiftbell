// T13 G2 테스트 - 공유 코드(SB2:) ownerId 경계 (#30 형식·경계 F)
// ownerId는 Firestore 문서 경로에 그대로 들어가므로 '/'·'.' 등 경로 문자를 코드 단계에서 거부해야 한다.
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftbell/services/friend_share_service.dart';

void main() {
  test('F-C01 encode/decode 왕복', () {
    final code = FriendShareService.encodeOwnerId('abc_DEF-123');
    expect(code, 'SB2:abc_DEF-123');
    expect(FriendShareService.decodeOwnerId(code), 'abc_DEF-123');
  });

  test('F-C02 앞뒤·접두사 뒤 공백은 허용(붙여넣기 대비)', () {
    expect(FriendShareService.decodeOwnerId('  SB2: abc  '), 'abc');
  });

  test('F-C03 길이 경계 1..128', () {
    expect(FriendShareService.decodeOwnerId('SB2:${'a' * 128}'), 'a' * 128);
    expect(FriendShareService.decodeOwnerId('SB2:${'a' * 129}'), isNull);
    expect(FriendShareService.decodeOwnerId('SB2:'), isNull);
    expect(FriendShareService.decodeOwnerId('SB2:   '), isNull);
  });

  test('F-C04 경로·특수 문자·다른 접두사 거부', () {
    for (final bad in [
      'SB2:a/b', 'SB2:../x', 'SB2:a.b', 'SB2:a b', 'SB2:한글', 'SB2:a\nb',
      'SB1:abc', 'sb2:abc', 'abc', '',
    ]) {
      expect(FriendShareService.decodeOwnerId(bad), isNull, reason: bad);
    }
  });

  test('F-C05 잘못된 ownerId는 인코딩 단계에서 FormatException', () {
    expect(() => FriendShareService.encodeOwnerId('a/b'), throwsFormatException);
    expect(() => FriendShareService.encodeOwnerId(''), throwsFormatException);
    expect(FriendShareService.isValidOwnerId('a' * 128), isTrue);
    expect(FriendShareService.isValidOwnerId('a' * 129), isFalse);
  });
}
