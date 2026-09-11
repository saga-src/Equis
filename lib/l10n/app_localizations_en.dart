// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Equis';

  @override
  String get homeNavigationLabel => 'Home';

  @override
  String get settingsNavigationLabel => 'Settings';

  @override
  String get availableMoneyTitle => 'Available money';

  @override
  String get availableMoneyPlaceholder =>
      'Your local financial overview will appear here.';

  @override
  String get addTransactionAction => 'Add transaction';

  @override
  String get foundationStatusTitle => 'Local-first foundation';

  @override
  String get foundationStatusBody =>
      'Your financial data will be committed locally before optional synchronization.';

  @override
  String get languageTitle => 'Language';

  @override
  String get appearanceTitle => 'Appearance';

  @override
  String get themeTitle => 'Theme';

  @override
  String get themeObsidianName => 'Obsidian Mode';

  @override
  String get themeObsidianDescription =>
      'Stable dark theme with translucent surfaces and emerald accents.';

  @override
  String get themeTrueLightName => 'True Light';

  @override
  String get themeTrueLightDescription =>
      'Clean, high-contrast light theme for daytime use.';

  @override
  String get themeLegacyName => 'Legacy';

  @override
  String get themeLegacyDescription =>
      'The original Equis v1 appearance without glass effects.';

  @override
  String get englishLanguage => 'English (United States)';

  @override
  String get portugueseLanguage => 'Portuguese (Brazil)';

  @override
  String get offlineReadyLabel => 'Offline ready';

  @override
  String get transactionTypeLabel => 'Type';

  @override
  String get expenseTypeLabel => 'Expense';

  @override
  String get incomeTypeLabel => 'Income';

  @override
  String get transferTypeLabel => 'Transfer';

  @override
  String get amountLabel => 'Amount';

  @override
  String get accountLabel => 'Account';

  @override
  String get categoryLabel => 'Category';

  @override
  String get saveLocallyAction => 'Save locally';

  @override
  String get optionalDetailsLabel => 'Optional details';

  @override
  String get transactionSavedMessage => 'Transaction saved locally';

  @override
  String get transactionSaveFailedMessage => 'Could not save the transaction';

  @override
  String get editTransactionAction => 'Edit transaction';

  @override
  String get deleteTransactionAction => 'Delete transaction';

  @override
  String get reconcileTransactionAction => 'Reconcile transaction';

  @override
  String get fromAccountLabel => 'From account';

  @override
  String get toAccountLabel => 'To account';

  @override
  String get dateLabel => 'Date';

  @override
  String get payeeLabel => 'Merchant or payee';

  @override
  String get notesLabel => 'Notes';

  @override
  String get requiredFieldMessage => 'Required field';

  @override
  String get localVaultErrorMessage =>
      'The encrypted local vault could not be opened.';

  @override
  String get setupRequiredMessage =>
      'Set up the local vault before adding transactions.';

  @override
  String get transactionNotFoundMessage => 'Transaction not found.';

  @override
  String get setupLocalVaultTitle => 'Set up your local vault';

  @override
  String get setupLocalVaultBody =>
      'Your data stays encrypted on this device and works offline.';

  @override
  String get profileNameLabel => 'Profile name';

  @override
  String get firstAccountNameLabel => 'First account name';

  @override
  String get reportingCurrencyLabel => 'Reporting currency';

  @override
  String get createLocalVaultAction => 'Create encrypted vault';

  @override
  String get recentTransactionsTitle => 'Recent transactions';

  @override
  String get noRecentTransactionsMessage => 'No transactions yet.';

  @override
  String get confirmDeleteTitle => 'Delete transaction?';

  @override
  String get confirmDeleteTransactionBody =>
      'This removes the transaction from balances while preserving a local deletion record.';

  @override
  String get cancelAction => 'Cancel';

  @override
  String get deleteAction => 'Delete';

  @override
  String get statusPendingLabel => 'Pending';

  @override
  String get statusClearedLabel => 'Cleared';

  @override
  String get statusReconciledLabel => 'Reconciled';

  @override
  String get statusCancelledLabel => 'Cancelled';

  @override
  String get categoryExpensesLabel => 'Expenses';

  @override
  String get categoryIncomeLabel => 'Income';

  @override
  String get categoryFoodLabel => 'Food';

  @override
  String get categoryHousingLabel => 'Housing';

  @override
  String get categoryTransportLabel => 'Transport';

  @override
  String get categorySalaryLabel => 'Salary';

  @override
  String get categoryOtherIncomeLabel => 'Other income';

  @override
  String get manageCategoriesTagsAction => 'Manage categories and tags';

  @override
  String get manageCategoriesTagsSubtitle =>
      'Create, translate, and organize your categories and tags.';

  @override
  String get alreadyHaveAccountAction => 'I already have an account';

  @override
  String get restoreExistingVaultTitle => 'Sign in and restore your data';

  @override
  String get restoreExistingVaultBody =>
      'Use your Equis account and the recovery key saved on your first device to download and decrypt your vault.';

  @override
  String get recoverySecretLabel => 'Recovery key';

  @override
  String get recoverySecretRestoreHint => 'It starts with equis-recovery-v1_.';

  @override
  String get restoreAndSyncAction => 'Restore and sync';

  @override
  String get restoreLocalDataSafetyMessage =>
      'Restoration is only allowed before a local vault is created, so existing device data is never overwritten.';

  @override
  String get restoreNoVaultMessage =>
      'No synchronized vault was found for this account.';

  @override
  String get restoreMultipleVaultsMessage =>
      'This account has more than one vault. Vault selection is not available yet.';

  @override
  String get restoreInvalidSecretMessage =>
      'The recovery key is invalid for this vault.';

  @override
  String get restoreLocalVaultExistsMessage =>
      'This device already has a local vault and it cannot be overwritten.';

  @override
  String get restoreSyncFailedMessage =>
      'The vault was recovered, but synchronization could not finish. Check your connection and retry.';

  @override
  String get editTranslationsAction => 'Edit names and translations';

  @override
  String get englishNameLabel => 'English name (optional)';

  @override
  String get portugueseNameLabel => 'Brazilian Portuguese name (optional)';

  @override
  String get localizedNamesHint =>
      'When a translation is empty, the main name is used.';

  @override
  String get categoriesTitle => 'Categories';

  @override
  String get tagsTitle => 'Tags';

  @override
  String get addCategoryAction => 'Add category';

  @override
  String get addTagAction => 'Add tag';

  @override
  String get categoryNameLabel => 'Category name';

  @override
  String get parentCategoryLabel => 'Parent category';

  @override
  String get noParentLabel => 'No parent';

  @override
  String get tagNameLabel => 'Tag name';

  @override
  String get noTagsMessage => 'No tags yet.';

  @override
  String get systemCategoryLabel => 'System category';

  @override
  String get archiveCategoryAction => 'Archive category';

  @override
  String get categoryArchiveFailedMessage => 'Archive child categories first.';

  @override
  String get expenseCategoriesTitle => 'Expense categories';

  @override
  String get incomeCategoriesTitle => 'Income categories';

  @override
  String get addAccountAction => 'Add account';

  @override
  String get accountNameLabel => 'Account name';

  @override
  String get accountTypeLabel => 'Account type';

  @override
  String get currencyLabel => 'Currency';

  @override
  String get checkingAccountType => 'Checking';

  @override
  String get savingsAccountType => 'Savings';

  @override
  String get cashAccountType => 'Cash';

  @override
  String get walletAccountType => 'Digital wallet';

  @override
  String get creditCardAccountType => 'Credit card';

  @override
  String get historyNavigationLabel => 'History';

  @override
  String get transactionHistoryTitle => 'Transaction history';

  @override
  String get filtersAction => 'Filters';

  @override
  String get historyFiltersTitle => 'Search and filters';

  @override
  String get minimumAmountLabel => 'Minimum amount';

  @override
  String get maximumAmountLabel => 'Maximum amount';

  @override
  String get fromDateLabel => 'From date';

  @override
  String get toDateLabel => 'To date';

  @override
  String get anyValueLabel => 'Any';

  @override
  String get includeDescendantCategoriesLabel => 'Include child categories';

  @override
  String get tagFilterLabel => 'Tag';

  @override
  String get statusFilterLabel => 'Status';

  @override
  String get clearFiltersAction => 'Clear';

  @override
  String get applyFiltersAction => 'Apply filters';

  @override
  String get loadMoreAction => 'Load more';

  @override
  String get noHistoryResultsMessage => 'No transactions match these filters.';

  @override
  String get historySearchFailedMessage =>
      'Could not search the local transaction history.';

  @override
  String get invalidFiltersMessage => 'Check the amount and date ranges.';

  @override
  String transactionTypeName(String type) {
    String _temp0 = intl.Intl.selectLogic(type, {
      'opening_balance': 'Opening balance',
      'expense': 'Expense',
      'income': 'Income',
      'transfer': 'Transfer',
      'currency_exchange': 'Currency exchange',
      'credit_card_purchase': 'Credit card purchase',
      'credit_card_payment': 'Credit card payment',
      'refund': 'Refund',
      'loan_payment': 'Loan payment',
      'investment_buy': 'Investment purchase',
      'investment_sell': 'Investment sale',
      'dividend': 'Dividend',
      'interest': 'Interest',
      'fee': 'Fee',
      'adjustment': 'Adjustment',
      'other': 'Transaction',
    });
    return '$_temp0';
  }

  @override
  String get recurringNavigationLabel => 'Scheduled';

  @override
  String get recurringTitle => 'Recurring activity';

  @override
  String get upcomingTabLabel => 'Upcoming';

  @override
  String get recurringRulesTabLabel => 'Rules';

  @override
  String get addRecurringAction => 'Add recurring';

  @override
  String get createRecurringAction => 'Create schedule';

  @override
  String get recurringLoadFailedMessage =>
      'Could not load recurring activity from the local vault.';

  @override
  String get noUpcomingOccurrencesMessage =>
      'No scheduled activity in the next 90 days.';

  @override
  String get noRecurringRulesMessage => 'No recurrence rules yet.';

  @override
  String get confirmOccurrenceAction => 'Confirm';

  @override
  String get skipOccurrenceAction => 'Skip';

  @override
  String get rescheduleOccurrenceAction => 'Reschedule';

  @override
  String get modifyOneOccurrenceAction => 'Modify this occurrence';

  @override
  String get modifyFutureOccurrencesAction =>
      'Modify this and future occurrences';

  @override
  String get endRecurrenceAction => 'End recurrence';

  @override
  String get endedRecurrenceLabel => 'Ended';

  @override
  String get recurrenceNameLabel => 'Schedule name';

  @override
  String get recurrenceStartsLabel => 'Starts on';

  @override
  String get recurrenceEndsLabel => 'Ends on (optional)';

  @override
  String get frequencyLabel => 'Frequency';

  @override
  String get intervalLabel => 'Every';

  @override
  String get dailyFrequencyLabel => 'Daily';

  @override
  String get weeklyFrequencyLabel => 'Weekly';

  @override
  String get monthlyFrequencyLabel => 'Monthly';

  @override
  String get yearlyFrequencyLabel => 'Yearly';

  @override
  String get scheduledOccurrenceLabel => 'Scheduled';

  @override
  String get pendingOccurrenceLabel => 'Changed';

  @override
  String get confirmedOccurrenceLabel => 'Confirmed';

  @override
  String get skippedOccurrenceLabel => 'Skipped';

  @override
  String get applyAction => 'Apply';

  @override
  String get thisMonthTitle => 'This month';

  @override
  String get incomeReportLabel => 'Income';

  @override
  String get expensesReportLabel => 'Expenses';

  @override
  String get netCashFlowLabel => 'Net cash flow';

  @override
  String get budgetDashboardTitle => 'Budget';

  @override
  String get budgetNextPhaseMessage =>
      'Budget tracking becomes available in the next phase.';

  @override
  String get upcomingDashboardTitle => 'Upcoming';

  @override
  String get upcomingNext30DaysLabel => 'Scheduled in the next 30 days';

  @override
  String get spendingByCategoryTitle => 'Spending by category';

  @override
  String get cashFlowChartTitle => 'Cash flow over time';

  @override
  String get accountBalancesTitle => 'Account balances';

  @override
  String get reportsSectionTitle => 'Reports';

  @override
  String get reportingIncompleteMessage =>
      'Some currencies are omitted because no local exchange rate is available.';

  @override
  String get reportingEstimatedMessage =>
      'Includes estimated cached exchange rates.';

  @override
  String get noSpendingDataMessage => 'No classified activity in this period.';

  @override
  String get originalCurrencyAmountLabel => 'Original currency';

  @override
  String get reportingAmountLabel => 'Reporting currency';

  @override
  String get cardsNavigationLabel => 'Cards';

  @override
  String get creditCardsTitle => 'Credit cards';

  @override
  String get noCreditCardsMessage =>
      'Create a credit-card account on Home to get started.';

  @override
  String get selectCardLabel => 'Card and currency';

  @override
  String get configureCardAction => 'Configure card';

  @override
  String get closingDayLabel => 'Closing day';

  @override
  String get dueDayLabel => 'Due day';

  @override
  String get creditLimitLabel => 'Credit limit';

  @override
  String get availableCreditLabel => 'Available credit';

  @override
  String get statementsTabLabel => 'Statements';

  @override
  String get installmentsTabLabel => 'Installments';

  @override
  String get addCardPurchaseAction => 'Add purchase';

  @override
  String get addInstallmentAction => 'Add installment purchase';

  @override
  String get feeInterestAction => 'Add fee or interest';

  @override
  String get payStatementAction => 'Pay statement';

  @override
  String get refundPurchaseAction => 'Refund purchase';

  @override
  String get noStatementsMessage => 'No statements for this card.';

  @override
  String get noInstallmentsMessage => 'No installment plans for this card.';

  @override
  String get originalAmountLabel => 'Original amount';

  @override
  String get financedAmountLabel => 'Total with interest';

  @override
  String get installmentCountLabel => 'Installment count';

  @override
  String get firstInstallmentDateLabel => 'First installment date';

  @override
  String get interestRateLabel => 'Interest rate (optional)';

  @override
  String get descriptionLabel => 'Description';

  @override
  String get currentInstallmentLabel => 'Current installment';

  @override
  String get remainingAmountLabel => 'Remaining amount';

  @override
  String get cancelInstallmentAction => 'Cancel and refund plan';

  @override
  String get cardLoadFailedMessage =>
      'Could not load credit-card data from the local vault.';

  @override
  String get futureStatementStatus => 'Future';

  @override
  String get openStatementStatus => 'Open';

  @override
  String get closedStatementStatus => 'Closed';

  @override
  String get paidStatementStatus => 'Paid';

  @override
  String get overdueStatementStatus => 'Overdue';

  @override
  String get saveAction => 'Save';

  @override
  String get budgetsNavigationLabel => 'Budgets';

  @override
  String get budgetsTitle => 'Budgets';

  @override
  String get addBudgetAction => 'Add budget';

  @override
  String get editBudgetAction => 'Edit budget';

  @override
  String get deleteBudgetAction => 'Delete budget';

  @override
  String get noBudgetsMessage =>
      'No budgets yet. Create one to start tracking your plan.';

  @override
  String get budgetLoadFailedMessage =>
      'Could not load budgets from the local vault.';

  @override
  String get budgetNameLabel => 'Budget name';

  @override
  String get budgetLimitLabel => 'Limit';

  @override
  String get budgetPeriodLabel => 'Period';

  @override
  String get weeklyBudgetPeriod => 'Weekly';

  @override
  String get monthlyBudgetPeriod => 'Monthly';

  @override
  String get yearlyBudgetPeriod => 'Yearly';

  @override
  String get customBudgetPeriod => 'Custom range';

  @override
  String get budgetWarningThresholdLabel => 'Warning threshold (%)';

  @override
  String get budgetScopeLabel => 'Scope';

  @override
  String get overallSpendingScope => 'Overall spending';

  @override
  String get budgetCategoriesScope => 'Categories';

  @override
  String get budgetAccountsScope => 'Accounts';

  @override
  String get budgetTagsScope => 'Tags';

  @override
  String get includeDescendantsLabel => 'Include descendant categories';

  @override
  String get customStartDateLabel => 'Start date';

  @override
  String get customEndDateLabel => 'End date';

  @override
  String get budgetUsedLabel => 'Used';

  @override
  String get budgetRemainingLabel => 'Remaining';

  @override
  String get budgetProjectedLabel => 'Projected';

  @override
  String get budgetSafeState => 'Safe';

  @override
  String get budgetApproachingState => 'Approaching limit';

  @override
  String get budgetReachedState => 'Limit reached';

  @override
  String get budgetExceededState => 'Exceeded';

  @override
  String get budgetLikelyExceedMessage =>
      'At the current pace, this budget is likely to be exceeded.';

  @override
  String get budgetIncompleteFxMessage =>
      'Some spending is omitted because a local exchange rate is unavailable.';

  @override
  String get budgetEstimatedFxMessage =>
      'This budget uses an estimated local exchange rate.';

  @override
  String get confirmDeleteBudgetBody =>
      'Delete this budget? Transactions and spending history will not be changed.';

  @override
  String activeBudgetsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count active budgets',
      one: '1 active budget',
      zero: 'No active budgets',
    );
    return '$_temp0';
  }

  @override
  String budgetUsagePercent(int percent) {
    return '$percent% used';
  }

  @override
  String get goalsNavigationLabel => 'Goals';

  @override
  String get goalsTitle => 'Goals and future cash flow';

  @override
  String get goalsTabLabel => 'Goals';

  @override
  String get cashFlowProjectionTabLabel => 'Future cash flow';

  @override
  String get addGoalAction => 'Add goal';

  @override
  String get editGoalAction => 'Edit goal';

  @override
  String get deleteGoalAction => 'Delete goal';

  @override
  String get noGoalsMessage =>
      'No goals yet. Create one to plan your next milestone.';

  @override
  String get goalLoadFailedMessage =>
      'Could not load goals and projections from the local vault.';

  @override
  String get goalNameLabel => 'Goal name';

  @override
  String get goalTypeLabel => 'Goal type';

  @override
  String get emergencyFundGoalType => 'Emergency fund';

  @override
  String get vacationGoalType => 'Vacation';

  @override
  String get vehicleGoalType => 'Vehicle';

  @override
  String get homeGoalType => 'Home';

  @override
  String get debtPayoffGoalType => 'Debt payoff';

  @override
  String get investmentGoalType => 'Investment';

  @override
  String get retirementGoalType => 'Retirement';

  @override
  String get educationGoalType => 'Education';

  @override
  String get customGoalType => 'Custom';

  @override
  String get goalTargetLabel => 'Target';

  @override
  String get goalCurrentLabel => 'Current';

  @override
  String get plannedMonthlyContributionLabel => 'Planned monthly contribution';

  @override
  String get requiredMonthlyContributionLabel =>
      'Required monthly contribution';

  @override
  String get expectedCompletionLabel => 'Estimated completion';

  @override
  String get goalTargetDateLabel => 'Target date';

  @override
  String get goalPriorityLabel => 'Priority';

  @override
  String get goalTrackingModeLabel => 'Progress tracking';

  @override
  String get manualGoalTracking => 'Manual contributions';

  @override
  String get linkedAccountsGoalTracking => 'Linked account balances';

  @override
  String get transactionsGoalTracking => 'Linked contributions';

  @override
  String get linkedGoalAccountsLabel => 'Linked pockets';

  @override
  String get addGoalContributionAction => 'Add contribution';

  @override
  String get goalContributionAmountLabel => 'Contribution amount';

  @override
  String get goalContributionDateLabel => 'Contribution date';

  @override
  String get goalContributionTransactionLabel =>
      'Associated transaction (optional)';

  @override
  String get goalContributionNotesLabel => 'Notes (optional)';

  @override
  String get goalReachedLabel => 'Target reached';

  @override
  String get cashFlowEstimateDisclaimer =>
      'This is an estimate based on known local data, not a guaranteed future balance.';

  @override
  String get openingAvailableLabel => 'Opening available';

  @override
  String get projectedClosingLabel => 'Projected closing';

  @override
  String get noProjectedEventsMessage =>
      'No known events in this projection window.';

  @override
  String get projectedBalanceLabel => 'Balance after event';

  @override
  String get recurringIncomeProjectionType => 'Recurring income';

  @override
  String get recurringExpenseProjectionType => 'Recurring expense';

  @override
  String get installmentProjectionType => 'Future installment';

  @override
  String get cardStatementProjectionType => 'Card statement';

  @override
  String get goalContributionProjectionType => 'Planned goal contribution';

  @override
  String get goalIncompleteFxMessage =>
      'Some linked balances are omitted because a local exchange rate is unavailable.';

  @override
  String get goalEstimatedFxMessage =>
      'This goal uses an estimated local exchange rate.';

  @override
  String get confirmDeleteGoalBody =>
      'Delete this goal? Linked accounts, transactions, and ledger history will not be changed.';

  @override
  String activeGoalsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count active goals',
      one: '1 active goal',
      zero: 'No active goals',
    );
    return '$_temp0';
  }

  @override
  String get investmentsNavigationLabel => 'Investments';

  @override
  String get investmentsTitle => 'Investments';

  @override
  String get portfolioValueLabel => 'Portfolio value';

  @override
  String get portfolioCostLabel => 'Cost basis';

  @override
  String get unrealizedResultLabel => 'Unrealized gain/loss';

  @override
  String get realizedResultLabel => 'Realized gain/loss';

  @override
  String get investmentIncomeLabel => 'Income received';

  @override
  String get allocationLabel => 'Allocation';

  @override
  String get addInstrumentAction => 'Add instrument';

  @override
  String get noInvestmentsMessage => 'No investment instruments yet.';

  @override
  String get investmentLoadFailedMessage =>
      'Could not load investments from the local vault.';

  @override
  String get instrumentNameLabel => 'Instrument name';

  @override
  String get instrumentSymbolLabel => 'Symbol';

  @override
  String get instrumentExchangeLabel => 'Exchange';

  @override
  String get assetClassLabel => 'Asset class';

  @override
  String get quantityLabel => 'Quantity';

  @override
  String get averageCostLabel => 'Average cost';

  @override
  String get unitPriceLabel => 'Unit price';

  @override
  String get feesLabel => 'Fees';

  @override
  String get taxesLabel => 'Taxes';

  @override
  String get investmentDateLabel => 'Date';

  @override
  String get cashAccountLabel => 'Investment cash account';

  @override
  String get buyInvestmentAction => 'Buy';

  @override
  String get sellInvestmentAction => 'Sell';

  @override
  String get dividendInvestmentAction => 'Dividend';

  @override
  String get interestInvestmentAction => 'Interest';

  @override
  String get feeInvestmentAction => 'Fee';

  @override
  String get depositInvestmentAction => 'Deposit';

  @override
  String get withdrawInvestmentAction => 'Withdraw';

  @override
  String get investmentAmountLabel => 'Amount';

  @override
  String get missingMarketPriceMessage =>
      'Add a market price to calculate market value and unrealized result.';

  @override
  String get insufficientLotsMessage =>
      'The sale quantity exceeds the available lots.';

  @override
  String get wealthNavigationLabel => 'Wealth';

  @override
  String get wealthTitle => 'Net worth and assets';

  @override
  String get netWorthLabel => 'Net worth';

  @override
  String get totalAssetsLabel => 'Assets';

  @override
  String get totalLiabilitiesLabel => 'Liabilities';

  @override
  String get physicalAssetsLabel => 'Physical assets';

  @override
  String get includedAccountsLabel => 'Included accounts';

  @override
  String get addAssetAction => 'Add asset';

  @override
  String get deleteAssetAction => 'Delete asset';

  @override
  String get addValuationAction => 'Update value';

  @override
  String get noAssetsMessage => 'No physical assets yet.';

  @override
  String get wealthLoadFailedMessage =>
      'Could not load net worth from the local vault.';

  @override
  String get assetNameLabel => 'Asset name';

  @override
  String get assetTypeLabel => 'Asset type';

  @override
  String get assetCostLabel => 'Purchase price';

  @override
  String get assetDateLabel => 'Purchase date';

  @override
  String get valuationMethodLabel => 'Valuation method';

  @override
  String get annualRateLabel => 'Annual rate (%)';

  @override
  String get usefulLifeMonthsLabel => 'Useful life (months)';

  @override
  String get salvageValueLabel => 'Salvage value';

  @override
  String get includeInNetWorthLabel => 'Include in net worth';

  @override
  String get currentValueLabel => 'Current value';

  @override
  String get valuationDateLabel => 'Valuation date';

  @override
  String get manualValuationMethod => 'Manual';

  @override
  String get straightLineValuationMethod => 'Straight-line depreciation';

  @override
  String get depreciationValuationMethod => 'Fixed percentage depreciation';

  @override
  String get appreciationValuationMethod => 'Fixed percentage appreciation';

  @override
  String get customValuationMethod => 'Custom schedule';

  @override
  String get wealthIncompleteFxMessage =>
      'Some values are omitted because a local exchange rate is unavailable.';

  @override
  String get wealthEstimatedFxMessage =>
      'This report uses estimated local exchange rates.';

  @override
  String get confirmDeleteAssetBody =>
      'Delete this asset? Its valuation history will also be removed.';

  @override
  String customIntervalLabel(int interval, String unit) {
    return 'Every $interval $unit';
  }

  @override
  String get refreshPricesAction => 'Refresh market prices';

  @override
  String get manualPriceAction => 'Set manual price';

  @override
  String get stalePriceMessage => 'The cached market price is out of date.';

  @override
  String get priceRefreshFailedMessage =>
      'Price refresh failed. The last local value is still in use.';

  @override
  String get intelligenceTitle => 'Financial insights';

  @override
  String get intelligenceSubtitle =>
      'Local estimates based on your recorded data';

  @override
  String get intelligencePrivacyMessage =>
      'These insights are calculated on this device. Transaction history is not sent to an external AI service.';

  @override
  String get intelligenceLoadFailedMessage =>
      'Could not calculate financial insights from the local vault.';

  @override
  String get intelligenceDisabledMessage =>
      'Financial insights are disabled. Ledger and normal app features are unaffected.';

  @override
  String get noInsightsMessage =>
      'There is not enough local history for insights yet.';

  @override
  String get refreshInsightsAction => 'Recalculate insights';

  @override
  String get calculationTraceTitle => 'How this was estimated';

  @override
  String spendingTrendInsight(String percent) {
    return 'Projected spending is $percent% compared with last month.';
  }

  @override
  String expenseAnomalyInsight(
    String category,
    String projected,
    String percent,
  ) {
    return '$category is projected at $projected, $percent% compared with last month.';
  }

  @override
  String budgetForecastInsight(String name, String projected, String limit) {
    return 'At the current pace, $name is projected at $projected against a $limit limit.';
  }

  @override
  String cashFlowForecastInsight(int days, String closing) {
    return 'The $days-day local cash-flow estimate ends at $closing.';
  }

  @override
  String recurringCommitmentsInsight(int count, String total) {
    return '$count recurring expenses totaling $total are expected in this forecast.';
  }

  @override
  String goalContributionInsight(String name, String gap) {
    return 'To stay on schedule for $name, the monthly contribution may need $gap more.';
  }

  @override
  String emergencyFundInsight(String months, String average) {
    return 'Liquid funds cover about $months months at the recent $average monthly expense average.';
  }

  @override
  String debtOverviewInsight(String debt, String percent) {
    return 'Recorded debt is $debt, or $percent% of recorded assets.';
  }

  @override
  String netWorthTrendInsight(String change, String percent, int months) {
    return 'Net worth changed $change ($percent%) across $months report points.';
  }

  @override
  String investmentConcentrationInsight(String name, String percent) {
    return '$name represents $percent% of priced investments.';
  }

  @override
  String get cloudAccountTitle => 'Equis cloud account';

  @override
  String get cloudAccountSettingsSubtitle =>
      'Optional sign-in, verification, and device identity';

  @override
  String get createEquisAccountAction => 'Create Equis Account';

  @override
  String get continueOfflineAction => 'Continue Offline';

  @override
  String get cloudAccountIntro =>
      'Cloud identity is optional. Your current vault stays local and keeps the same identifier.';

  @override
  String get emailLabel => 'Email';

  @override
  String get passwordLabel => 'Password';

  @override
  String get signInAction => 'Sign in';

  @override
  String get signOutAction => 'Sign out';

  @override
  String get awaitingVerificationTitle => 'Verify your email';

  @override
  String awaitingVerificationBody(String email) {
    return 'A verification message was sent to $email. After verification, sign in to link this local vault.';
  }

  @override
  String get resendVerificationAction => 'Resend verification email';

  @override
  String get cloudSignedInTitle => 'Cloud account connected';

  @override
  String cloudSignedInBody(String email) {
    return 'Signed in as $email. The local vault identifier was preserved.';
  }

  @override
  String get localAccessPreservedMessage =>
      'The cloud session is unavailable or signed out. Local vault access remains available.';

  @override
  String get cloudNotConfiguredMessage =>
      'Supabase is not configured in this build. You can continue using every local feature offline.';

  @override
  String get cloudSyncEncryptionPendingMessage =>
      'Secure synchronization is off until you export and confirm the vault recovery key.';

  @override
  String get secureSyncTitle => 'Secure synchronization';

  @override
  String get secureSyncDisabledBody =>
      'Your data stays local until you enable end-to-end encrypted synchronization.';

  @override
  String get enableSecureSyncAction => 'Enable secure sync';

  @override
  String get recoverySecretTitle => 'Save your recovery key';

  @override
  String get recoverySecretBody =>
      'Store this key somewhere safe. It is required to open the encrypted vault on a new device and Equis cannot recover it for you.';

  @override
  String get copyRecoverySecretAction => 'Copy recovery key';

  @override
  String get recoverySecretCopiedMessage => 'Recovery key copied';

  @override
  String get confirmRecoverySavedAction => 'I saved the recovery key';

  @override
  String get syncStatusSynced => 'Synchronized';

  @override
  String get syncStatusOffline =>
      'Offline — pending changes remain safely on this device';

  @override
  String get syncStatusError => 'Synchronization needs attention';

  @override
  String get syncStatusReady => 'Ready to synchronize';

  @override
  String syncDiagnostics(int pushed, int pulled, int conflicts) {
    return 'Last 24 hours: $pushed sent · $pulled received · $conflicts conflicts';
  }

  @override
  String get retrySyncAction => 'Sync now';

  @override
  String get syncConflictsTitle => 'Conflicts requiring review';

  @override
  String syncConflictBody(
    String entityType,
    String recordId,
    int localRevision,
    int remoteRevision,
  ) {
    return '$entityType · $recordId · local revision $localRevision, remote revision $remoteRevision';
  }

  @override
  String get keepLocalAction => 'Keep local';

  @override
  String get keepRemoteAction => 'Keep remote';

  @override
  String deviceIdentityLabel(String name, String platform, String identifier) {
    return 'Device: $name · $platform · $identifier';
  }

  @override
  String get authInvalidCredentialsMessage => 'Email or password is incorrect.';

  @override
  String get authEmailNotVerifiedMessage =>
      'Verify your email before signing in.';

  @override
  String get authWeakPasswordMessage => 'Choose a stronger password.';

  @override
  String get authAccountExistsMessage =>
      'An account already exists for this email. Try signing in.';

  @override
  String get authRateLimitedMessage =>
      'Too many attempts. Wait a moment and try again.';

  @override
  String get authNetworkMessage =>
      'The cloud service is unreachable. Local access is unaffected.';

  @override
  String get authVaultMismatchMessage =>
      'This vault is already linked to a different cloud account.';

  @override
  String get authUnknownMessage =>
      'The cloud account operation could not be completed.';

  @override
  String get portabilityTitle => 'Backup and export';

  @override
  String get portabilitySubtitle =>
      'Encrypted backups and explicit plaintext exports';

  @override
  String get createEncryptedBackupAction => 'Create encrypted backup';

  @override
  String get encryptedBackupDescription =>
      'Creates a password-protected .equis file with vault data and attachments.';

  @override
  String get validateBackupAction => 'Validate a backup';

  @override
  String get validateBackupDescription =>
      'Checks the password, format, integrity, and compatibility without restoring.';

  @override
  String get restoreBackupAction => 'Restore backup';

  @override
  String get restoreBackupDescription =>
      'Reconstruct a vault and its attachment links in this empty profile.';

  @override
  String get restoreRequiresCleanProfileMessage =>
      'Restore is available only before creating a vault in this profile.';

  @override
  String get exportJsonAction => 'Export vault as JSON';

  @override
  String get exportCsvAction => 'Export transactions as CSV';

  @override
  String get plaintextExportDescription =>
      'Exports logical vault data without encryption.';

  @override
  String get transactionCsvDescription =>
      'Exports exact minor values, currencies, movements, splits, tags, and conversions.';

  @override
  String get backupCreatedMessage => 'Encrypted backup created.';

  @override
  String get backupValidMessage => 'The backup is authentic and compatible.';

  @override
  String get backupRestoredMessage => 'Backup restored successfully.';

  @override
  String get restoreBackupConfirmation =>
      'Restore this backup into the empty local profile? Identifiers and relationships will be preserved.';

  @override
  String get plaintextPrivacyWarningTitle => 'Unencrypted financial data';

  @override
  String get plaintextPrivacyWarningBody =>
      'This export is not encrypted. It may contain amounts, descriptions, accounts, and other private financial data. Keep it in a secure location.';

  @override
  String get continueExportAction => 'Export anyway';

  @override
  String get exportCompletedMessage => 'Plaintext export created.';

  @override
  String get backupPasswordTitle => 'Backup password';

  @override
  String get confirmPasswordLabel => 'Confirm password';

  @override
  String get backupPasswordValidationMessage =>
      'Use at least 12 characters and enter matching passwords.';

  @override
  String get portabilityErrorMessage =>
      'The operation could not be completed. Check the file, password, and destination.';

  @override
  String get receiptAttachmentsTitle => 'Receipts and attachments';

  @override
  String get addAttachmentAction => 'Attach receipt or file';

  @override
  String get noAttachmentsMessage => 'No files attached to this transaction.';

  @override
  String get exportAttachmentAction => 'Decrypt and save a copy';

  @override
  String attachmentSizeLabel(int bytes) {
    return '$bytes bytes · encrypted on this device';
  }

  @override
  String get attachmentAddedMessage => 'The file was encrypted and attached.';

  @override
  String get attachmentExportedMessage => 'Decrypted copy saved.';

  @override
  String get attachmentErrorMessage =>
      'The attachment operation could not be completed.';

  @override
  String accountNatureLabel(String nature) {
    String _temp0 = intl.Intl.selectLogic(nature, {
      'asset': 'Asset',
      'liability': 'Liability',
      'other': 'Account',
    });
    return '$_temp0';
  }

  @override
  String physicalAssetTypeLabel(String type) {
    String _temp0 = intl.Intl.selectLogic(type, {
      'property': 'Property',
      'vehicle': 'Vehicle',
      'collectible': 'Collectible',
      'equipment': 'Equipment',
      'valuablePossession': 'Valuable possession',
      'other': 'Other',
    });
    return '$_temp0';
  }

  @override
  String investmentAssetClassLabel(String assetClass) {
    String _temp0 = intl.Intl.selectLogic(assetClass, {
      'stock': 'Stock',
      'etf': 'ETF',
      'fund': 'Fund',
      'reit': 'REIT',
      'fii': 'FII',
      'bond': 'Bond',
      'fixedIncome': 'Fixed income',
      'crypto': 'Cryptocurrency',
      'commodity': 'Commodity',
      'cashEquivalent': 'Cash equivalent',
      'other': 'Other',
    });
    return '$_temp0';
  }

  @override
  String syncEntityTypeLabel(String entityType) {
    String _temp0 = intl.Intl.selectLogic(entityType, {
      'vault': 'Vault',
      'account': 'Account',
      'category': 'Category',
      'counterparty': 'Counterparty',
      'tag': 'Tag',
      'transaction': 'Transaction',
      'recurring_rule': 'Recurring rule',
      'installment_plan': 'Installment plan',
      'credit_card_statement': 'Credit-card statement',
      'budget': 'Budget',
      'goal': 'Goal',
      'asset': 'Asset',
      'investment_instrument': 'Investment instrument',
      'manual_fx_rate': 'Manual exchange rate',
      'manual_market_price': 'Manual market price',
      'attachment': 'Attachment',
      'other': 'Record',
    });
    return '$_temp0';
  }

  @override
  String get refreshAction => 'Refresh';

  @override
  String get clearValueAction => 'Clear value';

  @override
  String get lastBackupLabel => 'Last backup';

  @override
  String get spendingByTagTitle => 'Spending by tag';

  @override
  String get withoutTagsLabel => 'Without tags';

  @override
  String get tagOverlapMessage =>
      'Each expense counts in full for every tag. Tag totals may overlap.';

  @override
  String get syncRunningLabel => 'Synchronizing...';

  @override
  String get syncPendingLabel => 'Pending changes';

  @override
  String get syncAutomaticPolicy =>
      'Changes sync automatically while the app is open. Conflicts keep the higher revision; equal revisions use the edit time, then a consistent content tie-break.';

  @override
  String get syncLastSuccessLabel => 'Last completed synchronization';

  @override
  String get syncNeverLabel => 'Not yet completed';

  @override
  String get syncNetworkHelp =>
      'Check your connection and try again. Your changes remain on this device.';

  @override
  String get syncSessionHelp =>
      'Your session has expired. Sign in again with the same account.';

  @override
  String get syncAccessHelp =>
      'This account or device cannot access the cloud vault. Check that you are using the original account.';

  @override
  String get syncCompatibilityHelp =>
      'The app and sync server are incompatible. Check the app version and server migrations.';

  @override
  String get syncPayloadHelp =>
      'A pending record could not be processed. Keep your data and report the diagnostic code.';

  @override
  String get syncCryptoHelp =>
      'The cloud data could not be decrypted. Keep your recovery key and report the diagnostic code.';

  @override
  String get syncLocalHelp =>
      'A local sync operation failed. Try again; if it persists, report the diagnostic code.';

  @override
  String get syncRemoteHelp =>
      'The sync server could not complete the request. Try again later.';

  @override
  String get vaultsTitle => 'Vaults and account';

  @override
  String get localVaultsLabel => 'Vaults on this device';

  @override
  String get newVaultAction => 'New vault';

  @override
  String get legacyVaultNotice =>
      'Local copy from the test release. Use your already migrated vault for synchronization.';

  @override
  String get vaultKeyLabel => 'Vault key';

  @override
  String get vaultKeyExplanation =>
      'This key unlocks this vault. Keep it safe. It is neither your account password nor your backup password.';

  @override
  String get showVaultKeyAction => 'Show vault key';

  @override
  String get vaultSyncAction => 'Synchronize active vault';

  @override
  String get accountCloudVaultsLabel => 'Account and cloud vaults';

  @override
  String get vaultOwnerExplanation =>
      'You can open backups offline. To synchronize, sign in to the owner account. The first upload permanently binds the vault to that account.';

  @override
  String get accountEmailLabel => 'Account email';

  @override
  String get accountPasswordLabel => 'Account password';

  @override
  String get accountSignInAction => 'Sign in';

  @override
  String get accountSignOutAction => 'Sign out';

  @override
  String get refreshVaultsAction => 'Refresh vault list';

  @override
  String get noCloudVaultsMessage => 'No new-format vaults in this account.';

  @override
  String get restoreCloudVaultAction => 'Restore cloud vault';

  @override
  String get vaultOperationFailed =>
      'Could not complete. Check the owner account, vault key, backup password and connection. Existing vaults were preserved.';

  @override
  String get restoreAddsVaultMessage =>
      'Adds the backup vault without replacing existing local vaults.';

  @override
  String get legacyBackupUnsupportedMessage =>
      'Use the backup of your already migrated vault. This old file belongs to the test release.';

  @override
  String get updatesTitle => 'App updates';

  @override
  String get updateAvailable => 'Available version';

  @override
  String get updateChecking => 'Checking for updates…';

  @override
  String get updateWaitingWifi => 'Waiting for Wi-Fi';

  @override
  String get updateDownloading => 'Downloading update…';

  @override
  String get updateReady => 'Update verified and ready to install.';

  @override
  String get updateFailed =>
      'Update unavailable or verification failed. You can try again; your data is unchanged.';

  @override
  String get updateInstalling => 'Preparing installation…';

  @override
  String get updateCheckHint =>
      'Checks run while Equis is open, at most every six hours.';

  @override
  String get updateAutomatic => 'Download updates automatically';

  @override
  String get updateCheck => 'Check for updates';

  @override
  String get updateDownloadNow => 'Download now (any connection)';

  @override
  String get updateInstall => 'Install update';

  @override
  String get updateInstallConfirm =>
      'Install the verified update? On Windows, Equis will close and reopen. Keep your backup; do not uninstall the app.';

  @override
  String get updateLater => 'Later';

  @override
  String get updatePermission =>
      'Allow installation from Equis in Android settings, then tap Install update again.';

  @override
  String get updateRecoveryRequired =>
      'Equis file replacement is running or was interrupted. Close this window. If the update does not finish, use the recovery helper as described in the release instructions. Your vaults have not been opened.';
}

