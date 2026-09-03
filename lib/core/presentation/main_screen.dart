import 'package:flutter/material.dart';
import 'package:opennutritracker/core/domain/usecase/get_config_usecase.dart';
import 'package:opennutritracker/core/presentation/main_navigation.dart';
import 'package:opennutritracker/core/presentation/widgets/add_item_bottom_sheet.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/core/presentation/widgets/home_appbar.dart';
import 'package:opennutritracker/features/home/home_page.dart';
import 'package:opennutritracker/core/presentation/widgets/main_appbar.dart';
import 'package:opennutritracker/features/profile/profile_page.dart';
import 'package:opennutritracker/features/recipes/presentation/screens/recipes_page.dart';
import 'package:opennutritracker/features/trends/presentation/trends_page.dart';
import 'package:opennutritracker/generated/l10n.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  MainDestination _selectedDestination = MainDestination.today;

  late List<Widget> _bodyPages;
  late List<PreferredSizeWidget?> _appbarPages;

  @override
  void didChangeDependencies() {
    _bodyPages = [
      const HomePage(),
      const TrendsPage(),
      const RecipesPage(),
      const ProfilePage(),
    ];
    _appbarPages = [
      const HomeAppbar(),
      MainAppbar(title: S.of(context).trendsLabel, iconData: Icons.insights),
      // RecipesPage owns its app bar because its create/import actions belong
      // to that surface. It can still be pushed as a standalone route.
      null,
      MainAppbar(title: S.of(context).youLabel, iconData: Icons.account_circle),
    ];
    super.didChangeDependencies();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final palette = isDark ? AppPalette.dark : AppPalette.light;
    return MainNavigationScope(
      selectedDestination: _selectedDestination,
      selectDestination: _setDestination,
      child: Scaffold(
        appBar: _appbarPages[_selectedDestination.index],
        body: IndexedStack(
          index: _selectedDestination.index,
          children: _bodyPages,
        ),
        floatingActionButton: Semantics(
          identifier: 'fab-add-item',
          child: FloatingActionButton(
            onPressed: () => _onFabPressed(context),
            tooltip: S.of(context).addLabel,
            child: const Icon(Icons.add, size: 30),
          ),
        ),
        floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
        bottomNavigationBar: MainBottomNavigationBar(
          selectedDestination: _selectedDestination,
          palette: palette,
          onSelect: _setDestination,
        ),
      ),
    );
  }

  void _setDestination(MainDestination destination) {
    setState(() {
      _selectedDestination = destination;
    });
  }

  Future<void> _onFabPressed(BuildContext context) async {
    final config = await locator<GetConfigUsecase>().getConfig();
    if (!context.mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext context) {
        return AddItemBottomSheet(
          day: DateTime.now(),
          showActivityTracking: config.showActivityTracking,
          usesImperialUnits: config.usesImperialFoodUnits,
          onOpenLibrary: () => _setDestination(MainDestination.library),
        );
      },
    );
  }
}

class MainBottomNavigationBar extends StatelessWidget {
  final MainDestination selectedDestination;
  final AppPalette palette;
  final ValueChanged<MainDestination> onSelect;

  const MainBottomNavigationBar({
    super.key,
    required this.selectedDestination,
    required this.palette,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final extraHeight = ((textScale - 1).clamp(0.0, 2.0)) * 32;
    return BottomAppBar(
      color: palette.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      height: 78 + extraHeight,
      padding: EdgeInsets.zero,
      shape: const CircularNotchedRectangle(),
      notchMargin: 8,
      child: Row(
        children: [
          _NavItem(
            // Keep the established automation id while presenting the
            // destination with Stable's user-facing Today label.
            id: 'nav-home',
            icon: Icons.home_outlined,
            selectedIcon: Icons.home_rounded,
            label: S.of(context).todayLabel,
            destination: MainDestination.today,
            selectedDestination: selectedDestination,
            palette: palette,
            onTap: onSelect,
          ),
          _NavItem(
            id: 'nav-trends',
            icon: Icons.insights_outlined,
            selectedIcon: Icons.insights_rounded,
            label: S.of(context).trendsLabel,
            destination: MainDestination.trends,
            selectedDestination: selectedDestination,
            palette: palette,
            onTap: onSelect,
          ),
          const SizedBox(width: 64), // notch gap for the centre Add FAB
          _NavItem(
            id: 'nav-library',
            icon: Icons.menu_book_outlined,
            selectedIcon: Icons.menu_book_rounded,
            label: S.of(context).libraryLabel,
            destination: MainDestination.library,
            selectedDestination: selectedDestination,
            palette: palette,
            onTap: onSelect,
          ),
          _NavItem(
            id: 'nav-you',
            icon: Icons.account_circle_outlined,
            selectedIcon: Icons.account_circle_rounded,
            label: S.of(context).youLabel,
            destination: MainDestination.you,
            selectedDestination: selectedDestination,
            palette: palette,
            onTap: onSelect,
          ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final String id;
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final MainDestination destination;
  final MainDestination selectedDestination;
  final AppPalette palette;
  final ValueChanged<MainDestination> onTap;

  const _NavItem({
    required this.id,
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.destination,
    required this.selectedDestination,
    required this.palette,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final selected = destination == selectedDestination;
    final color = selected
        ? Theme.of(context).colorScheme.primary
        : palette.textMuted;
    return Expanded(
      child: Semantics(
        identifier: id,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => onTap(destination),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(selected ? selectedIcon : icon, color: color, size: 26),
                const SizedBox(height: 3),
                Text(
                  label,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.fade,
                  style: Theme.of(
                    context,
                  ).textTheme.labelSmall?.copyWith(color: color),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
