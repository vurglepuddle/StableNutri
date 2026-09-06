import 'dart:async';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:flutter_zxing/flutter_zxing.dart';
import 'package:opennutritracker/core/domain/usecase/save_recipe_usecase.dart';
import 'package:opennutritracker/core/presentation/scanner_orientation_mixin.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/recipes/domain/entity/shared_recipe_payload.dart';
import 'package:opennutritracker/features/recipes/presentation/bloc/recipes_bloc.dart';
import 'package:opennutritracker/features/scanner/util/zxing_logging.dart';
import 'package:opennutritracker/generated/l10n.dart';

class ImportRecipeScannerArguments {
  /// QR text already captured by the standard barcode scanner. When set,
  /// the import screen skips its own camera and goes straight to the
  /// confirm dialog so the user doesn't have to point the camera twice.
  final String? initialCode;

  const ImportRecipeScannerArguments({this.initialCode});
}

class ImportRecipeScannerScreen extends StatefulWidget {
  const ImportRecipeScannerScreen({super.key});

  @override
  State<ImportRecipeScannerScreen> createState() =>
      _ImportRecipeScannerScreenState();
}

class _ImportRecipeScannerScreenState extends State<ImportRecipeScannerScreen>
    with ScannerOrientationMixin {
  static final _log = Logger('ImportRecipeScanner');
  bool _isProcessing = false;
  bool _handledInitialCode = false;

  @override
  void initState() {
    super.initState();
    configureZxingLogging();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments;
    if (!_handledInitialCode &&
        args is ImportRecipeScannerArguments &&
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
        title: Text(S.of(context).importRecipeLabel),
        actions: [
          IconButton(
            icon: const Icon(Icons.keyboard_outlined),
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
    // onScan call queued by ReaderWidget while the QR is still
    // in frame can't pass the gate. Without this, two detections
    // fired in the same microtask window both reach the dialog.
    _isProcessing = true;
    await _processCode(raw);
  }

  Future<void> _showPasteCodeDialog() async {
    final controller = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(S.of(ctx).pasteCodeLabel),
        content: TextField(
          controller: controller,
          maxLines: 5,
          decoration: InputDecoration(
            hintText: S.of(ctx).pasteCodeHint,
            border: const OutlineInputBorder(),
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
            child: Text(S.of(ctx).importRecipeLabel),
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
      final payload = SharedRecipePayload.fromJsonString(raw);
      if (!mounted) return;
      final confirmed = await _showConfirmDialog(payload);
      if (confirmed == true && mounted) {
        await locator<SaveRecipeUseCase>().save(payload.toRecipeEntity());
        locator<RecipesBloc>().add(const LoadRecipesEvent());
        if (mounted) {
          Navigator.of(context).pop();
          didPop = true;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(S.of(context).importRecipeSuccessLabel)),
          );
        }
      }
    } on SharedRecipeParseException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.of(context).importRecipeErrorLabel)),
        );
      }
    } finally {
      // Don't reset the flag on the success-and-pop path. Navigator.pop
      // schedules the pop for the next frame, so a buffered onScan
      // that ReaderWidget emits in the same microtask would otherwise
      // pass the gate and show a second confirm dialog — except by
      // then the scanner has popped, so the dialog appears on the
      // recipes screen.
      if (mounted && !didPop) {
        setState(() => _isProcessing = false);
      }
    }
  }

  Future<bool?> _showConfirmDialog(SharedRecipePayload payload) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(payload.name),
        content: Text(
          S.of(ctx).importRecipeConfirmContent(payload.ingredients.length),
        ),
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
}