/// The translations for English, as used in the United States (`en_US`).
class AppLocalizationsEnUs extends AppLocalizationsEn {
  AppLocalizationsEnUs() : super('en_US');

  @override
  String get appTitle => 'Equis';

  @override
  String get homeNavigationLabel => 'Home';

  @override
  String get settingsNavigationLabel => 'Settings';

  @override
  String get availableMoneyTitle => 'Available money';

  @override
  String get availableMoneyPlaceholder =>
      'Your local financial overview will appear here.';

  @override
  String get addTransactionAction => 'Add transaction';

  @override
  String get foundationStatusTitle => 'Local-first foundation';

  @override
  String get foundationStatusBody =>
      'Your financial data will be committed locally before optional synchronization.';

  @override
  String get languageTitle => 'Language';

  @override
  String get appearanceTitle => 'Appearance';

  @override
  String get themeTitle => 'Theme';

  @override
  String get themeObsidianName => 'Obsidian Mode';

  @override
  String get themeObsidianDescription =>
      'Stable dark theme with translucent surfaces and emerald accents.';

  @override
  String get themeTrueLightName => 'True Light';

  @override
  String get themeTrueLightDescription =>
      'Clean, high-contrast light theme for daytime use.';

  @override
  String get themeLegacyName => 'Legacy';

