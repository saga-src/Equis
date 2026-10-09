import 'package:equis/app/providers/app_providers.dart';
import 'package:equis/application/services/local_finance_session_service.dart';
import 'package:equis/domain/entities/account_aggregate.dart';
import 'package:equis/domain/entities/account_profile.dart';
import 'package:equis/domain/entities/category_node.dart';
import 'package:equis/domain/entities/vault_profile.dart';
import 'package:equis/domain/ledger/ledger_models.dart';
import 'package:equis/domain/recurring/recurrence_models.dart';
import 'package:equis/domain/shared/currency.dart';
import 'package:equis/domain/shared/local_date.dart';
import 'package:equis/domain/shared/money.dart';
import 'package:equis/domain/shared/utc_instant.dart';
import 'package:equis/domain/shared/uuid_v7.dart';
import 'package:equis/l10n/app_localizations.dart';
import 'package:equis/presentation/recurring/recurring_controller.dart';
import 'package:equis/presentation/recurring/recurring_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final locale in [const Locale('pt', 'BR'), const Locale('en', 'US')]) {
    for (final width in [360.0, 1280.0]) {
      testWidgets(
        'rule editor retains draft on failure and deletion confirms: $locale $width',
        (tester) async {
          await tester.binding.setSurfaceSize(Size(width, 1000));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          final vault = EntityId.generate(),
              account = EntityId.generate(),
              pocket = EntityId.generate(),
              category = EntityId.generate();
          const now = UtcInstant.fromEpochMicroseconds(1);
          final schedule = RecurringSchedule(
            rule: RecurringRule(
              id: EntityId.generate(),
              vaultId: vault,
              name: 'Rent',
              pattern: const RecurrencePattern(
                frequency: RecurrenceFrequency.monthly,
              ),
              timezone: 'UTC',
              startsOn: LocalDate(2026, 1, 31),
              createdAt: now,
              updatedAt: now,
            ),
            template: RecurringTemplate(
              transactionType: LedgerTransactionType.expense,
              title: 'Payee',
              notes: 'Note',
              movements: [
                LedgerMovement(
                  id: EntityId.generate(),
                  pocket: LedgerPocket(
                    id: pocket,
                    currency: CurrencyCode.brl,
                    nature: AccountNature.asset,
                  ),
                  amountMinor: -7250,
                  sortOrder: 0,
                ),
              ],
              splits: [
                LedgerSplit(
                  id: EntityId.generate(),
                  categoryId: category,
                  money: Money(currency: CurrencyCode.brl, minorUnits: 7250),
                  sortOrder: 0,
                ),
              ],
            ),
          );
          final finance = LocalFinanceSnapshot(
            vault: VaultProfile(
              id: vault,
              name: 'Local',
              baseCurrency: CurrencyCode.brl,
              locale: 'en-US',
              timezone: 'UTC',
              createdAt: now,
              updatedAt: now,
            ),
            accounts: [
              AccountAggregate(
                account: AccountProfile(
                  id: account,
                  vaultId: vault,
                  name: 'Checking',
                  type: AccountType.checking,
                  nature: AccountNature.asset,
                  createdAt: now,
                  updatedAt: now,
                ),
                pockets: [
                  AccountPocketProfile(
                    id: pocket,
                    accountId: account,
                    currency: CurrencyCode.brl,
                    isDefault: true,
                  ),
                ],
              ),
            ],
            categories: [
              CategoryNode(
                id: category,
                vaultId: vault,
                type: CategoryType.expense,
                customName: 'Housing',
                createdAt: now,
                updatedAt: now,
              ),
            ],
          );
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                recurringControllerProvider.overrideWith(
                  (ref) => RecurringController(service: null, vaultId: vault),
                ),
              ],
              child: MaterialApp(
                locale: locale,
                supportedLocales: AppLocalizations.supportedLocales,
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(1.5)),
                  child: child!,
                ),
                home: RecurringScreen(
                  financeOverride: finance,
                  stateOverride: RecurringState(
                    rules: [schedule],
                    upcoming: [
                      ScheduledOccurrence(
                        schedule: schedule,
                        recurrenceDate: LocalDate(2026, 1, 31),
                        scheduledDate: LocalDate(2026, 2, 2),
                        state: ScheduledOccurrenceState.pending,
                        transaction: LedgerTransaction(
                          id: EntityId.generate(),
                          vaultId: vault,
                          type: LedgerTransactionType.expense,
                          status: LedgerTransactionStatus.pending,
                          financialDate: LocalDate(2026, 2, 2),
                          title: 'Individual',
                          movements: [
                            LedgerMovement(
                              id: EntityId.generate(),
                              pocket: schedule.template.movements.single.pocket,
                              amountMinor: -9900,
                              sortOrder: 0,
                            ),
                          ],
                          splits: [
                            LedgerSplit(
                              id: EntityId.generate(),
                              categoryId: category,
                              money: Money(
                                currency: CurrencyCode.brl,
                                minorUnits: 9900,
                              ),
                              sortOrder: 0,
                            ),
                          ],
                          createdAt: now,
                          updatedAt: now,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final l10n = AppLocalizations.of(
            tester.element(find.byType(RecurringScreen)),
          );
          expect(find.text('Individual'), findsOneWidget);
          await tester.tap(
            find.byWidgetPredicate((widget) => widget is PopupMenuButton).first,
          );
          await tester.pumpAndSettle();
          await tester.tap(find.text(l10n.modifyOneOccurrenceAction));
          await tester.pumpAndSettle();
          expect(find.text('99.00'), findsOneWidget);
          expect(find.text('Individual'), findsNWidgets(2));
          await tester.tap(find.text(l10n.cancelAction));
          await tester.pumpAndSettle();
          await tester.tap(find.text(l10n.recurringRulesTabLabel));
          await tester.pumpAndSettle();
          await tester.tap(find.byTooltip(l10n.deleteRecurringAction));
          await tester.pumpAndSettle();
          expect(find.text(l10n.deleteRecurringConfirmation), findsOneWidget);
          await tester.tap(find.text(l10n.cancelAction));
          await tester.pumpAndSettle();
          await tester.tap(find.byTooltip(l10n.editRecurringAction));
          await tester.pumpAndSettle();
          expect(find.text('72.50'), findsOneWidget);
          expect(find.text('Payee'), findsOneWidget);
          await tester.enterText(find.byType(TextField).first, 'Changed');
          await tester.tap(find.text(l10n.applyAction));
          await tester.pumpAndSettle();
          expect(find.byType(AlertDialog), findsOneWidget);
          expect(find.text('Changed'), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
