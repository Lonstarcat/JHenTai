import '../model/download_batch_update.dart';

/// A resolved Future<void> is not proof that service registration succeeded.
Future<UpdateSubmissionResult> verifyUpdateRegistration({
  required bool Function() exists,
  required Future<void> Function() register,
}) async {
  if (exists()) {
    return const UpdateSubmissionResult(UpdateSubmissionStatus.alreadyPresent);
  }
  try {
    await register();
    return exists()
        ? const UpdateSubmissionResult(UpdateSubmissionStatus.submitted)
        : const UpdateSubmissionResult(
            UpdateSubmissionStatus.failed, 'batchUpdateRegistrationFailed');
  } catch (_) {
    return const UpdateSubmissionResult(
        UpdateSubmissionStatus.failed, 'batchUpdateRegistrationFailed');
  }
}