  @override
  String get themeLegacyDescription =>
      'The original Equis v1 appearance without glass effects.';

  @override
  String get englishLanguage => 'English (United States)';

  @override
  String get portugueseLanguage => 'Portuguese (Brazil)';

  @override
  String get offlineReadyLabel => 'Offline ready';

  @override
  String get transactionTypeLabel => 'Type';

  @override
  String get expenseTypeLabel => 'Expense';

  @override
  String get incomeTypeLabel => 'Income';

  @override
  String get transferTypeLabel => 'Transfer';

  @override
  String get amountLabel => 'Amount';

  @override
  String get accountLabel => 'Account';

  @override
  String get categoryLabel => 'Category';

  @override
  String get saveLocallyAction => 'Save locally';

  @override
  String get optionalDetailsLabel => 'Optional details';

  @override
  String get transactionSavedMessage => 'Transaction saved locally';

  @override
  String get transactionSaveFailedMessage => 'Could not save the transaction';

  @override
  String get editTransactionAction => 'Edit transaction';

  @override
  String get deleteTransactionAction => 'Delete transaction';

  @override
  String get reconcileTransactionAction => 'Reconcile transaction';

  @override
  String get fromAccountLabel => 'From account';

  @override
  String get toAccountLabel => 'To account';

  @override
  String get dateLabel => 'Date';

