/// A manual task start while the notification queue is paused transfers the
/// next Resume action to the task the user explicitly chose.
void replaceNotificationResumeTarget(Set<int> controlledGids, int gid) {
  controlledGids
    ..clear()
    ..add(gid);
}
