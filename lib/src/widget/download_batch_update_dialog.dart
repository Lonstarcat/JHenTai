import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../model/download_batch_update.dart';
import '../model/download_multi_select_toolbar.dart';
import '../service/download_batch_update_service.dart';
import '../utils/batch_update_display.dart';
import '../utils/byte_util.dart';
import 'batch_update_statistics.dart';

String batchUpdateStatusKey(BatchUpdateItemStatus status) => switch (status) {
      BatchUpdateItemStatus.skipped => 'batchUpdateSkipped',
      BatchUpdateItemStatus.latest => 'batchUpdateLatest',
      BatchUpdateItemStatus.existing => 'batchUpdateExisting',
      BatchUpdateItemStatus.available => 'batchUpdateAvailable',
      BatchUpdateItemStatus.failed => 'batchUpdateFailed',
      BatchUpdateItemStatus.submitted => 'batchUpdateSubmitted',
      BatchUpdateItemStatus.cancelled => 'batchUpdateCancelled',
    };

String batchUpdateSummary(DownloadBatchUpdateService service) =>
    '${'batchUpdateSubmitted'.tr}: ${service.count(BatchUpdateItemStatus.submitted)} · '
    '${'batchUpdateFailed'.tr}: ${service.count(BatchUpdateItemStatus.failed)} · '
    '${'batchUpdateSkipped'.tr}: ${service.count(BatchUpdateItemStatus.skipped)} · '
    '${'batchUpdateLatest'.tr}: ${service.count(BatchUpdateItemStatus.latest)} · '
    '${'batchUpdateExisting'.tr}: ${service.count(BatchUpdateItemStatus.existing)} · '
    '${'batchUpdateCancelled'.tr}: ${service.count(BatchUpdateItemStatus.cancelled)} · '
    '${'batchUpdateStopped'.tr}: ${service.stoppedCount}';