  @override
  String get payeeLabel => 'Merchant or payee';

  @override
  String get notesLabel => 'Notes';

  @override
  String get requiredFieldMessage => 'Required field';

  @override
  String get localVaultErrorMessage =>
      'The encrypted local vault could not be opened.';

  @override
  String get setupRequiredMessage =>
      'Set up the local vault before adding transactions.';

  @override
  String get transactionNotFoundMessage => 'Transaction not found.';

  @override
  String get setupLocalVaultTitle => 'Set up your local vault';

  @override
  String get setupLocalVaultBody =>
      'Your data stays encrypted on this device and works offline.';

  @override
  String get profileNameLabel => 'Profile name';

  @override
  String get firstAccountNameLabel => 'First account name';

  @override
  String get reportingCurrencyLabel => 'Reporting currency';

  @override
  String get createLocalVaultAction => 'Create encrypted vault';

  @override
  String get recentTransactionsTitle => 'Recent transactions';

  @override
  String get noRecentTransactionsMessage => 'No transactions yet.';

  @override
  String get confirmDeleteTitle => 'Delete transaction?';

  @override
  String get confirmDeleteTransactionBody =>
      'This removes the transaction from balances while preserving a local deletion record.';

  @override
  String get cancelAction => 'Cancel';

  @override
  String get deleteAction => 'Delete';

