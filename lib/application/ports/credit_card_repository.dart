import '../../domain/credit_cards/credit_card_models.dart';
import '../../domain/shared/local_date.dart';
import '../../domain/shared/utc_instant.dart';
import '../../domain/shared/uuid_v7.dart';

abstract interface class CreditCardRepository {
  Future<void> saveProfile(CreditCardProfile profile);
  Future<CreditCardProfile?> findProfile(EntityId accountId);
  Future<void> saveLimit(CreditCardLimit limit);
  Future<CreditCardLimit?> findLimit(EntityId pocketId);

  Future<void> saveStatement(CreditCardStatement statement);
  Future<CreditCardStatement?> findStatementForDate(
    EntityId pocketId,
    LocalDate date,
  );
  Future<List<CreditCardStatement>> listStatements(EntityId pocketId);
  Future<CreditCardStatementAmounts> statementAmounts(EntityId statementId);
  Future<int> outstandingMinor(EntityId pocketId);

  Future<void> saveInstallmentPlan(InstallmentPlanView plan);
  Future<InstallmentPlanView?> findInstallmentPlan(EntityId id);
  Future<List<InstallmentPlanView>> listInstallmentPlans(EntityId pocketId);
  Future<void> saveInstallment(CardInstallment installment);
  Future<void> updateInstallmentPlanStatus(
    InstallmentPlan plan,
    InstallmentPlanStatus status, {
    required UtcInstant at,
  });
}

final class CreditCardRevisionConflict implements Exception {
  const CreditCardRevisionConflict({
    required this.recordId,
    required this.expectedRevision,
    required this.actualRevision,
  });

  final EntityId recordId;
  final int expectedRevision;
  final int? actualRevision;
}
