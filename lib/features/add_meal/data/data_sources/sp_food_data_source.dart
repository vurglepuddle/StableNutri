import 'dart:io';

import 'package:logging/logging.dart';
import 'package:opennutritracker/core/data/data_source/config_data_source.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/core/utils/retry_util.dart';
import 'package:opennutritracker/core/utils/supported_language.dart';
import 'package:opennutritracker/features/add_meal/data/dto/sp/sp_const.dart';
import 'package:opennutritracker/features/add_meal/data/dto/sp/sp_food_dto.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Searches the Supabase multi-source food backend (`food_summary` view,
/// see opennutritracker-backend/sql/schema.sql).
class SpFoodDataSource {
  final log = Logger('SpFoodDataSource');

  Future<List<SpFoodDTO>> fetchSearchWordResults(
    String searchString, {
    String? localeName,
  }) async {
    if (!locator.isRegistered<SupabaseClient>() ||
        searchString.trim().isEmpty) {
      return const [];
    }

    try {
      return await withRetry(
        () async {
          log.fine('Fetching Supabase food results');
          final enabledSources = await _enabledSources();
          if (enabledSources != null && enabledSources.isEmpty) {
            log.fine('All Supabase food sources disabled; skipping search');
            return const <SpFoodDTO>[];
          }

          final supaBaseClient = locator<SupabaseClient>();
          final locale = SPConst.translationLocaleOf(
            SupportedLanguage.fromCode(localeName ?? Platform.localeName),
          );

          if (locale != null) {
            final localized = await _searchByTranslation(
              supaBaseClient,
              locale,
              searchString,
              enabledSources,
            );
            // Foods without a translation for this locale are only findable
            // by their English name, so an empty localized result set falls
            // through to the English search instead of returning nothing.
            if (localized.isNotEmpty) {
              log.fine('Successful localized ($locale) response from Supabase');
              return localized;
            }
          }

          final results = await _searchEnglish(
            supaBaseClient,
            searchString,
            enabledSources,
          );
          log.fine('Successful response from Supabase');
          return results;
        },
        shouldRetry: (error) =>
            error is! PostgrestException || error.code != 'PGRST202',
      );
    } on PostgrestException catch (exception) {
      if (exception.code == 'PGRST202') {
        // An older backend needs the SQL migration. Never fall back to GET,
        // which would expose the search term in request URLs again.
        log.warning(
          'Food backend search functions are missing; update its schema.',
        );
        return const [];
      }
      log.warning(
        'Food backend search failed; local results remain available.',
      );
      rethrow;
    } catch (_) {
      log.warning(
        'Food backend search failed; local results remain available.',
      );
      rethrow;
    }
  }

  /// Source codes the user allows in search results (Settings → Food
  /// databases), or null when everything is enabled and no filter is
  /// needed. An empty list means every backend source is disabled.
  Future<List<String>?> _enabledSources() async {
    final toggles = await locator<ConfigDataSource>().getFoodSourceToggles();
    if (toggles == null) return null;
    final enabled = SPConst.foodSourceDisplayNames.keys
        .where((code) => toggles[code] ?? true)
        .toList();
    if (enabled.length == SPConst.foodSourceDisplayNames.length) return null;
    return enabled;
  }

  Future<List<SpFoodDTO>> _searchEnglish(
    SupabaseClient client,
    String searchString,
    List<String>? enabledSources,
  ) async {
    final response = await _rpcRows(client, SPConst.searchFoodSummaryFn, {
      'term': searchString,
      'sources': enabledSources,
      'max_rows': SPConst.maxNumberOfItems,
    });

    return response.map((food) => SpFoodDTO.fromJson(food)).toList();
  }

  /// Two-step localized search: `food_summary` is a materialized view, so
  /// PostgREST cannot embed `food_translation` into it (no FK to follow).
  /// Match the translated descriptions first, then fetch the summary rows
  /// for the matched food ids and carry the translated name over.
  Future<List<SpFoodDTO>> _searchByTranslation(
    SupabaseClient client,
    String locale,
    String searchString,
    List<String>? enabledSources,
  ) async {
    final translationRows = await _rpcRows(
      client,
      SPConst.searchFoodTranslationFn,
      {
        'term': searchString,
        'loc': locale,
        'max_rows': SPConst.maxNumberOfItems,
      },
    );

    if (translationRows.isEmpty) return const [];

    final nameByFoodId = {
      for (final row in translationRows)
        row[SPConst.translationFoodId] as int:
            row[SPConst.translationDescription] as String?,
    };
    final machineTranslatedFoodIds = {
      for (final row in translationRows)
        if (row[SPConst.translationSource] == SPConst.translationSourceMachine)
          row[SPConst.translationFoodId] as int,
    };

    // The source filter is applied on the summary fetch rather than the
    // translation match: food_translation has no source column.
    final response = await _rpcRows(client, SPConst.foodSummaryByIdsFn, {
      'ids': nameByFoodId.keys.toList(),
      'sources': enabledSources,
    });

    return response.map((food) {
      final dto = SpFoodDTO.fromJson(food);
      dto.localizedName = nameByFoodId[dto.foodId];
      dto.localizedNameIsMachineTranslated = machineTranslatedFoodIds.contains(
        dto.foodId,
      );
      return dto;
    }).toList();
  }

  Future<List<Map<String, dynamic>>> _rpcRows(
    SupabaseClient client,
    String function,
    Map<String, dynamic> params,
  ) async {
    final response = await client.rpc(function, params: params);
    return (response as List).cast<Map<String, dynamic>>();
  }
}
