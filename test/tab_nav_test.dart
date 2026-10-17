import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:crx_pulse/widgets/tab_nav.dart';

/// Regression tests for the active tab being visibly cut off.
///
/// The old implementation raised the selected icon with a Matrix4
/// translation, which paints outside the widget's own box. With the
/// strip exactly as tall as an unselected tab, the raised icon crossed
/// the scroll viewport's top edge and was hard-clipped — and a centred
/// "pill" behind it put a hard edge straight through it as well.
///
/// So these assert geometry, not appearance: the selected icon must sit
/// fully inside the scrollable strip, with room to spare.
void main() {
  Future<void> pumpNav(WidgetTester tester, int index) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: TabNav(currentIndex: index, onTap: (_) {}),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// The scrollable strip that does the clipping.
  Rect stripRect(WidgetTester tester) =>
      tester.getRect(find.byType(SingleChildScrollView));

  testWidgets('selected icon is fully inside the strip, not clipped',
      (tester) async {
    await pumpNav(tester, 0);

    final strip = stripRect(tester);
    final icon = tester.getRect(find.byIcon(LucideIcons.layoutGrid));

    expect(icon.top, greaterThanOrEqualTo(strip.top),
        reason: 'selected icon is cut off at the top of the strip');
    expect(icon.bottom, lessThanOrEqualTo(strip.bottom),
        reason: 'selected icon is cut off at the bottom of the strip');
  });

  testWidgets('selected icon stays inside the strip for every tab',
      (tester) async {
    for (int i = 0; i < TabNav.items.length; i++) {
      await pumpNav(tester, i);
      final strip = stripRect(tester);
      final icon = tester.getRect(find.byIcon(TabNav.items[i].icon));

      expect(icon.top, greaterThanOrEqualTo(strip.top),
          reason: 'tab $i (${TabNav.items[i].label}) is clipped at the top');
      expect(icon.bottom, lessThanOrEqualTo(strip.bottom),
          reason: 'tab $i (${TabNav.items[i].label}) is clipped at the bottom');
    }
  });

  testWidgets('selected icon sits higher than when it is not selected',
      (tester) async {
    // The lift is the whole point of the active state — assert it still
    // happens, so the clipping fix cannot be "fixed" by removing it.
    await pumpNav(tester, 1);
    final raised = tester.getRect(find.byIcon(LucideIcons.layoutGrid));

    await pumpNav(tester, 0);
    final selected = tester.getRect(find.byIcon(LucideIcons.layoutGrid));

    expect(selected.center.dy, lessThan(raised.center.dy),
        reason: 'the selected tab should lift its icon above the others');
  });

  testWidgets('selecting a tab does not overflow the strip', (tester) async {
    await pumpNav(tester, 3);
    // pumpAndSettle would have rethrown a layout overflow by now; this
    // makes the intent explicit.
    expect(tester.takeException(), isNull);
  });
}
