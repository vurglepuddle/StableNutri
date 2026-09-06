import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart' show CameraException, FlashMode;
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_zxing/flutter_zxing.dart';
import 'package:logging/logging.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/presentation/scanner_orientation_mixin.dart';
import 'package:opennutritracker/core/presentation/widgets/error_dialog.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/core/utils/navigation_options.dart';
import 'package:opennutritracker/core/utils/shared_payload_router.dart';
import 'package:opennutritracker/features/add_meal/presentation/add_meal_type.dart';
import 'package:opennutritracker/features/home/presentation/screens/import_activity_scanner_screen.dart';
import 'package:opennutritracker/features/home/presentation/screens/import_meal_scanner_screen.dart';
import 'package:opennutritracker/features/meal_detail/meal_detail_screen.dart';
import 'package:opennutritracker/features/recipes/presentation/screens/import_recipe_scanner_screen.dart';
import 'package:opennutritracker/features/scanner/presentation/scanner_bloc.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/edit_meal/presentation/edit_meal_screen.dart';
import 'package:opennutritracker/features/recipes/presentation/widgets/food_search_tab_view.dart';
import 'package:opennutritracker/features/scanner/domain/usecase/attach_barcode_to_meal_usecase.dart';
import 'package:opennutritracker/features/scanner/presentation/widgets/barcode_not_found_view.dart';
import 'package:opennutritracker/features/settings/presentation/bloc/custom_meals_bloc.dart';
import 'package:opennutritracker/features/scanner/util/barcode_check_digit.dart';
import 'package:opennutritracker/features/scanner/util/gs1_gtin.dart';
import 'package:opennutritracker/features/scanner/util/zxing_logging.dart';
import 'package:opennutritracker/generated/l10n.dart';

