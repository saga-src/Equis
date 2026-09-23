import 'package:equis/background/android_background_jobs.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('market and FX jobs are retired without affecting other jobs', () {
    expect(
      AndroidBackgroundJobs.retiredPeriodicJobNames,
      containsAll({
        AndroidBackgroundJobNames.fxRefresh,
        AndroidBackgroundJobNames.marketRefresh,
      }),
    );
    expect(
      AndroidBackgroundJobs.scheduledPeriodicJobNames,
      containsAll({
        AndroidBackgroundJobNames.pendingSync,
        AndroidBackgroundJobNames.attachmentUpload,
        AndroidBackgroundJobNames.maintenance,
      }),
    );
    expect(
      AndroidBackgroundJobs.scheduledPeriodicJobNames,
      isNot(contains(AndroidBackgroundJobNames.fxRefresh)),
    );
    expect(
      AndroidBackgroundJobs.scheduledPeriodicJobNames,
      isNot(contains(AndroidBackgroundJobNames.marketRefresh)),
    );
  });
}
