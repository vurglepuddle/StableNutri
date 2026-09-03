import 'package:flutter/widgets.dart';

/// Stable destinations owned by the app's persistent bottom navigation.
///
/// Diary remains a full screen, but it is opened from Today rather than
/// occupying one of the four persistent destinations.
enum MainDestination { today, trends, library, you }

/// Lets descendants such as the You page switch an existing main-shell tab
/// instead of pushing a duplicate copy of that destination.
class MainNavigationScope extends InheritedWidget {
  final MainDestination selectedDestination;
  final ValueChanged<MainDestination> selectDestination;

  const MainNavigationScope({
    super.key,
    required this.selectedDestination,
    required this.selectDestination,
    required super.child,
  });

  static MainNavigationScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<MainNavigationScope>();
  }

  @override
  bool updateShouldNotify(MainNavigationScope oldWidget) {
    return selectedDestination != oldWidget.selectedDestination ||
        selectDestination != oldWidget.selectDestination;
  }
}
