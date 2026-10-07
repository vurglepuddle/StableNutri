import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:opennutritracker/core/utils/hive_db_provider.dart';
import 'package:opennutritracker/core/utils/launcher_widget_service.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/core/utils/notification_service.dart';
import 'package:opennutritracker/features/settings/domain/backup/full_backup_service.dart';
import 'package:opennutritracker/generated/l10n.dart';

class FullBackupPage extends StatefulWidget {
  const FullBackupPage({super.key});
  @override
  State<FullBackupPage> createState() => _FullBackupPageState();
}

class _FullBackupPageState extends State<FullBackupPage> {
  bool _busy = false;
  String? _message;
  final _db = locator<HiveDBProvider>();

  Future<void> _run(bool restoring) async {
    if (_busy || _db.restorePending) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    final s = S.of(context);
    try {
      final service = FullBackupService(_db);
      if (!restoring) {
        final bytes = await service.export();
        final saved = await FilePicker.saveFile(
          fileName: 'stable-full-backup.zip',
          type: FileType.custom,
          allowedExtensions: ['zip'],
          bytes: bytes,
        );
        if (saved != null) {
          final missing = service.inspect(bytes).missingPhotoCount;
          _message = missing == 0
              ? s.fullBackupDone
              : '${s.fullBackupDone}\n${s.fullBackupMissingPhotos(missing)}';
        }
      } else {
        final picked = await FilePicker.pickFiles(type: FileType.any);
        final path = picked?.files.single.path;
        if (path == null) return;
        final file = File(path);
        if (await file.length() > FullBackupService.maxBytes) {
          throw const FormatException('Too large');
        }
        final backup = service.inspect(await file.readAsBytes());
        if (!mounted) return;
        final confirm = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(s.fullBackupConfirm),
            content: SingleChildScrollView(
              child: Text(
                '${s.fullBackupConfirmBody(backup.profileCount)}'
                '${backup.missingPhotoCount == 0 ? '' : '\n${s.fullBackupMissingPhotos(backup.missingPhotoCount)}'}',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(s.dialogCancelLabel),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(s.fullBackupRestore),
              ),
            ],
          ),
        );
        if (confirm != true) return;
        await service.restore(backup);
        // The committed restore is authoritative even if the OS is unavailable.
        try {
          await locator<NotificationService>().cancelAllScheduled();
        } catch (_) {}
        try {
          await LauncherWidgetService.clear(discardWater: true);
        } catch (_) {}
        _message = s.fullBackupRestart;
      }
    } catch (_) {
      _message = _db.restorePending ? s.fullBackupRestart : s.fullBackupFailed;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return PopScope(
      canPop: !_busy && !_db.restorePending,
      child: Scaffold(
        appBar: AppBar(
          title: Text(s.fullBackupTitle),
          automaticallyImplyLeading: !_busy && !_db.restorePending,
        ),
        body: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(s.fullBackupGuide),
            const SizedBox(height: 16),
            Text(s.fullBackupPrivacy),
            const SizedBox(height: 24),
            if (_busy) const LinearProgressIndicator(),
            if (_message != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(_message!),
              ),
            if (_db.restorePending)
              Semantics(
                identifier: 'backup-restart',
                child: FilledButton(
                  onPressed: () => SystemNavigator.pop(),
                  child: Text(s.fullBackupClose),
                ),
              )
            else ...[
              Semantics(
                identifier: 'backup-export',
                child: FilledButton.icon(
                  onPressed: _busy ? null : () => _run(false),
                  icon: const Icon(Icons.save_alt),
                  label: Text(s.fullBackupExport),
                ),
              ),
              const SizedBox(height: 12),
              Semantics(
                identifier: 'backup-restore',
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : () => _run(true),
                  icon: const Icon(Icons.restore),
                  label: Text(s.fullBackupRestore),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
