import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftbell/widgets/tablet_keyboard_viewport.dart';

void main() {
  for (final size in [
    const Size(411, 891),
    const Size(932, 704),
    const Size(880, 1408),
    const Size(1408, 880)
  ]) {
    testWidgets('modal footer stays above keyboard at $size', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: MediaQuery(
          data: MediaQueryData(
              size: size, viewInsets: const EdgeInsets.only(bottom: 400)),
          child: KeyboardSafeViewport(
              enabled: true,
              child: Builder(builder: (context) {
                return Align(
                    alignment: Alignment.bottomCenter,
                    child: SizedBox(
                      height: MediaQuery.sizeOf(context).height * .9,
                      child: const Column(children: [
                        Expanded(child: SizedBox()),
                        SizedBox(
                            key: ValueKey('footer'), height: 48, width: 200)
                      ]),
                    ));
              })),
        ),
      ));
      expect(tester.getRect(find.byKey(const ValueKey('footer'))).bottom,
          closeTo(size.height - 400, .01));
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('disabled viewport preserves media and constraints',
      (tester) async {
    const media = MediaQueryData(
        size: Size(932, 704), viewInsets: EdgeInsets.only(bottom: 350));
    MediaQueryData? seen;
    await tester.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: MediaQuery(
          data: media,
          child: KeyboardSafeViewport(
              enabled: false,
              child: Builder(builder: (context) {
                seen = MediaQuery.of(context);
                return const SizedBox.expand(key: ValueKey('body'));
              })),
        )));
    expect(seen, media);
    expect(tester.getSize(find.byKey(const ValueKey('body'))),
        tester.view.physicalSize / tester.view.devicePixelRatio);
  });
}
