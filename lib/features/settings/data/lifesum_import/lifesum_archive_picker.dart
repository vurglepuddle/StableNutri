import 'package:file_picker/file_picker.dart';
import 'package:opennutritracker/features/settings/data/lifesum_import/lifesum_archive_cache.dart';
import 'package:opennutritracker/features/settings/domain/lifesum_import/lifesum_import_coordinator.dart';
import 'package:path_provider/path_provider.dart';

class FilePickerLifesumArchivePicker
    implements LifesumArchivePicker, LifesumArchiveCleanup {
  FilePickerLifesumArchivePicker();

  String? _ownedToken;

  @override
  Future<String?> pickArchivePath() async {
    final cache = LifesumArchiveCache(await getTemporaryDirectory());
    await cache.recover();
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const <String>['zip'],
      allowMultiple: false,
      withData: false,
    );
    final path = result?.files.single.path;
    _ownedToken = path == null ? null : await cache.track(path);
    return path;
  }

  @override
  Future<void> cleanupArchive() async {
    final token = _ownedToken;
    if (token == null) return;
    await LifesumArchiveCache(await getTemporaryDirectory()).release(token);
    _ownedToken = null;
  }
}
