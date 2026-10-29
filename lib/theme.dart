import 'package:flutter/material.dart';

abstract final class FlickTokens {
  static const background = Color(0xFF080808);
  static const surface1 = Color(0xFF141414);
  static const surface2 = Color(0xFF242424);
  static const outline = Color(0xFF454545);
  static const textPrimary = Color(0xFFF4F7FA);
  static const textSecondary = Color(0xFFB5B5B5);
  static const accent = Color(0xFFD91C2B);
  static const onAccent = Color(0xFFFFFFFF);
  static const playBg = Color(0xFFFFFFFF);
  static const playFg = background;
  static const progress = accent;
  static const success = Color(0xFF71D6A2);
  static const warning = Color(0xFFF3C46B);
  static const danger = Color(0xFFD6B3FF);
  static const activeMarker = accent;
  static const flickMark = accent;

  static const grid = 4.0;
  static const pageGutter = 20.0;
  static const railGap = 12.0;
  static const sectionGap = 28.0;
  static const artworkRadius = 8.0;
  static const controlRadius = 12.0;
  static const modalRadius = 24.0;
  static const minTouchTarget = 48.0;

  static const stateDuration = Duration(milliseconds: 120);
  static const artworkFadeDuration = Duration(milliseconds: 180);
  static const sheetDuration = Duration(milliseconds: 280);
  static const curveIn = Curves.easeOutCubic;
  static const curveOut = Curves.easeInCubic;

  static final modalBarrier = Colors.black.withValues(alpha: 0.56);

  static const sheetAnimationStyle = AnimationStyle(
    duration: sheetDuration,
    reverseDuration: sheetDuration,
  );
}

abstract final class FlickText {
  static const heroTitle = TextStyle(
    fontFamily: 'Manrope',
    fontSize: 36,
    height: 40 / 36,
    fontWeight: FontWeight.w800,
    letterSpacing: -1,
  );

  static const detailTitle = TextStyle(
    fontFamily: 'Manrope',
    fontSize: 28,
    height: 34 / 28,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.6,
  );

  static const pageTitle = TextStyle(
    fontFamily: 'Manrope',
    fontSize: 24,
    height: 30 / 24,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.4,
  );

  static const railHeading = TextStyle(
    fontFamily: 'Manrope',
    fontSize: 20,
    height: 26 / 20,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.2,
  );

  static const cardTitle = TextStyle(
    fontFamily: 'Manrope',
    fontSize: 16,
    height: 22 / 16,
    fontWeight: FontWeight.w700,
    letterSpacing: 0,
  );

  static const body = TextStyle(
    fontFamily: 'Manrope',
    fontSize: 14,
    height: 20 / 14,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
  );

  static const button = TextStyle(
    fontFamily: 'Manrope',
    fontSize: 14,
    height: 20 / 14,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.1,
  );

  static const metadata = TextStyle(
    fontFamily: 'Manrope',
    fontSize: 12,
    height: 16 / 12,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.1,
  );

  static const smallLabel = TextStyle(
    fontFamily: 'Manrope',
    fontSize: 12,
    height: 16 / 12,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.2,
  );

  static const theme = TextTheme(
    displaySmall: heroTitle,
    headlineSmall: detailTitle,
    titleLarge: pageTitle,
    titleMedium: railHeading,
    titleSmall: cardTitle,
    bodyLarge: body,
    bodyMedium: body,
    bodySmall: metadata,
    labelLarge: button,
    labelMedium: metadata,
    labelSmall: smallLabel,
  );
}

const monoStyle = TextStyle(
  fontFamily: 'RobotoMono',
  fontSize: 14,
  height: 20 / 14,
  fontWeight: FontWeight.w500,
  letterSpacing: 0,
  fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
);

@immutable
class FlickColors extends ThemeExtension<FlickColors> {
  const FlickColors({
    this.success = FlickTokens.success,
    this.warning = FlickTokens.warning,
    this.danger = FlickTokens.danger,
    this.playBg = FlickTokens.playBg,
    this.playFg = FlickTokens.playFg,
    this.progress = FlickTokens.progress,
    required this.scrimTop,
    required this.scrimBottom,
  });

