import 'package:file_picker/file_picker.dart';
import 'package:opennutritracker/features/settings/domain/lifesum_import/lifesum_import_coordinator.dart';

class FilePickerLifesumArchivePicker implements LifesumArchivePicker {
  const FilePickerLifesumArchivePicker();

  @override
  Future<String?> pickArchivePath() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const <String>['zip'],
      allowMultiple: false,
      withData: false,
    );
    return result?.files.single.path;
  }
}
