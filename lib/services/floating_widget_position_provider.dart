import 'package:flutter/material.dart';

/// Matches contexts/floating-widget.context.tsx - one shared position
/// for the thermal widget across the WHOLE app, not reset every time
/// you navigate to a different screen. Registered once at the root
/// (main.dart), same as every other app-wide provider.
class FloatingWidgetPositionProvider extends ChangeNotifier {
  Offset position = Offset.zero;
  bool _initialized = false;

  bool get isInitialized => _initialized;

  void initializeIfNeeded(Size screenSize, double widgetSize) {
    if (_initialized) return;
    position = Offset(screenSize.width - widgetSize - 20, screenSize.height * 0.38);
    _initialized = true;
  }

  void updatePosition(Offset newPosition) {
    position = newPosition;
    notifyListeners();
  }
}