  final Color success;
  final Color warning;
  final Color danger;
  final Color playBg;
  final Color playFg;
  final Color progress;

  /// Apply both gradients across the full hero bounds.
  final LinearGradient scrimTop;
  final LinearGradient scrimBottom;

  static final afterglow = FlickColors(
    scrimTop: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: <Color>[
        Colors.black.withValues(alpha: 0.55),
        Colors.black.withValues(alpha: 0),
      ],
      stops: const <double>[0, 0.28],
    ),
    scrimBottom: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: <Color>[
        FlickTokens.background.withValues(alpha: 0),
        FlickTokens.background.withValues(alpha: 0.28),
        FlickTokens.background.withValues(alpha: 0.82),
        FlickTokens.background,
      ],
      stops: const <double>[0.25, 0.45, 0.68, 1],
    ),
  );

  @override
  FlickColors copyWith({
    Color? success,
    Color? warning,
    Color? danger,
    Color? playBg,
    Color? playFg,
    Color? progress,
    LinearGradient? scrimTop,
    LinearGradient? scrimBottom,
  }) {
    return FlickColors(
      success: success ?? this.success,
      warning: warning ?? this.warning,
      danger: danger ?? this.danger,
      playBg: playBg ?? this.playBg,
      playFg: playFg ?? this.playFg,
      progress: progress ?? this.progress,
      scrimTop: scrimTop ?? this.scrimTop,
      scrimBottom: scrimBottom ?? this.scrimBottom,
    );
  }

  @override
  FlickColors lerp(covariant FlickColors? other, double t) {
    if (other == null) return this;
    return FlickColors(
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      playBg: Color.lerp(playBg, other.playBg, t)!,
      playFg: Color.lerp(playFg, other.playFg, t)!,
      progress: Color.lerp(progress, other.progress, t)!,
      scrimTop: LinearGradient.lerp(scrimTop, other.scrimTop, t)!,
      scrimBottom: LinearGradient.lerp(scrimBottom, other.scrimBottom, t)!,
    );
  }
}

extension FlickThemeContext on BuildContext {
  FlickColors get flick =>
      Theme.of(this).extension<FlickColors>() ?? FlickColors.afterglow;
}

const _controlShape = RoundedRectangleBorder(
  borderRadius: BorderRadius.all(
    Radius.circular(FlickTokens.controlRadius),
  ),
);

const _inputBorder = OutlineInputBorder(
  borderRadius: BorderRadius.all(
    Radius.circular(FlickTokens.controlRadius),
  ),
  borderSide: BorderSide.none,
);