/// The retail symbologies a food product barcode can arrive in.
///
/// This replaces ML Kit's `BarcodeType.product`. ZXing reports the *symbology*
/// a code was encoded in rather than guessing at what its contents mean, so the
/// check is a format test instead of a semantic one — which is also the more
/// dependable of the two: ML Kit's classifier was known to label perfectly
/// valid retail barcodes as `BarcodeType.unknown` depending on print quality
/// and camera angle.
const int _productBarcodeFormats =
    Format.ean13 | Format.ean8 | Format.upca | Format.upce;

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen>
    with ScannerOrientationMixin {
  final log = Logger('ScannerScreen');

  String? _scannedBarcode;
  IntakeTypeEntity? _intakeTypeEntity;
  DateTime? _day;
  bool _pickMode = false;
  // BlocBuilder can rebuild for [ScannerLoadedState] more than once before
  // the scanner route is fully unmounted (e.g. the route-transition's
  // parent rebuild propagates down). Without this latch, the second
  // microtask races against the now-removed scanner and ends up popping
  // whichever route is on top — in the recipe ingredient flow that's the
  // quantity-dialog bottom sheet, which then crashes with a result-type
  // mismatch. The latch makes the post-load navigation idempotent.
  bool _navigatedAfterLoad = false;

  late ScannerBloc _scannerBloc;

  // ReaderWidget owns the CameraController and its lifecycle (it is a
  // WidgetsBindingObserver itself, and stops/reopens the camera on
  // pause/resume). We only hold a reference so the appbar's torch and
  // flip-camera actions can drive it; never dispose it from here.
  CameraController? _cameraController;
  bool _torchOn = false;
  CameraLensDirection _lensDirection = CameraLensDirection.back;

  @override
  void initState() {
    super.initState();
    _scannerBloc = locator<ScannerBloc>();
    configureZxingLogging();
  }

  void _onCameraCreated(CameraController? controller, Exception? error) {
    if (!mounted) return;
    setState(() {
      _cameraController = controller;
      // A freshly opened camera always comes up with the torch off, so the
      // appbar icon has to follow it back down — otherwise flipping the
      // camera while the torch is on leaves the icon lit over a dark scene.
      _torchOn = false;
    });
  }

  Future<void> _toggleTorch() async {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) return;
    final turnOn = !_torchOn;
    try {
      await controller.setFlashMode(turnOn ? FlashMode.torch : FlashMode.off);
    } on CameraException {
      // Front cameras and some devices have no torch. Leave the icon where it
      // was rather than showing a state the hardware isn't actually in.
      return;
    }
    if (!mounted) return;
    setState(() => _torchOn = turnOn);
  }

  void _flipCamera() {
    setState(() {
      _lensDirection = _lensDirection == CameraLensDirection.back
          ? CameraLensDirection.front
          : CameraLensDirection.back;
    });
  }

  /// Debug-only. Fires once per frame that decoded nothing (roughly once a
  /// second, paced by `scanDelay`), so it is kept quiet unless zxing actually
  /// reported a reason — a bare "found nothing" is the normal state of a
  /// scanner pointed at a table and is not worth a line.
  void _onScanFailure(Code code) {
    if (!kDebugMode) return;
    final error = code.error;
    if (error == null || error.isEmpty) return;
    log.fine('onScanFailure: $error');
  }

  void _onScan(Code code) {
    // Logged before any filtering, so a code that decodes but gets dropped by
    // the format test below is still visible while debugging. Without this the
    // two failure modes — "nothing decoded" and "decoded but rejected" — look
    // identical from the log.
    if (kDebugMode) {
      log.fine(
        'onScan: "${code.text}" format=${code.format?.name} '
        'valid=${code.isValid}',
      );
    }
    if (_scannedBarcode != null) return;
    final raw = code.text;
    if (raw == null || raw.isEmpty) return;

    // Shared-QR codes generated by the app's share dialog arrive as plain
    // text/url. If one of these is recognised, hand off to the matching
    // import screen with the already-scanned code so the user doesn't have
    // to scan a second time. In pick mode (recipe ingredient picker) we
    // ignore these — handing off would silently abandon the recipe builder
    // mid-edit, and a shared meal/recipe/activity isn't a single ingredient
    // anyway.
    if (!_pickMode) {
      final kind = classifySharedPayload(raw);
      if (kind != null) {
        _scannedBarcode = raw;
        // Debug-only: scanned values are user data and must not reach a
        // release build's logcat. `kDebugMode` is a const false in release,
        // so this whole call is tree-shaken out rather than merely skipped.
        if (kDebugMode) log.fine('Shared payload found: $kind');
        _routeToSharedImport(kind, raw);
        return;
      }
    }

    // Only retail symbologies are treated as food barcodes. zxing-cpp
    // verifies the EAN/UPC check digit as part of decoding, so a code that
    // reaches here has already been validated — unlike manual entry, which
    // still needs [isValidBarcodeCheckDigit].
    if (((code.format ?? Format.none) & _productBarcodeFormats) != 0) {
      _scannedBarcode = raw;
      if (kDebugMode) log.fine('Barcode found: $raw (${code.format?.name})');
      _scannerBloc.add(ScannerLoadProductEvent(barcode: raw));
      return;
    }

    // Not a retail symbology, but it may still name a product: GS1 DataMatrix
    // carries the GTIN in AI(01), and is now printed on a lot of packaging —
    // pharmaceuticals, alcohol and tobacco across the EU, and everything under
    // Russia's Chestny ZNAK scheme. [gtinFromGs1] returns null for anything
    // that is not a GS1 string naming a consumer unit, so this cannot pick up
    // an arbitrary QR payload by accident.
    final gtin = gtinFromGs1(raw);
    if (gtin != null) {
      _scannedBarcode = gtin;
      if (kDebugMode) log.fine('GS1 GTIN found: $gtin (${code.format?.name})');
      _scannerBloc.add(ScannerLoadProductEvent(barcode: gtin));
    }
  }

  @override
  void didChangeDependencies() {
    final args =
        ModalRoute.of(context)?.settings.arguments as ScannerScreenArguments;
    _intakeTypeEntity = args.intakeTypeEntity;
    _day = args.day;
    _pickMode = args.pickMode;
    if (args.initialBarcode != null && _scannedBarcode == null) {
      _scannedBarcode = args.initialBarcode;
      _scannerBloc.add(ScannerLoadProductEvent(barcode: args.initialBarcode!));
    }
    super.didChangeDependencies();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final palette = isDark ? AppPalette.dark : AppPalette.light;
    return BlocBuilder<ScannerBloc, ScannerState>(
      bloc: _scannerBloc,
      builder: (context, state) {
        if (state is ScannerInitial) {
          if (_scannedBarcode != null) {
            return Scaffold(
              backgroundColor: palette.canvas,
              appBar: AppBar(backgroundColor: palette.canvas),
              body: const Center(child: CircularProgressIndicator()),
            );
          }
          return _getScannerContent(context);
        } else if (state is ScannerLoadingState) {
          return Scaffold(
            backgroundColor: palette.canvas,
            appBar: AppBar(backgroundColor: palette.canvas),
            body: const Center(child: CircularProgressIndicator()),
          );
        } else if (state is ScannerLoadedState) {
          // Push new route after build
          if (!_navigatedAfterLoad) {
            _navigatedAfterLoad = true;
            Future.microtask(() {
              if (!context.mounted) return;
              if (_pickMode) {
                // Recipe ingredient picker — hand the loaded MealEntity back
                // to whoever pushed us instead of routing into the meal-detail
                // logging flow.
                Navigator.of(context).pop(state.product);
                return;
              }
              Navigator.of(context).pushReplacementNamed(
                NavigationOptions.mealDetailRoute,
                arguments: MealDetailScreenArguments(
                  state.product,
                  _intakeTypeEntity!,
                  _day!,
                  state.usesImperialUnits,
                ),
              );
            });
          }
        } else if (state is ScannerFailedState) {
          // A code that decoded fine but matched nothing is not an error the
          // user can retry their way out of — the product simply isn't in any
          // of the sources yet. It gets its own screen offering the two ways
          // forward. A genuine fetch failure still gets the retry dialog,
          // because retrying is exactly the right move there.
          if (state.type == ScannerFailedStateType.productNotFound) {
            return Scaffold(
              backgroundColor: palette.canvas,
              appBar: AppBar(
                backgroundColor: palette.canvas,
                toolbarHeight: MediaQuery.textScalerOf(
                  context,
                ).scale(kToolbarHeight),
                title: Text(
                  S.of(context).scanProductLabel,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              body: BarcodeNotFoundView(
                barcode: state.barcode,
                onCreateItemPressed: () => _onCreateItemPressed(
                  state.barcode,
                  state.usesImperialUnits,
                ),
                onConnectExistingPressed: () => _onConnectExistingPressed(
                  state.barcode,
                  state.usesImperialUnits,
                ),
                onScanAgainPressed: _onScanAgainPressed,
              ),
            );
          }
          return Scaffold(
            backgroundColor: palette.canvas,
            appBar: AppBar(backgroundColor: palette.canvas),
            body: Center(
              child: ErrorDialog(
                errorText: S.of(context).errorFetchingProductData,
                onRefreshPressed: _onRefreshButtonPressed,
              ),
            ),
          );
        }
        return const SizedBox();
      },
    );
  }

  Scaffold _getScannerContent(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final palette = isDark ? AppPalette.dark : AppPalette.light;
    return Scaffold(
      backgroundColor: palette.canvas,
      appBar: AppBar(
        backgroundColor: palette.canvas,
        toolbarHeight: MediaQuery.textScalerOf(context).scale(kToolbarHeight),
        title: Text(
          S.of(context).scanProductLabel,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            icon: _torchOn
                ? const Icon(Icons.flash_on_rounded)
                : Icon(Icons.flash_off_rounded, color: palette.textMuted),
            onPressed: _toggleTorch,
          ),
          IconButton(
            icon: const Icon(Icons.flip_camera_android_rounded),
            onPressed: _flipCamera,
          ),
          buildPortraitLockAction(context),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ReaderWidget(
              onScan: _onScan,
              onScanFailure: _onScanFailure,
              onControllerCreated: _onCameraCreated,
              lensDirection: _lensDirection,
              // Decode every symbology, and let `_onScan` decide what counts
              // as a food barcode.
              //
              // Restricting this to the retail formats made the scanner
              // undebuggable: a label that is not EAN/UPC was never even
              // attempted, so a Code128 or ITF barcode and a genuinely
              // unreadable one produced exactly the same silence. Filtering in
              // Dart instead keeps the behaviour identical — the format test in
              // `_onScan` is still what gates the product lookup — while making
              // the difference visible in the log.
              //
              // The extra detectors cost decode time, which there is room
              // for: decoding measured 21-68 ms against a 250 ms `scanDelay`.
              codeFormat: Format.any,
              // ReaderWidget decodes a *square* crop of side
              // `min(imageWidth, imageHeight) * cropPercent`. At the 0.5
              // default that is a 360 px box out of a 1280x720 analysis frame,
              // which truncates a retail barcode held at normal scanning
              // distance — EAN-13 is wide and short, so it overruns the box
              // long before it fills it vertically, and never decodes.
              //
              // Decoding measured 3-28 ms per frame on device, so the tight
              // crop was buying no headroom worth having. Keep a visible aim
              // box, but a forgiving one.
              cropPercent: 0.9,
              // Default is a full second between attempts, which reads as lag
              // when a barcode is already in frame. Decoding measured 21-68 ms,
              // so a quarter second still leaves the decode loop mostly idle.
              scanDelay: const Duration(milliseconds: 250),
              // zxing's extra effort pass. Matters most for exactly this case:
              // 1D symbologies under uneven lighting or slight rotation.
              tryHarder: true,
              // The appbar already owns torch and flip, and there is no
              // gallery-import flow on this screen.
              showFlashlight: false,
              showToggleCamera: false,
              showGallery: false,
              loading: DecoratedBox(
                decoration: BoxDecoration(color: palette.canvas),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(Dimens.spacing16),
            child: Semantics(
              identifier: 'scanner-manual-entry-open',
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  shape: Dimens.shapeM,
                  side: BorderSide(
                    color: palette.border,
                    width: Dimens.hairline,
                  ),
                  padding: const EdgeInsets.symmetric(
                    vertical: Dimens.spacing16,
                  ),
                ),
                icon: const Icon(Icons.keyboard_rounded),
                label: Text(S.of(context).scannerManualEntryButton),
                onPressed: () => _showManualEntryDialog(context),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showManualEntryDialog(BuildContext context) async {
    final controller = TextEditingController();
    final rootMessenger = ScaffoldMessenger.of(context);
    final invalidMessage = S.of(context).scannerManualEntryInvalid;

    final submitted = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: Dimens.shapeL,
          title: Text(S.of(dialogContext).scannerManualEntryDialogTitle),
          content: Semantics(
            identifier: 'scanner-manual-entry-field',
            child: TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(14),
              ],
              decoration: InputDecoration(
                hintText: S.of(dialogContext).scannerManualEntryFieldHint,
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(S.of(dialogContext).scannerManualEntryCancel),
            ),
            Semantics(
              identifier: 'scanner-manual-entry-submit',
              child: TextButton(
                onPressed: () =>
                    Navigator.of(dialogContext).pop(controller.text.trim()),
                child: Text(S.of(dialogContext).scannerManualEntrySubmit),
              ),
            ),
          ],
        );
      },
    );

    if (!mounted) return;
    if (submitted == null || submitted.isEmpty) return;

    if (!isValidBarcodeCheckDigit(submitted)) {
      rootMessenger.showSnackBar(SnackBar(content: Text(invalidMessage)));
      return;
    }

    _scannedBarcode = submitted;
    if (kDebugMode) log.fine('Manual barcode entered: $submitted');
    _scannerBloc.add(ScannerLoadProductEvent(barcode: submitted));
  }

  void _routeToSharedImport(SharedPayloadKind kind, String code) {
    // Pick-mode skips shared-payload handling entirely (see _onScan), so
    // by the time we land here `_intakeTypeEntity` and `_day` were set from
    // the logging-flow args.
    final intakeType = _intakeTypeEntity!;
    final day = _day!;
    final navigator = Navigator.of(context);
    Future.microtask(() {
      if (!mounted) return;
      switch (kind) {
        case SharedPayloadKind.meal:
          navigator.pushReplacementNamed(
            NavigationOptions.importMealScannerRoute,
            arguments: ImportMealScannerArguments(
              intakeType,
              AddMealExtension.fromIntakeTypeEntity(intakeType),
              day,
              initialCode: code,
            ),
          );
        case SharedPayloadKind.activity:
          navigator.pushReplacementNamed(
            NavigationOptions.importActivityScannerRoute,
            arguments: ImportActivityScannerArguments(initialCode: code),
          );
        case SharedPayloadKind.recipe:
          navigator.pushReplacementNamed(
            NavigationOptions.importRecipeScannerRoute,
            arguments: ImportRecipeScannerArguments(initialCode: code),
          );
      }
    });
  }

  /// Hands the unresolved code to the existing custom-meal form, with the
  /// barcode pre-filled and editable — a misread digit is fixable there
  /// rather than being baked into a saved item.
  ///
  /// The form is pushed in its normal create-and-log mode, so saving lands
  /// the user on meal detail with the food ready to log, and its
  /// "Save for next time" box (on by default) keeps the item in the local
  /// custom-meal box. That box is what the barcode lookup consults first, so
  /// re-scanning the same package afterwards resolves straight to this item;
  /// it is also what the data export serialises, so the item travels with a
  /// backup like everything else the user has entered.
  Future<void> _onCreateItemPressed(
    String barcode,
    bool usesImperialUnits,
  ) async {
    final navigator = Navigator.of(context);
    final seed = MealEntity.empty().copyWith(code: barcode);

    if (_pickMode) {
      // The recipe ingredient picker has no day or intake type to give the
      // form — it decides those later, per ingredient. Push the save-only
      // variant and hand the saved meal back up, matching what a successful
      // scan does in pick mode.
      final created = await navigator.pushNamed(
        NavigationOptions.editMealRoute,
        arguments: EditMealScreenArguments(
          DateTime.now(),
          seed,
          IntakeTypeEntity.breakfast,
          usesImperialUnits,
          editOnly: true,
        ),
      );
      if (created is MealEntity && mounted) navigator.pop(created);
      return;
    }

    // Not `pushReplacement`: leaving the scanner underneath means backing out
    // of the form returns here rather than dropping the user out of the flow
    // entirely. The form's own save then removes back to the add-meal route.
    await navigator.pushNamed(
      NavigationOptions.editMealRoute,
      arguments: EditMealScreenArguments(
        _day!,
        seed,
        _intakeTypeEntity!,
        usesImperialUnits,
      ),
    );
  }

  /// Points the unresolved code at a food the user already has, then carries
  /// on into the flow the scan was headed for anyway.
  Future<void> _onConnectExistingPressed(
    String barcode,
    bool usesImperialUnits,
  ) async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final pickTitle = S.of(context).scannerConnectPickTitle;

    // The same search surface the recipe builder picks ingredients with.
    // `onBarcodePressed` is deliberately left off: a scan is what got us
    // here, and offering another one inside the picker would just nest a
    // second scanner over the first.
    final selected = await navigator.push<MealEntity>(
      MaterialPageRoute(
        builder: (pickContext) => Scaffold(
          appBar: AppBar(title: Text(pickTitle)),
          body: FoodSearchTabView(
            onMealSelected: (meal) => Navigator.of(pickContext).pop(meal),
          ),
        ),
      ),
    );
    if (selected == null || !mounted) return;

    final connected = await locator<AttachBarcodeToMealUseCase>().attachBarcode(
      selected,
      barcode,
    );
    // This path writes to the custom-meal box without ever passing back
    // through the Library, so the Library has to be told (see the same note
    // on EditMealBloc.saveCustomMeal).
    if (locator.isRegistered<CustomMealsBloc>()) {
      locator<CustomMealsBloc>().add(LoadCustomMealsEvent());
    }
    if (!mounted) return;

    messenger.showSnackBar(
      SnackBar(
        content: Text(
          S.of(context).scannerConnectedLabel(connected.name ?? barcode),
        ),
      ),
    );

    if (_pickMode) {
      navigator.pop(connected);
      return;
    }
    // Replace the scanner rather than stacking on it: the code is connected
    // and saved, so coming back to a dead "not found" screen would be a
    // stale view of a question already answered.
    navigator.pushReplacementNamed(
      NavigationOptions.mealDetailRoute,
      arguments: MealDetailScreenArguments(
        connected,
        _intakeTypeEntity!,
        _day!,
        usesImperialUnits,
      ),
    );
  }

  /// Back to the camera. The latched barcode has to be cleared alongside the
  /// bloc reset or [_onScan] would drop the next decode on the floor.
  void _onScanAgainPressed() {
    setState(() {
      _scannedBarcode = null;
      _navigatedAfterLoad = false;
    });
    _scannerBloc.add(const ScannerResetEvent());
  }

  void _onRefreshButtonPressed() {
    final barcode = _scannedBarcode;
    if (barcode != null) {
      _scannerBloc.add(ScannerLoadProductEvent(barcode: barcode));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(S.of(context).errorFetchingProductData)),
      );
    }
  }
}

class ScannerScreenArguments {
  // `day` and `intakeTypeEntity` are required for the normal logging flow
  // (the scanner routes into MealDetailScreen, which needs both). In
  // [ScannerScreenArguments.pick] they're left null because the screen
  // simply pops the scanned [MealEntity] back to its caller — the recipe
  // ingredient picker doesn't yet know which day or intake the user will
  // attach it to.
  final DateTime? day;
  final IntakeTypeEntity? intakeTypeEntity;
  final String? initialBarcode;
  final bool pickMode;

  ScannerScreenArguments(
    DateTime forDay,
    IntakeTypeEntity forIntakeType, {
    this.initialBarcode,
  }) : day = forDay,
       intakeTypeEntity = forIntakeType,
       pickMode = false;

  /// Opens the scanner in "pick" mode: on a successful product load it pops
  /// the resulting [MealEntity] back to the caller instead of routing into
  /// the meal-detail logging screen. Used by the recipe ingredient picker.
  ScannerScreenArguments.pick({this.initialBarcode})
    : day = null,
      intakeTypeEntity = null,
      pickMode = true;
}
