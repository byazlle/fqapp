// 标题栏与内容融为一体（用户反馈：之前顶栏和内容各自一块，只是底色相同）。
//
// 判据：
// - 滚动为 0 时顶栏完全透明——没有底色、没有分割线，标题就是内容的第一行；
// - 滚动后才从内容里浮出来：底色取页面画布色并对穿过的内容做模糊。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fanqieduanwan/widgets/brand/fused_app_bar.dart';

void main() {
  const canvas = Color(0xFFFDF7F2);

  Widget page({required bool metered}) {
    final scaffold = Scaffold(
      backgroundColor: canvas,
      appBar: FusedAppBar(
        title: const Text('我的'),
        canvas: canvas,
      ),
      body: ListView(
        children: [
          for (var i = 0; i < 60; i++)
            SizedBox(height: 40, child: Text('第 $i 行')),
        ],
      ),
    );
    return MaterialApp(
      home: metered ? FusedScrollMeter(child: scaffold) : scaffold,
    );
  }

  /// 顶栏里那块底色的 alpha（透明 = 0）。
  double barAlpha(WidgetTester tester) {
    final bar = tester.widget<AppBar>(find.byType(AppBar));
    return (bar.backgroundColor ?? Colors.transparent).a;
  }

  testWidgets('静止时顶栏透明，滚动后才从内容里浮出来', (tester) async {
    await tester.binding.setSurfaceSize(const Size(600, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(page(metered: true));
    await tester.pumpAndSettle();

    // 一屏之内没滚动：顶栏没有自己的底色，也没有分割线。
    expect(barAlpha(tester), 0);
    expect(tester.widget<AppBar>(find.byType(AppBar)).shape, isNull);

    // 内容滚过去之后：底色来自页面画布色，且随滚动加深。
    await tester.drag(find.byType(ListView), const Offset(0, -120));
    await tester.pumpAndSettle();
    final afterDrag = barAlpha(tester);
    expect(afterDrag, greaterThan(0));
    expect(tester.widget<AppBar>(find.byType(AppBar)).shape, isNotNull);
    final color = tester.widget<AppBar>(find.byType(AppBar)).backgroundColor!;
    // 材质取自内容：与页面画布同色（只差透明度）。
    expect(color.r, canvas.r);
    expect(color.g, canvas.g);
    expect(color.b, canvas.b);

    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(barAlpha(tester), greaterThanOrEqualTo(afterDrag));
    expect(tester.takeException(), isNull);
  });

  testWidgets('没套 FusedScrollMeter 时退化为普通透明顶栏', (tester) async {
    await tester.binding.setSurfaceSize(const Size(600, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(page(metered: false));
    await tester.pumpAndSettle();

    expect(barAlpha(tester), 0);
    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();
    // 没有计量器就永远停在「透明」这一档，不会突然变色。
    expect(barAlpha(tester), 0);
    expect(tester.takeException(), isNull);
  });
}
