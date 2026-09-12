import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:opennutritracker/core/data/health/health_connect_service.dart';
import 'package:opennutritracker/core/data/health/health_steps_sync.dart';
import 'package:opennutritracker/core/data/repository/daily_steps_repository.dart';
import 'package:opennutritracker/core/domain/entity/daily_steps.dart';
import 'package:opennutritracker/core/utils/hive_db_provider.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/generated/l10n.dart';

class HealthConnectScreen extends StatefulWidget {
  final HealthConnectService? service;
  final DailyStepsRepository? repository;
  final HealthStepsSync? sync;
  final String? profileName;
  const HealthConnectScreen({
    super.key,
    this.service,
    this.repository,
    this.sync,
    this.profileName,
  });

  @override
  State<HealthConnectScreen> createState() => _HealthConnectScreenState();
}

class _HealthConnectScreenState extends State<HealthConnectScreen> {
  late final HealthConnectService _service;
  late final DailyStepsRepository _repository;
  late final HealthStepsSync _sync;
  late final DailyStepsImport _target;
  late final String _profileName;
  late bool _enabled;
  List<DailySteps> _totals = [];
  bool _busy = false;
  StepSyncResult? _result;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? locator<HealthConnectService>();
    _repository = widget.repository ?? locator<DailyStepsRepository>();
    _sync = widget.sync ?? locator<HealthStepsSync>();
    _target = _repository.beginImport();
    _enabled = _repository.autoImportEnabled;
    _loadSaved();
    _profileName =
        widget.profileName ??
        locator<HiveDBProvider>().profileBox.values
            .firstWhere(
              (p) => p.id == locator<HiveDBProvider>().activeProfileId,
            )
            .name;
  }

  void _loadSaved() {
    _target.requireCurrentProfile();
    _totals = _repository.all()..sort((a, b) => b.day.compareTo(a.day));
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _result = null;
    });
    try {
      _target.requireCurrentProfile();
      await action();
      _target.requireCurrentProfile();
      _enabled = _repository.autoImportEnabled;
      _loadSaved();
    } catch (_) {
      _result = StepSyncResult.failed;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _enable() => _run(() async {
    if (await _service.status() != 'available') {
      _result = StepSyncResult.unavailable;
      return;
    }
    if (!await _service.requestReadPermissions()) {
      _result = StepSyncResult.permissionRequired;
      return;
    }
    _target.requireCurrentProfile();
    await _target.setAutoImport(true);
    _result = await _sync.sync(force: true);
  });

  String _resultText(S s, StepSyncResult result) => switch (result) {
    StepSyncResult.disabled => s.healthConnectDisabled,
    StepSyncResult.updated => s.healthConnectStepsUpdated,
    StepSyncResult.empty => s.healthConnectEmpty,
    StepSyncResult.permissionRequired => s.healthConnectPermissionNeeded,
    StepSyncResult.unavailable => s.healthConnectUnavailable,
    StepSyncResult.failed => s.healthConnectImportFailed,
  };

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(title: Text(s.healthConnectTitle)),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              s.healthConnectProfile(_profileName),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Text(s.healthConnectExplanation),
            const SizedBox(height: 12),
            Text(s.healthConnectReviewHint),
            const SizedBox(height: 16),
            if (_enabled)
              Semantics(
                identifier: 'health-connect-auto-import',
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(s.healthConnectAutomaticSteps),
                  value: _enabled,
                  onChanged: _busy
                      ? null
                      : (_) => _run(() async {
                          await _target.setAutoImport(false);
                          _result = StepSyncResult.disabled;
                        }),
                ),
              ),
            Semantics(
              identifier: 'health-connect-sync',
              child: FilledButton.icon(
                onPressed: _busy
                    ? null
                    : (!_enabled ||
                          _result == StepSyncResult.permissionRequired)
                    ? _enable
                    : () => _run(() async {
                        _result = await _sync.sync(force: true);
                      }),
                icon: const Icon(Icons.directions_walk_rounded),
                label: Text(
                  !_enabled || _result == StepSyncResult.permissionRequired
                      ? s.healthConnectEnableSteps
                      : s.healthConnectRefreshSteps,
                ),
              ),
            ),
            Semantics(
              identifier: 'health-connect-permissions',
              child: TextButton(
                onPressed: _busy ? null : () => _run(_service.openSettings),
                child: Text(s.healthConnectPermissions),
              ),
            ),
            if (_busy) const LinearProgressIndicator(),
            if (_result != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Semantics(
                  liveRegion: true,
                  child: Text(_resultText(s, _result!)),
                ),
              ),
            for (final total in _totals.take(30))
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.directions_walk_rounded),
                title: Text(DateFormat.yMMMd().format(total.day)),
                subtitle: Text(
                  s.healthConnectStepsCount(
                    NumberFormat.decimalPattern().format(total.steps),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
