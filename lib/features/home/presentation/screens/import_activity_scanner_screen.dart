import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:flutter_zxing/flutter_zxing.dart';
import 'package:opennutritracker/core/domain/usecase/get_physical_activity_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_user_usecase.dart';
import 'package:opennutritracker/core/presentation/scanner_orientation_mixin.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/calc/met_calc.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/activity_detail/presentation/bloc/activity_detail_bloc.dart';
import 'package:opennutritracker/features/diary/presentation/bloc/calendar_day_bloc.dart';
import 'package:opennutritracker/features/diary/presentation/bloc/diary_bloc.dart';
import 'package:opennutritracker/features/home/domain/entity/shared_activity_payload.dart';
import 'package:opennutritracker/features/home/presentation/bloc/home_bloc.dart';
import 'package:opennutritracker/features/scanner/util/zxing_logging.dart';
import 'package:opennutritracker/generated/l10n.dart';

class ImportActivityScannerArguments {
  /// QR text already captured by the standard barcode scanner. When set,
  /// the import screen skips its own camera and goes straight to the
  /// confirm dialog so the user doesn't have to point the camera twice.
  final String? initialCode;

  const ImportActivityScannerArguments({this.initialCode});
}

class ImportActivityScannerScreen extends StatefulWidget {
  const ImportActivityScannerScreen({super.key});

  @override
  State<ImportActivityScannerScreen> createState() =>
      _ImportActivityScannerScreenState();
}

class _ImportActivityScannerScreenState
    extends State<ImportActivityScannerScreen>
    with ScannerOrientationMixin {
  late ActivityDetailBloc _activityDetailBloc;
  late GetPhysicalActivityUsecase _getPhysicalActivityUsecase;
  late GetUserUsecase _getUserUsecase;
  static final _log = Logger('ImportActivityScanner');
  bool _isProcessing = false;
  bool _handledInitialCode = false;

  @override
  void initState() {
    super.initState();
    _activityDetailBloc = locator<ActivityDetailBloc>();
    _getPhysicalActivityUsecase = locator<GetPhysicalActivityUsecase>();
    _getUserUsecase = locator<GetUserUsecase>();
    configureZxingLogging();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments;
    if (!_handledInitialCode &&
        args is ImportActivityScannerArguments &&
        args.initialCode != null) {
      _handledInitialCode = true;
      _isProcessing = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _processCode(args.initialCode!);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(S.of(context).importActivityLabel),
        actions: [
          IconButton(
            icon: const Icon(Icons.keyboard_rounded),
            tooltip: S.of(context).pasteCodeLabel,
            onPressed: _showPasteCodeDialog,
          ),
          buildPortraitLockAction(context),
        ],
      ),
      body: ReaderWidget(
        onScan: _onScan,
        codeFormat: Format.qrCode,
        showGallery: false,
        // See the note in scanner_screen.dart: ReaderWidget decodes a square
        // crop of `min(imageWidth, imageHeight) * cropPercent`, which at the
        // 0.5 default is 360 px out of a 1280x720 frame. The share codes this
        // screen reads carry a whole JSON payload, so they are dense QR — the
        // smaller the crop, the fewer modules resolve and the less reliably
        // they decode.
        cropPercent: 0.9,
        scanDelay: const Duration(milliseconds: 250),
        tryHarder: true,
      ),
    );
  }

  void _onScan(Code code) async {
    // Logged before the processing gate so a scan that arrives while a dialog
    // is already up is still visible; without it these screens decode in
    // complete silence and a failed QR looks identical to a missing camera.
    if (kDebugMode) {
      _log.fine('onScan: "${code.text}" format=${code.format?.name}');
    }
    if (_isProcessing) return;
    final raw = code.text;
    if (raw == null) return;
    // Flip the flag synchronously, before any await, so a second
    // onScan call that ReaderWidget emits while the camera
    // still has the QR in frame can't pass the gate. The flag was
    // previously only flipped inside _processCode, leaving a brief
    // microtask window where two detections could both reach the
    // dialog.
    _isProcessing = true;
    await _processCode(raw);
  }

  Future<void> _showPasteCodeDialog() async {
    final controller = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: Dimens.shapeL,
        title: Text(S.of(ctx).pasteCodeLabel),
        content: TextField(
          controller: controller,
          maxLines: 5,
          decoration: InputDecoration(
            hintText: S.of(ctx).pasteCodeHint,
            border: const OutlineInputBorder(
              borderRadius: Dimens.borderRadiusS,
            ),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(S.of(ctx).dialogCancelLabel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: Text(S.of(ctx).importActivityLabel),
          ),
        ],
      ),
    );
    if (code != null && code.isNotEmpty) {
      await _processCode(code);
    }
  }

  Future<void> _processCode(String raw) async {
    // Idempotent set — _onScan flips the flag synchronously before
    // calling here, but the paste-code dialog path doesn't, so this
    // still needs to set it.
    setState(() => _isProcessing = true);

    var didPop = false;
    try {
      final payload = SharedActivityPayload.fromJsonString(raw);
      if (!mounted) return;
      final confirmed = await _showConfirmDialog(payload);
      if (confirmed == true && mounted) {
        await _importItems(payload);
        _refreshPages();
        if (mounted) {
          Navigator.of(context).pop();
          didPop = true;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(S.of(context).importActivitySuccessLabel)),
          );
        }
      }
    } on SharedActivityParseException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.of(context).importMealErrorLabel)),
        );
      }
    } finally {
      // Don't reset the flag on the success-and-pop path. Navigator.pop
      // schedules the pop for the next frame, so `mounted` stays true
      // for the rest of this microtask. If we reset _isProcessing to
      // false here, a buffered onScan that ReaderWidget emits in
      // the same microtask passes the gate and shows a second confirm
      // dialog — except by then the scanner has popped, so
      // showDialog walks up to the home navigator and the dialog
      // appears on the home screen.
      if (mounted && !didPop) {
        setState(() => _isProcessing = false);
      }
    }
  }

  Future<bool?> _showConfirmDialog(SharedActivityPayload payload) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: Dimens.shapeL,
        title: Text(S.of(ctx).importActivityConfirmTitle(payload.totalCount)),
        content: Text(S.of(ctx).importActivityConfirmContent),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(S.of(ctx).dialogCancelLabel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(S.of(ctx).dialogOKLabel),
          ),
        ],
      ),
    );
  }

  Future<void> _importItems(SharedActivityPayload payload) async {
    final messenger = ScaffoldMessenger.of(context);
    final user = await _getUserUsecase.getUserData();
    final allActivities = await _getPhysicalActivityUsecase
        .getAllPhysicalActivities();

    var skipped = 0;
    final today = DateTime.now();

    for (final item in payload.items) {
      final activity = allActivities.firstWhereOrNull(
        (a) => a.code == item.code,
      );
      if (activity == null) {
        skipped++;
        continue;
      }
      final burnedKcal = METCalc.getTotalBurnedKcal(
        user,
        activity,
        item.duration,
      );
      _activityDetailBloc.persistActivity(
        item.duration.toString(),
        burnedKcal,
        activity,
        today,
      );
    }

    if (skipped > 0) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('$skipped activity/activities could not be imported.'),
        ),
      );
    }
  }

  void _refreshPages() {
    locator<HomeBloc>().add(const LoadItemsEvent());
    locator<DiaryBloc>().add(const LoadDiaryYearEvent());
    locator<CalendarDayBloc>().add(RefreshCalendarDayEvent());
  }
}
