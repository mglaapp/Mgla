import 'package:material_ui/material_ui.dart';

/// Tokens the generated Material scheme has no slot for.
///
/// Attention is one of them: the design code keeps yellow and red as the only warm colours in the
/// product, and a warm accent has no place in a scheme seeded from ice. Declared here once so no
/// widget carries a colour literal.
class MglaPalette {
  MglaPalette._();

  static const Color warn = Color(0xFFF5B544);
  static const Color warnOn = Color(0xFF2A2011);
}
