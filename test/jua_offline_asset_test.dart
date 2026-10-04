import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  testWidgets('Jua loads from bundled assets with network fetching disabled',
      (tester) async {
    final original = GoogleFonts.config.allowRuntimeFetching;
    GoogleFonts.config.allowRuntimeFetching = false;
    addTearDown(() => GoogleFonts.config.allowRuntimeFetching = original);
    final style = GoogleFonts.jua();
    await GoogleFonts.pendingFonts([style]);
    expect(style.fontFamily, contains('Jua'));
    expect(tester.takeException(), isNull);
  });
}
