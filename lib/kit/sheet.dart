import 'package:flutter/material.dart';

import '../theme.dart';

/// The app's bottom sheet: themed surface, drag handle, Afterglow sheet motion, none under reduced motion.
Future<T?> showFlickSheet<T>(BuildContext context, WidgetBuilder builder) => showModalBottomSheet<T>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      sheetAnimationStyle:
          MediaQuery.disableAnimationsOf(context) ? AnimationStyle.noAnimation : FlickTokens.sheetAnimationStyle,
      builder: builder,
    );
