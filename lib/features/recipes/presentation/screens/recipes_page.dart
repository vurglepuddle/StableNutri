import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:opennutritracker/core/domain/usecase/delete_recipe_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_config_usecase.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/core/utils/navigation_options.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/edit_meal/presentation/edit_meal_screen.dart';
import 'package:opennutritracker/features/recipes/presentation/bloc/recipes_bloc.dart';
import 'package:opennutritracker/features/recipes/presentation/library_filter.dart';
import 'package:opennutritracker/features/recipes/presentation/screens/recipe_detail_screen.dart';
import 'package:opennutritracker/features/recipes/presentation/widgets/custom_meals_tab.dart';
import 'package:opennutritracker/features/recipes/presentation/widgets/recipe_list_item.dart';
import 'package:opennutritracker/features/settings/presentation/bloc/custom_meals_bloc.dart';
import 'package:opennutritracker/generated/l10n.dart';

class RecipesPage extends StatefulWidget {
  const RecipesPage({super.key});

  @override
  State<RecipesPage> createState() => _RecipesPageState();
}

class _RecipesPageState extends State<RecipesPage>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  late RecipesBloc _bloc;
  late CustomMealsBloc _customMealsBloc;
  late TabController _tabController;
  late TextEditingController _searchController;
  String _searchQuery = '';
  String? _activeTag;
  LibraryFilter _libraryFilter = LibraryFilter.all;
  bool _usesImperialUnits = false;
  // Multi-select state. Empty set = normal mode.
  final Set<String> _selectedIds = {};
  bool get _selectionMode => _selectedIds.isNotEmpty;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bloc = locator<RecipesBloc>();
    _customMealsBloc = locator<CustomMealsBloc>()..add(LoadCustomMealsEvent());
    _tabController = TabController(length: 2, vsync: this);
    _searchController = TextEditingController();
    _bloc.add(const LoadRecipesEvent());
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    final config = await locator<GetConfigUsecase>().getConfig();
    if (mounted) {
      setState(() => _usesImperialUnits = config.usesImperialFoodUnits);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _bloc.add(const LoadRecipesEvent());
      _customMealsBloc.add(LoadCustomMealsEvent());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Standalone pushed screen (reached from Add and from You): it owns its
    // Scaffold + AppBar, so the title bar clears the status bar / notch on
    // iPhone and the create/import actions live where you'd expect them.
    return Scaffold(
      appBar: AppBar(
        title: Text(S.of(context).libraryLabel),
        actions: [
          PopupMenuButton<_RecipesAction>(
            tooltip: S.of(context).addLabel,
            icon: const Icon(Icons.add),
            onSelected: (action) => _onAddSelected(context, action),
            itemBuilder: (context) => [
              PopupMenuItem(
                value: _RecipesAction.newRecipe,
                child: Row(
                  children: [
                    const Icon(Icons.menu_book_outlined),
                    const SizedBox(width: Dimens.spacing12),
                    Text(S.of(context).createRecipeTitle),
                  ],
                ),
              ),
              PopupMenuItem(
                value: _RecipesAction.newCustomMeal,
                child: Row(
                  children: [
                    const Icon(Icons.restaurant_outlined),
                    const SizedBox(width: Dimens.spacing12),
                    Text(S.of(context).newCustomMealLabel),
                  ],
                ),
              ),
              PopupMenuItem(
                value: _RecipesAction.importRecipe,
                child: Row(
                  children: [
                    const Icon(Icons.qr_code_scanner_outlined),
                    const SizedBox(width: Dimens.spacing12),
                    Text(S.of(context).importRecipeLabel),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: BlocProvider.value(
        value: _customMealsBloc,
        child: Column(
          children: [
            _buildLibraryFilters(context),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Dimens.spacing16,
                Dimens.spacing4,
                Dimens.spacing16,
                Dimens.spacing8,
              ),
              child: TextField(
                controller: _searchController,
                onChanged: (value) => setState(() => _searchQuery = value),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: S.of(context).librarySearchHint,
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _searchQuery.isEmpty
                      ? null
                      : IconButton(
                          tooltip: S.of(context).dialogCancelLabel,
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                          icon: const Icon(Icons.clear_rounded),
                        ),
                ),
              ),
            ),
            if (_libraryFilter == LibraryFilter.rescue)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Dimens.spacing16,
                  Dimens.spacing4,
                  Dimens.spacing16,
                  Dimens.spacing8,
                ),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.10),
                    borderRadius: Dimens.borderRadiusM,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(Dimens.spacing12),
                    child: Text(
                      S.of(context).libraryRescueDescription,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ),
              ),
            TabBar(
              controller: _tabController,
              tabs: [
                Tab(text: S.of(context).librarySavedMealsLabel),
                Tab(text: S.of(context).recipesLabel),
              ],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  CustomMealsTab(
                    usesImperialUnits: _usesImperialUnits,
                    filter: _libraryFilter,
                    searchQuery: _searchQuery,
                  ),
                  _buildRecipesTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLibraryFilters(BuildContext context) {
    Widget chip(LibraryFilter filter, String label, {IconData? icon}) {
      return Padding(
        padding: const EdgeInsets.only(right: Dimens.spacing8),
        child: ChoiceChip(
          avatar: icon == null ? null : Icon(icon, size: 16),
          label: Text(label),
          selected: _libraryFilter == filter,
          showCheckmark: false,
          onSelected: (_) => setState(() => _libraryFilter = filter),
        ),
      );
    }

    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(
          Dimens.spacing16,
          Dimens.spacing8,
          Dimens.spacing8,
          Dimens.spacing4,
        ),
        children: [
          chip(LibraryFilter.all, S.of(context).allItemsLabel),
          chip(
            LibraryFilter.favorites,
            S.of(context).libraryFavoritesLabel,
            icon: Icons.favorite_rounded,
          ),
          chip(
            LibraryFilter.rescue,
            S.of(context).libraryRescueLabel,
            icon: Icons.volunteer_activism_rounded,
          ),
        ],
      ),
    );
  }

  Future<void> _onAddSelected(
    BuildContext context,
    _RecipesAction action,
  ) async {
    switch (action) {
      case _RecipesAction.newRecipe:
        await Navigator.of(
          context,
        ).pushNamed(NavigationOptions.recipeBuilderRoute);
        _bloc.add(const LoadRecipesEvent());
      case _RecipesAction.newCustomMeal:
        await Navigator.of(context).pushNamed(
          NavigationOptions.editMealRoute,
          arguments: EditMealScreenArguments(
            DateTime.now(),
            MealEntity.empty(),
            IntakeTypeEntity.breakfast,
            false,
            editOnly: true,
          ),
        );
        _customMealsBloc.add(LoadCustomMealsEvent());
      case _RecipesAction.importRecipe:
        await Navigator.of(
          context,
        ).pushNamed(NavigationOptions.importRecipeScannerRoute);
        _bloc.add(const LoadRecipesEvent());
    }
  }

  Widget _buildRecipesTab() {
    return BlocBuilder<RecipesBloc, RecipesState>(
      bloc: _bloc,
      builder: (context, state) {
        if (state is RecipesLoading || state is RecipesInitial) {
          return const Center(child: CircularProgressIndicator());
        } else if (state is RecipesFailed) {
          // Don't expose raw exception text to users; show a friendly label.
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                S.of(context).recipesLoadErrorLabel,
                textAlign: TextAlign.center,
              ),
            ),
          );
        } else if (state is RecipesLoaded) {
          if (state.recipes.isEmpty) return _buildEmptyState(context);
          final q = _searchQuery.trim().toLowerCase();
          // Build the union of all tags across recipes (sorted) for the
          // filter chip row. Skipped entirely when no recipe has tags.
          final allTags = state.recipes.expand((r) => r.tags).toSet().toList()
            ..sort();
          // Reset _activeTag if the chosen tag no longer exists (e.g. user
          // removed it from every recipe).
          if (_activeTag != null && !allTags.contains(_activeTag)) {
            WidgetsBinding.instance.addPostFrameCallback(
              (_) => setState(() => _activeTag = null),
            );
          }
          final filtered = state.recipes.where((r) {
            final matchesQuery = q.isEmpty || r.name.toLowerCase().contains(q);
            final matchesTag =
                _activeTag == null || r.tags.contains(_activeTag);
            final matchesLibraryFilter = switch (_libraryFilter) {
              LibraryFilter.all => true,
              LibraryFilter.favorites => r.isFavorite,
              LibraryFilter.rescue => r.isRescue,
            };
            return matchesQuery && matchesTag && matchesLibraryFilter;
          }).toList();
          final isDark = Theme.of(context).brightness == Brightness.dark;
          final palette = isDark ? AppPalette.dark : AppPalette.light;
          return Column(
            children: [
              if (allTags.isNotEmpty)
                SizedBox(
                  height: 44,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(
                      horizontal: Dimens.spacing12,
                    ),
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: Dimens.spacing4,
                        ),
                        child: ChoiceChip(
                          label: Text(S.of(context).recipesFilterAllLabel),
                          selected: _activeTag == null,
                          onSelected: (_) => setState(() => _activeTag = null),
                        ),
                      ),
                      for (final tag in allTags)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: Dimens.spacing4,
                          ),
                          child: ChoiceChip(
                            label: Text(tag),
                            selected: _activeTag == tag,
                            onSelected: (selected) => setState(
                              () => _activeTag = selected ? tag : null,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              Expanded(
                child: filtered.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(Dimens.spacing32),
                          child: Text(
                            _searchQuery.isNotEmpty ||
                                    _activeTag != null ||
                                    _libraryFilter != LibraryFilter.all
                                ? S.of(context).libraryNoMatches
                                : S.of(context).recipesEmptyLabel,
                            style: Theme.of(context).textTheme.bodyLarge
                                ?.copyWith(color: palette.textMuted),
                          ),
                        ),
                      )
                    : Column(
                        children: [
                          if (_selectionMode) _buildSelectionBar(context),
                          Expanded(
                            child: ListView.builder(
                              padding: const EdgeInsets.symmetric(
                                vertical: Dimens.spacing8,
                              ),
                              itemCount: filtered.length,
                              itemBuilder: (context, index) {
                                final recipe = filtered[index];
                                final isSelected = _selectedIds.contains(
                                  recipe.id,
                                );
                                return RecipeListItem(
                                  recipe: recipe,
                                  onFavorite: () => _bloc.add(
                                    UpdateRecipeLibraryFlagsEvent(
                                      recipeId: recipe.id,
                                      favorite: !recipe.isFavorite,
                                      rescue: recipe.isRescue,
                                    ),
                                  ),
                                  onRescue: () => _bloc.add(
                                    UpdateRecipeLibraryFlagsEvent(
                                      recipeId: recipe.id,
                                      favorite: recipe.isFavorite,
                                      rescue: !recipe.isRescue,
                                    ),
                                  ),
                                  isSelected: isSelected,
                                  onTap: () async {
                                    if (_selectionMode) {
                                      setState(() {
                                        if (isSelected) {
                                          _selectedIds.remove(recipe.id);
                                        } else {
                                          _selectedIds.add(recipe.id);
                                        }
                                      });
                                      return;
                                    }
                                    await Navigator.of(context).pushNamed(
                                      NavigationOptions.recipeDetailRoute,
                                      arguments: RecipeDetailArguments(
                                        recipeId: recipe.id,
                                      ),
                                    );
                                    if (mounted) {
                                      _bloc.add(const LoadRecipesEvent());
                                    }
                                  },
                                  onLongPress: () {
                                    setState(() => _selectedIds.add(recipe.id));
                                  },
                                );
                              },
                            ),
                          ),
                        ],
                      ),
              ),
            ],
          );
        }
        return const SizedBox.shrink();
      },
    );
  }

  Widget _buildSelectionBar(BuildContext context) {
    final s = S.of(context);
    final accent = Theme.of(context).colorScheme.primary;
    return Container(
      margin: const EdgeInsets.fromLTRB(
        Dimens.spacing16,
        Dimens.spacing4,
        Dimens.spacing16,
        Dimens.spacing4,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: Dimens.spacing8,
        vertical: Dimens.spacing4,
      ),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: Dimens.borderRadiusM,
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: s.dialogCancelLabel,
            icon: Icon(Icons.close_rounded, color: accent),
            onPressed: () => setState(_selectedIds.clear),
          ),
          Expanded(
            child: Text(
              s.selectionCountLabel(_selectedIds.length),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: accent,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          IconButton(
            tooltip: s.dialogDeleteLabel,
            icon: Icon(Icons.delete_outline_rounded, color: accent),
            onPressed: _onBulkDelete,
          ),
        ],
      ),
    );
  }

  Future<void> _onBulkDelete() async {
    final s = S.of(context);
    final count = _selectedIds.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.deleteSelectedRecipesConfirmTitle(count)),
        content: Text(s.recipeDeleteConfirmContent),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(s.dialogCancelLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(s.dialogDeleteLabel),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final deleteUseCase = locator<DeleteRecipeUseCase>();
    for (final id in _selectedIds) {
      await deleteUseCase.delete(id);
    }
    if (!mounted) return;
    setState(_selectedIds.clear);
    _bloc.add(const LoadRecipesEvent());
  }

  Widget _buildEmptyState(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final palette = isDark ? AppPalette.dark : AppPalette.light;
    final accent = Theme.of(context).colorScheme.primary;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Dimens.spacing32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(Dimens.spacing24),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.menu_book_rounded, size: 56, color: accent),
            ),
            const SizedBox(height: Dimens.spacing24),
            Text(
              S.of(context).recipesEmptyLabel,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: Dimens.spacing8),
            Text(
              S.of(context).recipesEmptyHint,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: palette.textMuted),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

enum _RecipesAction { newRecipe, newCustomMeal, importRecipe }
