import '../ports/ledger_repository.dart';
import '../../domain/ledger/ledger_engine.dart';
import '../../domain/ledger/ledger_models.dart';
import '../../domain/shared/local_date.dart';
import '../../domain/shared/money.dart';
import '../../domain/shared/utc_instant.dart';
import '../../domain/shared/uuid_v7.dart';

enum EverydayTransactionType { expense, income, transfer }

final class EverydayTransactionService {
  EverydayTransactionService({required this.ledger, LedgerEngine? engine})
    : _engine = engine ?? LedgerEngine();

  final LedgerRepository ledger;
  final LedgerEngine _engine;

  Future<LedgerTransaction> addExpense({
    required EntityId vaultId,
    required LedgerPocket pocket,
    required Money amount,
    required EntityId categoryId,
    required LocalDate date,
    required UtcInstant now,
    List<EntityId> tagIds = const [],
    String? title,
    String? notes,
  }) => _save(
    _engine
        .expense(
          vaultId: vaultId,
          pocket: pocket,
          amount: amount,
          categoryId: categoryId,
          date: date,
          now: now,
        )
        .tagged(tagIds)
        .withDetails(title: title, notes: notes),
  );

  Future<LedgerTransaction> addIncome({
    required EntityId vaultId,
    required LedgerPocket pocket,
    required Money amount,
    required EntityId categoryId,
    required LocalDate date,
    required UtcInstant now,
    List<EntityId> tagIds = const [],
    String? title,
    String? notes,
  }) => _save(
    _engine
        .income(
          vaultId: vaultId,
          pocket: pocket,
          amount: amount,
          categoryId: categoryId,
          date: date,
          now: now,
        )
        .tagged(tagIds)
        .withDetails(title: title, notes: notes),
  );

  Future<LedgerTransaction> addTransfer({
    required EntityId vaultId,
    required LedgerPocket source,
    required LedgerPocket destination,
    required Money amount,
    required LocalDate date,
    required UtcInstant now,
    List<EntityId> tagIds = const [],
    String? title,
    String? notes,
  }) => _save(
    _engine
        .transfer(
          vaultId: vaultId,
          source: source,
          destination: destination,
          amount: amount,
          date: date,
          now: now,
        )
        .tagged(tagIds)
        .withDetails(title: title, notes: notes),
  );

  Future<LedgerTransaction> create({
    required EverydayTransactionType type,
    required EntityId vaultId,
    required LedgerPocket source,
    required Money amount,
    required LocalDate date,
    required UtcInstant now,
    EntityId? categoryId,
    LedgerPocket? destination,
    List<EntityId> tagIds = const [],
    String? title,
    String? notes,
  }) => switch (type) {
    EverydayTransactionType.expense => addExpense(
      vaultId: vaultId,
      pocket: source,
      amount: amount,
      categoryId:
          categoryId ?? (throw ArgumentError('An expense needs a category.')),
      date: date,
      now: now,
      tagIds: tagIds,
      title: title,
      notes: notes,
    ),
    EverydayTransactionType.income => addIncome(
      vaultId: vaultId,
      pocket: source,
      amount: amount,
      categoryId:
          categoryId ?? (throw ArgumentError('Income needs a category.')),
      date: date,
      now: now,
      tagIds: tagIds,
      title: title,
      notes: notes,
    ),
    EverydayTransactionType.transfer => addTransfer(
      vaultId: vaultId,
      source: source,
      destination:
          destination ??
          (throw ArgumentError('A transfer needs a destination.')),
      amount: amount,
      date: date,
      now: now,
      tagIds: tagIds,
      title: title,
      notes: notes,
    ),
  };

  Future<LedgerTransaction> update({
    required LedgerTransaction existing,
    required LedgerPocket source,
    required Money amount,
    required LocalDate date,
    required UtcInstant now,
    EntityId? categoryId,
    LedgerPocket? destination,
    List<EntityId> tagIds = const [],
    String? title,
    String? notes,
  }) async {
    final type = switch (existing.type) {
      LedgerTransactionType.expense => EverydayTransactionType.expense,
      LedgerTransactionType.income => EverydayTransactionType.income,
      LedgerTransactionType.transfer => EverydayTransactionType.transfer,
      _ => throw StateError('This transaction type is not an everyday entry.'),
    };
    final candidate = _build(
      type: type,
      vaultId: existing.vaultId,
      source: source,
      destination: destination,
      amount: amount,
      categoryId: categoryId,
      date: date,
      now: now,
    );
    final revised = existing.revise(
      movements: candidate.movements,
      splits: candidate.splits,
      financialDate: date,
      title: title,
      notes: notes,
      tagIds: tagIds,
      at: now,
    );
    await ledger.save(revised);
    return revised;
  }

  LedgerTransaction _build({
    required EverydayTransactionType type,
    required EntityId vaultId,
    required LedgerPocket source,
    required Money amount,
    required LocalDate date,
    required UtcInstant now,
    EntityId? categoryId,
    LedgerPocket? destination,
  }) => switch (type) {
    EverydayTransactionType.expense => _engine.expense(
      vaultId: vaultId,
      pocket: source,
      amount: amount,
      categoryId:
          categoryId ?? (throw ArgumentError('An expense needs a category.')),
      date: date,
      now: now,
    ),
    EverydayTransactionType.income => _engine.income(
      vaultId: vaultId,
      pocket: source,
      amount: amount,
      categoryId:
          categoryId ?? (throw ArgumentError('Income needs a category.')),
      date: date,
      now: now,
    ),
    EverydayTransactionType.transfer => _engine.transfer(
      vaultId: vaultId,
      source: source,
      destination:
          destination ??
          (throw ArgumentError('A transfer needs a destination.')),
      amount: amount,
      date: date,
      now: now,
    ),
  };

  Future<LedgerTransaction> _save(LedgerTransaction transaction) async {
    await ledger.save(transaction);
    return transaction;
  }
}
