import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fanqieduanwan/services/ui_scale.dart';
import 'package:fanqieduanwan/widgets/ui_zoom.dart';

void main() {
  test('ui scale clamps to a safe range', () {
    expect(clampUiScale(9), 1.4);
    expect(clampUiScale(0.1), 0.8);
    expect(clampUiScale(double.nan), 1.0);
    expect(clampUiScale(1.1), 1.1);
    expect(uiScaleLabel(1.25), '125%');
  });

  testWidgets('UiZoom shrinks the logical viewport and scales back', (
    tester,
  ) async {
    // MediaQuery.size 来自 View，而不是 setSurfaceSize；直接改 view 才能让
    // 缩放计算拿到 1000×800 的逻辑窗口。
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    late Size seen;
    await tester.pumpWidget(
      MaterialApp(
        home: UiZoom(
          scale: 1.25,
          child: Builder(
            builder: (context) {
              seen = MediaQuery.sizeOf(context);
              return const SizedBox.expand();
            },
          ),
        ),
      ),
    );
    await tester.pump();

    // 逻辑视口按 125% 缩小，物理窗口仍被铺满。
    expect(seen.width, closeTo(800, 0.5));
    expect(seen.height, closeTo(640, 0.5));
    expect(find.byType(FittedBox), findsOneWidget);
  });

  testWidgets('UiZoom at 100% adds no wrapper', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: UiZoom(scale: 1, child: SizedBox.expand()),
      ),
    );
    expect(find.byType(FittedBox), findsNothing);
  });
}