  @override
  String get statusPendingLabel => 'Pending';

  @override
  String get statusClearedLabel => 'Cleared';

  @override
  String get statusReconciledLabel => 'Reconciled';

  @override
  String get statusCancelledLabel => 'Cancelled';

  @override
  String get categoryExpensesLabel => 'Expenses';

  @override
  String get categoryIncomeLabel => 'Income';

  @override
  String get categoryFoodLabel => 'Food';

  @override
  String get categoryHousingLabel => 'Housing';

  @override
  String get categoryTransportLabel => 'Transport';

  @override
  String get categorySalaryLabel => 'Salary';

  @override
  String get categoryOtherIncomeLabel => 'Other income';

  @override
  String get manageCategoriesTagsAction => 'Manage categories and tags';

  @override
  String get manageCategoriesTagsSubtitle =>
      'Create, translate, and organize your categories and tags.';

  @override
  String get alreadyHaveAccountAction => 'I already have an account';

  @override
  String get restoreExistingVaultTitle => 'Sign in and restore your data';

  @override
  String get restoreExistingVaultBody =>
      'Use your Equis account and the recovery key saved on your first device to download and decrypt your vault.';

  @override
  String get recoverySecretLabel => 'Recovery key';

  @override
  String get recoverySecretRestoreHint => 'It starts with equis-recovery-v1_.';

  @override
  String get restoreAndSyncAction => 'Restore and sync';

  @override
  String get restoreLocalDataSafetyMessage =>
      'Restoration is only allowed before a local vault is created, so existing device data is never overwritten.';

  @override
  String get restoreNoVaultMessage =>
      'No synchronized vault was found for this account.';

  @override
  String get restoreMultipleVaultsMessage =>
      'This account has more than one vault. Vault selection is not available yet.';

  @override
  String get restoreInvalidSecretMessage =>
      'The recovery key is invalid for this vault.';

  @override
  String get restoreLocalVaultExistsMessage =>
      'This device already has a local vault and it cannot be overwritten.';

  @override
  String get restoreSyncFailedMessage =>
      'The vault was recovered, but synchronization could not finish. Check your connection and retry.';

  @override
  String get editTranslationsAction => 'Edit names and translations';

  @override
  String get englishNameLabel => 'English name (optional)';

  @override
  String get portugueseNameLabel => 'Brazilian Portuguese name (optional)';

  @override
  String get localizedNamesHint =>
      'When a translation is empty, the main name is used.';

  @override
  String get categoriesTitle => 'Categories';

  @override
  String get tagsTitle => 'Tags';

  @override
  String get addCategoryAction => 'Add category';

  @override
  String get addTagAction => 'Add tag';

  @override
  String get categoryNameLabel => 'Category name';

  @override
  String get parentCategoryLabel => 'Parent category';

  @override
  String get noParentLabel => 'No parent';

  @override
  String get tagNameLabel => 'Tag name';

  @override
  String get noTagsMessage => 'No tags yet.';

  @override
  String get systemCategoryLabel => 'System category';

  @override
  String get archiveCategoryAction => 'Archive category';

  @override
  String get categoryArchiveFailedMessage => 'Archive child categories first.';

  @override
  String get expenseCategoriesTitle => 'Expense categories';

  @override
  String get incomeCategoriesTitle => 'Income categories';

  @override
  String get addAccountAction => 'Add account';

  @override
  String get accountNameLabel => 'Account name';

  @override
  String get accountTypeLabel => 'Account type';

  @override
  String get currencyLabel => 'Currency';

  @override
  String get checkingAccountType => 'Checking';

  @override
  String get savingsAccountType => 'Savings';

  @override
  String get cashAccountType => 'Cash';

  @override
  String get walletAccountType => 'Digital wallet';

  @override
  String get creditCardAccountType => 'Credit card';

  @override
  String get historyNavigationLabel => 'History';

  @override
  String get transactionHistoryTitle => 'Transaction history';

  @override
  String get filtersAction => 'Filters';

  @override
  String get historyFiltersTitle => 'Search and filters';

  @override
  String get minimumAmountLabel => 'Minimum amount';

  @override
  String get maximumAmountLabel => 'Maximum amount';

  @override
  String get fromDateLabel => 'From date';

  @override
  String get toDateLabel => 'To date';

  @override
  String get anyValueLabel => 'Any';

  @override
  String get includeDescendantCategoriesLabel => 'Include child categories';

  @override
  String get tagFilterLabel => 'Tag';

  @override
  String get statusFilterLabel => 'Status';

  @override
  String get clearFiltersAction => 'Clear';

  @override
  String get applyFiltersAction => 'Apply filters';

  @override
  String get loadMoreAction => 'Load more';

  @override
  String get noHistoryResultsMessage => 'No transactions match these filters.';

  @override
  String get historySearchFailedMessage =>
      'Could not search the local transaction history.';

  @override
  String get invalidFiltersMessage => 'Check the amount and date ranges.';

  @override
  String transactionTypeName(String type) {
    String _temp0 = intl.Intl.selectLogic(type, {
      'opening_balance': 'Opening balance',
      'expense': 'Expense',
      'income': 'Income',
      'transfer': 'Transfer',
      'currency_exchange': 'Currency exchange',
      'credit_card_purchase': 'Credit card purchase',
      'credit_card_payment': 'Credit card payment',
      'refund': 'Refund',
      'loan_payment': 'Loan payment',
      'investment_buy': 'Investment purchase',
      'investment_sell': 'Investment sale',
      'dividend': 'Dividend',
      'interest': 'Interest',
      'fee': 'Fee',
      'adjustment': 'Adjustment',
      'other': 'Transaction',
    });
    return '$_temp0';
  }

  @override
  String get recurringNavigationLabel => 'Scheduled';

  @override
  String get recurringTitle => 'Recurring activity';

  @override
  String get upcomingTabLabel => 'Upcoming';

  @override
  String get recurringRulesTabLabel => 'Rules';

  @override
  String get addRecurringAction => 'Add recurring';

  @override
  String get createRecurringAction => 'Create schedule';

  @override
  String get recurringLoadFailedMessage =>
      'Could not load recurring activity from the local vault.';

  @override
  String get noUpcomingOccurrencesMessage =>
      'No scheduled activity in the next 90 days.';

  @override
  String get noRecurringRulesMessage => 'No recurrence rules yet.';

  @override
  String get confirmOccurrenceAction => 'Confirm';

  @override
  String get skipOccurrenceAction => 'Skip';

  @override
  String get rescheduleOccurrenceAction => 'Reschedule';

  @override
  String get modifyOneOccurrenceAction => 'Modify this occurrence';

  @override
  String get modifyFutureOccurrencesAction =>
      'Modify this and future occurrences';