ThemeData flickTheme() {
  const scheme = ColorScheme.dark(
    primary: FlickTokens.accent,
    onPrimary: FlickTokens.onAccent,
    primaryContainer: FlickTokens.surface2,
    onPrimaryContainer: FlickTokens.textPrimary,
    primaryFixed: FlickTokens.accent,
    primaryFixedDim: FlickTokens.accent,
    onPrimaryFixed: FlickTokens.onAccent,
    onPrimaryFixedVariant: FlickTokens.onAccent,
    secondary: FlickTokens.textPrimary,
    onSecondary: FlickTokens.background,
    secondaryContainer: FlickTokens.surface2,
    onSecondaryContainer: FlickTokens.textPrimary,
    secondaryFixed: FlickTokens.textPrimary,
    secondaryFixedDim: FlickTokens.textSecondary,
    onSecondaryFixed: FlickTokens.background,
    onSecondaryFixedVariant: FlickTokens.surface2,
    tertiary: FlickTokens.warning,
    onTertiary: FlickTokens.background,
    tertiaryContainer: FlickTokens.surface2,
    onTertiaryContainer: FlickTokens.warning,
    tertiaryFixed: FlickTokens.warning,
    tertiaryFixedDim: FlickTokens.warning,
    onTertiaryFixed: FlickTokens.background,
    onTertiaryFixedVariant: FlickTokens.surface2,
    error: FlickTokens.danger,
    onError: FlickTokens.background,
    errorContainer: FlickTokens.surface2,
    onErrorContainer: FlickTokens.danger,
    surface: FlickTokens.background,
    onSurface: FlickTokens.textPrimary,
    surfaceDim: FlickTokens.background,
    surfaceBright: FlickTokens.surface2,
    surfaceContainerLowest: FlickTokens.background,
    surfaceContainerLow: FlickTokens.surface1,
    surfaceContainer: FlickTokens.surface2,
    surfaceContainerHigh: FlickTokens.surface2,
    surfaceContainerHighest: FlickTokens.surface2,
    onSurfaceVariant: FlickTokens.textSecondary,
    outline: FlickTokens.outline,
    outlineVariant: FlickTokens.outline,
    shadow: Colors.black,
    scrim: Colors.black,
    inverseSurface: FlickTokens.textPrimary,
    onInverseSurface: FlickTokens.background,
    inversePrimary: FlickTokens.accent,
    surfaceTint: Colors.transparent,
  );

  final text = FlickText.theme.apply(
    bodyColor: FlickTokens.textPrimary,
    displayColor: FlickTokens.textPrimary,
  );

  // Chip merges labelStyle as a plain TextStyle, so a WidgetStateTextStyle loses its font here.
  final chipLabel = FlickText.metadata.copyWith(color: FlickTokens.textPrimary);

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    fontFamily: 'Manrope',
    colorScheme: scheme,
    textTheme: text,
    scaffoldBackgroundColor: FlickTokens.background,
    canvasColor: FlickTokens.background,
    applyElevationOverlayColor: false,
    splashFactory: InkRipple.splashFactory,
    materialTapTargetSize: MaterialTapTargetSize.padded,
    visualDensity: VisualDensity.standard,
    extensions: <ThemeExtension<dynamic>>[FlickColors.afterglow],
    iconTheme: const IconThemeData(color: FlickTokens.textPrimary),
    appBarTheme: AppBarThemeData(
      backgroundColor: FlickTokens.background,
      foregroundColor: FlickTokens.textPrimary,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleSpacing: FlickTokens.pageGutter,
      titleTextStyle: text.titleLarge,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: FlickTokens.surface1,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      elevation: 0,
      height: 80,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      indicatorColor: FlickTokens.surface2,
      indicatorShape: const StadiumBorder(),
      iconTheme: WidgetStateProperty.resolveWith<IconThemeData>(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected)
              ? FlickTokens.activeMarker
              : FlickTokens.textSecondary,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith<TextStyle>(
        (states) => FlickText.metadata.copyWith(
          color: states.contains(WidgetState.selected)
              ? FlickTokens.textPrimary
              : FlickTokens.textSecondary,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w600
              : FontWeight.w500,
        ),
      ),
    ),
    tabBarTheme: const TabBarThemeData(
      labelColor: FlickTokens.textPrimary,
      unselectedLabelColor: FlickTokens.textSecondary,
      labelStyle: FlickText.button,
      unselectedLabelStyle: FlickText.button,
      indicatorColor: FlickTokens.activeMarker,
      indicatorSize: TabBarIndicatorSize.label,
      indicator: UnderlineTabIndicator(
        borderSide: BorderSide(
          color: FlickTokens.activeMarker,
          width: 3,
        ),
        borderRadius: BorderRadius.all(Radius.circular(1.5)),
      ),
      dividerColor: FlickTokens.outline,
      dividerHeight: 1,
      splashFactory: InkRipple.splashFactory,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: FlickTokens.accent,
        foregroundColor: FlickTokens.onAccent,
        disabledBackgroundColor: FlickTokens.surface2,
        disabledForegroundColor:
            FlickTokens.textPrimary.withValues(alpha: 0.38),
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: _controlShape,
        textStyle: FlickText.button,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        animationDuration: FlickTokens.stateDuration,
        splashFactory: InkRipple.splashFactory,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: FlickTokens.textPrimary,
        disabledForegroundColor:
            FlickTokens.textPrimary.withValues(alpha: 0.38),
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        side: const BorderSide(color: FlickTokens.outline),
        shape: _controlShape,
        textStyle: FlickText.button,
        animationDuration: FlickTokens.stateDuration,
        splashFactory: InkRipple.splashFactory,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: FlickTokens.textPrimary,
        disabledForegroundColor:
            FlickTokens.textPrimary.withValues(alpha: 0.38),
        minimumSize: const Size(48, 48),
        shape: _controlShape,
        textStyle: FlickText.button,
        animationDuration: FlickTokens.stateDuration,
        splashFactory: InkRipple.splashFactory,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: FlickTokens.textPrimary,
        disabledForegroundColor:
            FlickTokens.textPrimary.withValues(alpha: 0.38),
        minimumSize: const Size(48, 48),
        tapTargetSize: MaterialTapTargetSize.padded,
        visualDensity: VisualDensity.standard,
        shape: _controlShape,
        animationDuration: FlickTokens.stateDuration,
      ),
    ),
    chipTheme: ChipThemeData(
      brightness: Brightness.dark,
      backgroundColor: FlickTokens.surface1,
      selectedColor: FlickTokens.accent,
      secondarySelectedColor: FlickTokens.accent,
      disabledColor: FlickTokens.surface1,
      color: WidgetStateProperty.resolveWith<Color?>(
        (states) => states.contains(WidgetState.disabled)
            ? FlickTokens.surface1
            : states.contains(WidgetState.selected)
            ? FlickTokens.accent
            : FlickTokens.surface1,
      ),
      labelStyle: chipLabel,
      secondaryLabelStyle: chipLabel,
      side: const BorderSide(color: FlickTokens.outline),
      shape: const StadiumBorder(),
      checkmarkColor: FlickTokens.onAccent,
      deleteIconColor: FlickTokens.textSecondary,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      labelPadding: const EdgeInsets.symmetric(horizontal: 4),
      elevation: 0,
      pressElevation: 0,
      shadowColor: Colors.transparent,
      selectedShadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
    ),
    inputDecorationTheme: InputDecorationThemeData(
      filled: true,
      fillColor: FlickTokens.surface2,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 16,
      ),
      constraints: const BoxConstraints(minHeight: 52),
      border: _inputBorder,
      enabledBorder: _inputBorder,
      disabledBorder: _inputBorder,
      focusedBorder: _inputBorder.copyWith(
        borderSide: const BorderSide(
          color: FlickTokens.textPrimary,
          width: 2,
        ),
      ),
      errorBorder: _inputBorder.copyWith(
        borderSide: const BorderSide(color: FlickTokens.danger),
      ),
      focusedErrorBorder: _inputBorder.copyWith(
        borderSide: const BorderSide(
          color: FlickTokens.danger,
          width: 2,
        ),
      ),
      hintStyle: FlickText.body.copyWith(color: FlickTokens.textSecondary),
      labelStyle: FlickText.body.copyWith(color: FlickTokens.textSecondary),
      floatingLabelStyle: WidgetStateTextStyle.resolveWith(
        (states) => FlickText.metadata.copyWith(
          color: states.contains(WidgetState.error)
              ? FlickTokens.danger
              : FlickTokens.textPrimary,
        ),
      ),
      helperStyle: FlickText.metadata.copyWith(
        color: FlickTokens.textSecondary,
      ),
      errorStyle: FlickText.metadata.copyWith(color: FlickTokens.danger),
      prefixIconColor: FlickTokens.textSecondary,
      suffixIconColor: FlickTokens.textSecondary,
      prefixIconConstraints: const BoxConstraints(
        minWidth: 48,
        minHeight: 48,
      ),
      suffixIconConstraints: const BoxConstraints(
        minWidth: 48,
        minHeight: 48,
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: FlickTokens.surface1,
      modalBackgroundColor: FlickTokens.surface1,
      modalBarrierColor: FlickTokens.modalBarrier,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      elevation: 0,
      modalElevation: 0,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(FlickTokens.modalRadius),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      showDragHandle: true,
      dragHandleColor: FlickTokens.textSecondary,
      dragHandleSize: const Size(32, 4),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: FlickTokens.surface1,
      barrierColor: FlickTokens.modalBarrier,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      elevation: 0,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(
          Radius.circular(FlickTokens.modalRadius),
        ),
      ),
      titleTextStyle: text.titleLarge,
      contentTextStyle: text.bodyMedium,
      iconColor: FlickTokens.textPrimary,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: FlickTokens.surface2,
      contentTextStyle: text.bodyMedium,
      actionTextColor: FlickTokens.textPrimary,
      behavior: SnackBarBehavior.floating,
      shape: _controlShape,
      elevation: 0,
      insetPadding: const EdgeInsets.all(FlickTokens.pageGutter),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: FlickTokens.progress,
      linearTrackColor: FlickTokens.surface2,
      circularTrackColor: FlickTokens.surface2,
      linearMinHeight: 3,
    ),
    listTileTheme: ListTileThemeData(
      titleTextStyle: text.titleSmall,
      subtitleTextStyle: FlickText.metadata.copyWith(
        color: FlickTokens.textSecondary,
      ),
      textColor: FlickTokens.textPrimary,
      iconColor: FlickTokens.textSecondary,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: FlickTokens.pageGutter,
      ),
      minTileHeight: FlickTokens.minTouchTarget,
    ),
    dividerTheme: const DividerThemeData(
      color: FlickTokens.outline,
      thickness: 1,
      space: 1,
    ),
    cardTheme: const CardThemeData(
      color: FlickTokens.surface1,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(
          Radius.circular(FlickTokens.artworkRadius),
        ),
      ),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: FlickTokens.textPrimary,
      selectionColor: FlickTokens.textPrimary.withValues(alpha: 0.24),
      selectionHandleColor: FlickTokens.textPrimary,
    ),
  );
}

