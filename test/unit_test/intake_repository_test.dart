import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:opennutritracker/core/data/data_source/intake_data_source.dart';
import 'package:opennutritracker/core/data/dbo/intake_dbo.dart';
import 'package:opennutritracker/core/data/repository/intake_repository.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/features/settings/domain/lifesum_import/lifesum_food_parser.dart';

import '../fixture/lifesum_food_copies_fixture.dart';
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

    IntakeEntity eaten(
      String id,
      MealEntity meal,
      DateTime at, {
      IntakeTypeEntity type = IntakeTypeEntity.lunch,
    }) => IntakeEntity(
      id: id,
      unit: 'g',
      amount: 100,
      type: type,
      meal: meal,
      dateTime: at,
    );

    test(
      'slot foods from 14 diary days precede global recents before dedup',
      () async {
        final box = await Hive.openBox<IntakeDBO>('intake_slot_recents');
        final repo = IntakeRepository(
          IntakeDataSource(FakeHiveDBProvider(intakeBox: box)),
        );
        final apple = food('apple', 'Apple');
        for (final intake in [
          eaten(
            'same-snack',
            apple,
            DateTime(2026, 10, 1),
            type: IntakeTypeEntity.snack,
          ),
          eaten('newer-lunch', apple, DateTime(2026, 10, 8)),
          eaten(
            'slot-new',
            food('banana', 'Banana'),
            DateTime(2026, 10, 7),
            type: IntakeTypeEntity.snack,
          ),
          eaten('other', food('soup', 'Soup'), DateTime(2026, 10, 9)),
          eaten(
            'old',
            food('old', 'Old snack'),
            DateTime(2026, 9, 25),
            type: IntakeTypeEntity.snack,
          ),
          eaten(
            'boundary',
            food('boundary', 'Boundary'),
            DateTime(2026, 9, 26),
            type: IntakeTypeEntity.snack,
          ),
          eaten(
            'future',
            food('future', 'Future'),
            DateTime(2026, 10, 10),
            type: IntakeTypeEntity.snack,
          ),
        ]) {
          await repo.addIntake(intake);
        }
        final before = jsonEncode(box.values.toList());
        final recents = await repo.getRecentIntake(
          preferredType: IntakeTypeEntity.snack,
          referenceDay: DateTime(2026, 10, 9),
        );
        expect(recents.map((i) => i.id), [
          'slot-new',
          'same-snack',
          'boundary',
          'future',
          'other',
          'old',
        ]);
        expect((await repo.getRecentIntake()).first.id, 'future');
        expect(jsonEncode(box.values.toList()), before);
      },
    );

    test(
      'slot window respects midnight labels and the diary boundary',
      () async {
        final box = await Hive.openBox<IntakeDBO>('intake_slot_boundary');
        final repo = IntakeRepository(
          IntakeDataSource(FakeHiveDBProvider(intakeBox: box)),
        );
        for (final (id, at, type) in [
          ('early', DateTime(2026, 9, 26, 3), IntakeTypeEntity.snack),
          ('label', DateTime(2026, 9, 26), IntakeTypeEntity.snack),
          ('late', DateTime(2026, 10, 10, 3), IntakeTypeEntity.snack),
          ('lunch', DateTime(2026, 10, 9, 20), IntakeTypeEntity.lunch),
        ]) {
          await repo.addIntake(eaten(id, food(id, id), at, type: type));
        }
        final recents = await repo.getRecentIntake(
          preferredType: IntakeTypeEntity.snack,
          referenceDay: DateTime(2026, 10, 9),
          dayStartOffsetMinutes: 240,
        );
        expect(recents.map((i) => i.id), ['late', 'label', 'lunch', 'early']);
      },
    );

    test('equivalent imported portions retain their slot priority', () async {
      final box = await Hive.openBox<IntakeDBO>('intake_slot_lifesum');
      final repo = IntakeRepository(
        IntakeDataSource(FakeHiveDBProvider(intakeBox: box)),
      );
      final copies = LifesumFoodParser.parse(lifesumFoodCopiesCsv()).intakes;
      await repo.addIntake(
        eaten(
          'snack',
          copies.first.meal,
          DateTime(2026, 10, 2),
          type: IntakeTypeEntity.snack,
        ),
      );
      await repo.addIntake(
        eaten('lunch', copies.last.meal, DateTime(2026, 10, 8)),
      );
      await repo.addIntake(
        eaten('other', food('other', 'Other'), DateTime(2026, 10, 9)),
      );
      final recents = await repo.getRecentIntake(
        preferredType: IntakeTypeEntity.snack,
        referenceDay: DateTime(2026, 10, 9),
      );
      expect(recents.map((i) => i.id), ['snack', 'other']);
      expect(box.length, 3);
    });

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

    test(
      'Lifesum portion copies show once in Recent and keep every stored log',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'lifesum-dedup-',
        );
        final box = await Hive.openBox<IntakeDBO>(
          'intake_lifesum_copies',
          path: directory.path,
        );
        addTearDown(() async {
          if (box.isOpen) await box.close();
          await directory.delete(recursive: true);
        });
        final repo = IntakeRepository(
          IntakeDataSource(FakeHiveDBProvider(intakeBox: box)),
        );
        final imported = LifesumFoodParser.parse(
          lifesumFoodCopiesCsv(),
        ).intakes;
        for (final intake in imported) {
          await repo.addIntake(intake);
        }
        final original = jsonEncode(box.values.toList());

        final recent = await repo.getRecentIntake();

        expect(recent.map((i) => i.id), [imported.last.id]);
        expect(box.length, 10);
        expect(jsonEncode(box.values.toList()), original);
      },
    );
  });
}
