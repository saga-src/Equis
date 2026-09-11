import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers/app_providers.dart';
import '../../domain/attachments/attachment_models.dart';
import '../../domain/shared/utc_instant.dart';
import '../../domain/shared/uuid_v7.dart';
import '../../l10n/app_localizations.dart';
import '../shared/equis_glass.dart';

class TransactionAttachmentsPanel extends ConsumerStatefulWidget {
  const TransactionAttachmentsPanel({
    required this.vaultId,
    required this.transactionId,
    super.key,
  });

  final EntityId vaultId;
  final EntityId transactionId;

  @override
  ConsumerState<TransactionAttachmentsPanel> createState() =>
      _TransactionAttachmentsPanelState();
}

class _TransactionAttachmentsPanelState
    extends ConsumerState<TransactionAttachmentsPanel> {
  List<AttachmentMetadata> _attachments = const [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_reload());
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return EquisGlassCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    l.receiptAttachmentsTitle,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  key: const Key('add-transaction-attachment'),
                  tooltip: l.addAttachmentAction,
                  onPressed: _busy ? null : _add,
                  icon: const Icon(Icons.attach_file),
                ),
              ],
            ),
            if (_busy) const LinearProgressIndicator(),
            if (_attachments.isEmpty && !_busy)
              Text(l.noAttachmentsMessage)
            else
              for (final attachment in _attachments)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(_stateIcon(attachment.uploadState)),
                  title: Text(attachment.originalFilename),
                  subtitle: Text(l.attachmentSizeLabel(attachment.byteSize)),
                  trailing: IconButton(
                    tooltip: l.exportAttachmentAction,
                    onPressed: _busy ? null : () => _export(attachment),
                    icon: const Icon(Icons.download_outlined),
                  ),
                ),
          ],
        ),
      ),
    );
  }

  Future<void> _reload() async {
    final service = ref.read(localAppDependenciesProvider)?.attachments;
    if (service == null) return;
    try {
      final values = await service.listForEntity(
        entityType: AttachmentEntityType.transaction,
        entityId: widget.transactionId,
      );
      if (mounted) setState(() => _attachments = values);
    } catch (_) {
      _showError();
    }
  }

  Future<void> _add() async {
    final selected = await openFile();
    if (selected == null || !mounted) return;
    await _run(() async {
      await ref
          .read(localAppDependenciesProvider)!
          .attachments
          .add(
            vaultId: widget.vaultId,
            sourcePath: selected.path,
            originalFilename: selected.name,
            mimeType: _mimeType(selected.name),
            links: [
              AttachmentLinkDefinition(
                entityType: AttachmentEntityType.transaction,
                entityId: widget.transactionId,
              ),
            ],
            now: UtcInstant.now(),
          );
      await _reload();
    }, AppLocalizations.of(context).attachmentAddedMessage);
  }

  Future<void> _export(AttachmentMetadata attachment) async {
    final location = await getSaveLocation(
      suggestedName: attachment.originalFilename,
    );
    if (location == null || !mounted) return;
    await _run(() async {
      await ref
          .read(localAppDependenciesProvider)!
          .attachments
          .exportClear(attachment, location.path);
    }, AppLocalizations.of(context).attachmentExportedMessage);
  }

  Future<void> _run(Future<void> Function() action, String success) async {
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(success)));
      }
    } catch (_) {
      _showError();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showError() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context).attachmentErrorMessage),
      ),
    );
  }
}

IconData _stateIcon(AttachmentUploadState state) => switch (state) {
  AttachmentUploadState.local => Icons.lock_outline,
  AttachmentUploadState.pending => Icons.cloud_upload_outlined,
  AttachmentUploadState.uploaded => Icons.cloud_done_outlined,
  AttachmentUploadState.failed => Icons.cloud_off_outlined,
};

String? _mimeType(String filename) {
  final lower = filename.toLowerCase();
  if (lower.endsWith('.pdf')) return 'application/pdf';
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
  if (lower.endsWith('.webp')) return 'image/webp';
  if (lower.endsWith('.txt')) return 'text/plain';
  return 'application/octet-stream';
}
