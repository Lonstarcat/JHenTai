import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

/// Owns view controllers for one DownloadPage, not the shared download services.
/// A details-page shortcut can push a second DownloadPage above the main tab;
/// its scroll positions and temporary item keys must not belong to that tab.
class DownloadPageControllerScope {
  final Map<Type, GetxController> _controllers = {};
  final List<VoidCallback> _disposers = [];
  bool _disposed = false;

  T obtain<T extends GetxController>(
    T Function() create, {
    void Function(T controller)? disposeResources,
  }) {
    if (_disposed) {
      throw StateError('Download page controller scope is disposed');
    }
    final existing = _controllers[T];
    if (existing != null) {
      return existing as T;
    }
    final controller = create();
    _controllers[T] = controller;
    _disposers.add(() {
      controller.onDelete();
      disposeResources?.call(controller);
    });
    controller.onStart();
    return controller;
  }

  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    for (final dispose in _disposers.reversed) {
      dispose();
    }
    _disposers.clear();
    _controllers.clear();
  }
}
