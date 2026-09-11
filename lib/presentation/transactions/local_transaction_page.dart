import 'package:equis/app/providers/app_providers.dart';
import 'package:equis/application/services/everyday_transaction_service.dart';
import 'package:equis/domain/entities/category_node.dart';
import 'package:equis/domain/ledger/ledger_models.dart';
import 'package:equis/domain/shared/money.dart';
import 'package:equis/domain/shared/uuid_v7.dart';
import 'package:equis/l10n/app_localizations.dart';
import 'package:equis/presentation/formatting/taxonomy_labels.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'quick_transaction_screen.dart';
import 'transaction_attachments_panel.dart';

class LocalTransactionPage extends ConsumerWidget {
  const LocalTransactionPage({this.transactionId, super.key});
  final String? transactionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(localFinanceControllerProvider);
    return state.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (error, stack) => Scaffold(
        appBar: AppBar(),
        body: Center(
          child: Text(AppLocalizations.of(context).localVaultErrorMessage),
        ),
      ),
      data: (snapshot) {
        if (snapshot?.vault == null) {
          return Scaffold(
            appBar: AppBar(),
            body: Center(
              child: Text(AppLocalizations.of(context).setupRequiredMessage),
            ),
          );
        }
        LedgerTransaction? existing;
        if (transactionId != null) {
          for (final transaction in snapshot!.recentTransactions) {
            if (transaction.id.value == transactionId) existing = transaction;
          }
          if (existing == null) {
            return Scaffold(
              appBar: AppBar(),
              body: Center(
                child: Text(
                  AppLocalizations.of(context).transactionNotFoundMessage,
                ),
              ),
            );
          }
        }
        final accounts = [
          for (final account in snapshot!.accounts)
            for (final pocket in account.pockets.where(
              (pocket) => !pocket.archived,
            ))
              QuickAccountOption(
                label: '${account.account.name} · ${pocket.currency.value}',
                pocket: LedgerPocket(
                  id: pocket.id,
                  currency: pocket.currency,
                  nature: account.account.nature,
                ),
              ),
        ];
        final categories = _categoryOptions(context, snapshot.categories);
        return QuickTransactionScreen(
          accounts: accounts,
          categories: categories,
          tags: [
            for (final tag in snapshot.tags)
              QuickTagOption(id: tag.id, label: tagLabel(context, tag)),
          ],
          initialDraft: existing == null ? null : _initial(existing),
          attachmentSection: existing == null
              ? null
              : TransactionAttachmentsPanel(
                  vaultId: snapshot.vault!.id,
                  transactionId: existing.id,
                ),
          onSave: (draft) async {
            final source = accounts
                .singleWhere(
                  (option) => option.pocket.id == draft.sourcePocketId,
                )
                .pocket;
            final destination = draft.destinationPocketId == null
                ? null
                : accounts
                      .singleWhere(
                        (option) =>
                            option.pocket.id == draft.destinationPocketId,
                      )
                      .pocket;
            final controller = ref.read(
              localFinanceControllerProvider.notifier,
            );
            if (existing == null) {
              await controller.createTransaction(
                type: _type(draft.type),
                source: source,
                destination: destination,
                amountText: draft.amountText,
                categoryId: draft.categoryId,
                date: draft.date,
                tagIds: draft.tagIds,
                title: draft.title,
                notes: draft.notes,
              );
            } else {
              await controller.updateTransaction(
                existing: existing,
                source: source,
                destination: destination,
                amountText: draft.amountText,
                categoryId: draft.categoryId,
                date: draft.date,
                tagIds: draft.tagIds,
                title: draft.title,
                notes: draft.notes,
              );
            }
            if (context.mounted) context.pop();
          },
        );
      },
    );
  }
}

EverydayTransactionType _type(QuickTransactionType type) => switch (type) {
  QuickTransactionType.expense => EverydayTransactionType.expense,
  QuickTransactionType.income => EverydayTransactionType.income,
  QuickTransactionType.transfer => EverydayTransactionType.transfer,
};

QuickTransactionDraft _initial(LedgerTransaction transaction) {
  final amount = Money(
    currency: transaction.movements.first.pocket.currency,
    minorUnits: transaction.movements.first.amountMinor.abs(),
  ).toMajor(2).toString();
  return QuickTransactionDraft(
    type: switch (transaction.type) {
      LedgerTransactionType.expense => QuickTransactionType.expense,
      LedgerTransactionType.income => QuickTransactionType.income,
      LedgerTransactionType.transfer => QuickTransactionType.transfer,
      _ => throw StateError('Unsupported quick transaction type.'),
    },
    amountText: amount,
    sourcePocketId: transaction.movements.first.pocket.id,
    destinationPocketId: transaction.type == LedgerTransactionType.transfer
        ? transaction.movements[1].pocket.id
        : null,
    categoryId: transaction.splits.isEmpty
        ? null
        : transaction.splits.first.categoryId,
    date: transaction.financialDate,
    tagIds: transaction.tagIds,
    title: transaction.title,
    notes: transaction.notes,
  );
}

List<QuickCategoryOption> _categoryOptions(
  BuildContext context,
  List<CategoryNode> categories,
) {
  final result = <QuickCategoryOption>[];
  for (final type in CategoryType.values) {
    final typed = categories
        .where((category) => category.type == type)
        .toList();
    final ids = typed.map((category) => category.id).toSet();
    final children = <EntityId, List<CategoryNode>>{};
    final roots = <CategoryNode>[];
    for (final category in typed) {
      if (category.parentId == null || !ids.contains(category.parentId)) {
        roots.add(category);
      } else {
        children.putIfAbsent(category.parentId!, () => []).add(category);
      }
    }
    void visit(CategoryNode category, int depth) {
      result.add(
        QuickCategoryOption(
          id: category.id,
          label:
              '${depth == 0 ? '' : '${List.filled(depth, '  ').join()}↳ '}'
              '${categoryLabel(context, category)}',
          type: category.type,
        ),
      );
      for (final child in children[category.id] ?? const <CategoryNode>[]) {
        visit(child, depth + 1);
      }
    }

    for (final root in roots) {
      visit(root, 0);
    }
  }
  return result;
}
