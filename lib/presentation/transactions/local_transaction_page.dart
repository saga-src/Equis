import 'package:equis/app/providers/app_providers.dart';
import 'package:equis/application/services/everyday_transaction_service.dart';
import 'package:equis/domain/entities/category_node.dart';
import 'package:equis/domain/entities/account_profile.dart';
import 'package:equis/domain/credit_cards/credit_card_models.dart';
import 'package:equis/domain/ledger/ledger_models.dart';
import 'package:equis/domain/shared/money.dart';
import 'package:equis/domain/shared/uuid_v7.dart';
import 'package:equis/l10n/app_localizations.dart';
import 'package:equis/presentation/formatting/taxonomy_labels.dart';
import 'package:equis/presentation/transactions/transaction_detail_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'quick_transaction_screen.dart';
import 'transaction_attachments_panel.dart';

class LocalTransactionPage extends ConsumerStatefulWidget {
  const LocalTransactionPage({this.transactionId, super.key});
  final String? transactionId;

  @override
  ConsumerState<LocalTransactionPage> createState() =>
      _LocalTransactionPageState();
}

class _LocalTransactionPageState extends ConsumerState<LocalTransactionPage> {
  LedgerTransaction? _opened;
  bool _redirected = false;

  @override
  void didUpdateWidget(LocalTransactionPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.transactionId != widget.transactionId) {
      _opened = null;
      _redirected = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(localFinanceControllerProvider);
    final snapshot = state.valueOrNull;
    if (snapshot == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: state.hasError
              ? Text(l10n.localVaultErrorMessage)
              : state.isLoading
              ? const CircularProgressIndicator()
              : Text(l10n.setupRequiredMessage),
        ),
      );
    }
    return Builder(
      builder: (context) {
        if (snapshot.vault == null) {
          return Scaffold(
            appBar: AppBar(),
            body: Center(child: Text(l10n.setupRequiredMessage)),
          );
        }
        if (_opened != null && _opened!.vaultId != snapshot.vault!.id) {
          _opened = null;
          _redirected = false;
        }
        final rawId = widget.transactionId;
        if (rawId != null) {
          EntityId id;
          try {
            id = EntityId.parse(rawId);
          } on FormatException {
            return Scaffold(
              appBar: AppBar(),
              body: Center(child: Text(l10n.transactionNotFoundMessage)),
            );
          }
          final detail = ref.watch(
            transactionDetailControllerProvider(
              TransactionDetailKey(
                vaultId: snapshot.vault!.id,
                transactionId: id,
              ),
            ),
          );
          final currentData = detail.data;
          final nowIneligible =
              currentData != null &&
              !everydayTransactionCanEdit(
                currentData.transaction,
                accounts: currentData.accounts,
                categories: currentData.categories,
              );
          if (_opened != null) {
            if (detail.status == TransactionDetailStatus.missing ||
                nowIneligible ||
                !everydayTransactionCanEdit(
                  _opened!,
                  accounts: snapshot.accounts,
                  categories: snapshot.categories,
                )) {
              return _redirectToDetails(context, rawId);
            }
          } else {
            switch (detail.status) {
              case TransactionDetailStatus.loading:
                return const Scaffold(
                  body: Center(child: CircularProgressIndicator()),
                );
              case TransactionDetailStatus.missing:
                return Scaffold(
                  appBar: AppBar(),
                  body: Center(child: Text(l10n.transactionNotFoundMessage)),
                );
              case TransactionDetailStatus.error:
                return Scaffold(
                  appBar: AppBar(),
                  body: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(l10n.transactionDetailLoadFailedMessage),
                        const SizedBox(height: 12),
                        OutlinedButton(
                          onPressed: () => ref
                              .read(
                                transactionDetailControllerProvider(
                                  TransactionDetailKey(
                                    vaultId: snapshot.vault!.id,
                                    transactionId: id,
                                  ),
                                ).notifier,
                              )
                              .reload(),
                          child: Text(l10n.transactionDetailRetryAction),
                        ),
                      ],
                    ),
                  ),
                );
              case TransactionDetailStatus.ready:
                final data = detail.data!;
                if (!everydayTransactionCanEdit(
                  data.transaction,
                  accounts: data.accounts,
                  categories: data.categories,
                )) {
                  return _redirectToDetails(context, rawId);
                }
                _opened = data.transaction;
            }
          }
        }
        final existing = _opened;
        final accounts = [
          for (final account in snapshot.accounts)
            if (account.account.deletedAt == null && !account.account.archived)
              for (final pocket in account.pockets.where(
                (pocket) => !pocket.archived,
              ))
                QuickAccountOption(
                  label: '${account.account.name} · ${pocket.currency.value}',
                  accountType: account.account.type,
                  card: account.account.type == AccountType.creditCard
                      ? CreditCardContext(
                          vaultId: snapshot.vault!.id,
                          accountId: account.account.id,
                          pocketId: pocket.id,
                          currency: pocket.currency,
                        )
                      : null,
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
          onRevisionConflict: existing == null
              ? null
              : () => context.replace(
                  '/transactions/${existing.id.value}/details',
                ),
          attachmentSection: existing == null
              ? null
              : TransactionAttachmentsPanel(
                  vaultId: snapshot.vault!.id,
                  transactionId: existing.id,
                ),
          onSave: (draft) async {
            final sourceOption = accounts.singleWhere(
              (option) => option.pocket.id == draft.sourcePocketId,
            );
            final source = sourceOption.pocket;
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
                sourceAccountType: sourceOption.accountType,
                card: sourceOption.card,
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

  Widget _redirectToDetails(BuildContext context, String rawId) {
    if (!_redirected) {
      _redirected = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.replace('/transactions/$rawId/details');
      });
    }
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
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