  @override
  String get endRecurrenceAction => 'End recurrence';

  @override
  String get endedRecurrenceLabel => 'Ended';

  @override
  String get recurrenceNameLabel => 'Schedule name';

  @override
  String get recurrenceStartsLabel => 'Starts on';

  @override
  String get recurrenceEndsLabel => 'Ends on (optional)';

  @override
  String get frequencyLabel => 'Frequency';

  @override
  String get intervalLabel => 'Every';

  @override
  String get dailyFrequencyLabel => 'Daily';

  @override
  String get weeklyFrequencyLabel => 'Weekly';

  @override
  String get monthlyFrequencyLabel => 'Monthly';

  @override
  String get yearlyFrequencyLabel => 'Yearly';

  @override
  String get scheduledOccurrenceLabel => 'Scheduled';

  @override
  String get pendingOccurrenceLabel => 'Changed';

  @override
  String get confirmedOccurrenceLabel => 'Confirmed';

  @override
  String get skippedOccurrenceLabel => 'Skipped';

  @override
  String get applyAction => 'Apply';

  @override
  String get thisMonthTitle => 'This month';

  @override
  String get incomeReportLabel => 'Income';

  @override
  String get expensesReportLabel => 'Expenses';

  @override
  String get netCashFlowLabel => 'Net cash flow';

  @override
  String get budgetDashboardTitle => 'Budget';

  @override
  String get budgetNextPhaseMessage =>
      'Budget tracking becomes available in the next phase.';

  @override
  String get upcomingDashboardTitle => 'Upcoming';

  @override
  String get upcomingNext30DaysLabel => 'Scheduled in the next 30 days';

  @override
  String get spendingByCategoryTitle => 'Spending by category';

  @override
  String get cashFlowChartTitle => 'Cash flow over time';

  @override
  String get accountBalancesTitle => 'Account balances';

  @override
  String get reportsSectionTitle => 'Reports';

  @override
  String get reportingIncompleteMessage =>
      'Some currencies are omitted because no local exchange rate is available.';

  @override
  String get reportingEstimatedMessage =>
      'Includes estimated cached exchange rates.';

  @override
  String get noSpendingDataMessage => 'No classified activity in this period.';

  @override
  String get originalCurrencyAmountLabel => 'Original currency';

  @override
  String get reportingAmountLabel => 'Reporting currency';

  @override
  String get cardsNavigationLabel => 'Cards';

  @override
  String get creditCardsTitle => 'Credit cards';

  @override
  String get noCreditCardsMessage =>
      'Create a credit-card account on Home to get started.';

  @override
  String get selectCardLabel => 'Card and currency';

  @override
  String get configureCardAction => 'Configure card';

  @override
  String get closingDayLabel => 'Closing day';

  @override
  String get dueDayLabel => 'Due day';

  @override
  String get creditLimitLabel => 'Credit limit';

  @override
  String get availableCreditLabel => 'Available credit';

  @override
  String get statementsTabLabel => 'Statements';

  @override
  String get installmentsTabLabel => 'Installments';

  @override
  String get addCardPurchaseAction => 'Add purchase';

  @override
  String get addInstallmentAction => 'Add installment purchase';

  @override
  String get feeInterestAction => 'Add fee or interest';

  @override
  String get payStatementAction => 'Pay statement';

  @override
  String get refundPurchaseAction => 'Refund purchase';

  @override
  String get noStatementsMessage => 'No statements for this card.';

  @override
  String get noInstallmentsMessage => 'No installment plans for this card.';

  @override
  String get originalAmountLabel => 'Original amount';

  @override
  String get financedAmountLabel => 'Total with interest';

  @override
  String get installmentCountLabel => 'Installment count';

  @override
  String get firstInstallmentDateLabel => 'First installment date';

  @override
  String get interestRateLabel => 'Interest rate (optional)';

  @override
  String get descriptionLabel => 'Description';

  @override
  String get currentInstallmentLabel => 'Current installment';

  @override
  String get remainingAmountLabel => 'Remaining amount';

  @override
  String get cancelInstallmentAction => 'Cancel and refund plan';

  @override
  String get cardLoadFailedMessage =>
      'Could not load credit-card data from the local vault.';

  @override
  String get futureStatementStatus => 'Future';

  @override
  String get openStatementStatus => 'Open';

  @override
  String get closedStatementStatus => 'Closed';

  @override
  String get paidStatementStatus => 'Paid';

  @override
  String get overdueStatementStatus => 'Overdue';

  @override
  String get saveAction => 'Save';

  @override
  String get budgetsNavigationLabel => 'Budgets';

  @override
  String get budgetsTitle => 'Budgets';

  @override
  String get addBudgetAction => 'Add budget';

  @override
  String get editBudgetAction => 'Edit budget';

  @override
  String get deleteBudgetAction => 'Delete budget';

  @override
  String get noBudgetsMessage =>
      'No budgets yet. Create one to start tracking your plan.';

  @override
  String get budgetLoadFailedMessage =>
      'Could not load budgets from the local vault.';

  @override
  String get budgetNameLabel => 'Budget name';

  @override
  String get budgetLimitLabel => 'Limit';

  @override
  String get budgetPeriodLabel => 'Period';

  @override
  String get weeklyBudgetPeriod => 'Weekly';

  @override
  String get monthlyBudgetPeriod => 'Monthly';

  @override
  String get yearlyBudgetPeriod => 'Yearly';

  @override
  String get customBudgetPeriod => 'Custom range';

  @override
  String get budgetWarningThresholdLabel => 'Warning threshold (%)';

  @override
  String get budgetScopeLabel => 'Scope';

  @override
  String get overallSpendingScope => 'Overall spending';

  @override
  String get budgetCategoriesScope => 'Categories';

  @override
  String get budgetAccountsScope => 'Accounts';

  @override
  String get budgetTagsScope => 'Tags';

  @override
  String get includeDescendantsLabel => 'Include descendant categories';

  @override
  String get customStartDateLabel => 'Start date';

  @override
  String get customEndDateLabel => 'End date';

  @override
  String get budgetUsedLabel => 'Used';

  @override
  String get budgetRemainingLabel => 'Remaining';

  @override
  String get budgetProjectedLabel => 'Projected';

  @override
  String get budgetSafeState => 'Safe';

  @override
  String get budgetApproachingState => 'Approaching limit';

  @override
  String get budgetReachedState => 'Limit reached';

  @override
  String get budgetExceededState => 'Exceeded';

  @override
  String get budgetLikelyExceedMessage =>
      'At the current pace, this budget is likely to be exceeded.';

  @override
  String get budgetIncompleteFxMessage =>
      'Some spending is omitted because a local exchange rate is unavailable.';

  @override
  String get budgetEstimatedFxMessage =>
      'This budget uses an estimated local exchange rate.';

  @override
  String get confirmDeleteBudgetBody =>
      'Delete this budget? Transactions and spending history will not be changed.';

