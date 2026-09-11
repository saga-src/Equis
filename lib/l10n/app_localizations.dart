import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_pt.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('en', 'US'),
    Locale('pt'),
    Locale('pt', 'BR'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'Equis'**
  String get appTitle;

  /// No description provided for @homeNavigationLabel.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get homeNavigationLabel;

  /// No description provided for @settingsNavigationLabel.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsNavigationLabel;

  /// No description provided for @availableMoneyTitle.
  ///
  /// In en, this message translates to:
  /// **'Available money'**
  String get availableMoneyTitle;

  /// No description provided for @availableMoneyPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Your local financial overview will appear here.'**
  String get availableMoneyPlaceholder;

  /// No description provided for @addTransactionAction.
  ///
  /// In en, this message translates to:
  /// **'Add transaction'**
  String get addTransactionAction;

  /// No description provided for @foundationStatusTitle.
  ///
  /// In en, this message translates to:
  /// **'Local-first foundation'**
  String get foundationStatusTitle;

  /// No description provided for @foundationStatusBody.
  ///
  /// In en, this message translates to:
  /// **'Your financial data will be committed locally before optional synchronization.'**
  String get foundationStatusBody;

  /// No description provided for @languageTitle.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get languageTitle;

  /// No description provided for @appearanceTitle.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get appearanceTitle;

  /// No description provided for @themeTitle.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get themeTitle;

  /// No description provided for @themeObsidianName.
  ///
  /// In en, this message translates to:
  /// **'Obsidian Mode'**
  String get themeObsidianName;

  /// No description provided for @themeObsidianDescription.
  ///
  /// In en, this message translates to:
  /// **'Stable dark theme with translucent surfaces and emerald accents.'**
  String get themeObsidianDescription;

  /// No description provided for @themeTrueLightName.
  ///
  /// In en, this message translates to:
  /// **'True Light'**
  String get themeTrueLightName;

  /// No description provided for @themeTrueLightDescription.
  ///
  /// In en, this message translates to:
  /// **'Clean, high-contrast light theme for daytime use.'**
  String get themeTrueLightDescription;

  /// No description provided for @themeLegacyName.
  ///
  /// In en, this message translates to:
  /// **'Legacy'**
  String get themeLegacyName;

  /// No description provided for @themeLegacyDescription.
  ///
  /// In en, this message translates to:
  /// **'The original Equis v1 appearance without glass effects.'**
  String get themeLegacyDescription;

  /// No description provided for @englishLanguage.
  ///
  /// In en, this message translates to:
  /// **'English (United States)'**
  String get englishLanguage;

  /// No description provided for @portugueseLanguage.
  ///
  /// In en, this message translates to:
  /// **'Portuguese (Brazil)'**
  String get portugueseLanguage;

  /// No description provided for @offlineReadyLabel.
  ///
  /// In en, this message translates to:
  /// **'Offline ready'**
  String get offlineReadyLabel;

  /// No description provided for @transactionTypeLabel.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get transactionTypeLabel;

  /// No description provided for @expenseTypeLabel.
  ///
  /// In en, this message translates to:
  /// **'Expense'**
  String get expenseTypeLabel;

  /// No description provided for @incomeTypeLabel.
  ///
  /// In en, this message translates to:
  /// **'Income'**
  String get incomeTypeLabel;

  /// No description provided for @transferTypeLabel.
  ///
  /// In en, this message translates to:
  /// **'Transfer'**
  String get transferTypeLabel;

  /// No description provided for @amountLabel.
  ///
  /// In en, this message translates to:
  /// **'Amount'**
  String get amountLabel;

  /// No description provided for @accountLabel.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get accountLabel;

  /// No description provided for @categoryLabel.
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get categoryLabel;

  /// No description provided for @saveLocallyAction.
  ///
  /// In en, this message translates to:
  /// **'Save locally'**
  String get saveLocallyAction;

  /// No description provided for @optionalDetailsLabel.
  ///
  /// In en, this message translates to:
  /// **'Optional details'**
  String get optionalDetailsLabel;

  /// No description provided for @transactionSavedMessage.
  ///
  /// In en, this message translates to:
  /// **'Transaction saved locally'**
  String get transactionSavedMessage;

  /// No description provided for @transactionSaveFailedMessage.
  ///
  /// In en, this message translates to:
  /// **'Could not save the transaction'**
  String get transactionSaveFailedMessage;

  /// No description provided for @editTransactionAction.
  ///
  /// In en, this message translates to:
  /// **'Edit transaction'**
  String get editTransactionAction;

  /// No description provided for @deleteTransactionAction.
  ///
  /// In en, this message translates to:
  /// **'Delete transaction'**
  String get deleteTransactionAction;

  /// No description provided for @reconcileTransactionAction.
  ///
  /// In en, this message translates to:
  /// **'Reconcile transaction'**
  String get reconcileTransactionAction;

  /// No description provided for @fromAccountLabel.
  ///
  /// In en, this message translates to:
  /// **'From account'**
  String get fromAccountLabel;

  /// No description provided for @toAccountLabel.
  ///
  /// In en, this message translates to:
  /// **'To account'**
  String get toAccountLabel;

  /// No description provided for @dateLabel.
  ///
  /// In en, this message translates to:
  /// **'Date'**
  String get dateLabel;

  /// No description provided for @payeeLabel.
  ///
  /// In en, this message translates to:
  /// **'Merchant or payee'**
  String get payeeLabel;

  /// No description provided for @notesLabel.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get notesLabel;

  /// No description provided for @requiredFieldMessage.
  ///
  /// In en, this message translates to:
  /// **'Required field'**
  String get requiredFieldMessage;

  /// No description provided for @localVaultErrorMessage.
  ///
  /// In en, this message translates to:
  /// **'The encrypted local vault could not be opened.'**
  String get localVaultErrorMessage;

  /// No description provided for @setupRequiredMessage.
  ///
  /// In en, this message translates to:
  /// **'Set up the local vault before adding transactions.'**
  String get setupRequiredMessage;

  /// No description provided for @transactionNotFoundMessage.
  ///
  /// In en, this message translates to:
  /// **'Transaction not found.'**
  String get transactionNotFoundMessage;

  /// No description provided for @setupLocalVaultTitle.
  ///
  /// In en, this message translates to:
  /// **'Set up your local vault'**
  String get setupLocalVaultTitle;

  /// No description provided for @setupLocalVaultBody.
  ///
  /// In en, this message translates to:
  /// **'Your data stays encrypted on this device and works offline.'**
  String get setupLocalVaultBody;

  /// No description provided for @profileNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Profile name'**
  String get profileNameLabel;

  /// No description provided for @firstAccountNameLabel.
  ///
  /// In en, this message translates to:
  /// **'First account name'**
  String get firstAccountNameLabel;

  /// No description provided for @reportingCurrencyLabel.
  ///
  /// In en, this message translates to:
  /// **'Reporting currency'**
  String get reportingCurrencyLabel;

  /// No description provided for @createLocalVaultAction.
  ///
  /// In en, this message translates to:
  /// **'Create encrypted vault'**
  String get createLocalVaultAction;

  /// No description provided for @recentTransactionsTitle.
  ///
  /// In en, this message translates to:
  /// **'Recent transactions'**
  String get recentTransactionsTitle;

  /// No description provided for @noRecentTransactionsMessage.
  ///
  /// In en, this message translates to:
  /// **'No transactions yet.'**
  String get noRecentTransactionsMessage;

  /// No description provided for @confirmDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete transaction?'**
  String get confirmDeleteTitle;

  /// No description provided for @confirmDeleteTransactionBody.
  ///
  /// In en, this message translates to:
  /// **'This removes the transaction from balances while preserving a local deletion record.'**
  String get confirmDeleteTransactionBody;

  /// No description provided for @cancelAction.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancelAction;

  /// No description provided for @deleteAction.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get deleteAction;

  /// No description provided for @statusPendingLabel.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get statusPendingLabel;

  /// No description provided for @statusClearedLabel.
  ///
  /// In en, this message translates to:
  /// **'Cleared'**
  String get statusClearedLabel;

  /// No description provided for @statusReconciledLabel.
  ///
  /// In en, this message translates to:
  /// **'Reconciled'**
  String get statusReconciledLabel;

  /// No description provided for @statusCancelledLabel.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get statusCancelledLabel;

  /// No description provided for @categoryExpensesLabel.
  ///
  /// In en, this message translates to:
  /// **'Expenses'**
  String get categoryExpensesLabel;

  /// No description provided for @categoryIncomeLabel.
  ///
  /// In en, this message translates to:
  /// **'Income'**
  String get categoryIncomeLabel;

  /// No description provided for @categoryFoodLabel.
  ///
  /// In en, this message translates to:
  /// **'Food'**
  String get categoryFoodLabel;

  /// No description provided for @categoryHousingLabel.
  ///
  /// In en, this message translates to:
  /// **'Housing'**
  String get categoryHousingLabel;

  /// No description provided for @categoryTransportLabel.
  ///
  /// In en, this message translates to:
  /// **'Transport'**
  String get categoryTransportLabel;

  /// No description provided for @categorySalaryLabel.
  ///
  /// In en, this message translates to:
  /// **'Salary'**
  String get categorySalaryLabel;

  /// No description provided for @categoryOtherIncomeLabel.
  ///
  /// In en, this message translates to:
  /// **'Other income'**
  String get categoryOtherIncomeLabel;

  /// No description provided for @manageCategoriesTagsAction.
  ///
  /// In en, this message translates to:
  /// **'Manage categories and tags'**
  String get manageCategoriesTagsAction;

  /// No description provided for @manageCategoriesTagsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Create, translate, and organize your categories and tags.'**
  String get manageCategoriesTagsSubtitle;

  /// No description provided for @alreadyHaveAccountAction.
  ///
  /// In en, this message translates to:
  /// **'I already have an account'**
  String get alreadyHaveAccountAction;

  /// No description provided for @restoreExistingVaultTitle.
  ///
  /// In en, this message translates to:
  /// **'Sign in and restore your data'**
  String get restoreExistingVaultTitle;

  /// No description provided for @restoreExistingVaultBody.
  ///
  /// In en, this message translates to:
  /// **'Use your Equis account and the recovery key saved on your first device to download and decrypt your vault.'**
  String get restoreExistingVaultBody;

  /// No description provided for @recoverySecretLabel.
  ///
  /// In en, this message translates to:
  /// **'Recovery key'**
  String get recoverySecretLabel;

  /// No description provided for @recoverySecretRestoreHint.
  ///
  /// In en, this message translates to:
  /// **'It starts with equis-recovery-v1_.'**
  String get recoverySecretRestoreHint;

  /// No description provided for @restoreAndSyncAction.
  ///
  /// In en, this message translates to:
  /// **'Restore and sync'**
  String get restoreAndSyncAction;

  /// No description provided for @restoreLocalDataSafetyMessage.
  ///
  /// In en, this message translates to:
  /// **'Restoration is only allowed before a local vault is created, so existing device data is never overwritten.'**
  String get restoreLocalDataSafetyMessage;

  /// No description provided for @restoreNoVaultMessage.
  ///
  /// In en, this message translates to:
  /// **'No synchronized vault was found for this account.'**
  String get restoreNoVaultMessage;

  /// No description provided for @restoreMultipleVaultsMessage.
  ///
  /// In en, this message translates to:
  /// **'This account has more than one vault. Vault selection is not available yet.'**
  String get restoreMultipleVaultsMessage;

  /// No description provided for @restoreInvalidSecretMessage.
  ///
  /// In en, this message translates to:
  /// **'The recovery key is invalid for this vault.'**
  String get restoreInvalidSecretMessage;

  /// No description provided for @restoreLocalVaultExistsMessage.
  ///
  /// In en, this message translates to:
  /// **'This device already has a local vault and it cannot be overwritten.'**
  String get restoreLocalVaultExistsMessage;

  /// No description provided for @restoreSyncFailedMessage.
  ///
  /// In en, this message translates to:
  /// **'The vault was recovered, but synchronization could not finish. Check your connection and retry.'**
  String get restoreSyncFailedMessage;

  /// No description provided for @editTranslationsAction.
  ///
  /// In en, this message translates to:
  /// **'Edit names and translations'**
  String get editTranslationsAction;

  /// No description provided for @englishNameLabel.
  ///
  /// In en, this message translates to:
  /// **'English name (optional)'**
  String get englishNameLabel;

  /// No description provided for @portugueseNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Brazilian Portuguese name (optional)'**
  String get portugueseNameLabel;

  /// No description provided for @localizedNamesHint.
  ///
  /// In en, this message translates to:
  /// **'When a translation is empty, the main name is used.'**
  String get localizedNamesHint;

  /// No description provided for @categoriesTitle.
  ///
  /// In en, this message translates to:
  /// **'Categories'**
  String get categoriesTitle;

  /// No description provided for @tagsTitle.
  ///
  /// In en, this message translates to:
  /// **'Tags'**
  String get tagsTitle;

  /// No description provided for @addCategoryAction.
  ///
  /// In en, this message translates to:
  /// **'Add category'**
  String get addCategoryAction;

  /// No description provided for @addTagAction.
  ///
  /// In en, this message translates to:
  /// **'Add tag'**
  String get addTagAction;

  /// No description provided for @categoryNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Category name'**
  String get categoryNameLabel;

  /// No description provided for @parentCategoryLabel.
  ///
  /// In en, this message translates to:
  /// **'Parent category'**
  String get parentCategoryLabel;

  /// No description provided for @noParentLabel.
  ///
  /// In en, this message translates to:
  /// **'No parent'**
  String get noParentLabel;

  /// No description provided for @tagNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Tag name'**
  String get tagNameLabel;

  /// No description provided for @noTagsMessage.
  ///
  /// In en, this message translates to:
  /// **'No tags yet.'**
  String get noTagsMessage;

  /// No description provided for @systemCategoryLabel.
  ///
  /// In en, this message translates to:
  /// **'System category'**
  String get systemCategoryLabel;

  /// No description provided for @archiveCategoryAction.
  ///
  /// In en, this message translates to:
  /// **'Archive category'**
  String get archiveCategoryAction;

  /// No description provided for @categoryArchiveFailedMessage.
  ///
  /// In en, this message translates to:
  /// **'Archive child categories first.'**
  String get categoryArchiveFailedMessage;

  /// No description provided for @expenseCategoriesTitle.
  ///
  /// In en, this message translates to:
  /// **'Expense categories'**
  String get expenseCategoriesTitle;

  /// No description provided for @incomeCategoriesTitle.
  ///
  /// In en, this message translates to:
  /// **'Income categories'**
  String get incomeCategoriesTitle;

  /// No description provided for @addAccountAction.
  ///
  /// In en, this message translates to:
  /// **'Add account'**
  String get addAccountAction;

  /// No description provided for @accountNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Account name'**
  String get accountNameLabel;

  /// No description provided for @accountTypeLabel.
  ///
  /// In en, this message translates to:
  /// **'Account type'**
  String get accountTypeLabel;

  /// No description provided for @currencyLabel.
  ///
  /// In en, this message translates to:
  /// **'Currency'**
  String get currencyLabel;

  /// No description provided for @checkingAccountType.
  ///
  /// In en, this message translates to:
  /// **'Checking'**
  String get checkingAccountType;

  /// No description provided for @savingsAccountType.
  ///
  /// In en, this message translates to:
  /// **'Savings'**
  String get savingsAccountType;

  /// No description provided for @cashAccountType.
  ///
  /// In en, this message translates to:
  /// **'Cash'**
  String get cashAccountType;

  /// No description provided for @walletAccountType.
  ///
  /// In en, this message translates to:
  /// **'Digital wallet'**
  String get walletAccountType;

  /// No description provided for @creditCardAccountType.
  ///
  /// In en, this message translates to:
  /// **'Credit card'**
  String get creditCardAccountType;

  /// No description provided for @historyNavigationLabel.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get historyNavigationLabel;

  /// No description provided for @transactionHistoryTitle.
  ///
  /// In en, this message translates to:
  /// **'Transaction history'**
  String get transactionHistoryTitle;

  /// No description provided for @filtersAction.
  ///
  /// In en, this message translates to:
  /// **'Filters'**
  String get filtersAction;

  /// No description provided for @historyFiltersTitle.
  ///
  /// In en, this message translates to:
  /// **'Search and filters'**
  String get historyFiltersTitle;

  /// No description provided for @minimumAmountLabel.
  ///
  /// In en, this message translates to:
  /// **'Minimum amount'**
  String get minimumAmountLabel;

  /// No description provided for @maximumAmountLabel.
  ///
  /// In en, this message translates to:
  /// **'Maximum amount'**
  String get maximumAmountLabel;

  /// No description provided for @fromDateLabel.
  ///
  /// In en, this message translates to:
  /// **'From date'**
  String get fromDateLabel;

  /// No description provided for @toDateLabel.
  ///
  /// In en, this message translates to:
  /// **'To date'**
  String get toDateLabel;

  /// No description provided for @anyValueLabel.
  ///
  /// In en, this message translates to:
  /// **'Any'**
  String get anyValueLabel;

  /// No description provided for @includeDescendantCategoriesLabel.
  ///
  /// In en, this message translates to:
  /// **'Include child categories'**
  String get includeDescendantCategoriesLabel;

  /// No description provided for @tagFilterLabel.
  ///
  /// In en, this message translates to:
  /// **'Tag'**
  String get tagFilterLabel;

  /// No description provided for @statusFilterLabel.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get statusFilterLabel;

  /// No description provided for @clearFiltersAction.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clearFiltersAction;

  /// No description provided for @applyFiltersAction.
  ///
  /// In en, this message translates to:
  /// **'Apply filters'**
  String get applyFiltersAction;

  /// No description provided for @loadMoreAction.
  ///
  /// In en, this message translates to:
  /// **'Load more'**
  String get loadMoreAction;

  /// No description provided for @noHistoryResultsMessage.
  ///
  /// In en, this message translates to:
  /// **'No transactions match these filters.'**
  String get noHistoryResultsMessage;

  /// No description provided for @historySearchFailedMessage.
  ///
  /// In en, this message translates to:
  /// **'Could not search the local transaction history.'**
  String get historySearchFailedMessage;

  /// No description provided for @invalidFiltersMessage.
  ///
  /// In en, this message translates to:
  /// **'Check the amount and date ranges.'**
  String get invalidFiltersMessage;

  /// No description provided for @transactionTypeName.
  ///
  /// In en, this message translates to:
  /// **'{type, select, opening_balance{Opening balance} expense{Expense} income{Income} transfer{Transfer} currency_exchange{Currency exchange} credit_card_purchase{Credit card purchase} credit_card_payment{Credit card payment} refund{Refund} loan_payment{Loan payment} investment_buy{Investment purchase} investment_sell{Investment sale} dividend{Dividend} interest{Interest} fee{Fee} adjustment{Adjustment} other{Transaction}}'**
  String transactionTypeName(String type);

  /// No description provided for @recurringNavigationLabel.
  ///
  /// In en, this message translates to:
  /// **'Scheduled'**
  String get recurringNavigationLabel;

  /// No description provided for @recurringTitle.
  ///
  /// In en, this message translates to:
  /// **'Recurring activity'**
  String get recurringTitle;

  /// No description provided for @upcomingTabLabel.
  ///
  /// In en, this message translates to:
  /// **'Upcoming'**
  String get upcomingTabLabel;

  /// No description provided for @recurringRulesTabLabel.
  ///
  /// In en, this message translates to:
  /// **'Rules'**
  String get recurringRulesTabLabel;

  /// No description provided for @addRecurringAction.
  ///
  /// In en, this message translates to:
  /// **'Add recurring'**
  String get addRecurringAction;

  /// No description provided for @createRecurringAction.
  ///
  /// In en, this message translates to:
  /// **'Create schedule'**
  String get createRecurringAction;

  /// No description provided for @recurringLoadFailedMessage.
  ///
  /// In en, this message translates to:
  /// **'Could not load recurring activity from the local vault.'**
  String get recurringLoadFailedMessage;

  /// No description provided for @noUpcomingOccurrencesMessage.
  ///
  /// In en, this message translates to:
  /// **'No scheduled activity in the next 90 days.'**
  String get noUpcomingOccurrencesMessage;

  /// No description provided for @noRecurringRulesMessage.
  ///
  /// In en, this message translates to:
  /// **'No recurrence rules yet.'**
  String get noRecurringRulesMessage;

  /// No description provided for @confirmOccurrenceAction.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get confirmOccurrenceAction;

  /// No description provided for @skipOccurrenceAction.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get skipOccurrenceAction;

  /// No description provided for @rescheduleOccurrenceAction.
  ///
  /// In en, this message translates to:
  /// **'Reschedule'**
  String get rescheduleOccurrenceAction;

  /// No description provided for @modifyOneOccurrenceAction.
  ///
  /// In en, this message translates to:
  /// **'Modify this occurrence'**
  String get modifyOneOccurrenceAction;

  /// No description provided for @modifyFutureOccurrencesAction.
  ///
  /// In en, this message translates to:
  /// **'Modify this and future occurrences'**
  String get modifyFutureOccurrencesAction;

  /// No description provided for @endRecurrenceAction.
  ///
  /// In en, this message translates to:
  /// **'End recurrence'**
  String get endRecurrenceAction;

  /// No description provided for @endedRecurrenceLabel.
  ///
  /// In en, this message translates to:
  /// **'Ended'**
  String get endedRecurrenceLabel;

  /// No description provided for @recurrenceNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Schedule name'**
  String get recurrenceNameLabel;

  /// No description provided for @recurrenceStartsLabel.
  ///
  /// In en, this message translates to:
  /// **'Starts on'**
  String get recurrenceStartsLabel;

  /// No description provided for @recurrenceEndsLabel.
  ///
  /// In en, this message translates to:
  /// **'Ends on (optional)'**
  String get recurrenceEndsLabel;

  /// No description provided for @frequencyLabel.
  ///
  /// In en, this message translates to:
  /// **'Frequency'**
  String get frequencyLabel;

  /// No description provided for @intervalLabel.
  ///
  /// In en, this message translates to:
  /// **'Every'**
  String get intervalLabel;

  /// No description provided for @dailyFrequencyLabel.
  ///
  /// In en, this message translates to:
  /// **'Daily'**
  String get dailyFrequencyLabel;

  /// No description provided for @weeklyFrequencyLabel.
  ///
  /// In en, this message translates to:
  /// **'Weekly'**
  String get weeklyFrequencyLabel;

  /// No description provided for @monthlyFrequencyLabel.
  ///
  /// In en, this message translates to:
  /// **'Monthly'**
  String get monthlyFrequencyLabel;

  /// No description provided for @yearlyFrequencyLabel.
  ///
  /// In en, this message translates to:
  /// **'Yearly'**
  String get yearlyFrequencyLabel;

  /// No description provided for @scheduledOccurrenceLabel.
  ///
  /// In en, this message translates to:
  /// **'Scheduled'**
  String get scheduledOccurrenceLabel;

  /// No description provided for @pendingOccurrenceLabel.
  ///
  /// In en, this message translates to:
  /// **'Changed'**
  String get pendingOccurrenceLabel;

  /// No description provided for @confirmedOccurrenceLabel.
  ///
  /// In en, this message translates to:
  /// **'Confirmed'**
  String get confirmedOccurrenceLabel;

  /// No description provided for @skippedOccurrenceLabel.
  ///
  /// In en, this message translates to:
  /// **'Skipped'**
  String get skippedOccurrenceLabel;

  /// No description provided for @applyAction.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get applyAction;

  /// No description provided for @thisMonthTitle.
  ///
  /// In en, this message translates to:
  /// **'This month'**
  String get thisMonthTitle;

  /// No description provided for @incomeReportLabel.
  ///
  /// In en, this message translates to:
  /// **'Income'**
  String get incomeReportLabel;

  /// No description provided for @expensesReportLabel.
  ///
  /// In en, this message translates to:
  /// **'Expenses'**
  String get expensesReportLabel;

  /// No description provided for @netCashFlowLabel.
  ///
  /// In en, this message translates to:
  /// **'Net cash flow'**
  String get netCashFlowLabel;

  /// No description provided for @budgetDashboardTitle.
  ///
  /// In en, this message translates to:
  /// **'Budget'**
  String get budgetDashboardTitle;

  /// No description provided for @budgetNextPhaseMessage.
  ///
  /// In en, this message translates to:
  /// **'Budget tracking becomes available in the next phase.'**
  String get budgetNextPhaseMessage;

  /// No description provided for @upcomingDashboardTitle.
  ///
  /// In en, this message translates to:
  /// **'Upcoming'**
  String get upcomingDashboardTitle;

  /// No description provided for @upcomingNext30DaysLabel.
  ///
  /// In en, this message translates to:
  /// **'Scheduled in the next 30 days'**
  String get upcomingNext30DaysLabel;

  /// No description provided for @spendingByCategoryTitle.
  ///
  /// In en, this message translates to:
  /// **'Spending by category'**
  String get spendingByCategoryTitle;

  /// No description provided for @cashFlowChartTitle.
  ///
  /// In en, this message translates to:
  /// **'Cash flow over time'**
  String get cashFlowChartTitle;

  /// No description provided for @accountBalancesTitle.
  ///
  /// In en, this message translates to:
  /// **'Account balances'**
  String get accountBalancesTitle;

  /// No description provided for @reportsSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Reports'**
  String get reportsSectionTitle;

  /// No description provided for @reportingIncompleteMessage.
  ///
  /// In en, this message translates to:
  /// **'Some currencies are omitted because no local exchange rate is available.'**
  String get reportingIncompleteMessage;

  /// No description provided for @reportingEstimatedMessage.
  ///
  /// In en, this message translates to:
  /// **'Includes estimated cached exchange rates.'**
  String get reportingEstimatedMessage;

  /// No description provided for @noSpendingDataMessage.
  ///
  /// In en, this message translates to:
  /// **'No classified activity in this period.'**
  String get noSpendingDataMessage;

  /// No description provided for @originalCurrencyAmountLabel.
  ///
  /// In en, this message translates to:
  /// **'Original currency'**
  String get originalCurrencyAmountLabel;

  /// No description provided for @reportingAmountLabel.
  ///
  /// In en, this message translates to:
  /// **'Reporting currency'**
  String get reportingAmountLabel;

  /// No description provided for @cardsNavigationLabel.
  ///
  /// In en, this message translates to:
  /// **'Cards'**
  String get cardsNavigationLabel;

  /// No description provided for @creditCardsTitle.
  ///
  /// In en, this message translates to:
  /// **'Credit cards'**
  String get creditCardsTitle;

  /// No description provided for @noCreditCardsMessage.
  ///
  /// In en, this message translates to:
  /// **'Create a credit-card account on Home to get started.'**
  String get noCreditCardsMessage;

  /// No description provided for @selectCardLabel.
  ///
  /// In en, this message translates to:
  /// **'Card and currency'**
  String get selectCardLabel;

  /// No description provided for @configureCardAction.
  ///
  /// In en, this message translates to:
  /// **'Configure card'**
  String get configureCardAction;

  /// No description provided for @closingDayLabel.
  ///
  /// In en, this message translates to:
  /// **'Closing day'**
  String get closingDayLabel;

  /// No description provided for @dueDayLabel.
  ///
  /// In en, this message translates to:
  /// **'Due day'**
  String get dueDayLabel;

  /// No description provided for @creditLimitLabel.
  ///
  /// In en, this message translates to:
  /// **'Credit limit'**
  String get creditLimitLabel;

  /// No description provided for @availableCreditLabel.
  ///
  /// In en, this message translates to:
  /// **'Available credit'**
  String get availableCreditLabel;

  /// No description provided for @statementsTabLabel.
  ///
  /// In en, this message translates to:
  /// **'Statements'**
  String get statementsTabLabel;

  /// No description provided for @installmentsTabLabel.
  ///
  /// In en, this message translates to:
  /// **'Installments'**
  String get installmentsTabLabel;

  /// No description provided for @addCardPurchaseAction.
  ///
  /// In en, this message translates to:
  /// **'Add purchase'**
  String get addCardPurchaseAction;

  /// No description provided for @addInstallmentAction.
  ///
  /// In en, this message translates to:
  /// **'Add installment purchase'**
  String get addInstallmentAction;

  /// No description provided for @feeInterestAction.
  ///
  /// In en, this message translates to:
  /// **'Add fee or interest'**
  String get feeInterestAction;

  /// No description provided for @payStatementAction.
  ///
  /// In en, this message translates to:
  /// **'Pay statement'**
  String get payStatementAction;

  /// No description provided for @refundPurchaseAction.
  ///
  /// In en, this message translates to:
  /// **'Refund purchase'**
  String get refundPurchaseAction;

  /// No description provided for @noStatementsMessage.
  ///
  /// In en, this message translates to:
  /// **'No statements for this card.'**
  String get noStatementsMessage;

  /// No description provided for @noInstallmentsMessage.
  ///
  /// In en, this message translates to:
  /// **'No installment plans for this card.'**
  String get noInstallmentsMessage;

  /// No description provided for @originalAmountLabel.
  ///
  /// In en, this message translates to:
  /// **'Original amount'**
  String get originalAmountLabel;

  /// No description provided for @financedAmountLabel.
  ///
  /// In en, this message translates to:
  /// **'Total with interest'**
  String get financedAmountLabel;

  /// No description provided for @installmentCountLabel.
  ///
  /// In en, this message translates to:
  /// **'Installment count'**
  String get installmentCountLabel;

  /// No description provided for @firstInstallmentDateLabel.
  ///
  /// In en, this message translates to:
  /// **'First installment date'**
  String get firstInstallmentDateLabel;

  /// No description provided for @interestRateLabel.
  ///
  /// In en, this message translates to:
  /// **'Interest rate (optional)'**
  String get interestRateLabel;

  /// No description provided for @descriptionLabel.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get descriptionLabel;

  /// No description provided for @currentInstallmentLabel.
  ///
  /// In en, this message translates to:
  /// **'Current installment'**
  String get currentInstallmentLabel;

  /// No description provided for @remainingAmountLabel.
  ///
  /// In en, this message translates to:
  /// **'Remaining amount'**
  String get remainingAmountLabel;

  /// No description provided for @cancelInstallmentAction.
  ///
  /// In en, this message translates to:
  /// **'Cancel and refund plan'**
  String get cancelInstallmentAction;

  /// No description provided for @cardLoadFailedMessage.
  ///
  /// In en, this message translates to:
  /// **'Could not load credit-card data from the local vault.'**
  String get cardLoadFailedMessage;

  /// No description provided for @futureStatementStatus.
  ///
  /// In en, this message translates to:
  /// **'Future'**
  String get futureStatementStatus;

  /// No description provided for @openStatementStatus.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get openStatementStatus;

  /// No description provided for @closedStatementStatus.
  ///
  /// In en, this message translates to:
  /// **'Closed'**
  String get closedStatementStatus;

  /// No description provided for @paidStatementStatus.
  ///
  /// In en, this message translates to:
  /// **'Paid'**
  String get paidStatementStatus;

  /// No description provided for @overdueStatementStatus.
  ///
  /// In en, this message translates to:
  /// **'Overdue'**
  String get overdueStatementStatus;

  /// No description provided for @saveAction.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get saveAction;

  /// No description provided for @budgetsNavigationLabel.
  ///
  /// In en, this message translates to:
  /// **'Budgets'**
  String get budgetsNavigationLabel;

  /// No description provided for @budgetsTitle.
  ///
  /// In en, this message translates to:
  /// **'Budgets'**
  String get budgetsTitle;

  /// No description provided for @addBudgetAction.
  ///
  /// In en, this message translates to:
  /// **'Add budget'**
  String get addBudgetAction;

  /// No description provided for @editBudgetAction.
  ///
  /// In en, this message translates to:
  /// **'Edit budget'**
  String get editBudgetAction;

  /// No description provided for @deleteBudgetAction.
  ///
  /// In en, this message translates to:
  /// **'Delete budget'**
  String get deleteBudgetAction;

  /// No description provided for @noBudgetsMessage.
  ///
  /// In en, this message translates to:
  /// **'No budgets yet. Create one to start tracking your plan.'**
  String get noBudgetsMessage;

  /// No description provided for @budgetLoadFailedMessage.
  ///
  /// In en, this message translates to:
  /// **'Could not load budgets from the local vault.'**
  String get budgetLoadFailedMessage;

  /// No description provided for @budgetNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Budget name'**
  String get budgetNameLabel;

  /// No description provided for @budgetLimitLabel.
  ///
  /// In en, this message translates to:
  /// **'Limit'**
  String get budgetLimitLabel;

  /// No description provided for @budgetPeriodLabel.
  ///
  /// In en, this message translates to:
  /// **'Period'**
  String get budgetPeriodLabel;

  /// No description provided for @weeklyBudgetPeriod.
  ///
  /// In en, this message translates to:
  /// **'Weekly'**
  String get weeklyBudgetPeriod;

  /// No description provided for @monthlyBudgetPeriod.
  ///
  /// In en, this message translates to:
  /// **'Monthly'**
  String get monthlyBudgetPeriod;

  /// No description provided for @yearlyBudgetPeriod.
  ///
  /// In en, this message translates to:
  /// **'Yearly'**
  String get yearlyBudgetPeriod;

  /// No description provided for @customBudgetPeriod.
  ///
  /// In en, this message translates to:
  /// **'Custom range'**
  String get customBudgetPeriod;

  /// No description provided for @budgetWarningThresholdLabel.
  ///
  /// In en, this message translates to:
  /// **'Warning threshold (%)'**
  String get budgetWarningThresholdLabel;

  /// No description provided for @budgetScopeLabel.
  ///
  /// In en, this message translates to:
  /// **'Scope'**
  String get budgetScopeLabel;

  /// No description provided for @overallSpendingScope.
  ///
  /// In en, this message translates to:
  /// **'Overall spending'**
  String get overallSpendingScope;

  /// No description provided for @budgetCategoriesScope.
  ///
  /// In en, this message translates to:
  /// **'Categories'**
  String get budgetCategoriesScope;

  /// No description provided for @budgetAccountsScope.
  ///
  /// In en, this message translates to:
  /// **'Accounts'**
  String get budgetAccountsScope;

  /// No description provided for @budgetTagsScope.
  ///
  /// In en, this message translates to:
  /// **'Tags'**
  String get budgetTagsScope;

  /// No description provided for @includeDescendantsLabel.
  ///
  /// In en, this message translates to:
  /// **'Include descendant categories'**
  String get includeDescendantsLabel;

  /// No description provided for @customStartDateLabel.
  ///
  /// In en, this message translates to:
  /// **'Start date'**
  String get customStartDateLabel;

  /// No description provided for @customEndDateLabel.
  ///
  /// In en, this message translates to:
  /// **'End date'**
  String get customEndDateLabel;

  /// No description provided for @budgetUsedLabel.
  ///
  /// In en, this message translates to:
  /// **'Used'**
  String get budgetUsedLabel;

  /// No description provided for @budgetRemainingLabel.
  ///
  /// In en, this message translates to:
  /// **'Remaining'**
  String get budgetRemainingLabel;

  /// No description provided for @budgetProjectedLabel.
  ///
  /// In en, this message translates to:
  /// **'Projected'**
  String get budgetProjectedLabel;

  /// No description provided for @budgetSafeState.
  ///
  /// In en, this message translates to:
  /// **'Safe'**
  String get budgetSafeState;

  /// No description provided for @budgetApproachingState.
  ///
  /// In en, this message translates to:
  /// **'Approaching limit'**
  String get budgetApproachingState;

  /// No description provided for @budgetReachedState.
  ///
  /// In en, this message translates to:
  /// **'Limit reached'**
  String get budgetReachedState;

  /// No description provided for @budgetExceededState.
  ///
  /// In en, this message translates to:
  /// **'Exceeded'**
  String get budgetExceededState;

  /// No description provided for @budgetLikelyExceedMessage.
  ///
  /// In en, this message translates to:
  /// **'At the current pace, this budget is likely to be exceeded.'**
  String get budgetLikelyExceedMessage;

  /// No description provided for @budgetIncompleteFxMessage.
  ///
  /// In en, this message translates to:
  /// **'Some spending is omitted because a local exchange rate is unavailable.'**
  String get budgetIncompleteFxMessage;

  /// No description provided for @budgetEstimatedFxMessage.
  ///
  /// In en, this message translates to:
  /// **'This budget uses an estimated local exchange rate.'**
  String get budgetEstimatedFxMessage;

  /// No description provided for @confirmDeleteBudgetBody.
  ///
  /// In en, this message translates to:
  /// **'Delete this budget? Transactions and spending history will not be changed.'**
  String get confirmDeleteBudgetBody;

  /// No description provided for @activeBudgetsCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No active budgets} =1{1 active budget} other{{count} active budgets}}'**
  String activeBudgetsCount(int count);

  /// No description provided for @budgetUsagePercent.
  ///
  /// In en, this message translates to:
  /// **'{percent}% used'**
  String budgetUsagePercent(int percent);

  /// No description provided for @goalsNavigationLabel.
  ///
  /// In en, this message translates to:
  /// **'Goals'**
  String get goalsNavigationLabel;

  /// No description provided for @goalsTitle.
  ///
  /// In en, this message translates to:
  /// **'Goals and future cash flow'**
  String get goalsTitle;

  /// No description provided for @goalsTabLabel.
  ///
  /// In en, this message translates to:
  /// **'Goals'**
  String get goalsTabLabel;

  /// No description provided for @cashFlowProjectionTabLabel.
  ///
  /// In en, this message translates to:
  /// **'Future cash flow'**
  String get cashFlowProjectionTabLabel;

  /// No description provided for @addGoalAction.
  ///
  /// In en, this message translates to:
  /// **'Add goal'**
  String get addGoalAction;

  /// No description provided for @editGoalAction.
  ///
  /// In en, this message translates to:
  /// **'Edit goal'**
  String get editGoalAction;

  /// No description provided for @deleteGoalAction.
  ///
  /// In en, this message translates to:
  /// **'Delete goal'**
  String get deleteGoalAction;

  /// No description provided for @noGoalsMessage.
  ///
  /// In en, this message translates to:
  /// **'No goals yet. Create one to plan your next milestone.'**
  String get noGoalsMessage;

  /// No description provided for @goalLoadFailedMessage.
  ///
  /// In en, this message translates to:
  /// **'Could not load goals and projections from the local vault.'**
  String get goalLoadFailedMessage;

  /// No description provided for @goalNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Goal name'**
  String get goalNameLabel;

  /// No description provided for @goalTypeLabel.
  ///
  /// In en, this message translates to:
  /// **'Goal type'**
  String get goalTypeLabel;

  /// No description provided for @emergencyFundGoalType.
  ///
  /// In en, this message translates to:
  /// **'Emergency fund'**
  String get emergencyFundGoalType;

  /// No description provided for @vacationGoalType.
  ///
  /// In en, this message translates to:
  /// **'Vacation'**
  String get vacationGoalType;

  /// No description provided for @vehicleGoalType.
  ///
  /// In en, this message translates to:
  /// **'Vehicle'**
  String get vehicleGoalType;

  /// No description provided for @homeGoalType.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get homeGoalType;

  /// No description provided for @debtPayoffGoalType.
  ///
  /// In en, this message translates to:
  /// **'Debt payoff'**
  String get debtPayoffGoalType;

  /// No description provided for @investmentGoalType.
  ///
  /// In en, this message translates to:
  /// **'Investment'**
  String get investmentGoalType;

  /// No description provided for @retirementGoalType.
  ///
  /// In en, this message translates to:
  /// **'Retirement'**
  String get retirementGoalType;

  /// No description provided for @educationGoalType.
  ///
  /// In en, this message translates to:
  /// **'Education'**
  String get educationGoalType;

  /// No description provided for @customGoalType.
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get customGoalType;

  /// No description provided for @goalTargetLabel.
  ///
  /// In en, this message translates to:
  /// **'Target'**
  String get goalTargetLabel;

  /// No description provided for @goalCurrentLabel.
  ///
  /// In en, this message translates to:
  /// **'Current'**
  String get goalCurrentLabel;

  /// No description provided for @plannedMonthlyContributionLabel.
  ///
  /// In en, this message translates to:
  /// **'Planned monthly contribution'**
  String get plannedMonthlyContributionLabel;

  /// No description provided for @requiredMonthlyContributionLabel.
  ///
  /// In en, this message translates to:
  /// **'Required monthly contribution'**
  String get requiredMonthlyContributionLabel;

  /// No description provided for @expectedCompletionLabel.
  ///
  /// In en, this message translates to:
  /// **'Estimated completion'**
  String get expectedCompletionLabel;

  /// No description provided for @goalTargetDateLabel.
  ///
  /// In en, this message translates to:
  /// **'Target date'**
  String get goalTargetDateLabel;

  /// No description provided for @goalPriorityLabel.
  ///
  /// In en, this message translates to:
  /// **'Priority'**
  String get goalPriorityLabel;

  /// No description provided for @goalTrackingModeLabel.
  ///
  /// In en, this message translates to:
  /// **'Progress tracking'**
  String get goalTrackingModeLabel;

  /// No description provided for @manualGoalTracking.
  ///
  /// In en, this message translates to:
  /// **'Manual contributions'**
  String get manualGoalTracking;

  /// No description provided for @linkedAccountsGoalTracking.
  ///
  /// In en, this message translates to:
  /// **'Linked account balances'**
  String get linkedAccountsGoalTracking;

  /// No description provided for @transactionsGoalTracking.
  ///
  /// In en, this message translates to:
  /// **'Linked contributions'**
  String get transactionsGoalTracking;

  /// No description provided for @linkedGoalAccountsLabel.
  ///
  /// In en, this message translates to:
  /// **'Linked pockets'**
  String get linkedGoalAccountsLabel;

  /// No description provided for @addGoalContributionAction.
  ///
  /// In en, this message translates to:
  /// **'Add contribution'**
  String get addGoalContributionAction;

  /// No description provided for @goalContributionAmountLabel.
  ///
  /// In en, this message translates to:
  /// **'Contribution amount'**
  String get goalContributionAmountLabel;

  /// No description provided for @goalContributionDateLabel.
  ///
  /// In en, this message translates to:
  /// **'Contribution date'**
  String get goalContributionDateLabel;

  /// No description provided for @goalContributionTransactionLabel.
  ///
  /// In en, this message translates to:
  /// **'Associated transaction (optional)'**
  String get goalContributionTransactionLabel;

  /// No description provided for @goalContributionNotesLabel.
  ///
  /// In en, this message translates to:
  /// **'Notes (optional)'**
  String get goalContributionNotesLabel;

  /// No description provided for @goalReachedLabel.
  ///
  /// In en, this message translates to:
  /// **'Target reached'**
  String get goalReachedLabel;

  /// No description provided for @cashFlowEstimateDisclaimer.
  ///
  /// In en, this message translates to:
  /// **'This is an estimate based on known local data, not a guaranteed future balance.'**
  String get cashFlowEstimateDisclaimer;

  /// No description provided for @openingAvailableLabel.
  ///
  /// In en, this message translates to:
  /// **'Opening available'**
  String get openingAvailableLabel;

  /// No description provided for @projectedClosingLabel.
  ///
  /// In en, this message translates to:
  /// **'Projected closing'**
  String get projectedClosingLabel;

  /// No description provided for @noProjectedEventsMessage.
  ///
  /// In en, this message translates to:
  /// **'No known events in this projection window.'**
  String get noProjectedEventsMessage;

  /// No description provided for @projectedBalanceLabel.
  ///
  /// In en, this message translates to:
  /// **'Balance after event'**
  String get projectedBalanceLabel;

  /// No description provided for @recurringIncomeProjectionType.
  ///
  /// In en, this message translates to:
  /// **'Recurring income'**
  String get recurringIncomeProjectionType;

  /// No description provided for @recurringExpenseProjectionType.
  ///
  /// In en, this message translates to:
  /// **'Recurring expense'**
  String get recurringExpenseProjectionType;

  /// No description provided for @installmentProjectionType.
  ///
  /// In en, this message translates to:
  /// **'Future installment'**
  String get installmentProjectionType;

  /// No description provided for @cardStatementProjectionType.
  ///
  /// In en, this message translates to:
  /// **'Card statement'**
  String get cardStatementProjectionType;

  /// No description provided for @goalContributionProjectionType.
  ///
  /// In en, this message translates to:
  /// **'Planned goal contribution'**
  String get goalContributionProjectionType;

  /// No description provided for @goalIncompleteFxMessage.
  ///
  /// In en, this message translates to:
  /// **'Some linked balances are omitted because a local exchange rate is unavailable.'**
  String get goalIncompleteFxMessage;

  /// No description provided for @goalEstimatedFxMessage.
  ///
  /// In en, this message translates to:
  /// **'This goal uses an estimated local exchange rate.'**
  String get goalEstimatedFxMessage;

  /// No description provided for @confirmDeleteGoalBody.
  ///
  /// In en, this message translates to:
  /// **'Delete this goal? Linked accounts, transactions, and ledger history will not be changed.'**
  String get confirmDeleteGoalBody;

  /// No description provided for @activeGoalsCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No active goals} =1{1 active goal} other{{count} active goals}}'**
  String activeGoalsCount(int count);

  /// No description provided for @investmentsNavigationLabel.
  ///
  /// In en, this message translates to:
  /// **'Investments'**
  String get investmentsNavigationLabel;

  /// No description provided for @investmentsTitle.
  ///
  /// In en, this message translates to:
  /// **'Investments'**
  String get investmentsTitle;

  /// No description provided for @portfolioValueLabel.
  ///
  /// In en, this message translates to:
  /// **'Portfolio value'**
  String get portfolioValueLabel;

  /// No description provided for @portfolioCostLabel.
  ///
  /// In en, this message translates to:
  /// **'Cost basis'**
  String get portfolioCostLabel;

  /// No description provided for @unrealizedResultLabel.
  ///
  /// In en, this message translates to:
  /// **'Unrealized gain/loss'**
  String get unrealizedResultLabel;

  /// No description provided for @realizedResultLabel.
  ///
  /// In en, this message translates to:
  /// **'Realized gain/loss'**
  String get realizedResultLabel;

  /// No description provided for @investmentIncomeLabel.
  ///
  /// In en, this message translates to:
  /// **'Income received'**
  String get investmentIncomeLabel;

  /// No description provided for @allocationLabel.
  ///
  /// In en, this message translates to:
  /// **'Allocation'**
  String get allocationLabel;

  /// No description provided for @addInstrumentAction.
  ///
  /// In en, this message translates to:
  /// **'Add instrument'**
  String get addInstrumentAction;

  /// No description provided for @noInvestmentsMessage.
  ///
  /// In en, this message translates to:
  /// **'No investment instruments yet.'**
  String get noInvestmentsMessage;

  /// No description provided for @investmentLoadFailedMessage.
  ///
  /// In en, this message translates to:
  /// **'Could not load investments from the local vault.'**
  String get investmentLoadFailedMessage;

  /// No description provided for @instrumentNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Instrument name'**
  String get instrumentNameLabel;

  /// No description provided for @instrumentSymbolLabel.
  ///
  /// In en, this message translates to:
  /// **'Symbol'**
  String get instrumentSymbolLabel;

  /// No description provided for @instrumentExchangeLabel.
  ///
  /// In en, this message translates to:
  /// **'Exchange'**
  String get instrumentExchangeLabel;

  /// No description provided for @assetClassLabel.
  ///
  /// In en, this message translates to:
  /// **'Asset class'**
  String get assetClassLabel;

  /// No description provided for @quantityLabel.
  ///
  /// In en, this message translates to:
  /// **'Quantity'**
  String get quantityLabel;

  /// No description provided for @averageCostLabel.
  ///
  /// In en, this message translates to:
  /// **'Average cost'**
  String get averageCostLabel;

  /// No description provided for @unitPriceLabel.
  ///
  /// In en, this message translates to:
  /// **'Unit price'**
  String get unitPriceLabel;

  /// No description provided for @feesLabel.
  ///
  /// In en, this message translates to:
  /// **'Fees'**
  String get feesLabel;

  /// No description provided for @taxesLabel.
  ///
  /// In en, this message translates to:
  /// **'Taxes'**
  String get taxesLabel;

  /// No description provided for @investmentDateLabel.
  ///
  /// In en, this message translates to:
  /// **'Date'**
  String get investmentDateLabel;

  /// No description provided for @cashAccountLabel.
  ///
  /// In en, this message translates to:
  /// **'Investment cash account'**
  String get cashAccountLabel;

  /// No description provided for @buyInvestmentAction.
  ///
  /// In en, this message translates to:
  /// **'Buy'**
  String get buyInvestmentAction;

  /// No description provided for @sellInvestmentAction.
  ///
  /// In en, this message translates to:
  /// **'Sell'**
  String get sellInvestmentAction;

  /// No description provided for @dividendInvestmentAction.
  ///
  /// In en, this message translates to:
  /// **'Dividend'**
  String get dividendInvestmentAction;

  /// No description provided for @interestInvestmentAction.
  ///
  /// In en, this message translates to:
  /// **'Interest'**
  String get interestInvestmentAction;

  /// No description provided for @feeInvestmentAction.
  ///
  /// In en, this message translates to:
  /// **'Fee'**
  String get feeInvestmentAction;

  /// No description provided for @depositInvestmentAction.
  ///
  /// In en, this message translates to:
  /// **'Deposit'**
  String get depositInvestmentAction;

  /// No description provided for @withdrawInvestmentAction.
  ///
  /// In en, this message translates to:
  /// **'Withdraw'**
  String get withdrawInvestmentAction;

  /// No description provided for @investmentAmountLabel.
  ///
  /// In en, this message translates to:
  /// **'Amount'**
  String get investmentAmountLabel;

  /// No description provided for @missingMarketPriceMessage.
  ///
  /// In en, this message translates to:
  /// **'Add a market price to calculate market value and unrealized result.'**
  String get missingMarketPriceMessage;

  /// No description provided for @insufficientLotsMessage.
  ///
  /// In en, this message translates to:
  /// **'The sale quantity exceeds the available lots.'**
  String get insufficientLotsMessage;

  /// No description provided for @wealthNavigationLabel.
  ///
  /// In en, this message translates to:
  /// **'Wealth'**
  String get wealthNavigationLabel;

  /// No description provided for @wealthTitle.
  ///
  /// In en, this message translates to:
  /// **'Net worth and assets'**
  String get wealthTitle;

  /// No description provided for @netWorthLabel.
  ///
  /// In en, this message translates to:
  /// **'Net worth'**
  String get netWorthLabel;

  /// No description provided for @totalAssetsLabel.
  ///
  /// In en, this message translates to:
  /// **'Assets'**
  String get totalAssetsLabel;

  /// No description provided for @totalLiabilitiesLabel.
  ///
  /// In en, this message translates to:
  /// **'Liabilities'**
  String get totalLiabilitiesLabel;

  /// No description provided for @physicalAssetsLabel.
  ///
  /// In en, this message translates to:
  /// **'Physical assets'**
  String get physicalAssetsLabel;

  /// No description provided for @includedAccountsLabel.
  ///
  /// In en, this message translates to:
  /// **'Included accounts'**
  String get includedAccountsLabel;

  /// No description provided for @addAssetAction.
  ///
  /// In en, this message translates to:
  /// **'Add asset'**
  String get addAssetAction;

  /// No description provided for @deleteAssetAction.
  ///
  /// In en, this message translates to:
  /// **'Delete asset'**
  String get deleteAssetAction;

  /// No description provided for @addValuationAction.
  ///
  /// In en, this message translates to:
  /// **'Update value'**
  String get addValuationAction;

  /// No description provided for @noAssetsMessage.
  ///
  /// In en, this message translates to:
  /// **'No physical assets yet.'**
  String get noAssetsMessage;

  /// No description provided for @wealthLoadFailedMessage.
  ///
  /// In en, this message translates to:
  /// **'Could not load net worth from the local vault.'**
  String get wealthLoadFailedMessage;

  /// No description provided for @assetNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Asset name'**
  String get assetNameLabel;

  /// No description provided for @assetTypeLabel.
  ///
  /// In en, this message translates to:
  /// **'Asset type'**
  String get assetTypeLabel;

  /// No description provided for @assetCostLabel.
  ///
  /// In en, this message translates to:
  /// **'Purchase price'**
  String get assetCostLabel;

  /// No description provided for @assetDateLabel.
  ///
  /// In en, this message translates to:
  /// **'Purchase date'**
  String get assetDateLabel;

  /// No description provided for @valuationMethodLabel.
  ///
  /// In en, this message translates to:
  /// **'Valuation method'**
  String get valuationMethodLabel;

  /// No description provided for @annualRateLabel.
  ///
  /// In en, this message translates to:
  /// **'Annual rate (%)'**
  String get annualRateLabel;

  /// No description provided for @usefulLifeMonthsLabel.
  ///
  /// In en, this message translates to:
  /// **'Useful life (months)'**
  String get usefulLifeMonthsLabel;

  /// No description provided for @salvageValueLabel.
  ///
  /// In en, this message translates to:
  /// **'Salvage value'**
  String get salvageValueLabel;

  /// No description provided for @includeInNetWorthLabel.
  ///
  /// In en, this message translates to:
  /// **'Include in net worth'**
  String get includeInNetWorthLabel;

  /// No description provided for @currentValueLabel.
  ///
  /// In en, this message translates to:
  /// **'Current value'**
  String get currentValueLabel;

  /// No description provided for @valuationDateLabel.
  ///
  /// In en, this message translates to:
  /// **'Valuation date'**
  String get valuationDateLabel;

  /// No description provided for @manualValuationMethod.
  ///
  /// In en, this message translates to:
  /// **'Manual'**
  String get manualValuationMethod;

  /// No description provided for @straightLineValuationMethod.
  ///
  /// In en, this message translates to:
  /// **'Straight-line depreciation'**
  String get straightLineValuationMethod;

  /// No description provided for @depreciationValuationMethod.
  ///
  /// In en, this message translates to:
  /// **'Fixed percentage depreciation'**
  String get depreciationValuationMethod;

  /// No description provided for @appreciationValuationMethod.
  ///
  /// In en, this message translates to:
  /// **'Fixed percentage appreciation'**
  String get appreciationValuationMethod;

  /// No description provided for @customValuationMethod.
  ///
  /// In en, this message translates to:
  /// **'Custom schedule'**
  String get customValuationMethod;

  /// No description provided for @wealthIncompleteFxMessage.
  ///
  /// In en, this message translates to:
  /// **'Some values are omitted because a local exchange rate is unavailable.'**
  String get wealthIncompleteFxMessage;

  /// No description provided for @wealthEstimatedFxMessage.
  ///
  /// In en, this message translates to:
  /// **'This report uses estimated local exchange rates.'**
  String get wealthEstimatedFxMessage;

  /// No description provided for @confirmDeleteAssetBody.
  ///
  /// In en, this message translates to:
  /// **'Delete this asset? Its valuation history will also be removed.'**
  String get confirmDeleteAssetBody;

  /// No description provided for @customIntervalLabel.
  ///
  /// In en, this message translates to:
  /// **'Every {interval} {unit}'**
  String customIntervalLabel(int interval, String unit);

  /// No description provided for @refreshPricesAction.
  ///
  /// In en, this message translates to:
  /// **'Refresh market prices'**
  String get refreshPricesAction;

  /// No description provided for @manualPriceAction.
  ///
  /// In en, this message translates to:
  /// **'Set manual price'**
  String get manualPriceAction;

  /// No description provided for @stalePriceMessage.
  ///
  /// In en, this message translates to:
  /// **'The cached market price is out of date.'**
  String get stalePriceMessage;

  /// No description provided for @priceRefreshFailedMessage.
  ///
  /// In en, this message translates to:
  /// **'Price refresh failed. The last local value is still in use.'**
  String get priceRefreshFailedMessage;

  /// No description provided for @intelligenceTitle.
  ///
  /// In en, this message translates to:
  /// **'Financial insights'**
  String get intelligenceTitle;

  /// No description provided for @intelligenceSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Local estimates based on your recorded data'**
  String get intelligenceSubtitle;

  /// No description provided for @intelligencePrivacyMessage.
  ///
  /// In en, this message translates to:
  /// **'These insights are calculated on this device. Transaction history is not sent to an external AI service.'**
  String get intelligencePrivacyMessage;

  /// No description provided for @intelligenceLoadFailedMessage.
  ///
  /// In en, this message translates to:
  /// **'Could not calculate financial insights from the local vault.'**
  String get intelligenceLoadFailedMessage;

  /// No description provided for @intelligenceDisabledMessage.
  ///
  /// In en, this message translates to:
  /// **'Financial insights are disabled. Ledger and normal app features are unaffected.'**
  String get intelligenceDisabledMessage;

  /// No description provided for @noInsightsMessage.
  ///
  /// In en, this message translates to:
  /// **'There is not enough local history for insights yet.'**
  String get noInsightsMessage;

  /// No description provided for @refreshInsightsAction.
  ///
  /// In en, this message translates to:
  /// **'Recalculate insights'**
  String get refreshInsightsAction;

  /// No description provided for @calculationTraceTitle.
  ///
  /// In en, this message translates to:
  /// **'How this was estimated'**
  String get calculationTraceTitle;

  /// No description provided for @spendingTrendInsight.
  ///
  /// In en, this message translates to:
  /// **'Projected spending is {percent}% compared with last month.'**
  String spendingTrendInsight(String percent);

  /// No description provided for @expenseAnomalyInsight.
  ///
  /// In en, this message translates to:
  /// **'{category} is projected at {projected}, {percent}% compared with last month.'**
  String expenseAnomalyInsight(
    String category,
    String projected,
    String percent,
  );

  /// No description provided for @budgetForecastInsight.
  ///
  /// In en, this message translates to:
  /// **'At the current pace, {name} is projected at {projected} against a {limit} limit.'**
  String budgetForecastInsight(String name, String projected, String limit);

  /// No description provided for @cashFlowForecastInsight.
  ///
  /// In en, this message translates to:
  /// **'The {days}-day local cash-flow estimate ends at {closing}.'**
  String cashFlowForecastInsight(int days, String closing);

  /// No description provided for @recurringCommitmentsInsight.
  ///
  /// In en, this message translates to:
  /// **'{count} recurring expenses totaling {total} are expected in this forecast.'**
  String recurringCommitmentsInsight(int count, String total);

  /// No description provided for @goalContributionInsight.
  ///
  /// In en, this message translates to:
  /// **'To stay on schedule for {name}, the monthly contribution may need {gap} more.'**
  String goalContributionInsight(String name, String gap);

  /// No description provided for @emergencyFundInsight.
  ///
  /// In en, this message translates to:
  /// **'Liquid funds cover about {months} months at the recent {average} monthly expense average.'**
  String emergencyFundInsight(String months, String average);

  /// No description provided for @debtOverviewInsight.
  ///
  /// In en, this message translates to:
  /// **'Recorded debt is {debt}, or {percent}% of recorded assets.'**
  String debtOverviewInsight(String debt, String percent);

  /// No description provided for @netWorthTrendInsight.
  ///
  /// In en, this message translates to:
  /// **'Net worth changed {change} ({percent}%) across {months} report points.'**
  String netWorthTrendInsight(String change, String percent, int months);

  /// No description provided for @investmentConcentrationInsight.
  ///
  /// In en, this message translates to:
  /// **'{name} represents {percent}% of priced investments.'**
  String investmentConcentrationInsight(String name, String percent);

  /// No description provided for @cloudAccountTitle.
  ///
  /// In en, this message translates to:
  /// **'Equis cloud account'**
  String get cloudAccountTitle;

  /// No description provided for @cloudAccountSettingsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Optional sign-in, verification, and device identity'**
  String get cloudAccountSettingsSubtitle;

  /// No description provided for @createEquisAccountAction.
  ///
  /// In en, this message translates to:
  /// **'Create Equis Account'**
  String get createEquisAccountAction;

  /// No description provided for @continueOfflineAction.
  ///
  /// In en, this message translates to:
  /// **'Continue Offline'**
  String get continueOfflineAction;

  /// No description provided for @cloudAccountIntro.
  ///
  /// In en, this message translates to:
  /// **'Cloud identity is optional. Your current vault stays local and keeps the same identifier.'**
  String get cloudAccountIntro;

  /// No description provided for @emailLabel.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get emailLabel;

  /// No description provided for @passwordLabel.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get passwordLabel;

  /// No description provided for @signInAction.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get signInAction;

  /// No description provided for @signOutAction.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get signOutAction;

  /// No description provided for @awaitingVerificationTitle.
  ///
  /// In en, this message translates to:
  /// **'Verify your email'**
  String get awaitingVerificationTitle;

  /// No description provided for @awaitingVerificationBody.
  ///
  /// In en, this message translates to:
  /// **'A verification message was sent to {email}. After verification, sign in to link this local vault.'**
  String awaitingVerificationBody(String email);

  /// No description provided for @resendVerificationAction.
  ///
  /// In en, this message translates to:
  /// **'Resend verification email'**
  String get resendVerificationAction;

  /// No description provided for @cloudSignedInTitle.
  ///
  /// In en, this message translates to:
  /// **'Cloud account connected'**
  String get cloudSignedInTitle;

  /// No description provided for @cloudSignedInBody.
  ///
  /// In en, this message translates to:
  /// **'Signed in as {email}. The local vault identifier was preserved.'**
  String cloudSignedInBody(String email);

  /// No description provided for @localAccessPreservedMessage.
  ///
  /// In en, this message translates to:
  /// **'The cloud session is unavailable or signed out. Local vault access remains available.'**
  String get localAccessPreservedMessage;

  /// No description provided for @cloudNotConfiguredMessage.
  ///
  /// In en, this message translates to:
  /// **'Supabase is not configured in this build. You can continue using every local feature offline.'**
  String get cloudNotConfiguredMessage;

  /// No description provided for @cloudSyncEncryptionPendingMessage.
  ///
  /// In en, this message translates to:
  /// **'Secure synchronization is off until you export and confirm the vault recovery key.'**
  String get cloudSyncEncryptionPendingMessage;

  /// No description provided for @secureSyncTitle.
  ///
  /// In en, this message translates to:
  /// **'Secure synchronization'**
  String get secureSyncTitle;

  /// No description provided for @secureSyncDisabledBody.
  ///
  /// In en, this message translates to:
  /// **'Your data stays local until you enable end-to-end encrypted synchronization.'**
  String get secureSyncDisabledBody;

  /// No description provided for @enableSecureSyncAction.
  ///
  /// In en, this message translates to:
  /// **'Enable secure sync'**
  String get enableSecureSyncAction;

  /// No description provided for @recoverySecretTitle.
  ///
  /// In en, this message translates to:
  /// **'Save your recovery key'**
  String get recoverySecretTitle;

  /// No description provided for @recoverySecretBody.
  ///
  /// In en, this message translates to:
  /// **'Store this key somewhere safe. It is required to open the encrypted vault on a new device and Equis cannot recover it for you.'**
  String get recoverySecretBody;

  /// No description provided for @copyRecoverySecretAction.
  ///
  /// In en, this message translates to:
  /// **'Copy recovery key'**
  String get copyRecoverySecretAction;

  /// No description provided for @recoverySecretCopiedMessage.
  ///
  /// In en, this message translates to:
  /// **'Recovery key copied'**
  String get recoverySecretCopiedMessage;

  /// No description provided for @confirmRecoverySavedAction.
  ///
  /// In en, this message translates to:
  /// **'I saved the recovery key'**
  String get confirmRecoverySavedAction;

  /// No description provided for @syncStatusSynced.
  ///
  /// In en, this message translates to:
  /// **'Synchronized'**
  String get syncStatusSynced;

  /// No description provided for @syncStatusOffline.
  ///
  /// In en, this message translates to:
  /// **'Offline — pending changes remain safely on this device'**
  String get syncStatusOffline;

  /// No description provided for @syncStatusError.
  ///
  /// In en, this message translates to:
  /// **'Synchronization needs attention'**
  String get syncStatusError;

  /// No description provided for @syncStatusReady.
  ///
  /// In en, this message translates to:
  /// **'Ready to synchronize'**
  String get syncStatusReady;

  /// No description provided for @syncDiagnostics.
  ///
  /// In en, this message translates to:
  /// **'Last 24 hours: {pushed} sent · {pulled} received · {conflicts} conflicts'**
  String syncDiagnostics(int pushed, int pulled, int conflicts);

  /// No description provided for @retrySyncAction.
  ///
  /// In en, this message translates to:
  /// **'Sync now'**
  String get retrySyncAction;

  /// No description provided for @syncConflictsTitle.
  ///
  /// In en, this message translates to:
  /// **'Conflicts requiring review'**
  String get syncConflictsTitle;

  /// No description provided for @syncConflictBody.
  ///
  /// In en, this message translates to:
  /// **'{entityType} · {recordId} · local revision {localRevision}, remote revision {remoteRevision}'**
  String syncConflictBody(
    String entityType,
    String recordId,
    int localRevision,
    int remoteRevision,
  );

  /// No description provided for @keepLocalAction.
  ///
  /// In en, this message translates to:
  /// **'Keep local'**
  String get keepLocalAction;

  /// No description provided for @keepRemoteAction.
  ///
  /// In en, this message translates to:
  /// **'Keep remote'**
  String get keepRemoteAction;

  /// No description provided for @deviceIdentityLabel.
  ///
  /// In en, this message translates to:
  /// **'Device: {name} · {platform} · {identifier}'**
  String deviceIdentityLabel(String name, String platform, String identifier);

  /// No description provided for @authInvalidCredentialsMessage.
  ///
  /// In en, this message translates to:
  /// **'Email or password is incorrect.'**
  String get authInvalidCredentialsMessage;

  /// No description provided for @authEmailNotVerifiedMessage.
  ///
  /// In en, this message translates to:
  /// **'Verify your email before signing in.'**
  String get authEmailNotVerifiedMessage;

  /// No description provided for @authWeakPasswordMessage.
  ///
  /// In en, this message translates to:
  /// **'Choose a stronger password.'**
  String get authWeakPasswordMessage;

  /// No description provided for @authAccountExistsMessage.
  ///
  /// In en, this message translates to:
  /// **'An account already exists for this email. Try signing in.'**
  String get authAccountExistsMessage;

  /// No description provided for @authRateLimitedMessage.
  ///
  /// In en, this message translates to:
  /// **'Too many attempts. Wait a moment and try again.'**
  String get authRateLimitedMessage;

  /// No description provided for @authNetworkMessage.
  ///
  /// In en, this message translates to:
  /// **'The cloud service is unreachable. Local access is unaffected.'**
  String get authNetworkMessage;

  /// No description provided for @authVaultMismatchMessage.
  ///
  /// In en, this message translates to:
  /// **'This vault is already linked to a different cloud account.'**
  String get authVaultMismatchMessage;

  /// No description provided for @authUnknownMessage.
  ///
  /// In en, this message translates to:
  /// **'The cloud account operation could not be completed.'**
  String get authUnknownMessage;

  /// No description provided for @portabilityTitle.
  ///
  /// In en, this message translates to:
  /// **'Backup and export'**
  String get portabilityTitle;

  /// No description provided for @portabilitySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Encrypted backups and explicit plaintext exports'**
  String get portabilitySubtitle;

  /// No description provided for @createEncryptedBackupAction.
  ///
  /// In en, this message translates to:
  /// **'Create encrypted backup'**
  String get createEncryptedBackupAction;

  /// No description provided for @encryptedBackupDescription.
  ///
  /// In en, this message translates to:
  /// **'Creates a password-protected .equis file with vault data and attachments.'**
  String get encryptedBackupDescription;

  /// No description provided for @validateBackupAction.
  ///
  /// In en, this message translates to:
  /// **'Validate a backup'**
  String get validateBackupAction;

  /// No description provided for @validateBackupDescription.
  ///
  /// In en, this message translates to:
  /// **'Checks the password, format, integrity, and compatibility without restoring.'**
  String get validateBackupDescription;

  /// No description provided for @restoreBackupAction.
  ///
  /// In en, this message translates to:
  /// **'Restore backup'**
  String get restoreBackupAction;

  /// No description provided for @restoreBackupDescription.
  ///
  /// In en, this message translates to:
  /// **'Reconstruct a vault and its attachment links in this empty profile.'**
  String get restoreBackupDescription;

  /// No description provided for @restoreRequiresCleanProfileMessage.
  ///
  /// In en, this message translates to:
  /// **'Restore is available only before creating a vault in this profile.'**
  String get restoreRequiresCleanProfileMessage;

  /// No description provided for @exportJsonAction.
  ///
  /// In en, this message translates to:
  /// **'Export vault as JSON'**
  String get exportJsonAction;

  /// No description provided for @exportCsvAction.
  ///
  /// In en, this message translates to:
  /// **'Export transactions as CSV'**
  String get exportCsvAction;

  /// No description provided for @plaintextExportDescription.
  ///
  /// In en, this message translates to:
  /// **'Exports logical vault data without encryption.'**
  String get plaintextExportDescription;

  /// No description provided for @transactionCsvDescription.
  ///
  /// In en, this message translates to:
  /// **'Exports exact minor values, currencies, movements, splits, tags, and conversions.'**
  String get transactionCsvDescription;

  /// No description provided for @backupCreatedMessage.
  ///
  /// In en, this message translates to:
  /// **'Encrypted backup created.'**
  String get backupCreatedMessage;

  /// No description provided for @backupValidMessage.
  ///
  /// In en, this message translates to:
  /// **'The backup is authentic and compatible.'**
  String get backupValidMessage;

  /// No description provided for @backupRestoredMessage.
  ///
  /// In en, this message translates to:
  /// **'Backup restored successfully.'**
  String get backupRestoredMessage;

  /// No description provided for @restoreBackupConfirmation.
  ///
  /// In en, this message translates to:
  /// **'Restore this backup into the empty local profile? Identifiers and relationships will be preserved.'**
  String get restoreBackupConfirmation;

  /// No description provided for @plaintextPrivacyWarningTitle.
  ///
  /// In en, this message translates to:
  /// **'Unencrypted financial data'**
  String get plaintextPrivacyWarningTitle;

  /// No description provided for @plaintextPrivacyWarningBody.
  ///
  /// In en, this message translates to:
  /// **'This export is not encrypted. It may contain amounts, descriptions, accounts, and other private financial data. Keep it in a secure location.'**
  String get plaintextPrivacyWarningBody;

  /// No description provided for @continueExportAction.
  ///
  /// In en, this message translates to:
  /// **'Export anyway'**
  String get continueExportAction;

  /// No description provided for @exportCompletedMessage.
  ///
  /// In en, this message translates to:
  /// **'Plaintext export created.'**
  String get exportCompletedMessage;

  /// No description provided for @backupPasswordTitle.
  ///
  /// In en, this message translates to:
  /// **'Backup password'**
  String get backupPasswordTitle;

  /// No description provided for @confirmPasswordLabel.
  ///
  /// In en, this message translates to:
  /// **'Confirm password'**
  String get confirmPasswordLabel;

  /// No description provided for @backupPasswordValidationMessage.
  ///
  /// In en, this message translates to:
  /// **'Use at least 12 characters and enter matching passwords.'**
  String get backupPasswordValidationMessage;

  /// No description provided for @portabilityErrorMessage.
  ///
  /// In en, this message translates to:
  /// **'The operation could not be completed. Check the file, password, and destination.'**
  String get portabilityErrorMessage;

  /// No description provided for @receiptAttachmentsTitle.
  ///
  /// In en, this message translates to:
  /// **'Receipts and attachments'**
  String get receiptAttachmentsTitle;

  /// No description provided for @addAttachmentAction.
  ///
  /// In en, this message translates to:
  /// **'Attach receipt or file'**
  String get addAttachmentAction;

  /// No description provided for @noAttachmentsMessage.
  ///
  /// In en, this message translates to:
  /// **'No files attached to this transaction.'**
  String get noAttachmentsMessage;

  /// No description provided for @exportAttachmentAction.
  ///
  /// In en, this message translates to:
  /// **'Decrypt and save a copy'**
  String get exportAttachmentAction;

  /// No description provided for @attachmentSizeLabel.
  ///
  /// In en, this message translates to:
  /// **'{bytes} bytes · encrypted on this device'**
  String attachmentSizeLabel(int bytes);

  /// No description provided for @attachmentAddedMessage.
  ///
  /// In en, this message translates to:
  /// **'The file was encrypted and attached.'**
  String get attachmentAddedMessage;

  /// No description provided for @attachmentExportedMessage.
  ///
  /// In en, this message translates to:
  /// **'Decrypted copy saved.'**
  String get attachmentExportedMessage;

  /// No description provided for @attachmentErrorMessage.
  ///
  /// In en, this message translates to:
  /// **'The attachment operation could not be completed.'**
  String get attachmentErrorMessage;

  /// No description provided for @accountNatureLabel.
  ///
  /// In en, this message translates to:
  /// **'{nature, select, asset{Asset} liability{Liability} other{Account}}'**
  String accountNatureLabel(String nature);

  /// No description provided for @physicalAssetTypeLabel.
  ///
  /// In en, this message translates to:
  /// **'{type, select, property{Property} vehicle{Vehicle} collectible{Collectible} equipment{Equipment} valuablePossession{Valuable possession} other{Other}}'**
  String physicalAssetTypeLabel(String type);

  /// No description provided for @investmentAssetClassLabel.
  ///
  /// In en, this message translates to:
  /// **'{assetClass, select, stock{Stock} etf{ETF} fund{Fund} reit{REIT} fii{FII} bond{Bond} fixedIncome{Fixed income} crypto{Cryptocurrency} commodity{Commodity} cashEquivalent{Cash equivalent} other{Other}}'**
  String investmentAssetClassLabel(String assetClass);

  /// No description provided for @syncEntityTypeLabel.
  ///
  /// In en, this message translates to:
  /// **'{entityType, select, vault{Vault} account{Account} category{Category} counterparty{Counterparty} tag{Tag} transaction{Transaction} recurring_rule{Recurring rule} installment_plan{Installment plan} credit_card_statement{Credit-card statement} budget{Budget} goal{Goal} asset{Asset} investment_instrument{Investment instrument} manual_fx_rate{Manual exchange rate} manual_market_price{Manual market price} attachment{Attachment} other{Record}}'**
  String syncEntityTypeLabel(String entityType);

  /// No description provided for @refreshAction.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get refreshAction;

  /// No description provided for @clearValueAction.
  ///
  /// In en, this message translates to:
  /// **'Clear value'**
  String get clearValueAction;

  /// No description provided for @lastBackupLabel.
  ///
  /// In en, this message translates to:
  /// **'Last backup'**
  String get lastBackupLabel;

  /// No description provided for @spendingByTagTitle.
  ///
  /// In en, this message translates to:
  /// **'Spending by tag'**
  String get spendingByTagTitle;

  /// No description provided for @withoutTagsLabel.
  ///
  /// In en, this message translates to:
  /// **'Without tags'**
  String get withoutTagsLabel;

  /// No description provided for @tagOverlapMessage.
  ///
  /// In en, this message translates to:
  /// **'Each expense counts in full for every tag. Tag totals may overlap.'**
  String get tagOverlapMessage;

  /// No description provided for @syncRunningLabel.
  ///
  /// In en, this message translates to:
  /// **'Synchronizing...'**
  String get syncRunningLabel;

  /// No description provided for @syncPendingLabel.
  ///
  /// In en, this message translates to:
  /// **'Pending changes'**
  String get syncPendingLabel;

  /// No description provided for @syncAutomaticPolicy.
  ///
  /// In en, this message translates to:
  /// **'Changes sync automatically while the app is open. Conflicts keep the higher revision; equal revisions use the edit time, then a consistent content tie-break.'**
  String get syncAutomaticPolicy;

  /// No description provided for @syncLastSuccessLabel.
  ///
  /// In en, this message translates to:
  /// **'Last completed synchronization'**
  String get syncLastSuccessLabel;

  /// No description provided for @syncNeverLabel.
  ///
  /// In en, this message translates to:
  /// **'Not yet completed'**
  String get syncNeverLabel;

  /// No description provided for @syncNetworkHelp.
  ///
  /// In en, this message translates to:
  /// **'Check your connection and try again. Your changes remain on this device.'**
  String get syncNetworkHelp;

  /// No description provided for @syncSessionHelp.
  ///
  /// In en, this message translates to:
  /// **'Your session has expired. Sign in again with the same account.'**
  String get syncSessionHelp;

  /// No description provided for @syncAccessHelp.
  ///
  /// In en, this message translates to:
  /// **'This account or device cannot access the cloud vault. Check that you are using the original account.'**
  String get syncAccessHelp;

  /// No description provided for @syncCompatibilityHelp.
  ///
  /// In en, this message translates to:
  /// **'The app and sync server are incompatible. Check the app version and server migrations.'**
  String get syncCompatibilityHelp;

  /// No description provided for @syncPayloadHelp.
  ///
  /// In en, this message translates to:
  /// **'A pending record could not be processed. Keep your data and report the diagnostic code.'**
  String get syncPayloadHelp;

  /// No description provided for @syncCryptoHelp.
  ///
  /// In en, this message translates to:
  /// **'The cloud data could not be decrypted. Keep your recovery key and report the diagnostic code.'**
  String get syncCryptoHelp;

  /// No description provided for @syncLocalHelp.
  ///
  /// In en, this message translates to:
  /// **'A local sync operation failed. Try again; if it persists, report the diagnostic code.'**
  String get syncLocalHelp;

  /// No description provided for @syncRemoteHelp.
  ///
  /// In en, this message translates to:
  /// **'The sync server could not complete the request. Try again later.'**
  String get syncRemoteHelp;

  /// No description provided for @vaultsTitle.
  ///
  /// In en, this message translates to:
  /// **'Vaults and account'**
  String get vaultsTitle;

  /// No description provided for @localVaultsLabel.
  ///
  /// In en, this message translates to:
  /// **'Vaults on this device'**
  String get localVaultsLabel;

  /// No description provided for @newVaultAction.
  ///
  /// In en, this message translates to:
  /// **'New vault'**
  String get newVaultAction;

  /// No description provided for @legacyVaultNotice.
  ///
  /// In en, this message translates to:
  /// **'Local copy from the test release. Use your already migrated vault for synchronization.'**
  String get legacyVaultNotice;

  /// No description provided for @vaultKeyLabel.
  ///
  /// In en, this message translates to:
  /// **'Vault key'**
  String get vaultKeyLabel;

  /// No description provided for @vaultKeyExplanation.
  ///
  /// In en, this message translates to:
  /// **'This key unlocks this vault. Keep it safe. It is neither your account password nor your backup password.'**
  String get vaultKeyExplanation;

  /// No description provided for @showVaultKeyAction.
  ///
  /// In en, this message translates to:
  /// **'Show vault key'**
  String get showVaultKeyAction;

  /// No description provided for @vaultSyncAction.
  ///
  /// In en, this message translates to:
  /// **'Synchronize active vault'**
  String get vaultSyncAction;

  /// No description provided for @accountCloudVaultsLabel.
  ///
  /// In en, this message translates to:
  /// **'Account and cloud vaults'**
  String get accountCloudVaultsLabel;

  /// No description provided for @vaultOwnerExplanation.
  ///
  /// In en, this message translates to:
  /// **'You can open backups offline. To synchronize, sign in to the owner account. The first upload permanently binds the vault to that account.'**
  String get vaultOwnerExplanation;

  /// No description provided for @accountEmailLabel.
  ///
  /// In en, this message translates to:
  /// **'Account email'**
  String get accountEmailLabel;

  /// No description provided for @accountPasswordLabel.
  ///
  /// In en, this message translates to:
  /// **'Account password'**
  String get accountPasswordLabel;

  /// No description provided for @accountSignInAction.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get accountSignInAction;

  /// No description provided for @accountSignOutAction.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get accountSignOutAction;

  /// No description provided for @refreshVaultsAction.
  ///
  /// In en, this message translates to:
  /// **'Refresh vault list'**
  String get refreshVaultsAction;

  /// No description provided for @noCloudVaultsMessage.
  ///
  /// In en, this message translates to:
  /// **'No new-format vaults in this account.'**
  String get noCloudVaultsMessage;

  /// No description provided for @restoreCloudVaultAction.
  ///
  /// In en, this message translates to:
  /// **'Restore cloud vault'**
  String get restoreCloudVaultAction;

  /// No description provided for @vaultOperationFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not complete. Check the owner account, vault key, backup password and connection. Existing vaults were preserved.'**
  String get vaultOperationFailed;

  /// No description provided for @restoreAddsVaultMessage.
  ///
  /// In en, this message translates to:
  /// **'Adds the backup vault without replacing existing local vaults.'**
  String get restoreAddsVaultMessage;

  /// No description provided for @legacyBackupUnsupportedMessage.
  ///
  /// In en, this message translates to:
  /// **'Use the backup of your already migrated vault. This old file belongs to the test release.'**
  String get legacyBackupUnsupportedMessage;

  /// No description provided for @updatesTitle.
  ///
  /// In en, this message translates to:
  /// **'App updates'**
  String get updatesTitle;

  /// No description provided for @updateAvailable.
  ///
  /// In en, this message translates to:
  /// **'Available version'**
  String get updateAvailable;

  /// No description provided for @updateChecking.
  ///
  /// In en, this message translates to:
  /// **'Checking for updates…'**
  String get updateChecking;

  /// No description provided for @updateWaitingWifi.
  ///
  /// In en, this message translates to:
  /// **'Waiting for Wi-Fi'**
  String get updateWaitingWifi;

  /// No description provided for @updateDownloading.
  ///
  /// In en, this message translates to:
  /// **'Downloading update…'**
  String get updateDownloading;

  /// No description provided for @updateReady.
  ///
  /// In en, this message translates to:
  /// **'Update verified and ready to install.'**
  String get updateReady;

  /// No description provided for @updateFailed.
  ///
  /// In en, this message translates to:
  /// **'Update unavailable or verification failed. You can try again; your data is unchanged.'**
  String get updateFailed;

  /// No description provided for @updateInstalling.
  ///
  /// In en, this message translates to:
  /// **'Preparing installation…'**
  String get updateInstalling;

  /// No description provided for @updateCheckHint.
  ///
  /// In en, this message translates to:
  /// **'Checks run while Equis is open, at most every six hours.'**
  String get updateCheckHint;

  /// No description provided for @updateAutomatic.
  ///
  /// In en, this message translates to:
  /// **'Download updates automatically'**
  String get updateAutomatic;

  /// No description provided for @updateCheck.
  ///
  /// In en, this message translates to:
  /// **'Check for updates'**
  String get updateCheck;

  /// No description provided for @updateDownloadNow.
  ///
  /// In en, this message translates to:
  /// **'Download now (any connection)'**
  String get updateDownloadNow;

  /// No description provided for @updateInstall.
  ///
  /// In en, this message translates to:
  /// **'Install update'**
  String get updateInstall;

  /// No description provided for @updateInstallConfirm.
  ///
  /// In en, this message translates to:
  /// **'Install the verified update? On Windows, Equis will close and reopen. Keep your backup; do not uninstall the app.'**
  String get updateInstallConfirm;

  /// No description provided for @updateLater.
  ///
  /// In en, this message translates to:
  /// **'Later'**
  String get updateLater;

  /// No description provided for @updatePermission.
  ///
  /// In en, this message translates to:
  /// **'Allow installation from Equis in Android settings, then tap Install update again.'**
  String get updatePermission;

  /// No description provided for @updateRecoveryRequired.
  ///
  /// In en, this message translates to:
  /// **'Equis file replacement is running or was interrupted. Close this window. If the update does not finish, use the recovery helper as described in the release instructions. Your vaults have not been opened.'**
  String get updateRecoveryRequired;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'pt'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when language+country codes are specified.
  switch (locale.languageCode) {
    case 'en':
      {
        switch (locale.countryCode) {
          case 'US':
            return AppLocalizationsEnUs();
        }
        break;
      }
    case 'pt':
      {
        switch (locale.countryCode) {
          case 'BR':
            return AppLocalizationsPtBr();
        }
        break;
      }
  }

  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'pt':
      return AppLocalizationsPt();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
