import 'package:flutter/material.dart';
import '../../application/services/everyday_transaction_service.dart';

import '../../app/theme/equis_theme.dart';
import '../../domain/ledger/ledger_models.dart';
import '../../l10n/app_localizations.dart';
import '../formatting/equis_formatters.dart';

enum TransactionSemantic { expense, income, transfer, neutral }

enum TransactionAction { edit, reconcile, delete }

TransactionSemantic transactionSemantic(LedgerTransactionType type) =>
    switch (type) {
      LedgerTransactionType.expense => TransactionSemantic.expense,
      LedgerTransactionType.income => TransactionSemantic.income,
      LedgerTransactionType.transfer => TransactionSemantic.transfer,
      _ => TransactionSemantic.neutral,
    };

Color transactionSemanticColor(
  BuildContext context,
  LedgerTransactionType type,
) {
  final theme = Theme.of(context);
  return switch (transactionSemantic(type)) {
    TransactionSemantic.expense => theme.colorScheme.error,
    TransactionSemantic.income =>
      theme.brightness == Brightness.dark
          ? const Color(0xFF34D399)
          : const Color(0xFF047857),
    TransactionSemantic.transfer =>
      theme.brightness == Brightness.dark
          ? const Color(0xFF60A5FA)
          : const Color(0xFF1D4ED8),
    TransactionSemantic.neutral => theme.colorScheme.onSurfaceVariant,
  };
}

bool transactionIsEditable(LedgerTransaction transaction) =>
    everydayTransactionHasEditableShape(transaction);

List<TransactionAction> transactionActions(
  LedgerTransaction transaction, {
  bool? canEdit,
}) => [
  if (canEdit ?? transactionIsEditable(transaction)) TransactionAction.edit,
  if (transaction.status == LedgerTransactionStatus.cleared)
    TransactionAction.reconcile,
  TransactionAction.delete,
];

IconData transactionIcon(LedgerTransactionType type) => switch (type) {
  LedgerTransactionType.expense => Icons.arrow_upward,
  LedgerTransactionType.income => Icons.arrow_downward,
  LedgerTransactionType.transfer => Icons.swap_horiz,
  _ => Icons.receipt_long_outlined,
};

String transactionAmountLabel(
  BuildContext context,
  LedgerTransaction transaction,
) {
  if (transaction.type == LedgerTransactionType.transfer) return '↔';
  final movement = transaction.movements.first;
  final sign = switch (transactionSemantic(transaction.type)) {
    TransactionSemantic.expense => '−',
    TransactionSemantic.income => '+',
    _ => movement.amountMinor < 0 ? '−' : '+',
  };
  return '$sign ${EquisFormatters.moneyMinor(context, currency: movement.pocket.currency, minor: movement.amountMinor.abs())}';
}

final class TransactionSemanticIcon extends StatelessWidget {
  const TransactionSemanticIcon({required this.transaction, super.key});

  final LedgerTransaction transaction;

  @override
  Widget build(BuildContext context) => Icon(
    transactionIcon(transaction.type),
    key: ValueKey('transaction-icon-${transaction.id.value}'),
    color: transactionSemanticColor(context, transaction.type),
  );
}

final class TransactionAmountText extends StatelessWidget {
  const TransactionAmountText({required this.transaction, super.key});

  final LedgerTransaction transaction;

  @override
  Widget build(BuildContext context) => Text(
    transactionAmountLabel(context, transaction),
    key: ValueKey('transaction-amount-${transaction.id.value}'),
    style: EquisTypography.numeric.copyWith(
      color: transactionSemanticColor(context, transaction.type),
    ),
  );
}

final class TransactionActionMenu extends StatelessWidget {
  const TransactionActionMenu({
    required this.transaction,
    required this.onSelected,
    this.canEdit,
    super.key,
  });

  final LedgerTransaction transaction;
  final ValueChanged<TransactionAction> onSelected;
  final bool? canEdit;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return PopupMenuButton<TransactionAction>(
      key: ValueKey('transaction-actions-${transaction.id.value}'),
      onSelected: onSelected,
      itemBuilder: (context) => [
        for (final action in transactionActions(transaction, canEdit: canEdit))
          PopupMenuItem(
            value: action,
            child: Text(switch (action) {
              TransactionAction.edit => l10n.editTransactionAction,
              TransactionAction.reconcile => l10n.reconcileTransactionAction,
              TransactionAction.delete => l10n.deleteTransactionAction,
            }),
          ),
      ],
    );
  }
}