ButtonStyle playButtonStyle(BuildContext context) {
  final colors = context.flick;
  return FilledButton.styleFrom(
    backgroundColor: colors.playBg,
    foregroundColor: colors.playFg,
    disabledBackgroundColor: colors.playBg.withValues(alpha: 0.12),
    disabledForegroundColor: colors.playBg.withValues(alpha: 0.38),
    minimumSize: const Size(48, 48),
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
    shape: _controlShape,
    textStyle: FlickText.button,
    elevation: 0,
    surfaceTintColor: Colors.transparent,
    animationDuration: FlickTokens.stateDuration,
    splashFactory: InkRipple.splashFactory,
  );
}

/// The Light Cut: a solid screen with a diagonal slit. Pass `label: null`
/// when the mark sits next to the "Flick" wordmark, so it is announced once.
class FlickMark extends StatelessWidget {
  const FlickMark({super.key, this.size = 24, this.label = 'Flick'})
      : master = false,
        assert(size > 0);

  /// The 108-unit launcher master on its full canvas, so it lines up with the
  /// native splash icon (res/drawable/splash_mark.xml).
  const FlickMark.master({super.key, required this.size})
      : master = true,
        label = null,
        assert(size > 0);

  final double size;
  final String? label;
  final bool master;

  @override
  Widget build(BuildContext context) {
    final mark = CustomPaint(
      size: Size.square(size),
      painter: master ? _FlickMarkPainter.master : _FlickMarkPainter.small,
    );
    return label == null
        ? ExcludeSemantics(child: mark)
        : Semantics(label: label, image: true, child: ExcludeSemantics(child: mark));
  }
}

