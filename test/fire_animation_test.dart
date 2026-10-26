import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jangjak_diary/diary/diary_store.dart';
import 'package:jangjak_diary/home/animated_fireplace.dart';
import 'package:jangjak_diary/home/home_widgets.dart';

void main() {
  Future<void> showFire(
    WidgetTester tester, {
    bool reduced = false,
    FireLevel level = FireLevel.smallFire,
  }) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        FakeAccessibilityFeatures(disableAnimations: reduced);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.pumpWidget(
      MaterialApp(
        home: Center(child: AnimatedFireplace(level: level)),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }

  List<double> flameMatrix(WidgetTester tester) => List.of(
    tester
        .widget<Transform>(find.byKey(const Key('flame-motion')))
        .transform
        .storage,
  );

  testWidgets('the flame flickers while the fireplace shell stays still', (
    tester,
  ) async {
    await showFire(tester);
    final first = flameMatrix(tester);
    final shell = tester.getRect(find.byType(FireplaceArt));
    await tester.pump(const Duration(milliseconds: 300));
    expect(flameMatrix(tester), isNot(orderedEquals(first)));
    expect(tester.getRect(find.byType(FireplaceArt)), shell);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('system reduced motion stops continuous flame movement', (
    tester,
  ) async {
    await showFire(tester, reduced: true);
    final first = flameMatrix(tester);
    await tester.pump(const Duration(milliseconds: 300));
    expect(flameMatrix(tester), orderedEquals(first));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('ashes have no visible or moving flame', (tester) async {
    await showFire(tester, level: FireLevel.ash);
    final rect = tester.getRect(
      find.descendant(
        of: find.byKey(const Key('flame-motion')),
        matching: find.byType(DesignIcon),
      ),
    );
    expect(rect.width, 0);
    expect(rect.height, 0);
    final first = flameMatrix(tester);
    await tester.pump(const Duration(milliseconds: 300));
    expect(flameMatrix(tester), orderedEquals(first));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'all six levels grow visibly and keep the flame inside the opening',
    (tester) async {
      var previousHeight = -1.0;
      for (final level in FireLevel.values) {
        await showFire(tester, reduced: true, level: level);
        await tester.pumpAndSettle();
        final shell = tester.getTopLeft(find.byType(FireplaceArt));
        final flame = tester.getRect(
          find.descendant(
            of: find.byKey(const Key('flame-motion')),
            matching: find.byType(DesignIcon),
          ),
        );
        expect(flame.height, greaterThan(previousHeight), reason: level.label);
        expect(flame.left - shell.dx, greaterThanOrEqualTo(74));
        expect(flame.right - shell.dx, lessThanOrEqualTo(228));
        expect(flame.top - shell.dy, greaterThanOrEqualTo(99));
        expect(flame.bottom - shell.dy, lessThanOrEqualTo(267));
        previousHeight = flame.height;
      }
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
