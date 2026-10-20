import 'package:material_ui/material_ui.dart';

extension TvFocusThemeExt on ThemeData {
  /// A ring around the focused button on a TV.
  ///
  /// A remote has no pointer, so the focus is the only thing saying where OK will land, and
  /// Material 3 marks a focused button with a 10% overlay only: on the light filled button
  /// "Sign in with phone" the focused and the idle state were the same pixels (Android TV
  /// emulator, 20-10), and on a text button like "Create account" nothing showed at all.
  ///
  /// The ring is onSurface, not primary: the filled button IS primary, and a ring of its own
  /// colour would vanish into it. Idle buttons keep their own outline (null falls through to
  /// the button's default style).
  ThemeData withTvFocus(bool isTV) {
    if (!isTV) return this;
    final ring = WidgetStateProperty.resolveWith<BorderSide?>(
      (states) => states.contains(WidgetState.focused)
          ? BorderSide(color: colorScheme.onSurface, width: 3)
          : null,
    );
    ButtonStyle withRing(ButtonStyle? style) =>
        (style ?? const ButtonStyle()).copyWith(side: ring);
    return copyWith(
      // Rows and tiles (ListTile, InkWell) mark focus with this fill: the default 12% left
      // the Tools list on the emulator looking untouched while the remote walked down it.
      focusColor: colorScheme.primary.withValues(alpha: 0.4),
      filledButtonTheme: FilledButtonThemeData(
        style: withRing(filledButtonTheme.style),
      ),
      textButtonTheme: TextButtonThemeData(
        style: withRing(textButtonTheme.style),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: withRing(outlinedButtonTheme.style),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: withRing(elevatedButtonTheme.style),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: withRing(iconButtonTheme.style),
      ),
    );
  }
}