class _FlickMarkPainter extends CustomPainter {
  const _FlickMarkPainter(this.canvasSize, this.outline, this.slit);

  // Optical redraw for 16-48dp: wider slit, bridges of at least 4 units.
  static const small = _FlickMarkPainter(24, [
    Offset(2, 4), Offset(19.5, 4), Offset(22, 6.5), Offset(22, 20), Offset(4.5, 20), Offset(2, 17.5),
  ], [
    Offset(6.5, 16), Offset(10.5, 16), Offset(17.5, 8), Offset(13.5, 8),
  ]);

  static const master = _FlickMarkPainter(108, [
    Offset(28, 34), Offset(74, 34), Offset(80, 40), Offset(80, 74), Offset(34, 74), Offset(28, 68),
  ], [
    Offset(40, 65), Offset(50, 65), Offset(68, 43), Offset(58, 43),
  ]);

  final double canvasSize;
  final List<Offset> outline;
  final List<Offset> slit;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..fillType = PathFillType.evenOdd
      ..addPolygon(outline, true)
      ..addPolygon(slit, true);

    canvas.save();
    canvas.scale(size.width / canvasSize, size.height / canvasSize);
    canvas.drawPath(path, Paint()..color = FlickTokens.flickMark);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _FlickMarkPainter oldDelegate) => oldDelegate != this;
}
