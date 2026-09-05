import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/features/settings/data/lifesum_import/lifesum_archive_cache.dart';

void main() {
  late Directory directory;
  late LifesumArchiveCache cache;
  setUp(() {
    directory = Directory.systemTemp.createTempSync('stable_picker_cache_');
    cache = LifesumArchiveCache(directory);
  });
  tearDown(() => directory.deleteSync(recursive: true));

  File create(String relative) {
    final file = File('${directory.path}/$relative');
    file.parent.createSync(recursive: true);
    return file..writeAsStringSync('synthetic archive');
  }

  test(
    'cleans only the selected copy, including after a fresh session',
    () async {
      final selected = create('file_picker/123/selected.zip');
      final unrelated = create('file_picker/456/unrelated.zip');
      await cache.track(selected.path);
      await LifesumArchiveCache(directory).recover();
      expect(selected.existsSync(), isFalse);
      expect(unrelated.existsSync(), isTrue);
      await cache.recover();
    },
  );

  test(
    'never owns or removes the original outside file-picker cache',
    () async {
      final original = create('documents/original.zip');
      await cache.track(original.path);
      await cache.recover();
      expect(original.existsSync(), isTrue);
    },
  );

  test('rejects a stale marker escaping the picker directory', () async {
    final original = create('documents/original.zip');
    create(
      'lifesum-picker-owner',
    ).writeAsStringSync('file_picker/../documents/original.zip');
    await cache.recover();
    expect(original.existsSync(), isTrue);
  });

  test('recovers when the operating system already evicted the copy', () async {
    final selected = create('file_picker/123/selected.zip');
    await cache.track(selected.path);
    selected.deleteSync();
    await cache.recover();
    expect(
      File('${directory.path}/lifesum-picker-owner').existsSync(),
      isFalse,
    );
  });
}
