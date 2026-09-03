import 'dart:io';

import 'package:archive/archive.dart';

/// Entirely synthetic Lifesum-shaped data. Nothing here was copied from a
/// personal export.
const sanitizedLifesumFiles = <String, String>{
  'food.csv':
      'date,meal_type,title,brand,serving_name,amount,amount_in_grams,'
      'calories,carbs,carbs_fiber,carbs_sugar,cholesterol,fat,'
      'fat_saturated,fat_unsaturated,potassium,protein,sodium\n'
      '2024-01-02,breakfast,Example oats,Sample brand,g,80,80,300,50,8,'
      '4,0,6,1,5,0.2,10,0.1\n',
  'weighins.csv':
      'date,weight_kg,height_cm,goal_weight_kg\n'
      '2024-01-02,70,170,68\n',
  'bodyfat.csv': 'date,bodyfat_pct\n2024-01-02,20\n',
  'bodymeasures.csv': 'date,measure,value,unit\n2024-01-02,waist,80,cm\n',
  'recipes.csv':
      'title,description,servings,created,calories,carbs,carbs_fiber,'
      'carbs_sugar,cholesterol,fat,fat_saturated,fat_unsaturated,potassium,'
      'protein,sodium,ingredient_title,ingredient_brand,'
      'ingredient_serving_name,ingredient_amount\n'
      'Example bowl,,2,2024-01-02 12:00:00 +0000 UTC,400,50,8,4,0,10,2,8,'
      '0.2,20,0.1,Example ingredient,,serving,1\n',
  'exercise.csv':
      'date,title,duration_min,calories_burned,source\n'
      '2024-01-02,Example walk,30,120,Lifesum\n',
  'events.csv': 'event_timestamp,event_name\n2024-01-02T12:00:00Z,example\n',
  'README': 'Synthetic test fixture.\n',
};

File writeSanitizedLifesumZip(
  Directory directory, {
  Map<String, String> files = sanitizedLifesumFiles,
}) {
  final archive = Archive();
  for (final entry in files.entries) {
    archive.add(ArchiveFile.string(entry.key, entry.value));
  }
  final output = File('${directory.path}${Platform.pathSeparator}lifesum.zip');
  output.writeAsBytesSync(ZipEncoder().encode(archive), flush: true);
  return output;
}
