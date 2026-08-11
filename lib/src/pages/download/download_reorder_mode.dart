abstract interface class DownloadReorderModeParticipant {
  void exitEditMode();
}

final Set<DownloadReorderModeParticipant> _activeReorderModes = {};

void registerDownloadReorderMode(DownloadReorderModeParticipant participant) {
  _activeReorderModes.add(participant);
}

void unregisterDownloadReorderMode(DownloadReorderModeParticipant participant) {
  _activeReorderModes.remove(participant);
}

void exitAllDownloadReorderModes() {
  final List<DownloadReorderModeParticipant> activeModes =
      _activeReorderModes.toList();
  _activeReorderModes.clear();
  for (final DownloadReorderModeParticipant participant in activeModes) {
    participant.exitEditMode();
  }
}
