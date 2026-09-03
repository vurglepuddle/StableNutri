import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/presentation/main_navigation.dart';
import 'package:opennutritracker/core/presentation/main_screen.dart';
import 'package:opennutritracker/core/presentation/widgets/home_appbar.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/utils/navigation_options.dart';
import 'package:opennutritracker/generated/l10n.dart';

Widget _app({
  required MainDestination selected,
  required ValueChanged<MainDestination> onSelect,
  double textScale = 1,
}) {
  return MaterialApp(
    localizationsDelegates: const [
      S.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
    ],
    supportedLocales: S.delegate.supportedLocales,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: Scaffold(
      floatingActionButton: const FloatingActionButton(
        onPressed: null,
        child: Icon(Icons.add),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: MainBottomNavigationBar(
        selectedDestination: selected,
        palette: AppPalette.light,
        onSelect: onSelect,
      ),
    ),
  );
}

void main() {
  testWidgets('uses the approved Stable destination order', (tester) async {
    await tester.pumpWidget(
      _app(selected: MainDestination.today, onSelect: (_) {}),
    );
    await tester.pumpAndSettle();

    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Trends'), findsOneWidget);
    expect(find.text('Library'), findsOneWidget);
    expect(find.text('You'), findsOneWidget);
    expect(find.text('Diary'), findsNothing);

    final labels = tester
        .widgetList<Text>(find.byType(Text))
        .map((widget) => widget.data)
        .whereType<String>()
        .toList();
    expect(labels, ['Today', 'Trends', 'Library', 'You']);
  });

  testWidgets('selects Library through the shell callback', (tester) async {
    MainDestination? selected;
    await tester.pumpWidget(
      _app(
        selected: MainDestination.today,
        onSelect: (destination) => selected = destination,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Library'));
    expect(selected, MainDestination.library);
  });

  testWidgets('opens the full Diary from Today', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          S.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: S.delegate.supportedLocales,
        routes: {
          NavigationOptions.diaryRoute: (_) =>
              const Scaffold(body: Text('Diary route body')),
        },
        home: const Scaffold(appBar: HomeAppbar()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Diary'));
    await tester.pumpAndSettle();

    expect(find.text('Diary route body'), findsOneWidget);
  });

  testWidgets('fits at 320 px with 1.6x text', (tester) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _app(selected: MainDestination.library, onSelect: (_) {}, textScale: 1.6),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Library'), findsOneWidget);
  });
}
