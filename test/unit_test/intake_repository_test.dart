import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:opennutritracker/core/data/data_source/intake_data_source.dart';
import 'package:opennutritracker/core/data/dbo/intake_dbo.dart';
import 'package:opennutritracker/core/data/repository/intake_repository.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';

import '../fixture/meal_entity_fixtures.dart';
import '../helpers/hive_test_setup.dart';
import '../helpers/fake_hive_db_provider.dart';

void main() {
  group('IntakeRepository test', () {
    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      Hive.init(".");
      registerHiveAdaptersOnce();
    });

    tearDown(() {
      Hive.deleteFromDisk();
    });

    test('returns last added first', () async {
      final box = await Hive.openBox<IntakeDBO>('intake_test');

      final repo = IntakeRepository(
        IntakeDataSource(FakeHiveDBProvider(intakeBox: box)),
      );

      await repo.addIntake(
        IntakeEntity(
          id: "1",
          unit: "g",
          amount: 1,
          type: IntakeTypeEntity.breakfast,
          meal: MealEntityFixtures.mealOne,
          dateTime: DateTime.utc(2024, 1, 1, 0, 0, 0),
        ),
      );
      await repo.addIntake(
        IntakeEntity(
          id: "2",
          unit: "g",
          amount: 1,
          type: IntakeTypeEntity.breakfast,
          meal: MealEntityFixtures.mealTwo,
          dateTime: DateTime.utc(2024, 1, 2, 0, 0, 0),
        ),
      );
      await repo.addIntake(
        IntakeEntity(
          id: "3",
          unit: "g",
          amount: 1,
          type: IntakeTypeEntity.breakfast,
          meal: MealEntityFixtures.mealThree,
          dateTime: DateTime.utc(2024, 1, 3, 0, 0, 0),
        ),
      );

      final recents = (await repo.getRecentIntake()).map((e) => e.id).toList();
      expect(recents, List.from(["3", "2", "1"]));
    });

    MealEntity food(
      String code,
      String name, {
      MealSourceEntity source = MealSourceEntity.custom,
      double kcal = 50,
    }) => MealEntity(
      code: code,
      name: name,
      url: null,
      mealQuantity: null,
      mealUnit: 'g',
      servingQuantity: null,
      servingUnit: 'g',
      servingSize: null,
      nutriments: MealNutrimentsEntity(
        energyKcal100: kcal,
        carbohydrates100: 10,
        fat100: 1,
        proteins100: 2,
        sugars100: null,
        saturatedFat100: null,
        fiber100: null,
      ),
      source: source,
    );

    IntakeEntity eaten(String id, MealEntity meal, DateTime at) => IntakeEntity(
      id: id,
      unit: 'g',
      amount: 100,
      type: IntakeTypeEntity.lunch,
      meal: meal,
      dateTime: at,
    );

    test('newest food first, whatever its source', () async {
      final box = await Hive.openBox<IntakeDBO>('intake_recent_order');
      final repo = IntakeRepository(
        IntakeDataSource(FakeHiveDBProvider(intakeBox: box)),
      );
      // Imported history is custom-sourced; a searched soup is not.
      await repo.addIntake(
        eaten('pie', food('lifesum-pie', 'Apple pie'), DateTime(2026, 9, 23)),
      );
      await repo.addIntake(
        eaten(
          'soup',
          food('off-soup', 'Soup', source: MealSourceEntity.off),
          DateTime(2026, 9, 24, 13),
        ),
      );
      await repo.addIntake(
        eaten('old', food('lifesum-old', 'Porridge'), DateTime(2025, 1, 1)),
      );

      final recents = (await repo.getRecentIntake()).map((e) => e.id);
      expect(recents, ['soup', 'pie', 'old']);
    });

    test('same-moment entries list the latest logged first', () async {
      final box = await Hive.openBox<IntakeDBO>('intake_recent_ties');
      final repo = IntakeRepository(
        IntakeDataSource(FakeHiveDBProvider(intakeBox: box)),
      );
      final day = DateTime(2026, 9, 20);
      await repo.addIntake(eaten('first', food('a', 'Bread'), day));
      await repo.addIntake(eaten('second', food('b', 'Butter'), day));

      final recents = (await repo.getRecentIntake()).map((e) => e.id);
      expect(recents, ['second', 'first']);
    });

    test('copies of one food show once; different foods stay', () async {
      final box = await Hive.openBox<IntakeDBO>('intake_recent_copies');
      final repo = IntakeRepository(
        IntakeDataSource(FakeHiveDBProvider(intakeBox: box)),
      );
      // Each imported copy carries its own code.
      await repo.addIntake(
        eaten('a', food('lifesum-1', 'Banana'), DateTime(2026, 9, 1)),
      );
      await repo.addIntake(
        eaten('b', food('lifesum-2', ' banana '), DateTime(2026, 9, 2)),
      );
      await repo.addIntake(
        eaten('c', food('lifesum-3', 'Banana', kcal: 90), DateTime(2026, 9, 3)),
      );

      final recents = (await repo.getRecentIntake()).map((e) => e.id);
      expect(recents, ['c', 'b']);
    });
  });
}
