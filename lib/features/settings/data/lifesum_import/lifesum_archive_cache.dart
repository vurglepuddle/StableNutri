import 'dart:io';

/// Records ownership of the selected file-picker copy only. The marker stays
/// in temporary storage so the next workflow can clean up after a crash.
class LifesumArchiveCache {
  const LifesumArchiveCache(this.temporaryDirectory);

  final Directory temporaryDirectory;
  File get _marker =>
      File.fromUri(temporaryDirectory.uri.resolve('lifesum-picker-owner'));

  Future<Uri> _rootUri() async =>
      Directory(await temporaryDirectory.resolveSymbolicLinks()).uri;

  Future<String?> track(String path) async {
    final owned = await _ownedFile(path);
    if (owned == null) {
      return null; // Desktop pickers may return the user's original.
    }
    final root = await _rootUri();
    final token = owned.uri.toString().substring(root.toString().length);
    try {
      await _marker.writeAsString(token, flush: true);
    } on Object {
      await owned.delete();
      rethrow;
    }
    return token;
  }

  Future<void> release(String token) async {
    if (await _marker.exists() && await _marker.readAsString() == token) {
      await recover();
    }
  }

  Future<void> recover() async {
    if (!await _marker.exists()) return;
    final relative = await _marker.readAsString();
    if (!Uri.parse(relative).isAbsolute) {
      final root = await _rootUri();
      final owned = await _ownedFile(root.resolve(relative).toFilePath());
      if (owned != null) await owned.delete();
    }
    await _marker.delete();
  }

  Future<File?> _ownedFile(String path) async {
    final pickerRoot = (await _rootUri()).resolve('file_picker/').toString();
    final file = File(path);
    if (await FileSystemEntity.type(path, followLinks: false) !=
        FileSystemEntityType.file) {
      return null;
    }
    final resolved = await file.resolveSymbolicLinks();
    if (!File(resolved).uri.toString().startsWith(pickerRoot)) return null;
    return File(resolved);
  }
}