  @override
  String activeBudgetsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count active budgets',
      one: '1 active budget',
      zero: 'No active budgets',
    );
    return '$_temp0';
  }

  @override
  String budgetUsagePercent(int percent) {
    return '$percent% used';
  }

  @override
  String get goalsNavigationLabel => 'Goals';

  @override
  String get goalsTitle => 'Goals and future cash flow';

  @override
  String get goalsTabLabel => 'Goals';

  @override
  String get cashFlowProjectionTabLabel => 'Future cash flow';

  @override
  String get addGoalAction => 'Add goal';

  @override
  String get editGoalAction => 'Edit goal';

  @override
  String get deleteGoalAction => 'Delete goal';

  @override
  String get noGoalsMessage =>
      'No goals yet. Create one to plan your next milestone.';

  @override
  String get goalLoadFailedMessage =>
      'Could not load goals and projections from the local vault.';

  @override
  String get goalNameLabel => 'Goal name';

  @override
  String get goalTypeLabel => 'Goal type';

  @override
  String get emergencyFundGoalType => 'Emergency fund';

  @override
  String get vacationGoalType => 'Vacation';

  @override
  String get vehicleGoalType => 'Vehicle';

  @override
  String get homeGoalType => 'Home';

  @override
  String get debtPayoffGoalType => 'Debt payoff';

  @override
  String get investmentGoalType => 'Investment';

  @override
  String get retirementGoalType => 'Retirement';

  @override
  String get educationGoalType => 'Education';

  @override
  String get customGoalType => 'Custom';

  @override
  String get goalTargetLabel => 'Target';

  @override
  String get goalCurrentLabel => 'Current';

  @override
  String get plannedMonthlyContributionLabel => 'Planned monthly contribution';

  @override
  String get requiredMonthlyContributionLabel =>
      'Required monthly contribution';

  @override
  String get expectedCompletionLabel => 'Estimated completion';

  @override
  String get goalTargetDateLabel => 'Target date';

  @override
  String get goalPriorityLabel => 'Priority';

  @override
  String get goalTrackingModeLabel => 'Progress tracking';

  @override
  String get manualGoalTracking => 'Manual contributions';

  @override
  String get linkedAccountsGoalTracking => 'Linked account balances';

  @override
  String get transactionsGoalTracking => 'Linked contributions';

  @override
  String get linkedGoalAccountsLabel => 'Linked pockets';

  @override
  String get addGoalContributionAction => 'Add contribution';

  @override
  String get goalContributionAmountLabel => 'Contribution amount';

  @override
  String get goalContributionDateLabel => 'Contribution date';

  @override
  String get goalContributionTransactionLabel =>
      'Associated transaction (optional)';

  @override
  String get goalContributionNotesLabel => 'Notes (optional)';

  @override
  String get goalReachedLabel => 'Target reached';

  @override
  String get cashFlowEstimateDisclaimer =>
      'This is an estimate based on known local data, not a guaranteed future balance.';

  @override
  String get openingAvailableLabel => 'Opening available';

  @override
  String get projectedClosingLabel => 'Projected closing';

  @override
  String get noProjectedEventsMessage =>
      'No known events in this projection window.';

  @override
  String get projectedBalanceLabel => 'Balance after event';

  @override
  String get recurringIncomeProjectionType => 'Recurring income';

  @override
  String get recurringExpenseProjectionType => 'Recurring expense';

  @override
  String get installmentProjectionType => 'Future installment';

  @override
  String get cardStatementProjectionType => 'Card statement';

  @override
  String get goalContributionProjectionType => 'Planned goal contribution';

  @override
  String get goalIncompleteFxMessage =>
      'Some linked balances are omitted because a local exchange rate is unavailable.';

  @override
  String get goalEstimatedFxMessage =>
      'This goal uses an estimated local exchange rate.';

  @override
  String get confirmDeleteGoalBody =>
      'Delete this goal? Linked accounts, transactions, and ledger history will not be changed.';

  @override
  String activeGoalsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count active goals',
      one: '1 active goal',
      zero: 'No active goals',
    );
    return '$_temp0';
  }

  @override
  String get investmentsNavigationLabel => 'Investments';

  @override
  String get investmentsTitle => 'Investments';

  @override
  String get portfolioValueLabel => 'Portfolio value';

  @override
  String get portfolioCostLabel => 'Cost basis';

  @override
  String get unrealizedResultLabel => 'Unrealized gain/loss';

  @override
  String get realizedResultLabel => 'Realized gain/loss';

  @override
  String get investmentIncomeLabel => 'Income received';

  @override
  String get allocationLabel => 'Allocation';

  @override
  String get addInstrumentAction => 'Add instrument';

  @override
  String get noInvestmentsMessage => 'No investment instruments yet.';

  @override
  String get investmentLoadFailedMessage =>
      'Could not load investments from the local vault.';

  @override
  String get instrumentNameLabel => 'Instrument name';

  @override
  String get instrumentSymbolLabel => 'Symbol';

  @override
  String get instrumentExchangeLabel => 'Exchange';

  @override
  String get assetClassLabel => 'Asset class';

  @override
  String get quantityLabel => 'Quantity';

  @override
  String get averageCostLabel => 'Average cost';

  @override
  String get unitPriceLabel => 'Unit price';

  @override
  String get feesLabel => 'Fees';

  @override
  String get taxesLabel => 'Taxes';

  @override
  String get investmentDateLabel => 'Date';

  @override
  String get cashAccountLabel => 'Investment cash account';

  @override
  String get buyInvestmentAction => 'Buy';

  @override
  String get sellInvestmentAction => 'Sell';

  @override
  String get dividendInvestmentAction => 'Dividend';

  @override
  String get interestInvestmentAction => 'Interest';

  @override
  String get feeInvestmentAction => 'Fee';

  @override
  String get depositInvestmentAction => 'Deposit';

  @override
  String get withdrawInvestmentAction => 'Withdraw';

  @override
  String get investmentAmountLabel => 'Amount';

  @override
  String get missingMarketPriceMessage =>
      'Add a market price to calculate market value and unrealized result.';

  @override
  String get insufficientLotsMessage =>
      'The sale quantity exceeds the available lots.';

  @override
  String get wealthNavigationLabel => 'Wealth';

  @override
  String get wealthTitle => 'Net worth and assets';

  @override
  String get netWorthLabel => 'Net worth';

  @override
  String get totalAssetsLabel => 'Assets';

  @override
  String get totalLiabilitiesLabel => 'Liabilities';

  @override
  String get physicalAssetsLabel => 'Physical assets';

  @override
  String get includedAccountsLabel => 'Included accounts';

  @override
  String get addAssetAction => 'Add asset';

  @override
  String get deleteAssetAction => 'Delete asset';

  @override
  String get addValuationAction => 'Update value';

  @override
  String get noAssetsMessage => 'No physical assets yet.';

  @override
  String get wealthLoadFailedMessage =>
      'Could not load net worth from the local vault.';

  @override
  String get assetNameLabel => 'Asset name';

  @override
  String get assetTypeLabel => 'Asset type';

  @override
  String get assetCostLabel => 'Purchase price';

  @override
  String get assetDateLabel => 'Purchase date';

  @override
  String get valuationMethodLabel => 'Valuation method';

  @override
  String get annualRateLabel => 'Annual rate (%)';

  @override
  String get usefulLifeMonthsLabel => 'Useful life (months)';

  @override
  String get salvageValueLabel => 'Salvage value';

  @override
  String get includeInNetWorthLabel => 'Include in net worth';

  @override
  String get currentValueLabel => 'Current value';

  @override
  String get valuationDateLabel => 'Valuation date';

  @override
  String get manualValuationMethod => 'Manual';

  @override
  String get straightLineValuationMethod => 'Straight-line depreciation';

  @override
  String get depreciationValuationMethod => 'Fixed percentage depreciation';

  @override
  String get appreciationValuationMethod => 'Fixed percentage appreciation';

  @override
  String get customValuationMethod => 'Custom schedule';

  @override
  String get wealthIncompleteFxMessage =>
      'Some values are omitted because a local exchange rate is unavailable.';

  @override
  String get wealthEstimatedFxMessage =>
      'This report uses estimated local exchange rates.';

  @override
  String get confirmDeleteAssetBody =>
      'Delete this asset? Its valuation history will also be removed.';

  @override
  String customIntervalLabel(int interval, String unit) {
    return 'Every $interval $unit';
  }

  @override
  String get refreshPricesAction => 'Refresh market prices';

  @override
  String get manualPriceAction => 'Set manual price';

  @override
  String get stalePriceMessage => 'The cached market price is out of date.';

  @override
  String get priceRefreshFailedMessage =>
      'Price refresh failed. The last local value is still in use.';

  @override
  String get intelligenceTitle => 'Financial insights';

  @override
  String get intelligenceSubtitle =>
      'Local estimates based on your recorded data';

  @override
  String get intelligencePrivacyMessage =>
      'These insights are calculated on this device. Transaction history is not sent to an external AI service.';

  @override
  String get intelligenceLoadFailedMessage =>
      'Could not calculate financial insights from the local vault.';

  @override
  String get intelligenceDisabledMessage =>
      'Financial insights are disabled. Ledger and normal app features are unaffected.';

  @override
  String get noInsightsMessage =>
      'There is not enough local history for insights yet.';

  @override
  String get refreshInsightsAction => 'Recalculate insights';

  @override
  String get calculationTraceTitle => 'How this was estimated';

  @override
  String spendingTrendInsight(String percent) {
    return 'Projected spending is $percent% compared with last month.';
  }

  @override
  String expenseAnomalyInsight(
    String category,
    String projected,
    String percent,
  ) {
    return '$category is projected at $projected, $percent% compared with last month.';
  }

  @override
  String budgetForecastInsight(String name, String projected, String limit) {
    return 'At the current pace, $name is projected at $projected against a $limit limit.';
  }

  @override
  String cashFlowForecastInsight(int days, String closing) {
    return 'The $days-day local cash-flow estimate ends at $closing.';
  }

  @override
  String recurringCommitmentsInsight(int count, String total) {
    return '$count recurring expenses totaling $total are expected in this forecast.';
  }

  @override
  String goalContributionInsight(String name, String gap) {
    return 'To stay on schedule for $name, the monthly contribution may need $gap more.';
  }

  @override
  String emergencyFundInsight(String months, String average) {
    return 'Liquid funds cover about $months months at the recent $average monthly expense average.';
  }

  @override
  String debtOverviewInsight(String debt, String percent) {
    return 'Recorded debt is $debt, or $percent% of recorded assets.';
  }

  @override
  String netWorthTrendInsight(String change, String percent, int months) {
    return 'Net worth changed $change ($percent%) across $months report points.';
  }

  @override
  String investmentConcentrationInsight(String name, String percent) {
    return '$name represents $percent% of priced investments.';
  }

  @override
  String get cloudAccountTitle => 'Equis cloud account';

  @override
  String get cloudAccountSettingsSubtitle =>
      'Optional sign-in, verification, and device identity';

  @override
  String get createEquisAccountAction => 'Create Equis Account';

  @override
  String get continueOfflineAction => 'Continue Offline';

  @override
  String get cloudAccountIntro =>
      'Cloud identity is optional. Your current vault stays local and keeps the same identifier.';

  @override
  String get emailLabel => 'Email';

  @override
  String get passwordLabel => 'Password';

  @override
  String get signInAction => 'Sign in';

  @override
  String get signOutAction => 'Sign out';

  @override
  String get awaitingVerificationTitle => 'Verify your email';

  @override
  String awaitingVerificationBody(String email) {
    return 'A verification message was sent to $email. After verification, sign in to link this local vault.';
  }

  @override
  String get resendVerificationAction => 'Resend verification email';

  @override
  String get cloudSignedInTitle => 'Cloud account connected';

  @override
  String cloudSignedInBody(String email) {
    return 'Signed in as $email. The local vault identifier was preserved.';
  }

  @override
  String get localAccessPreservedMessage =>
      'The cloud session is unavailable or signed out. Local vault access remains available.';

  @override
  String get cloudNotConfiguredMessage =>
      'Supabase is not configured in this build. You can continue using every local feature offline.';

  @override
  String get cloudSyncEncryptionPendingMessage =>
      'Secure synchronization is off until you export and confirm the vault recovery key.';

  @override
  String get secureSyncTitle => 'Secure synchronization';

  @override
  String get secureSyncDisabledBody =>
      'Your data stays local until you enable end-to-end encrypted synchronization.';

  @override
  String get enableSecureSyncAction => 'Enable secure sync';

  @override
  String get recoverySecretTitle => 'Save your recovery key';

  @override
  String get recoverySecretBody =>
      'Store this key somewhere safe. It is required to open the encrypted vault on a new device and Equis cannot recover it for you.';

  @override
  String get copyRecoverySecretAction => 'Copy recovery key';

  @override
  String get recoverySecretCopiedMessage => 'Recovery key copied';

  @override
  String get confirmRecoverySavedAction => 'I saved the recovery key';

  @override
  String get syncStatusSynced => 'Synchronized';

  @override
  String get syncStatusOffline =>
      'Offline — pending changes remain safely on this device';

  @override
  String get syncStatusError => 'Synchronization needs attention';

  @override
  String get syncStatusReady => 'Ready to synchronize';

  @override
  String syncDiagnostics(int pushed, int pulled, int conflicts) {
    return 'Last 24 hours: $pushed sent · $pulled received · $conflicts conflicts';
  }

  @override
  String get retrySyncAction => 'Sync now';

  @override
  String get syncConflictsTitle => 'Conflicts requiring review';

  @override
  String syncConflictBody(
    String entityType,
    String recordId,
    int localRevision,
    int remoteRevision,
  ) {
    return '$entityType · $recordId · local revision $localRevision, remote revision $remoteRevision';
  }

  @override
  String get keepLocalAction => 'Keep local';

  @override
  String get keepRemoteAction => 'Keep remote';

  @override
  String deviceIdentityLabel(String name, String platform, String identifier) {
    return 'Device: $name · $platform · $identifier';
  }

  @override
  String get authInvalidCredentialsMessage => 'Email or password is incorrect.';

  @override
  String get authEmailNotVerifiedMessage =>
      'Verify your email before signing in.';

  @override
  String get authWeakPasswordMessage => 'Choose a stronger password.';

  @override
  String get authAccountExistsMessage =>
      'An account already exists for this email. Try signing in.';

  @override
  String get authRateLimitedMessage =>
      'Too many attempts. Wait a moment and try again.';

  @override
  String get authNetworkMessage =>
      'The cloud service is unreachable. Local access is unaffected.';

  @override
  String get authVaultMismatchMessage =>
      'This vault is already linked to a different cloud account.';

  @override
  String get authUnknownMessage =>
      'The cloud account operation could not be completed.';

  @override
  String get portabilityTitle => 'Backup and export';

  @override
  String get portabilitySubtitle =>
      'Encrypted backups and explicit plaintext exports';

  @override
  String get createEncryptedBackupAction => 'Create encrypted backup';

  @override
  String get encryptedBackupDescription =>
      'Creates a password-protected .equis file with vault data and attachments.';

  @override
  String get validateBackupAction => 'Validate a backup';

  @override
  String get validateBackupDescription =>
      'Checks the password, format, integrity, and compatibility without restoring.';

  @override
  String get restoreBackupAction => 'Restore backup';

  @override
  String get restoreBackupDescription =>
      'Reconstruct a vault and its attachment links in this empty profile.';

  @override
  String get restoreRequiresCleanProfileMessage =>
      'Restore is available only before creating a vault in this profile.';

  @override
  String get exportJsonAction => 'Export vault as JSON';

  @override
  String get exportCsvAction => 'Export transactions as CSV';

  @override
  String get plaintextExportDescription =>
      'Exports logical vault data without encryption.';

  @override
  String get transactionCsvDescription =>
      'Exports exact minor values, currencies, movements, splits, tags, and conversions.';

  @override
  String get backupCreatedMessage => 'Encrypted backup created.';

  @override
  String get backupValidMessage => 'The backup is authentic and compatible.';

  @override
  String get backupRestoredMessage => 'Backup restored successfully.';

  @override
  String get restoreBackupConfirmation =>
      'Restore this backup into the empty local profile? Identifiers and relationships will be preserved.';

  @override
  String get plaintextPrivacyWarningTitle => 'Unencrypted financial data';

  @override
  String get plaintextPrivacyWarningBody =>
      'This export is not encrypted. It may contain amounts, descriptions, accounts, and other private financial data. Keep it in a secure location.';

  @override
  String get continueExportAction => 'Export anyway';

  @override
  String get exportCompletedMessage => 'Plaintext export created.';

  @override
  String get backupPasswordTitle => 'Backup password';

  @override
  String get confirmPasswordLabel => 'Confirm password';

  @override
  String get backupPasswordValidationMessage =>
      'Use at least 12 characters and enter matching passwords.';

  @override
  String get portabilityErrorMessage =>
      'The operation could not be completed. Check the file, password, and destination.';

  @override
  String get receiptAttachmentsTitle => 'Receipts and attachments';

  @override
  String get addAttachmentAction => 'Attach receipt or file';

  @override
  String get noAttachmentsMessage => 'No files attached to this transaction.';

  @override
  String get exportAttachmentAction => 'Decrypt and save a copy';

  @override
  String attachmentSizeLabel(int bytes) {
    return '$bytes bytes · encrypted on this device';
  }

  @override
  String get attachmentAddedMessage => 'The file was encrypted and attached.';

  @override
  String get attachmentExportedMessage => 'Decrypted copy saved.';

  @override
  String get attachmentErrorMessage =>
      'The attachment operation could not be completed.';

  @override
  String accountNatureLabel(String nature) {
    String _temp0 = intl.Intl.selectLogic(nature, {
      'asset': 'Asset',
      'liability': 'Liability',
      'other': 'Account',
    });
    return '$_temp0';
  }

  @override
  String physicalAssetTypeLabel(String type) {
    String _temp0 = intl.Intl.selectLogic(type, {
      'property': 'Property',
      'vehicle': 'Vehicle',
      'collectible': 'Collectible',
      'equipment': 'Equipment',
      'valuablePossession': 'Valuable possession',
      'other': 'Other',
    });
    return '$_temp0';
  }

  @override
  String investmentAssetClassLabel(String assetClass) {
    String _temp0 = intl.Intl.selectLogic(assetClass, {
      'stock': 'Stock',
      'etf': 'ETF',
      'fund': 'Fund',
      'reit': 'REIT',
      'fii': 'FII',
      'bond': 'Bond',
      'fixedIncome': 'Fixed income',
      'crypto': 'Cryptocurrency',
      'commodity': 'Commodity',
      'cashEquivalent': 'Cash equivalent',
      'other': 'Other',
    });
    return '$_temp0';
  }

  @override
  String syncEntityTypeLabel(String entityType) {
    String _temp0 = intl.Intl.selectLogic(entityType, {
      'vault': 'Vault',
      'account': 'Account',
      'category': 'Category',
      'counterparty': 'Counterparty',
      'tag': 'Tag',
      'transaction': 'Transaction',
      'recurring_rule': 'Recurring rule',
      'installment_plan': 'Installment plan',
      'credit_card_statement': 'Credit-card statement',
      'budget': 'Budget',
      'goal': 'Goal',
      'asset': 'Asset',
      'investment_instrument': 'Investment instrument',
      'manual_fx_rate': 'Manual exchange rate',
      'manual_market_price': 'Manual market price',
      'attachment': 'Attachment',
      'other': 'Record',
    });
    return '$_temp0';
  }

  @override
  String get refreshAction => 'Refresh';

  @override
  String get clearValueAction => 'Clear value';

  @override
  String get lastBackupLabel => 'Last backup';

  @override
  String get spendingByTagTitle => 'Spending by tag';

  @override
  String get withoutTagsLabel => 'Without tags';

  @override
  String get tagOverlapMessage =>
      'Each expense counts in full for every tag. Tag totals may overlap.';

  @override
  String get syncRunningLabel => 'Synchronizing...';

  @override
  String get syncPendingLabel => 'Pending changes';

  @override
  String get syncAutomaticPolicy =>
      'Changes sync automatically while the app is open. Conflicts keep the higher revision; equal revisions use the edit time, then a consistent content tie-break.';

  @override
  String get syncLastSuccessLabel => 'Last completed synchronization';

  @override
  String get syncNeverLabel => 'Not yet completed';

  @override
  String get syncNetworkHelp =>
      'Check your connection and try again. Your changes remain on this device.';

  @override
  String get syncSessionHelp =>
      'Your session has expired. Sign in again with the same account.';

  @override
  String get syncAccessHelp =>
      'This account or device cannot access the cloud vault. Check that you are using the original account.';

  @override
  String get syncCompatibilityHelp =>
      'The app and sync server are incompatible. Check the app version and server migrations.';

  @override
  String get syncPayloadHelp =>
      'A pending record could not be processed. Keep your data and report the diagnostic code.';

  @override
  String get syncCryptoHelp =>
      'The cloud data could not be decrypted. Keep your recovery key and report the diagnostic code.';

  @override
  String get syncLocalHelp =>
      'A local sync operation failed. Try again; if it persists, report the diagnostic code.';

  @override
  String get syncRemoteHelp =>
      'The sync server could not complete the request. Try again later.';

  @override
  String get vaultsTitle => 'Vaults and account';

  @override
  String get localVaultsLabel => 'Vaults on this device';

  @override
  String get newVaultAction => 'New vault';

  @override
  String get legacyVaultNotice =>
      'Local copy from the test release. Use your already migrated vault for synchronization.';

  @override
  String get vaultKeyLabel => 'Vault key';

  @override
  String get vaultKeyExplanation =>
      'This key unlocks this vault. Keep it safe. It is neither your account password nor your backup password.';

  @override
  String get showVaultKeyAction => 'Show vault key';

  @override
  String get vaultSyncAction => 'Synchronize active vault';

  @override
  String get accountCloudVaultsLabel => 'Account and cloud vaults';

  @override
  String get vaultOwnerExplanation =>
      'You can open backups offline. To synchronize, sign in to the owner account. The first upload permanently binds the vault to that account.';

  @override
  String get accountEmailLabel => 'Account email';

  @override
  String get accountPasswordLabel => 'Account password';

  @override
  String get accountSignInAction => 'Sign in';

  @override
  String get accountSignOutAction => 'Sign out';

  @override
  String get refreshVaultsAction => 'Refresh vault list';

  @override
  String get noCloudVaultsMessage => 'No new-format vaults in this account.';

  @override
  String get restoreCloudVaultAction => 'Restore cloud vault';

  @override
  String get vaultOperationFailed =>
      'Could not complete. Check the owner account, vault key, backup password and connection. Existing vaults were preserved.';

  @override
  String get restoreAddsVaultMessage =>
      'Adds the backup vault without replacing existing local vaults.';

  @override
  String get legacyBackupUnsupportedMessage =>
      'Use the backup of your already migrated vault. This old file belongs to the test release.';

  @override
  String get updatesTitle => 'App updates';

  @override
  String get updateAvailable => 'Available version';

  @override
  String get updateChecking => 'Checking for updates…';

  @override
  String get updateWaitingWifi => 'Waiting for Wi-Fi';

  @override
  String get updateDownloading => 'Downloading update…';

  @override
  String get updateReady => 'Update verified and ready to install.';

  @override
  String get updateFailed =>
      'Update unavailable or verification failed. You can try again; your data is unchanged.';

  @override
  String get updateInstalling => 'Preparing installation…';

  @override
  String get updateCheckHint =>
      'Checks run while Equis is open, at most every six hours.';

  @override
  String get updateAutomatic => 'Download updates automatically';

  @override
  String get updateCheck => 'Check for updates';

  @override
  String get updateDownloadNow => 'Download now (any connection)';

  @override
  String get updateInstall => 'Install update';

  @override
  String get updateInstallConfirm =>
      'Install the verified update? On Windows, Equis will close and reopen. Keep your backup; do not uninstall the app.';

  @override
  String get updateLater => 'Later';

  @override
  String get updatePermission =>
      'Allow installation from Equis in Android settings, then tap Install update again.';

  @override
  String get updateRecoveryRequired =>
      'Equis file replacement is running or was interrupted. Close this window. If the update does not finish, use the recovery helper as described in the release instructions. Your vaults have not been opened.';
}