class DownloadBatchUpdateDialog extends StatelessWidget {
  final DownloadBatchUpdateService service;
  final VoidCallback onSubmit;
  const DownloadBatchUpdateDialog(
      {super.key, required this.service, required this.onSubmit});

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: service,
      builder: (context, _) {
        final review = service.phase == BatchUpdatePhase.review;
        final busy = service.phase == BatchUpdatePhase.checking ||
            service.phase == BatchUpdatePhase.submitting;
        final archive = service.sessionKind == DownloadToolbarKind.archive;
        final visible = service.items.where(isVisibleBatchUpdateItem).toList();
        final stats = BatchUpdateDisplayStats.fromItems(service.items);
        final failed = service.count(BatchUpdateItemStatus.failed);
        final inProgress = busy &&
                service.currentTitle != null &&
                service.current < service.total &&
                !service.backend.globallyPaused
            ? 1
            : 0;
        return AlertDialog(
          title: Text('batchUpdate'.tr),
          content: SizedBox(
            width: 580,
            height: MediaQuery.sizeOf(context).height * .56,
            child: LayoutBuilder(
                builder: (context, constraints) => Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (archive) ...[
                          Text('batchUpdateArchiveWarning'.tr),
                          const SizedBox(height: 8),
                        ],
                        Expanded(
                            child: ListView.builder(
                          key: const ValueKey('batch-update-list'),
                          itemCount: visible.length,
                          itemBuilder: (context, index) {
                            final item = visible[index];
                            final quote = item.quote;
                            return CheckboxListTile(
                              key: ValueKey('batch-update-${item.source.gid}'),
                              contentPadding: EdgeInsets.zero,
                              value: item.selected,
                              onChanged: review &&
                                      item.status ==
                                          BatchUpdateItemStatus.available
                                  ? (value) => service.select(item, value!)
                                  : null,
                              title: Text(item.target?.japaneseTitle ??
                                  item.target?.rawTitle ??
                                  item.source.title),
                              subtitle: Text([
                                '${item.source.gid} → ${item.target!.galleryUrl.gid} · ${batchUpdateStatusKey(item.status).tr}',
                                if (quote != null)
                                  '${item.source.parseSource == 1 ? 'archiveBotShort'.tr : 'official'.tr} · ${item.source.original ? 'original'.tr : 'resample'.tr} · ${byte2String(quote.sizeBytes.toDouble())} · ${quote.cost}',
                                if (item.reason != null) item.reason!.tr,
                              ].join('\n')),
                              isThreeLine: quote != null || item.reason != null,
                              controlAffinity: ListTileControlAffinity.leading,
                            );
                          },
                        )),
                        const Divider(),
                        // A bounded footer stays above actions without squeezing narrow
                        // screens into overflow; long translated statistics can scroll.
                        ConstrainedBox(
                          constraints: BoxConstraints(
                              maxHeight: constraints.maxHeight * .42),
                          child: SingleChildScrollView(
                            key: const ValueKey('batch-update-statistics'),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  BatchUpdateStatistics(items: [
                                    BatchUpdateStatistic(
                                        'batchUpdateTotalSize'.tr,
                                        stats.unknownSize
                                            ? '—'
                                            : byte2String(
                                                stats.sizeBytes.toDouble()),
                                        Icons.storage_outlined),
                                    BatchUpdateStatistic(
                                        'batchUpdateUpdateCount'.tr,
                                        '${stats.updateCount}',
                                        Icons.update),
                                    BatchUpdateStatistic(
                                        'GP',
                                        stats.unknownGp ? '—' : '${stats.gp}',
                                        Icons.toll_outlined),
                                    BatchUpdateStatistic(
                                        'Bot GP',
                                        '${stats.botGp}',
                                        Icons.smart_toy_outlined),
                                  ]),
                                  const SizedBox(height: 8),
                                  if (busy) ...[
                                    Text(
                                        '${service.phase == BatchUpdatePhase.checking ? 'batchUpdateChecking'.tr : 'batchUpdateSubmitting'.tr} ${service.current} / ${service.total}'),
                                    const SizedBox(height: 4),
                                    LinearProgressIndicator(
                                        value: service.total == 0
                                            ? null
                                            : service.current / service.total),
                                    const SizedBox(height: 8),
                                  ],
                                  BatchUpdateStatistics(compact: true, items: [
                                    BatchUpdateStatistic(
                                        'batchUpdateTotalCount'.tr,
                                        '${service.items.length}',
                                        Icons.list_alt),
                                    BatchUpdateStatistic(
                                        'batchUpdateAvailable'.tr,
                                        '${service.count(BatchUpdateItemStatus.available)}',
                                        Icons.update),
                                    BatchUpdateStatistic(
                                        'batchUpdateInProgressCount'.tr,
                                        '$inProgress',
                                        Icons.sync),
                                    BatchUpdateStatistic('batchUpdateFailed'.tr,
                                        '$failed', Icons.error_outline,
                                        onTap: failed == 0
                                            ? null
                                            : () => _showFailures(context)),
                                    BatchUpdateStatistic(
                                        'batchUpdateExistingCount'.tr,
                                        '${service.count(BatchUpdateItemStatus.existing)}',
                                        Icons.copy_outlined),
                                    BatchUpdateStatistic(
                                        'batchUpdateStoppedCount'.tr,
                                        '${service.stoppedCount}',
                                        Icons.pause_circle_outline),
                                  ]),
                                ]),
                          ),
                        ),
                      ],
                    )),
          ),
          actions: [
            if (service.active)
              TextButton(
                  onPressed: service.cancel,
                  child: Text('batchUpdateStopPending'.tr)),
            TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child:
                    Text(busy ? 'batchUpdateHide'.tr : 'batchUpdateClose'.tr)),
            if (review)
              FilledButton(
                  onPressed: service.selectedCount == 0 ? null : onSubmit,
                  child: Text('batchUpdateConfirmUpdate'.tr)),
          ],
        );
      });

  Future<void> _showFailures(BuildContext context) {
    // Retain this batch if a new one starts while its details remain open.
    final batchItems = service.items;
    return showDialog<void>(
      context: context,
      builder: (context) => AnimatedBuilder(
        animation: service,
        builder: (context, _) {
          // Read the existing records only: opening details never restarts checks
          // or paid archive operations. Failed items need not have a target.
          final failures = batchItems
              .where((item) => item.status == BatchUpdateItemStatus.failed)
              .toList();
          return AlertDialog(
            title: Text('batchUpdateFailureDetails'.tr),
            content: SizedBox(
              width: 580,
              height: MediaQuery.sizeOf(context).height * .5,
              child: failures.isEmpty
                  ? Center(child: Text('batchUpdateNoFailures'.tr))
                  : ListView.separated(
                      itemCount: failures.length,
                      separatorBuilder: (_, __) => const Divider(),
                      itemBuilder: (context, index) {
                        final item = failures[index];
                        final reason = item.reason?.trim();
                        return ListTile(
                          key: ValueKey(
                              'batch-update-failure-${item.source.gid}'),
                          contentPadding: EdgeInsets.zero,
                          title: Text(item.source.title.trim().isEmpty
                              ? 'untitledGallery'.tr
                              : item.source.title),
                          subtitle: Text('GID: ${item.source.gid}'
                              '${item.target == null ? '' : ' → ${item.target!.galleryUrl.gid}'}\n'
                              '${'batchUpdateFailureReason'.tr}: ${reason == null || reason.isEmpty ? 'batchUpdateFailureUnknown'.tr : reason.tr}'),
                        );
                      },
                    ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text('batchUpdateClose'.tr))
            ],
          );
        },
      ),
    );
  }
}
