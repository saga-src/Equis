// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Portuguese (`pt`).
class AppLocalizationsPt extends AppLocalizations {
  AppLocalizationsPt([String locale = 'pt']) : super(locale);

  @override
  String get appTitle => 'Equis';

  @override
  String get homeNavigationLabel => 'Início';

  @override
  String get settingsNavigationLabel => 'Configurações';

  @override
  String get availableMoneyTitle => 'Dinheiro disponível';

  @override
  String get availableMoneyPlaceholder =>
      'Seu panorama financeiro local aparecerá aqui.';

  @override
  String get addTransactionAction => 'Adicionar transação';

  @override
  String get foundationStatusTitle => 'Fundação local-first';

  @override
  String get foundationStatusBody =>
      'Seus dados financeiros serão gravados localmente antes da sincronização opcional.';

  @override
  String get languageTitle => 'Idioma';

  @override
  String get appearanceTitle => 'Aparência';

  @override
  String get themeTitle => 'Tema';

  @override
  String get themeObsidianName => 'Modo Obsidian';

  @override
  String get themeObsidianDescription =>
      'Tema escuro estável com superfícies translúcidas e detalhes em esmeralda.';

  @override
  String get themeTrueLightName => 'True Light';

  @override
  String get themeTrueLightDescription =>
      'Tema claro, limpo e de alto contraste para uso diurno.';

  @override
  String get themeLegacyName => 'Legado';

  @override
  String get themeLegacyDescription =>
      'A aparência original do Equis v1, sem efeitos de vidro.';

  @override
  String get englishLanguage => 'Inglês (Estados Unidos)';

  @override
  String get portugueseLanguage => 'Português (Brasil)';

  @override
  String get offlineReadyLabel => 'Pronto para uso offline';

  @override
  String get transactionTypeLabel => 'Tipo';

  @override
  String get expenseTypeLabel => 'Despesa';

  @override
  String get incomeTypeLabel => 'Receita';

  @override
  String get transferTypeLabel => 'Transferência';

  @override
  String get amountLabel => 'Valor';

  @override
  String get accountLabel => 'Conta';

  @override
  String get categoryLabel => 'Categoria';

  @override
  String get saveLocallyAction => 'Salvar localmente';

  @override
  String get optionalDetailsLabel => 'Detalhes opcionais';

  @override
  String get transactionSavedMessage => 'Transação salva localmente';

  @override
  String get transactionSaveFailedMessage =>
      'Não foi possível salvar a transação';

  @override
  String get editTransactionAction => 'Editar transação';

  @override
  String get deleteTransactionAction => 'Excluir transação';

  @override
  String get reconcileTransactionAction => 'Conciliar transação';

  @override
  String get fromAccountLabel => 'Conta de origem';

  @override
  String get toAccountLabel => 'Conta de destino';

  @override
  String get dateLabel => 'Data';

  @override
  String get payeeLabel => 'Estabelecimento ou favorecido';

  @override
  String get notesLabel => 'Observações';

  @override
  String get requiredFieldMessage => 'Campo obrigatório';

  @override
  String get localVaultErrorMessage =>
      'Não foi possível abrir o cofre local criptografado.';

  @override
  String get setupRequiredMessage =>
      'Configure o cofre local antes de adicionar transações.';

  @override
  String get transactionNotFoundMessage => 'Transação não encontrada.';

  @override
  String get setupLocalVaultTitle => 'Configure seu cofre local';

  @override
  String get setupLocalVaultBody =>
      'Seus dados ficam criptografados neste dispositivo e funcionam offline.';

  @override
  String get profileNameLabel => 'Nome do perfil';

  @override
  String get firstAccountNameLabel => 'Nome da primeira conta';

  @override
  String get reportingCurrencyLabel => 'Moeda de relatório';

  @override
  String get createLocalVaultAction => 'Criar cofre criptografado';

  @override
  String get recentTransactionsTitle => 'Transações recentes';

  @override
  String get noRecentTransactionsMessage => 'Nenhuma transação ainda.';

  @override
  String get confirmDeleteTitle => 'Excluir transação?';

  @override
  String get confirmDeleteTransactionBody =>
      'Isto remove a transação dos saldos e preserva um registro local da exclusão.';

  @override
  String get cancelAction => 'Cancelar';

  @override
  String get deleteAction => 'Excluir';

  @override
  String get statusPendingLabel => 'Pendente';

  @override
  String get statusClearedLabel => 'Compensada';

  @override
  String get statusReconciledLabel => 'Conciliada';

  @override
  String get statusCancelledLabel => 'Cancelada';

  @override
  String get categoryExpensesLabel => 'Despesas';

  @override
  String get categoryIncomeLabel => 'Receitas';

  @override
  String get categoryFoodLabel => 'Alimentação';

  @override
  String get categoryHousingLabel => 'Moradia';

  @override
  String get categoryTransportLabel => 'Transporte';

  @override
  String get categorySalaryLabel => 'Salário';

  @override
  String get categoryOtherIncomeLabel => 'Outras receitas';

  @override
  String get manageCategoriesTagsAction => 'Gerenciar categorias e etiquetas';

  @override
  String get manageCategoriesTagsSubtitle =>
      'Crie, traduza e organize suas categorias e etiquetas.';

  @override
  String get alreadyHaveAccountAction => 'Já tenho uma conta';

  @override
  String get restoreExistingVaultTitle => 'Entrar e restaurar seus dados';

  @override
  String get restoreExistingVaultBody =>
      'Use sua conta Equis e a chave de recuperação salva no primeiro dispositivo para baixar e descriptografar seu cofre.';

  @override
  String get recoverySecretLabel => 'Chave de recuperação';

  @override
  String get recoverySecretRestoreHint => 'Ela começa com equis-recovery-v1_.';

  @override
  String get restoreAndSyncAction => 'Restaurar e sincronizar';

  @override
  String get restoreLocalDataSafetyMessage =>
      'A restauração só é permitida antes da criação de um cofre local; os dados existentes no dispositivo nunca são sobrescritos.';

  @override
  String get restoreNoVaultMessage =>
      'Nenhum cofre sincronizado foi encontrado para esta conta.';

  @override
  String get restoreMultipleVaultsMessage =>
      'Esta conta possui mais de um cofre. A seleção de cofre ainda não está disponível.';

  @override
  String get restoreInvalidSecretMessage =>
      'A chave de recuperação não corresponde a este cofre.';

  @override
  String get restoreLocalVaultExistsMessage =>
      'Este dispositivo já possui um cofre local e ele não pode ser sobrescrito.';

  @override
  String get restoreSyncFailedMessage =>
      'O cofre foi recuperado, mas a sincronização não terminou. Verifique sua conexão e tente novamente.';

  @override
  String get editTranslationsAction => 'Editar nomes e traduções';

  @override
  String get englishNameLabel => 'Nome em inglês (opcional)';

  @override
  String get portugueseNameLabel => 'Nome em português do Brasil (opcional)';

  @override
  String get localizedNamesHint =>
      'Quando uma tradução estiver vazia, o nome principal será usado.';

  @override
  String get categoriesTitle => 'Categorias';

  @override
  String get tagsTitle => 'Etiquetas';

  @override
  String get addCategoryAction => 'Adicionar categoria';

  @override
  String get addTagAction => 'Adicionar etiqueta';

  @override
  String get categoryNameLabel => 'Nome da categoria';

  @override
  String get parentCategoryLabel => 'Categoria superior';

  @override
  String get noParentLabel => 'Sem categoria superior';

  @override
  String get tagNameLabel => 'Nome da etiqueta';

  @override
  String get noTagsMessage => 'Nenhuma etiqueta ainda.';

  @override
  String get systemCategoryLabel => 'Categoria do sistema';

  @override
  String get archiveCategoryAction => 'Arquivar categoria';

  @override
  String get categoryArchiveFailedMessage =>
      'Arquive primeiro as categorias filhas.';

  @override
  String get expenseCategoriesTitle => 'Categorias de despesas';

  @override
  String get incomeCategoriesTitle => 'Categorias de receitas';

  @override
  String get addAccountAction => 'Adicionar conta';

  @override
  String get accountNameLabel => 'Nome da conta';

  @override
  String get accountTypeLabel => 'Tipo de conta';

  @override
  String get currencyLabel => 'Moeda';

  @override
  String get checkingAccountType => 'Conta-corrente';

  @override
  String get savingsAccountType => 'Poupança';

  @override
  String get cashAccountType => 'Dinheiro';

  @override
  String get walletAccountType => 'Carteira digital';

  @override
  String get creditCardAccountType => 'Cartão de crédito';

  @override
  String get historyNavigationLabel => 'Histórico';

  @override
  String get transactionHistoryTitle => 'Histórico de transações';

  @override
  String get filtersAction => 'Filtros';

  @override
  String get historyFiltersTitle => 'Busca e filtros';

  @override
  String get minimumAmountLabel => 'Valor mínimo';

  @override
  String get maximumAmountLabel => 'Valor máximo';

  @override
  String get fromDateLabel => 'Data inicial';

  @override
  String get toDateLabel => 'Data final';

  @override
  String get anyValueLabel => 'Qualquer';

  @override
  String get includeDescendantCategoriesLabel => 'Incluir categorias filhas';

  @override
  String get tagFilterLabel => 'Etiqueta';

  @override
  String get statusFilterLabel => 'Status';

  @override
  String get clearFiltersAction => 'Limpar';

  @override
  String get applyFiltersAction => 'Aplicar filtros';

  @override
  String get loadMoreAction => 'Carregar mais';

  @override
  String get noHistoryResultsMessage =>
      'Nenhuma transação corresponde a estes filtros.';

  @override
  String get historySearchFailedMessage =>
      'Não foi possível buscar no histórico local.';

  @override
  String get invalidFiltersMessage => 'Confira os intervalos de valor e data.';

  @override
  String transactionTypeName(String type) {
    String _temp0 = intl.Intl.selectLogic(type, {
      'opening_balance': 'Saldo inicial',
      'expense': 'Despesa',
      'income': 'Receita',
      'transfer': 'Transferência',
      'currency_exchange': 'Câmbio',
      'credit_card_purchase': 'Compra no cartão',
      'credit_card_payment': 'Pagamento de cartão',
      'refund': 'Reembolso',
      'loan_payment': 'Pagamento de empréstimo',
      'investment_buy': 'Compra de investimento',
      'investment_sell': 'Venda de investimento',
      'dividend': 'Dividendo',
      'interest': 'Juros',
      'fee': 'Tarifa',
      'adjustment': 'Ajuste',
      'other': 'Transação',
    });
    return '$_temp0';
  }

  @override
  String get recurringNavigationLabel => 'Agendado';

  @override
  String get recurringTitle => 'Atividade recorrente';

  @override
  String get upcomingTabLabel => 'Próximas';

  @override
  String get recurringRulesTabLabel => 'Regras';

  @override
  String get addRecurringAction => 'Adicionar recorrência';

  @override
  String get createRecurringAction => 'Criar agendamento';

  @override
  String get recurringLoadFailedMessage =>
      'Não foi possível carregar as recorrências do cofre local.';

  @override
  String get noUpcomingOccurrencesMessage =>
      'Nenhuma atividade agendada nos próximos 90 dias.';

  @override
  String get noRecurringRulesMessage => 'Nenhuma regra de recorrência ainda.';

  @override
  String get confirmOccurrenceAction => 'Confirmar';

  @override
  String get skipOccurrenceAction => 'Pular';

  @override
  String get rescheduleOccurrenceAction => 'Reagendar';

  @override
  String get modifyOneOccurrenceAction => 'Alterar somente esta ocorrência';

  @override
  String get modifyFutureOccurrencesAction =>
      'Alterar esta e as próximas ocorrências';

  @override
  String get endRecurrenceAction => 'Encerrar recorrência';

  @override
  String get endedRecurrenceLabel => 'Encerrada';

  @override
  String get recurrenceNameLabel => 'Nome do agendamento';

  @override
  String get recurrenceStartsLabel => 'Início';

  @override
  String get recurrenceEndsLabel => 'Término (opcional)';

  @override
  String get frequencyLabel => 'Frequência';

  @override
  String get intervalLabel => 'A cada';

  @override
  String get dailyFrequencyLabel => 'Diária';

  @override
  String get weeklyFrequencyLabel => 'Semanal';

  @override
  String get monthlyFrequencyLabel => 'Mensal';

  @override
  String get yearlyFrequencyLabel => 'Anual';

  @override
  String get scheduledOccurrenceLabel => 'Agendada';

  @override
  String get pendingOccurrenceLabel => 'Alterada';

  @override
  String get confirmedOccurrenceLabel => 'Confirmada';

  @override
  String get skippedOccurrenceLabel => 'Pulada';

  @override
  String get applyAction => 'Aplicar';

  @override
  String get thisMonthTitle => 'Este mês';

  @override
  String get incomeReportLabel => 'Receitas';

  @override
  String get expensesReportLabel => 'Despesas';

  @override
  String get netCashFlowLabel => 'Fluxo de caixa líquido';

  @override
  String get budgetDashboardTitle => 'Orçamento';

  @override
  String get budgetNextPhaseMessage =>
      'O acompanhamento do orçamento estará disponível na próxima fase.';

  @override
  String get upcomingDashboardTitle => 'Próximos';

  @override
  String get upcomingNext30DaysLabel => 'Agendados nos próximos 30 dias';

  @override
  String get spendingByCategoryTitle => 'Despesas por categoria';

  @override
  String get cashFlowChartTitle => 'Fluxo de caixa ao longo do tempo';

  @override
  String get accountBalancesTitle => 'Saldos das contas';

  @override
  String get reportsSectionTitle => 'Relatórios';

  @override
  String get reportingIncompleteMessage =>
      'Algumas moedas foram omitidas porque não há taxa de câmbio local disponível.';

  @override
  String get reportingEstimatedMessage =>
      'Inclui taxas de câmbio estimadas do cache.';

  @override
  String get noSpendingDataMessage =>
      'Nenhuma atividade classificada neste período.';

  @override
  String get originalCurrencyAmountLabel => 'Moeda original';

  @override
  String get reportingAmountLabel => 'Moeda de relatório';

  @override
  String get cardsNavigationLabel => 'Cartões';

  @override
  String get creditCardsTitle => 'Cartões de crédito';

  @override
  String get noCreditCardsMessage =>
      'Crie uma conta de cartão de crédito no Início para começar.';

  @override
  String get selectCardLabel => 'Cartão e moeda';

  @override
  String get configureCardAction => 'Configurar cartão';

  @override
  String get closingDayLabel => 'Dia de fechamento';

  @override
  String get dueDayLabel => 'Dia de vencimento';

  @override
  String get creditLimitLabel => 'Limite de crédito';

  @override
  String get availableCreditLabel => 'Limite disponível';

  @override
  String get statementsTabLabel => 'Faturas';

  @override
  String get installmentsTabLabel => 'Parcelamentos';

  @override
  String get addCardPurchaseAction => 'Adicionar compra';

  @override
  String get addInstallmentAction => 'Adicionar compra parcelada';

  @override
  String get feeInterestAction => 'Adicionar tarifa ou juros';

  @override
  String get payStatementAction => 'Pagar fatura';

  @override
  String get refundPurchaseAction => 'Estornar compra';

  @override
  String get noStatementsMessage => 'Nenhuma fatura para este cartão.';

  @override
  String get noInstallmentsMessage => 'Nenhum parcelamento para este cartão.';

  @override
  String get originalAmountLabel => 'Valor original';

  @override
  String get financedAmountLabel => 'Total com juros';

  @override
  String get installmentCountLabel => 'Quantidade de parcelas';

  @override
  String get firstInstallmentDateLabel => 'Data da primeira parcela';

  @override
  String get interestRateLabel => 'Taxa de juros (opcional)';

  @override
  String get descriptionLabel => 'Descrição';

  @override
  String get currentInstallmentLabel => 'Parcela atual';

  @override
  String get remainingAmountLabel => 'Valor restante';

  @override
  String get cancelInstallmentAction => 'Cancelar e estornar plano';

  @override
  String get cardLoadFailedMessage =>
      'Não foi possível carregar os cartões do cofre local.';

  @override
  String get futureStatementStatus => 'Futura';

  @override
  String get openStatementStatus => 'Aberta';

  @override
  String get closedStatementStatus => 'Fechada';

  @override
  String get paidStatementStatus => 'Paga';

  @override
  String get overdueStatementStatus => 'Vencida';

  @override
  String get saveAction => 'Salvar';

  @override
  String get budgetsNavigationLabel => 'Orçamentos';

  @override
  String get budgetsTitle => 'Orçamentos';

  @override
  String get addBudgetAction => 'Adicionar orçamento';

  @override
  String get editBudgetAction => 'Editar orçamento';

  @override
  String get deleteBudgetAction => 'Excluir orçamento';

  @override
  String get noBudgetsMessage =>
      'Nenhum orçamento ainda. Crie um para começar a acompanhar seu plano.';

  @override
  String get budgetLoadFailedMessage =>
      'Não foi possível carregar os orçamentos do cofre local.';

  @override
  String get budgetNameLabel => 'Nome do orçamento';

  @override
  String get budgetLimitLabel => 'Limite';

  @override
  String get budgetPeriodLabel => 'Período';

  @override
  String get weeklyBudgetPeriod => 'Semanal';

  @override
  String get monthlyBudgetPeriod => 'Mensal';

  @override
  String get yearlyBudgetPeriod => 'Anual';

  @override
  String get customBudgetPeriod => 'Intervalo personalizado';

  @override
  String get budgetWarningThresholdLabel => 'Limite do alerta (%)';

  @override
  String get budgetScopeLabel => 'Escopo';

  @override
  String get overallSpendingScope => 'Gastos gerais';

  @override
  String get budgetCategoriesScope => 'Categorias';

  @override
  String get budgetAccountsScope => 'Contas';

  @override
  String get budgetTagsScope => 'Etiquetas';

  @override
  String get includeDescendantsLabel => 'Incluir categorias descendentes';

  @override
  String get customStartDateLabel => 'Data inicial';

  @override
  String get customEndDateLabel => 'Data final';

  @override
  String get budgetUsedLabel => 'Usado';

  @override
  String get budgetRemainingLabel => 'Restante';

  @override
  String get budgetProjectedLabel => 'Projetado';

  @override
  String get budgetSafeState => 'Seguro';

  @override
  String get budgetApproachingState => 'Próximo do limite';

  @override
  String get budgetReachedState => 'Limite atingido';

  @override
  String get budgetExceededState => 'Excedido';

  @override
  String get budgetLikelyExceedMessage =>
      'No ritmo atual, este orçamento provavelmente será excedido.';

  @override
  String get budgetIncompleteFxMessage =>
      'Alguns gastos foram omitidos porque uma taxa de câmbio local não está disponível.';

  @override
  String get budgetEstimatedFxMessage =>
      'Este orçamento usa uma taxa de câmbio local estimada.';

  @override
  String get confirmDeleteBudgetBody =>
      'Excluir este orçamento? As transações e o histórico de gastos não serão alterados.';

  @override
  String activeBudgetsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count orçamentos ativos',
      one: '1 orçamento ativo',
      zero: 'Nenhum orçamento ativo',
    );
    return '$_temp0';
  }

  @override
  String budgetUsagePercent(int percent) {
    return '$percent% usado';
  }

  @override
  String get goalsNavigationLabel => 'Metas';

  @override
  String get goalsTitle => 'Metas e fluxo de caixa futuro';

  @override
  String get goalsTabLabel => 'Metas';

  @override
  String get cashFlowProjectionTabLabel => 'Fluxo de caixa futuro';

  @override
  String get addGoalAction => 'Adicionar meta';

  @override
  String get editGoalAction => 'Editar meta';

  @override
  String get deleteGoalAction => 'Excluir meta';

  @override
  String get noGoalsMessage =>
      'Nenhuma meta ainda. Crie uma para planejar seu próximo objetivo.';

  @override
  String get goalLoadFailedMessage =>
      'Não foi possível carregar as metas e projeções do cofre local.';

  @override
  String get goalNameLabel => 'Nome da meta';

  @override
  String get goalTypeLabel => 'Tipo da meta';

  @override
  String get emergencyFundGoalType => 'Reserva de emergência';

  @override
  String get vacationGoalType => 'Viagem';

  @override
  String get vehicleGoalType => 'Veículo';

  @override
  String get homeGoalType => 'Imóvel';

  @override
  String get debtPayoffGoalType => 'Quitar dívida';

  @override
  String get investmentGoalType => 'Investimento';

  @override
  String get retirementGoalType => 'Aposentadoria';

  @override
  String get educationGoalType => 'Educação';

  @override
  String get customGoalType => 'Personalizada';

  @override
  String get goalTargetLabel => 'Objetivo';

  @override
  String get goalCurrentLabel => 'Atual';

  @override
  String get plannedMonthlyContributionLabel => 'Aporte mensal planejado';

  @override
  String get requiredMonthlyContributionLabel => 'Aporte mensal necessário';

  @override
  String get expectedCompletionLabel => 'Conclusão estimada';

  @override
  String get goalTargetDateLabel => 'Data-alvo';

  @override
  String get goalPriorityLabel => 'Prioridade';

  @override
  String get goalTrackingModeLabel => 'Acompanhamento do progresso';

  @override
  String get manualGoalTracking => 'Aportes manuais';

  @override
  String get linkedAccountsGoalTracking => 'Saldos de contas vinculadas';

  @override
  String get transactionsGoalTracking => 'Aportes vinculados';

  @override
  String get linkedGoalAccountsLabel => 'Bolsos vinculados';

  @override
  String get addGoalContributionAction => 'Adicionar aporte';

  @override
  String get goalContributionAmountLabel => 'Valor do aporte';

  @override
  String get goalContributionDateLabel => 'Data do aporte';

  @override
  String get goalContributionTransactionLabel =>
      'Transação associada (opcional)';

  @override
  String get goalContributionNotesLabel => 'Observações (opcional)';

  @override
  String get goalReachedLabel => 'Objetivo atingido';

  @override
  String get cashFlowEstimateDisclaimer =>
      'Esta é uma estimativa baseada nos dados locais conhecidos, não uma garantia de saldo futuro.';

  @override
  String get openingAvailableLabel => 'Disponível inicial';

  @override
  String get projectedClosingLabel => 'Saldo final projetado';

  @override
  String get noProjectedEventsMessage =>
      'Nenhum evento conhecido nesta janela de projeção.';

  @override
  String get projectedBalanceLabel => 'Saldo após o evento';

  @override
  String get recurringIncomeProjectionType => 'Receita recorrente';

  @override
  String get recurringExpenseProjectionType => 'Despesa recorrente';

  @override
  String get installmentProjectionType => 'Parcela futura';

  @override
  String get cardStatementProjectionType => 'Fatura do cartão';

  @override
  String get goalContributionProjectionType => 'Aporte planejado para meta';

  @override
  String get goalIncompleteFxMessage =>
      'Alguns saldos vinculados foram omitidos porque uma taxa de câmbio local não está disponível.';

  @override
  String get goalEstimatedFxMessage =>
      'Esta meta usa uma taxa de câmbio local estimada.';

  @override
  String get confirmDeleteGoalBody =>
      'Excluir esta meta? Contas vinculadas, transações e o histórico do ledger não serão alterados.';

  @override
  String activeGoalsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count metas ativas',
      one: '1 meta ativa',
      zero: 'Nenhuma meta ativa',
    );
    return '$_temp0';
  }

  @override
  String get investmentsNavigationLabel => 'Investimentos';

  @override
  String get investmentsTitle => 'Investimentos';

  @override
  String get portfolioValueLabel => 'Valor da carteira';

  @override
  String get portfolioCostLabel => 'Custo de aquisição';

  @override
  String get unrealizedResultLabel => 'Ganho/perda não realizado';

  @override
  String get realizedResultLabel => 'Ganho/perda realizado';

  @override
  String get investmentIncomeLabel => 'Rendimentos recebidos';

  @override
  String get allocationLabel => 'Alocação';

  @override
  String get addInstrumentAction => 'Adicionar instrumento';

  @override
  String get noInvestmentsMessage =>
      'Nenhum instrumento de investimento cadastrado.';

  @override
  String get investmentLoadFailedMessage =>
      'Não foi possível carregar os investimentos do cofre local.';

  @override
  String get instrumentNameLabel => 'Nome do instrumento';

  @override
  String get instrumentSymbolLabel => 'Símbolo';

  @override
  String get instrumentExchangeLabel => 'Bolsa';

  @override
  String get assetClassLabel => 'Classe de ativo';

  @override
  String get quantityLabel => 'Quantidade';

  @override
  String get averageCostLabel => 'Custo médio';

  @override
  String get unitPriceLabel => 'Preço unitário';

  @override
  String get feesLabel => 'Taxas';

  @override
  String get taxesLabel => 'Impostos';

  @override
  String get investmentDateLabel => 'Data';

  @override
  String get cashAccountLabel => 'Conta de caixa do investimento';

  @override
  String get buyInvestmentAction => 'Comprar';

  @override
  String get sellInvestmentAction => 'Vender';

  @override
  String get dividendInvestmentAction => 'Dividendo';

  @override
  String get interestInvestmentAction => 'Juros';

  @override
  String get feeInvestmentAction => 'Tarifa';

  @override
  String get depositInvestmentAction => 'Depositar';

  @override
  String get withdrawInvestmentAction => 'Retirar';

  @override
  String get investmentAmountLabel => 'Valor';

  @override
  String get missingMarketPriceMessage =>
      'Adicione uma cotação para calcular valor de mercado e resultado não realizado.';

  @override
  String get insufficientLotsMessage =>
      'A quantidade vendida excede os lotes disponíveis.';

  @override
  String get wealthNavigationLabel => 'Patrimônio';

  @override
  String get wealthTitle => 'Patrimônio líquido e bens';

  @override
  String get netWorthLabel => 'Patrimônio líquido';

  @override
  String get totalAssetsLabel => 'Ativos';

  @override
  String get totalLiabilitiesLabel => 'Passivos';

  @override
  String get physicalAssetsLabel => 'Bens físicos';

  @override
  String get includedAccountsLabel => 'Contas incluídas';

  @override
  String get addAssetAction => 'Adicionar bem';

  @override
  String get deleteAssetAction => 'Excluir bem';

  @override
  String get addValuationAction => 'Atualizar valor';

  @override
  String get noAssetsMessage => 'Nenhum bem físico cadastrado.';

  @override
  String get wealthLoadFailedMessage =>
      'Não foi possível carregar o patrimônio do cofre local.';

  @override
  String get assetNameLabel => 'Nome do bem';

  @override
  String get assetTypeLabel => 'Tipo de bem';

  @override
  String get assetCostLabel => 'Preço de compra';

  @override
  String get assetDateLabel => 'Data da compra';

  @override
  String get valuationMethodLabel => 'Método de avaliação';

  @override
  String get annualRateLabel => 'Taxa anual (%)';

  @override
  String get usefulLifeMonthsLabel => 'Vida útil (meses)';

  @override
  String get salvageValueLabel => 'Valor residual';

  @override
  String get includeInNetWorthLabel => 'Incluir no patrimônio';

  @override
  String get currentValueLabel => 'Valor atual';

  @override
  String get valuationDateLabel => 'Data da avaliação';

  @override
  String get manualValuationMethod => 'Manual';

  @override
  String get straightLineValuationMethod => 'Depreciação linear';

  @override
  String get depreciationValuationMethod => 'Depreciação percentual fixa';

  @override
  String get appreciationValuationMethod => 'Valorização percentual fixa';

  @override
  String get customValuationMethod => 'Agenda personalizada';

  @override
  String get wealthIncompleteFxMessage =>
      'Alguns valores foram omitidos porque não há taxa de câmbio local.';

  @override
  String get wealthEstimatedFxMessage =>
      'Este relatório usa taxas de câmbio locais estimadas.';

  @override
  String get confirmDeleteAssetBody =>
      'Excluir este bem? O histórico de avaliações também será removido.';

  @override
  String customIntervalLabel(int interval, String unit) {
    return 'A cada $interval $unit';
  }

  @override
  String get refreshPricesAction => 'Atualizar cotações';

  @override
  String get manualPriceAction => 'Definir preço manual';

  @override
  String get stalePriceMessage => 'A cotação em cache está desatualizada.';

  @override
  String get priceRefreshFailedMessage =>
      'A atualização falhou. O último valor local continua em uso.';

  @override
  String get intelligenceTitle => 'Análises financeiras';

  @override
  String get intelligenceSubtitle =>
      'Estimativas locais baseadas nos seus dados registrados';

  @override
  String get intelligencePrivacyMessage =>
      'Estas análises são calculadas neste dispositivo. O histórico de transações não é enviado a um serviço externo de IA.';

  @override
  String get intelligenceLoadFailedMessage =>
      'Não foi possível calcular as análises financeiras do cofre local.';

  @override
  String get intelligenceDisabledMessage =>
      'As análises financeiras estão desativadas. O livro-razão e os recursos normais não são afetados.';

  @override
  String get noInsightsMessage =>
      'Ainda não há histórico local suficiente para gerar análises.';

  @override
  String get refreshInsightsAction => 'Recalcular análises';

  @override
  String get calculationTraceTitle => 'Como esta estimativa foi calculada';

  @override
  String spendingTrendInsight(String percent) {
    return 'A despesa projetada está em $percent% em comparação com o mês anterior.';
  }

  @override
  String expenseAnomalyInsight(
    String category,
    String projected,
    String percent,
  ) {
    return 'A projeção de $category é $projected, $percent% em comparação com o mês anterior.';
  }

  @override
  String budgetForecastInsight(String name, String projected, String limit) {
    return 'No ritmo atual, $name está projetado em $projected para um limite de $limit.';
  }

  @override
  String cashFlowForecastInsight(int days, String closing) {
    return 'A estimativa local de fluxo de caixa para $days dias termina em $closing.';
  }

  @override
  String recurringCommitmentsInsight(int count, String total) {
    return 'Há previsão de $count despesas recorrentes, somando $total, neste período.';
  }

  @override
  String goalContributionInsight(String name, String gap) {
    return 'Para manter o prazo de $name, a contribuição mensal pode precisar de mais $gap.';
  }

  @override
  String emergencyFundInsight(String months, String average) {
    return 'Os recursos líquidos cobrem cerca de $months meses pela média recente de despesas de $average.';
  }

  @override
  String debtOverviewInsight(String debt, String percent) {
    return 'A dívida registrada é $debt, equivalente a $percent% dos ativos registrados.';
  }

  @override
  String netWorthTrendInsight(String change, String percent, int months) {
    return 'O patrimônio variou $change ($percent%) em $months pontos do relatório.';
  }

  @override
  String investmentConcentrationInsight(String name, String percent) {
    return '$name representa $percent% dos investimentos com cotação.';
  }

  @override
  String get cloudAccountTitle => 'Conta Equis na nuvem';

  @override
  String get cloudAccountSettingsSubtitle =>
      'Login opcional, verificação e identidade do dispositivo';

  @override
  String get createEquisAccountAction => 'Criar Conta Equis';

  @override
  String get continueOfflineAction => 'Continuar Offline';

  @override
  String get cloudAccountIntro =>
      'A identidade na nuvem é opcional. Seu cofre atual continua local e mantém o mesmo identificador.';

  @override
  String get emailLabel => 'E-mail';

  @override
  String get passwordLabel => 'Senha';

  @override
  String get signInAction => 'Entrar';

  @override
  String get signOutAction => 'Sair';

  @override
  String get awaitingVerificationTitle => 'Verifique seu e-mail';

  @override
  String awaitingVerificationBody(String email) {
    return 'Uma mensagem de verificação foi enviada para $email. Depois de verificar, entre para vincular este cofre local.';
  }

  @override
  String get resendVerificationAction => 'Reenviar e-mail de verificação';

  @override
  String get cloudSignedInTitle => 'Conta na nuvem conectada';

  @override
  String cloudSignedInBody(String email) {
    return 'Conectado como $email. O identificador do cofre local foi preservado.';
  }

  @override
  String get localAccessPreservedMessage =>
      'A sessão na nuvem está indisponível ou desconectada. O acesso ao cofre local continua disponível.';

  @override
  String get cloudNotConfiguredMessage =>
      'O Supabase não está configurado nesta versão. Você pode continuar usando todos os recursos locais offline.';

  @override
  String get cloudSyncEncryptionPendingMessage =>
      'A sincronização segura fica desligada até você exportar e confirmar a chave de recuperação do cofre.';

  @override
  String get secureSyncTitle => 'Sincronização segura';

  @override
  String get secureSyncDisabledBody =>
      'Seus dados permanecem locais até você ativar a sincronização criptografada de ponta a ponta.';

  @override
  String get enableSecureSyncAction => 'Ativar sincronização segura';

  @override
  String get recoverySecretTitle => 'Salve sua chave de recuperação';

  @override
  String get recoverySecretBody =>
      'Guarde esta chave em um local seguro. Ela é necessária para abrir o cofre criptografado em um novo dispositivo e a Equis não consegue recuperá-la por você.';

  @override
  String get copyRecoverySecretAction => 'Copiar chave de recuperação';

  @override
  String get recoverySecretCopiedMessage => 'Chave de recuperação copiada';

  @override
  String get confirmRecoverySavedAction => 'Salvei a chave de recuperação';

  @override
  String get syncStatusSynced => 'Sincronizado';

  @override
  String get syncStatusOffline =>
      'Offline — as alterações pendentes continuam seguras neste dispositivo';

  @override
  String get syncStatusError => 'A sincronização precisa de atenção';

  @override
  String get syncStatusReady => 'Pronto para sincronizar';

  @override
  String syncDiagnostics(int pushed, int pulled, int conflicts) {
    return 'Últimas 24 horas: $pushed enviados · $pulled recebidos · $conflicts conflitos';
  }

  @override
  String get retrySyncAction => 'Sincronizar agora';

  @override
  String get syncConflictsTitle => 'Conflitos que exigem revisão';

  @override
  String syncConflictBody(
    String entityType,
    String recordId,
    int localRevision,
    int remoteRevision,
  ) {
    return '$entityType · $recordId · revisão local $localRevision, revisão remota $remoteRevision';
  }

  @override
  String get keepLocalAction => 'Manter local';

  @override
  String get keepRemoteAction => 'Manter remoto';

  @override
  String deviceIdentityLabel(String name, String platform, String identifier) {
    return 'Dispositivo: $name · $platform · $identifier';
  }

  @override
  String get authInvalidCredentialsMessage =>
      'O e-mail ou a senha está incorreto.';

  @override
  String get authEmailNotVerifiedMessage =>
      'Verifique seu e-mail antes de entrar.';

  @override
  String get authWeakPasswordMessage => 'Escolha uma senha mais forte.';

  @override
  String get authAccountExistsMessage =>
      'Já existe uma conta para este e-mail. Tente entrar.';

  @override
  String get authRateLimitedMessage =>
      'Muitas tentativas. Aguarde um momento e tente novamente.';

  @override
  String get authNetworkMessage =>
      'O serviço de nuvem está inacessível. O acesso local não foi afetado.';

  @override
  String get authVaultMismatchMessage =>
      'Este cofre já está vinculado a outra conta na nuvem.';

  @override
  String get authUnknownMessage =>
      'Não foi possível concluir a operação da conta na nuvem.';

  @override
  String get portabilityTitle => 'Backup e exportação';

  @override
  String get portabilitySubtitle =>
      'Backups criptografados e exportações abertas com confirmação';

  @override
  String get createEncryptedBackupAction => 'Criar backup criptografado';

  @override
  String get encryptedBackupDescription =>
      'Cria um arquivo .equis protegido por senha com os dados e anexos do cofre.';

  @override
  String get validateBackupAction => 'Validar um backup';

  @override
  String get validateBackupDescription =>
      'Confere senha, formato, integridade e compatibilidade sem restaurar.';

  @override
  String get restoreBackupAction => 'Restaurar backup';

  @override
  String get restoreBackupDescription =>
      'Reconstrói um cofre e os vínculos dos anexos neste perfil vazio.';

  @override
  String get restoreRequiresCleanProfileMessage =>
      'A restauração só fica disponível antes de criar um cofre neste perfil.';

  @override
  String get exportJsonAction => 'Exportar cofre como JSON';

  @override
  String get exportCsvAction => 'Exportar transações como CSV';

  @override
  String get plaintextExportDescription =>
      'Exporta os dados lógicos do cofre sem criptografia.';

  @override
  String get transactionCsvDescription =>
      'Exporta valores mínimos exatos, moedas, movimentos, divisões, etiquetas e conversões.';

  @override
  String get backupCreatedMessage => 'Backup criptografado criado.';

  @override
  String get backupValidMessage => 'O backup é autêntico e compatível.';

  @override
  String get backupRestoredMessage => 'Backup restaurado com sucesso.';

  @override
  String get restoreBackupConfirmation =>
      'Restaurar este backup no perfil local vazio? Identificadores e relações serão preservados.';

  @override
  String get plaintextPrivacyWarningTitle =>
      'Dados financeiros sem criptografia';

  @override
  String get plaintextPrivacyWarningBody =>
      'Esta exportação não é criptografada. Ela pode conter valores, descrições, contas e outros dados financeiros privados. Guarde-a em local seguro.';

  @override
  String get continueExportAction => 'Exportar mesmo assim';

  @override
  String get exportCompletedMessage => 'Exportação aberta criada.';

  @override
  String get backupPasswordTitle => 'Senha do backup';

  @override
  String get confirmPasswordLabel => 'Confirmar senha';

  @override
  String get backupPasswordValidationMessage =>
      'Use pelo menos 12 caracteres e digite senhas iguais.';

  @override
  String get portabilityErrorMessage =>
      'Não foi possível concluir a operação. Confira o arquivo, a senha e o destino.';

  @override
  String get receiptAttachmentsTitle => 'Comprovantes e anexos';

  @override
  String get addAttachmentAction => 'Anexar comprovante ou arquivo';

  @override
  String get noAttachmentsMessage => 'Nenhum arquivo anexado a esta transação.';

  @override
  String get exportAttachmentAction => 'Descriptografar e salvar uma cópia';

  @override
  String attachmentSizeLabel(int bytes) {
    return '$bytes bytes · criptografado neste dispositivo';
  }

  @override
  String get attachmentAddedMessage => 'O arquivo foi criptografado e anexado.';

  @override
  String get attachmentExportedMessage => 'Cópia descriptografada salva.';

  @override
  String get attachmentErrorMessage =>
      'Não foi possível concluir a operação com o anexo.';

  @override
  String accountNatureLabel(String nature) {
    String _temp0 = intl.Intl.selectLogic(nature, {
      'asset': 'Ativo',
      'liability': 'Passivo',
      'other': 'Conta',
    });
    return '$_temp0';
  }

  @override
  String physicalAssetTypeLabel(String type) {
    String _temp0 = intl.Intl.selectLogic(type, {
      'property': 'Imóvel',
      'vehicle': 'Veículo',
      'collectible': 'Colecionável',
      'equipment': 'Equipamento',
      'valuablePossession': 'Bem valioso',
      'other': 'Outro',
    });
    return '$_temp0';
  }

  @override
  String investmentAssetClassLabel(String assetClass) {
    String _temp0 = intl.Intl.selectLogic(assetClass, {
      'stock': 'Ação',
      'etf': 'ETF',
      'fund': 'Fundo',
      'reit': 'REIT',
      'fii': 'FII',
      'bond': 'Título',
      'fixedIncome': 'Renda fixa',
      'crypto': 'Criptomoeda',
      'commodity': 'Commodity',
      'cashEquivalent': 'Equivalente de caixa',
      'other': 'Outro',
    });
    return '$_temp0';
  }

  @override
  String syncEntityTypeLabel(String entityType) {
    String _temp0 = intl.Intl.selectLogic(entityType, {
      'vault': 'Cofre',
      'account': 'Conta',
      'category': 'Categoria',
      'counterparty': 'Contraparte',
      'tag': 'Etiqueta',
      'transaction': 'Transação',
      'recurring_rule': 'Regra recorrente',
      'installment_plan': 'Plano de parcelas',
      'credit_card_statement': 'Fatura de cartão',
      'budget': 'Orçamento',
      'goal': 'Meta',
      'asset': 'Bem',
      'investment_instrument': 'Instrumento de investimento',
      'manual_fx_rate': 'Câmbio manual',
      'manual_market_price': 'Preço manual',
      'attachment': 'Anexo',
      'other': 'Registro',
    });
    return '$_temp0';
  }

  @override
  String get refreshAction => 'Atualizar';

  @override
  String get clearValueAction => 'Limpar valor';

  @override
  String get lastBackupLabel => 'Último backup';

  @override
  String get spendingByTagTitle => 'Despesas por tag';

  @override
  String get withoutTagsLabel => 'Sem tags';

  @override
  String get tagOverlapMessage =>
      'Cada despesa conta integralmente em cada tag. Os totais das tags podem se sobrepor.';

  @override
  String get syncRunningLabel => 'Sincronizando...';

  @override
  String get syncPendingLabel => 'Alterações pendentes';

  @override
  String get syncAutomaticPolicy =>
      'As alterações sincronizam automaticamente enquanto o app está aberto. Conflitos mantêm a maior revisão; revisões iguais usam a data da edição e, em novo empate, um critério consistente pelo conteúdo.';

  @override
  String get syncLastSuccessLabel => 'Última sincronização concluída';

  @override
  String get syncNeverLabel => 'Ainda não concluída';

  @override
  String get syncNetworkHelp =>
      'Verifique a conexão e tente novamente. Suas alterações continuam neste dispositivo.';

  @override
  String get syncSessionHelp =>
      'Sua sessão expirou. Entre novamente com a mesma conta.';

  @override
  String get syncAccessHelp =>
      'Esta conta ou dispositivo não tem acesso ao cofre na nuvem. Confira se está usando a conta original.';

  @override
  String get syncCompatibilityHelp =>
      'O app e o servidor de sincronização são incompatíveis. Confira a versão do app e as migrações do servidor.';

  @override
  String get syncPayloadHelp =>
      'Um registro pendente não pôde ser processado. Mantenha seus dados e informe o código de diagnóstico.';

  @override
  String get syncCryptoHelp =>
      'Não foi possível descriptografar os dados da nuvem. Guarde sua chave de recuperação e informe o código de diagnóstico.';

  @override
  String get syncLocalHelp =>
      'Uma operação local de sincronização falhou. Tente novamente; se persistir, informe o código de diagnóstico.';

  @override
  String get syncRemoteHelp =>
      'O servidor não conseguiu concluir a solicitação. Tente novamente mais tarde.';

  @override
  String get vaultsTitle => 'Cofres e conta';

  @override
  String get localVaultsLabel => 'Cofres neste aparelho';

  @override
  String get newVaultAction => 'Novo cofre';

  @override
  String get legacyVaultNotice =>
      'Cópia local da versão de testes. Use seu cofre já migrado para sincronizar.';

  @override
  String get vaultKeyLabel => 'Chave do cofre';

  @override
  String get vaultKeyExplanation =>
      'Esta chave abre este cofre. Guarde-a em local seguro. Ela não é a senha da conta nem a senha do backup.';

  @override
  String get showVaultKeyAction => 'Mostrar chave do cofre';

  @override
  String get vaultSyncAction => 'Sincronizar cofre ativo';

  @override
  String get accountCloudVaultsLabel => 'Conta e cofres na nuvem';

  @override
  String get vaultOwnerExplanation =>
      'Você pode abrir backups offline. Para sincronizar, entre na conta proprietária. O primeiro envio vincula permanentemente o cofre à conta.';

  @override
  String get accountEmailLabel => 'E-mail da conta';

  @override
  String get accountPasswordLabel => 'Senha da conta';

  @override
  String get accountSignInAction => 'Entrar na conta';

  @override
  String get accountSignOutAction => 'Sair da conta';

  @override
  String get refreshVaultsAction => 'Atualizar lista de cofres';

  @override
  String get noCloudVaultsMessage =>
      'Nenhum cofre do novo formato nesta conta.';

  @override
  String get restoreCloudVaultAction => 'Restaurar cofre da nuvem';

  @override
  String get vaultOperationFailed =>
      'Não foi possível concluir. Confira a conta proprietária, a chave do cofre, a senha do backup e a conexão. Seus cofres existentes foram preservados.';

  @override
  String get restoreAddsVaultMessage =>
      'Adiciona o cofre do backup sem substituir os cofres locais existentes.';

  @override
  String get legacyBackupUnsupportedMessage =>
      'Use o backup do cofre que você já migrou. Este arquivo antigo pertence à versão de testes.';

  @override
  String get updatesTitle => 'Atualizações do aplicativo';

  @override
  String get updateAvailable => 'Versão disponível';

  @override
  String get updateChecking => 'Verificando atualizações…';

  @override
  String get updateWaitingWifi => 'Aguardando Wi-Fi';

  @override
  String get updateDownloading => 'Baixando atualização…';

  @override
  String get updateReady => 'Atualização verificada e pronta para instalar.';

  @override
  String get updateFailed =>
      'Atualização indisponível ou falha na verificação. Tente novamente; seus dados foram preservados.';

  @override
  String get updateInstalling => 'Preparando instalação…';

  @override
  String get updateCheckHint =>
      'As verificações acontecem com o Equis aberto, a cada seis horas.';

  @override
  String get updateAutomatic => 'Baixar atualizações automaticamente';

  @override
  String get updateCheck => 'Verificar atualizações';

  @override
  String get updateDownloadNow => 'Baixar agora (qualquer conexão)';

  @override
  String get updateInstall => 'Instalar atualização';

  @override
  String get updateInstallConfirm =>
      'Instalar a atualização verificada? No Windows, o Equis será fechado e reaberto. Guarde seu backup; não desinstale o app.';

  @override
  String get updateLater => 'Mais tarde';

  @override
  String get updatePermission =>
      'Permita instalar pelo Equis nas configurações do Android e toque novamente em Instalar atualização.';

  @override
  String get updateRecoveryRequired =>
      'Uma substituição de arquivos do Equis está em andamento ou foi interrompida. Feche esta janela. Se a atualização não concluir, use o auxiliar de recuperação conforme as instruções da versão. Seus cofres não foram abertos.';
}

/// The translations for Portuguese, as used in Brazil (`pt_BR`).
class AppLocalizationsPtBr extends AppLocalizationsPt {
  AppLocalizationsPtBr() : super('pt_BR');

  @override
  String get appTitle => 'Equis';

  @override
  String get homeNavigationLabel => 'Início';

  @override
  String get settingsNavigationLabel => 'Configurações';

  @override
  String get availableMoneyTitle => 'Dinheiro disponível';

  @override
  String get availableMoneyPlaceholder =>
      'Seu panorama financeiro local aparecerá aqui.';

  @override
  String get addTransactionAction => 'Adicionar transação';

  @override
  String get foundationStatusTitle => 'Fundação local-first';

  @override
  String get foundationStatusBody =>
      'Seus dados financeiros serão gravados localmente antes da sincronização opcional.';

  @override
  String get languageTitle => 'Idioma';

  @override
  String get appearanceTitle => 'Aparência';

  @override
  String get themeTitle => 'Tema';

  @override
  String get themeObsidianName => 'Modo Obsidian';

  @override
  String get themeObsidianDescription =>
      'Tema escuro estável com superfícies translúcidas e detalhes em esmeralda.';

  @override
  String get themeTrueLightName => 'True Light';

  @override
  String get themeTrueLightDescription =>
      'Tema claro, limpo e de alto contraste para uso diurno.';

  @override
  String get themeLegacyName => 'Legado';

  @override
  String get themeLegacyDescription =>
      'A aparência original do Equis v1, sem efeitos de vidro.';

  @override
  String get englishLanguage => 'Inglês (Estados Unidos)';

  @override
  String get portugueseLanguage => 'Português (Brasil)';

  @override
  String get offlineReadyLabel => 'Pronto para uso offline';

  @override
  String get transactionTypeLabel => 'Tipo';

  @override
  String get expenseTypeLabel => 'Despesa';

  @override
  String get incomeTypeLabel => 'Receita';

  @override
  String get transferTypeLabel => 'Transferência';

  @override
  String get amountLabel => 'Valor';

  @override
  String get accountLabel => 'Conta';

  @override
  String get categoryLabel => 'Categoria';

  @override
  String get saveLocallyAction => 'Salvar localmente';

  @override
  String get optionalDetailsLabel => 'Detalhes opcionais';

  @override
  String get transactionSavedMessage => 'Transação salva localmente';

  @override
  String get transactionSaveFailedMessage =>
      'Não foi possível salvar a transação';

  @override
  String get editTransactionAction => 'Editar transação';

  @override
  String get deleteTransactionAction => 'Excluir transação';

  @override
  String get reconcileTransactionAction => 'Conciliar transação';

  @override
  String get fromAccountLabel => 'Conta de origem';

  @override
  String get toAccountLabel => 'Conta de destino';

  @override
  String get dateLabel => 'Data';

  @override
  String get payeeLabel => 'Estabelecimento ou favorecido';

  @override
  String get notesLabel => 'Observações';

  @override
  String get requiredFieldMessage => 'Campo obrigatório';

  @override
  String get localVaultErrorMessage =>
      'Não foi possível abrir o cofre local criptografado.';

  @override
  String get setupRequiredMessage =>
      'Configure o cofre local antes de adicionar transações.';

  @override
  String get transactionNotFoundMessage => 'Transação não encontrada.';

  @override
  String get setupLocalVaultTitle => 'Configure seu cofre local';

  @override
  String get setupLocalVaultBody =>
      'Seus dados ficam criptografados neste dispositivo e funcionam offline.';

  @override
  String get profileNameLabel => 'Nome do perfil';

  @override
  String get firstAccountNameLabel => 'Nome da primeira conta';

  @override
  String get reportingCurrencyLabel => 'Moeda de relatório';

  @override
  String get createLocalVaultAction => 'Criar cofre criptografado';

  @override
  String get recentTransactionsTitle => 'Transações recentes';

  @override
  String get noRecentTransactionsMessage => 'Nenhuma transação ainda.';

  @override
  String get confirmDeleteTitle => 'Excluir transação?';

  @override
  String get confirmDeleteTransactionBody =>
      'Isto remove a transação dos saldos e preserva um registro local da exclusão.';

  @override
  String get cancelAction => 'Cancelar';

  @override
  String get deleteAction => 'Excluir';

  @override
  String get statusPendingLabel => 'Pendente';

  @override
  String get statusClearedLabel => 'Compensada';

  @override
  String get statusReconciledLabel => 'Conciliada';

  @override
  String get statusCancelledLabel => 'Cancelada';

  @override
  String get categoryExpensesLabel => 'Despesas';

  @override
  String get categoryIncomeLabel => 'Receitas';

  @override
  String get categoryFoodLabel => 'Alimentação';

  @override
  String get categoryHousingLabel => 'Moradia';

  @override
  String get categoryTransportLabel => 'Transporte';

  @override
  String get categorySalaryLabel => 'Salário';

  @override
  String get categoryOtherIncomeLabel => 'Outras receitas';

  @override
  String get manageCategoriesTagsAction => 'Gerenciar categorias e etiquetas';

  @override
  String get manageCategoriesTagsSubtitle =>
      'Crie, traduza e organize suas categorias e etiquetas.';

  @override
  String get alreadyHaveAccountAction => 'Já tenho uma conta';

  @override
  String get restoreExistingVaultTitle => 'Entrar e restaurar seus dados';

  @override
  String get restoreExistingVaultBody =>
      'Use sua conta Equis e a chave de recuperação salva no primeiro dispositivo para baixar e descriptografar seu cofre.';

  @override
  String get recoverySecretLabel => 'Chave de recuperação';

  @override
  String get recoverySecretRestoreHint => 'Ela começa com equis-recovery-v1_.';

  @override
  String get restoreAndSyncAction => 'Restaurar e sincronizar';

  @override
  String get restoreLocalDataSafetyMessage =>
      'A restauração só é permitida antes da criação de um cofre local; os dados existentes no dispositivo nunca são sobrescritos.';

  @override
  String get restoreNoVaultMessage =>
      'Nenhum cofre sincronizado foi encontrado para esta conta.';

  @override
  String get restoreMultipleVaultsMessage =>
      'Esta conta possui mais de um cofre. A seleção de cofre ainda não está disponível.';

  @override
  String get restoreInvalidSecretMessage =>
      'A chave de recuperação não corresponde a este cofre.';

  @override
  String get restoreLocalVaultExistsMessage =>
      'Este dispositivo já possui um cofre local e ele não pode ser sobrescrito.';

  @override
  String get restoreSyncFailedMessage =>
      'O cofre foi recuperado, mas a sincronização não terminou. Verifique sua conexão e tente novamente.';

  @override
  String get editTranslationsAction => 'Editar nomes e traduções';

  @override
  String get englishNameLabel => 'Nome em inglês (opcional)';

  @override
  String get portugueseNameLabel => 'Nome em português do Brasil (opcional)';

  @override
  String get localizedNamesHint =>
      'Quando uma tradução estiver vazia, o nome principal será usado.';

  @override
  String get categoriesTitle => 'Categorias';

  @override
  String get tagsTitle => 'Etiquetas';

  @override
  String get addCategoryAction => 'Adicionar categoria';

  @override
  String get addTagAction => 'Adicionar etiqueta';

  @override
  String get categoryNameLabel => 'Nome da categoria';

  @override
  String get parentCategoryLabel => 'Categoria superior';

  @override
  String get noParentLabel => 'Sem categoria superior';

  @override
  String get tagNameLabel => 'Nome da etiqueta';

  @override
  String get noTagsMessage => 'Nenhuma etiqueta ainda.';

  @override
  String get systemCategoryLabel => 'Categoria do sistema';

  @override
  String get archiveCategoryAction => 'Arquivar categoria';

  @override
  String get categoryArchiveFailedMessage =>
      'Arquive primeiro as categorias filhas.';

  @override
  String get expenseCategoriesTitle => 'Categorias de despesas';

  @override
  String get incomeCategoriesTitle => 'Categorias de receitas';

  @override
  String get addAccountAction => 'Adicionar conta';

  @override
  String get accountNameLabel => 'Nome da conta';

  @override
  String get accountTypeLabel => 'Tipo de conta';

  @override
  String get currencyLabel => 'Moeda';

  @override
  String get checkingAccountType => 'Conta-corrente';

  @override
  String get savingsAccountType => 'Poupança';

  @override
  String get cashAccountType => 'Dinheiro';

  @override
  String get walletAccountType => 'Carteira digital';

  @override
  String get creditCardAccountType => 'Cartão de crédito';

  @override
  String get historyNavigationLabel => 'Histórico';

  @override
  String get transactionHistoryTitle => 'Histórico de transações';

  @override
  String get filtersAction => 'Filtros';

  @override
  String get historyFiltersTitle => 'Busca e filtros';

  @override
  String get minimumAmountLabel => 'Valor mínimo';

  @override
  String get maximumAmountLabel => 'Valor máximo';

  @override
  String get fromDateLabel => 'Data inicial';

  @override
  String get toDateLabel => 'Data final';

  @override
  String get anyValueLabel => 'Qualquer';

  @override
  String get includeDescendantCategoriesLabel => 'Incluir categorias filhas';

  @override
  String get tagFilterLabel => 'Etiqueta';

  @override
  String get statusFilterLabel => 'Status';

  @override
  String get clearFiltersAction => 'Limpar';

  @override
  String get applyFiltersAction => 'Aplicar filtros';

  @override
  String get loadMoreAction => 'Carregar mais';

  @override
  String get noHistoryResultsMessage =>
      'Nenhuma transação corresponde a estes filtros.';

  @override
  String get historySearchFailedMessage =>
      'Não foi possível buscar no histórico local.';

  @override
  String get invalidFiltersMessage => 'Confira os intervalos de valor e data.';

  @override
  String transactionTypeName(String type) {
    String _temp0 = intl.Intl.selectLogic(type, {
      'opening_balance': 'Saldo inicial',
      'expense': 'Despesa',
      'income': 'Receita',
      'transfer': 'Transferência',
      'currency_exchange': 'Câmbio',
      'credit_card_purchase': 'Compra no cartão',
      'credit_card_payment': 'Pagamento de cartão',
      'refund': 'Reembolso',
      'loan_payment': 'Pagamento de empréstimo',
      'investment_buy': 'Compra de investimento',
      'investment_sell': 'Venda de investimento',
      'dividend': 'Dividendo',
      'interest': 'Juros',
      'fee': 'Tarifa',
      'adjustment': 'Ajuste',
      'other': 'Transação',
    });
    return '$_temp0';
  }

  @override
  String get recurringNavigationLabel => 'Agendado';

  @override
  String get recurringTitle => 'Atividade recorrente';

  @override
  String get upcomingTabLabel => 'Próximas';

  @override
  String get recurringRulesTabLabel => 'Regras';

  @override
  String get addRecurringAction => 'Adicionar recorrência';

  @override
  String get createRecurringAction => 'Criar agendamento';

  @override
  String get recurringLoadFailedMessage =>
      'Não foi possível carregar as recorrências do cofre local.';

  @override
  String get noUpcomingOccurrencesMessage =>
      'Nenhuma atividade agendada nos próximos 90 dias.';

  @override
  String get noRecurringRulesMessage => 'Nenhuma regra de recorrência ainda.';

  @override
  String get confirmOccurrenceAction => 'Confirmar';

  @override
  String get skipOccurrenceAction => 'Pular';

  @override
  String get rescheduleOccurrenceAction => 'Reagendar';

  @override
  String get modifyOneOccurrenceAction => 'Alterar somente esta ocorrência';

  @override
  String get modifyFutureOccurrencesAction =>
      'Alterar esta e as próximas ocorrências';

  @override
  String get endRecurrenceAction => 'Encerrar recorrência';

  @override
  String get endedRecurrenceLabel => 'Encerrada';

  @override
  String get recurrenceNameLabel => 'Nome do agendamento';

  @override
  String get recurrenceStartsLabel => 'Início';

  @override
  String get recurrenceEndsLabel => 'Término (opcional)';

  @override
  String get frequencyLabel => 'Frequência';

  @override
  String get intervalLabel => 'A cada';

  @override
  String get dailyFrequencyLabel => 'Diária';

  @override
  String get weeklyFrequencyLabel => 'Semanal';

  @override
  String get monthlyFrequencyLabel => 'Mensal';

  @override
  String get yearlyFrequencyLabel => 'Anual';

  @override
  String get scheduledOccurrenceLabel => 'Agendada';

  @override
  String get pendingOccurrenceLabel => 'Alterada';

  @override
  String get confirmedOccurrenceLabel => 'Confirmada';

  @override
  String get skippedOccurrenceLabel => 'Pulada';

  @override
  String get applyAction => 'Aplicar';

  @override
  String get thisMonthTitle => 'Este mês';

  @override
  String get incomeReportLabel => 'Receitas';

  @override
  String get expensesReportLabel => 'Despesas';

  @override
  String get netCashFlowLabel => 'Fluxo de caixa líquido';

  @override
  String get budgetDashboardTitle => 'Orçamento';

  @override
  String get budgetNextPhaseMessage =>
      'O acompanhamento do orçamento estará disponível na próxima fase.';

  @override
  String get upcomingDashboardTitle => 'Próximos';

  @override
  String get upcomingNext30DaysLabel => 'Agendados nos próximos 30 dias';

  @override
  String get spendingByCategoryTitle => 'Despesas por categoria';

  @override
  String get cashFlowChartTitle => 'Fluxo de caixa ao longo do tempo';

  @override
  String get accountBalancesTitle => 'Saldos das contas';

  @override
  String get reportsSectionTitle => 'Relatórios';

  @override
  String get reportingIncompleteMessage =>
      'Algumas moedas foram omitidas porque não há taxa de câmbio local disponível.';

  @override
  String get reportingEstimatedMessage =>
      'Inclui taxas de câmbio estimadas do cache.';

  @override
  String get noSpendingDataMessage =>
      'Nenhuma atividade classificada neste período.';

  @override
  String get originalCurrencyAmountLabel => 'Moeda original';

  @override
  String get reportingAmountLabel => 'Moeda de relatório';

  @override
  String get cardsNavigationLabel => 'Cartões';

  @override
  String get creditCardsTitle => 'Cartões de crédito';

  @override
  String get noCreditCardsMessage =>
      'Crie uma conta de cartão de crédito no Início para começar.';

  @override
  String get selectCardLabel => 'Cartão e moeda';

  @override
  String get configureCardAction => 'Configurar cartão';

  @override
  String get closingDayLabel => 'Dia de fechamento';

  @override
  String get dueDayLabel => 'Dia de vencimento';

  @override
  String get creditLimitLabel => 'Limite de crédito';

  @override
  String get availableCreditLabel => 'Limite disponível';

  @override
  String get statementsTabLabel => 'Faturas';

  @override
  String get installmentsTabLabel => 'Parcelamentos';

  @override
  String get addCardPurchaseAction => 'Adicionar compra';

  @override
  String get addInstallmentAction => 'Adicionar compra parcelada';

  @override
  String get feeInterestAction => 'Adicionar tarifa ou juros';

  @override
  String get payStatementAction => 'Pagar fatura';

  @override
  String get refundPurchaseAction => 'Estornar compra';

  @override
  String get noStatementsMessage => 'Nenhuma fatura para este cartão.';

  @override
  String get noInstallmentsMessage => 'Nenhum parcelamento para este cartão.';

  @override
  String get originalAmountLabel => 'Valor original';

  @override
  String get financedAmountLabel => 'Total com juros';

  @override
  String get installmentCountLabel => 'Quantidade de parcelas';

  @override
  String get firstInstallmentDateLabel => 'Data da primeira parcela';

  @override
  String get interestRateLabel => 'Taxa de juros (opcional)';

  @override
  String get descriptionLabel => 'Descrição';

  @override
  String get currentInstallmentLabel => 'Parcela atual';

  @override
  String get remainingAmountLabel => 'Valor restante';

  @override
  String get cancelInstallmentAction => 'Cancelar e estornar plano';

  @override
  String get cardLoadFailedMessage =>
      'Não foi possível carregar os cartões do cofre local.';

  @override
  String get futureStatementStatus => 'Futura';

  @override
  String get openStatementStatus => 'Aberta';

  @override
  String get closedStatementStatus => 'Fechada';

  @override
  String get paidStatementStatus => 'Paga';

  @override
  String get overdueStatementStatus => 'Vencida';

  @override
  String get saveAction => 'Salvar';

  @override
  String get budgetsNavigationLabel => 'Orçamentos';

  @override
  String get budgetsTitle => 'Orçamentos';

  @override
  String get addBudgetAction => 'Adicionar orçamento';

  @override
  String get editBudgetAction => 'Editar orçamento';

  @override
  String get deleteBudgetAction => 'Excluir orçamento';

  @override
  String get noBudgetsMessage =>
      'Nenhum orçamento ainda. Crie um para começar a acompanhar seu plano.';

  @override
  String get budgetLoadFailedMessage =>
      'Não foi possível carregar os orçamentos do cofre local.';

  @override
  String get budgetNameLabel => 'Nome do orçamento';

  @override
  String get budgetLimitLabel => 'Limite';

  @override
  String get budgetPeriodLabel => 'Período';

  @override
  String get weeklyBudgetPeriod => 'Semanal';

  @override
  String get monthlyBudgetPeriod => 'Mensal';

  @override
  String get yearlyBudgetPeriod => 'Anual';

  @override
  String get customBudgetPeriod => 'Intervalo personalizado';

  @override
  String get budgetWarningThresholdLabel => 'Limite do alerta (%)';

  @override
  String get budgetScopeLabel => 'Escopo';

  @override
  String get overallSpendingScope => 'Gastos gerais';

  @override
  String get budgetCategoriesScope => 'Categorias';

  @override
  String get budgetAccountsScope => 'Contas';

  @override
  String get budgetTagsScope => 'Etiquetas';

  @override
  String get includeDescendantsLabel => 'Incluir categorias descendentes';

  @override
  String get customStartDateLabel => 'Data inicial';

  @override
  String get customEndDateLabel => 'Data final';

  @override
  String get budgetUsedLabel => 'Usado';

  @override
  String get budgetRemainingLabel => 'Restante';

  @override
  String get budgetProjectedLabel => 'Projetado';

  @override
  String get budgetSafeState => 'Seguro';

  @override
  String get budgetApproachingState => 'Próximo do limite';

  @override
  String get budgetReachedState => 'Limite atingido';

  @override
  String get budgetExceededState => 'Excedido';

  @override
  String get budgetLikelyExceedMessage =>
      'No ritmo atual, este orçamento provavelmente será excedido.';

  @override
  String get budgetIncompleteFxMessage =>
      'Alguns gastos foram omitidos porque uma taxa de câmbio local não está disponível.';

  @override
  String get budgetEstimatedFxMessage =>
      'Este orçamento usa uma taxa de câmbio local estimada.';

  @override
  String get confirmDeleteBudgetBody =>
      'Excluir este orçamento? As transações e o histórico de gastos não serão alterados.';

  @override
  String activeBudgetsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count orçamentos ativos',
      one: '1 orçamento ativo',
      zero: 'Nenhum orçamento ativo',
    );
    return '$_temp0';
  }

  @override
  String budgetUsagePercent(int percent) {
    return '$percent% usado';
  }

  @override
  String get goalsNavigationLabel => 'Metas';

  @override
  String get goalsTitle => 'Metas e fluxo de caixa futuro';

  @override
  String get goalsTabLabel => 'Metas';

  @override
  String get cashFlowProjectionTabLabel => 'Fluxo de caixa futuro';

  @override
  String get addGoalAction => 'Adicionar meta';

  @override
  String get editGoalAction => 'Editar meta';

  @override
  String get deleteGoalAction => 'Excluir meta';

  @override
  String get noGoalsMessage =>
      'Nenhuma meta ainda. Crie uma para planejar seu próximo objetivo.';

  @override
  String get goalLoadFailedMessage =>
      'Não foi possível carregar as metas e projeções do cofre local.';

  @override
  String get goalNameLabel => 'Nome da meta';

  @override
  String get goalTypeLabel => 'Tipo da meta';

  @override
  String get emergencyFundGoalType => 'Reserva de emergência';

  @override
  String get vacationGoalType => 'Viagem';

  @override
  String get vehicleGoalType => 'Veículo';

  @override
  String get homeGoalType => 'Imóvel';

  @override
  String get debtPayoffGoalType => 'Quitar dívida';

  @override
  String get investmentGoalType => 'Investimento';

  @override
  String get retirementGoalType => 'Aposentadoria';

  @override
  String get educationGoalType => 'Educação';

  @override
  String get customGoalType => 'Personalizada';

  @override
  String get goalTargetLabel => 'Objetivo';

  @override
  String get goalCurrentLabel => 'Atual';

  @override
  String get plannedMonthlyContributionLabel => 'Aporte mensal planejado';

  @override
  String get requiredMonthlyContributionLabel => 'Aporte mensal necessário';

  @override
  String get expectedCompletionLabel => 'Conclusão estimada';

  @override
  String get goalTargetDateLabel => 'Data-alvo';

  @override
  String get goalPriorityLabel => 'Prioridade';

  @override
  String get goalTrackingModeLabel => 'Acompanhamento do progresso';

  @override
  String get manualGoalTracking => 'Aportes manuais';

  @override
  String get linkedAccountsGoalTracking => 'Saldos de contas vinculadas';

  @override
  String get transactionsGoalTracking => 'Aportes vinculados';

  @override
  String get linkedGoalAccountsLabel => 'Bolsos vinculados';

  @override
  String get addGoalContributionAction => 'Adicionar aporte';

  @override
  String get goalContributionAmountLabel => 'Valor do aporte';

  @override
  String get goalContributionDateLabel => 'Data do aporte';

  @override
  String get goalContributionTransactionLabel =>
      'Transação associada (opcional)';

  @override
  String get goalContributionNotesLabel => 'Observações (opcional)';

  @override
  String get goalReachedLabel => 'Objetivo atingido';

  @override
  String get cashFlowEstimateDisclaimer =>
      'Esta é uma estimativa baseada nos dados locais conhecidos, não uma garantia de saldo futuro.';

  @override
  String get openingAvailableLabel => 'Disponível inicial';

  @override
  String get projectedClosingLabel => 'Saldo final projetado';

  @override
  String get noProjectedEventsMessage =>
      'Nenhum evento conhecido nesta janela de projeção.';

  @override
  String get projectedBalanceLabel => 'Saldo após o evento';

  @override
  String get recurringIncomeProjectionType => 'Receita recorrente';

  @override
  String get recurringExpenseProjectionType => 'Despesa recorrente';

  @override
  String get installmentProjectionType => 'Parcela futura';

  @override
  String get cardStatementProjectionType => 'Fatura do cartão';

  @override
  String get goalContributionProjectionType => 'Aporte planejado para meta';

  @override
  String get goalIncompleteFxMessage =>
      'Alguns saldos vinculados foram omitidos porque uma taxa de câmbio local não está disponível.';

  @override
  String get goalEstimatedFxMessage =>
      'Esta meta usa uma taxa de câmbio local estimada.';

  @override
  String get confirmDeleteGoalBody =>
      'Excluir esta meta? Contas vinculadas, transações e o histórico do ledger não serão alterados.';

  @override
  String activeGoalsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count metas ativas',
      one: '1 meta ativa',
      zero: 'Nenhuma meta ativa',
    );
    return '$_temp0';
  }

  @override
  String get investmentsNavigationLabel => 'Investimentos';

  @override
  String get investmentsTitle => 'Investimentos';

  @override
  String get portfolioValueLabel => 'Valor da carteira';

  @override
  String get portfolioCostLabel => 'Custo de aquisição';

  @override
  String get unrealizedResultLabel => 'Ganho/perda não realizado';

  @override
  String get realizedResultLabel => 'Ganho/perda realizado';

  @override
  String get investmentIncomeLabel => 'Rendimentos recebidos';

  @override
  String get allocationLabel => 'Alocação';

  @override
  String get addInstrumentAction => 'Adicionar instrumento';

  @override
  String get noInvestmentsMessage =>
      'Nenhum instrumento de investimento cadastrado.';

  @override
  String get investmentLoadFailedMessage =>
      'Não foi possível carregar os investimentos do cofre local.';

  @override
  String get instrumentNameLabel => 'Nome do instrumento';

  @override
  String get instrumentSymbolLabel => 'Símbolo';

  @override
  String get instrumentExchangeLabel => 'Bolsa';

  @override
  String get assetClassLabel => 'Classe de ativo';

  @override
  String get quantityLabel => 'Quantidade';

  @override
  String get averageCostLabel => 'Custo médio';

  @override
  String get unitPriceLabel => 'Preço unitário';

  @override
  String get feesLabel => 'Taxas';

  @override
  String get taxesLabel => 'Impostos';

  @override
  String get investmentDateLabel => 'Data';

  @override
  String get cashAccountLabel => 'Conta de caixa do investimento';

  @override
  String get buyInvestmentAction => 'Comprar';

  @override
  String get sellInvestmentAction => 'Vender';

  @override
  String get dividendInvestmentAction => 'Dividendo';

  @override
  String get interestInvestmentAction => 'Juros';

  @override
  String get feeInvestmentAction => 'Tarifa';

  @override
  String get depositInvestmentAction => 'Depositar';

  @override
  String get withdrawInvestmentAction => 'Retirar';

  @override
  String get investmentAmountLabel => 'Valor';

  @override
  String get missingMarketPriceMessage =>
      'Adicione uma cotação para calcular valor de mercado e resultado não realizado.';

  @override
  String get insufficientLotsMessage =>
      'A quantidade vendida excede os lotes disponíveis.';

  @override
  String get wealthNavigationLabel => 'Patrimônio';

  @override
  String get wealthTitle => 'Patrimônio líquido e bens';

  @override
  String get netWorthLabel => 'Patrimônio líquido';

  @override
  String get totalAssetsLabel => 'Ativos';

  @override
  String get totalLiabilitiesLabel => 'Passivos';

  @override
  String get physicalAssetsLabel => 'Bens físicos';

  @override
  String get includedAccountsLabel => 'Contas incluídas';

  @override
  String get addAssetAction => 'Adicionar bem';

  @override
  String get deleteAssetAction => 'Excluir bem';

  @override
  String get addValuationAction => 'Atualizar valor';

  @override
  String get noAssetsMessage => 'Nenhum bem físico cadastrado.';

  @override
  String get wealthLoadFailedMessage =>
      'Não foi possível carregar o patrimônio do cofre local.';

  @override
  String get assetNameLabel => 'Nome do bem';

  @override
  String get assetTypeLabel => 'Tipo de bem';

  @override
  String get assetCostLabel => 'Preço de compra';

  @override
  String get assetDateLabel => 'Data da compra';

  @override
  String get valuationMethodLabel => 'Método de avaliação';

  @override
  String get annualRateLabel => 'Taxa anual (%)';

  @override
  String get usefulLifeMonthsLabel => 'Vida útil (meses)';

  @override
  String get salvageValueLabel => 'Valor residual';

  @override
  String get includeInNetWorthLabel => 'Incluir no patrimônio';

  @override
  String get currentValueLabel => 'Valor atual';

  @override
  String get valuationDateLabel => 'Data da avaliação';

  @override
  String get manualValuationMethod => 'Manual';

  @override
  String get straightLineValuationMethod => 'Depreciação linear';

  @override
  String get depreciationValuationMethod => 'Depreciação percentual fixa';

  @override
  String get appreciationValuationMethod => 'Valorização percentual fixa';

  @override
  String get customValuationMethod => 'Agenda personalizada';

  @override
  String get wealthIncompleteFxMessage =>
      'Alguns valores foram omitidos porque não há taxa de câmbio local.';

  @override
  String get wealthEstimatedFxMessage =>
      'Este relatório usa taxas de câmbio locais estimadas.';

  @override
  String get confirmDeleteAssetBody =>
      'Excluir este bem? O histórico de avaliações também será removido.';

  @override
  String customIntervalLabel(int interval, String unit) {
    return 'A cada $interval $unit';
  }

  @override
  String get refreshPricesAction => 'Atualizar cotações';

  @override
  String get manualPriceAction => 'Definir preço manual';

  @override
  String get stalePriceMessage => 'A cotação em cache está desatualizada.';

  @override
  String get priceRefreshFailedMessage =>
      'A atualização falhou. O último valor local continua em uso.';

  @override
  String get intelligenceTitle => 'Análises financeiras';

  @override
  String get intelligenceSubtitle =>
      'Estimativas locais baseadas nos seus dados registrados';

  @override
  String get intelligencePrivacyMessage =>
      'Estas análises são calculadas neste dispositivo. O histórico de transações não é enviado a um serviço externo de IA.';

  @override
  String get intelligenceLoadFailedMessage =>
      'Não foi possível calcular as análises financeiras do cofre local.';

  @override
  String get intelligenceDisabledMessage =>
      'As análises financeiras estão desativadas. O livro-razão e os recursos normais não são afetados.';

  @override
  String get noInsightsMessage =>
      'Ainda não há histórico local suficiente para gerar análises.';

  @override
  String get refreshInsightsAction => 'Recalcular análises';

  @override
  String get calculationTraceTitle => 'Como esta estimativa foi calculada';

  @override
  String spendingTrendInsight(String percent) {
    return 'A despesa projetada está em $percent% em comparação com o mês anterior.';
  }

  @override
  String expenseAnomalyInsight(
    String category,
    String projected,
    String percent,
  ) {
    return 'A projeção de $category é $projected, $percent% em comparação com o mês anterior.';
  }

  @override
  String budgetForecastInsight(String name, String projected, String limit) {
    return 'No ritmo atual, $name está projetado em $projected para um limite de $limit.';
  }

  @override
  String cashFlowForecastInsight(int days, String closing) {
    return 'A estimativa local de fluxo de caixa para $days dias termina em $closing.';
  }

  @override
  String recurringCommitmentsInsight(int count, String total) {
    return 'Há previsão de $count despesas recorrentes, somando $total, neste período.';
  }

  @override
  String goalContributionInsight(String name, String gap) {
    return 'Para manter o prazo de $name, a contribuição mensal pode precisar de mais $gap.';
  }

  @override
  String emergencyFundInsight(String months, String average) {
    return 'Os recursos líquidos cobrem cerca de $months meses pela média recente de despesas de $average.';
  }

  @override
  String debtOverviewInsight(String debt, String percent) {
    return 'A dívida registrada é $debt, equivalente a $percent% dos ativos registrados.';
  }

  @override
  String netWorthTrendInsight(String change, String percent, int months) {
    return 'O patrimônio variou $change ($percent%) em $months pontos do relatório.';
  }

  @override
  String investmentConcentrationInsight(String name, String percent) {
    return '$name representa $percent% dos investimentos com cotação.';
  }

  @override
  String get cloudAccountTitle => 'Conta Equis na nuvem';

  @override
  String get cloudAccountSettingsSubtitle =>
      'Login opcional, verificação e identidade do dispositivo';

  @override
  String get createEquisAccountAction => 'Criar Conta Equis';

  @override
  String get continueOfflineAction => 'Continuar Offline';

  @override
  String get cloudAccountIntro =>
      'A identidade na nuvem é opcional. Seu cofre atual continua local e mantém o mesmo identificador.';

  @override
  String get emailLabel => 'E-mail';

  @override
  String get passwordLabel => 'Senha';

  @override
  String get signInAction => 'Entrar';

  @override
  String get signOutAction => 'Sair';

  @override
  String get awaitingVerificationTitle => 'Verifique seu e-mail';

  @override
  String awaitingVerificationBody(String email) {
    return 'Uma mensagem de verificação foi enviada para $email. Depois de verificar, entre para vincular este cofre local.';
  }

  @override
  String get resendVerificationAction => 'Reenviar e-mail de verificação';

  @override
  String get cloudSignedInTitle => 'Conta na nuvem conectada';

  @override
  String cloudSignedInBody(String email) {
    return 'Conectado como $email. O identificador do cofre local foi preservado.';
  }

  @override
  String get localAccessPreservedMessage =>
      'A sessão na nuvem está indisponível ou desconectada. O acesso ao cofre local continua disponível.';

  @override
  String get cloudNotConfiguredMessage =>
      'O Supabase não está configurado nesta versão. Você pode continuar usando todos os recursos locais offline.';

  @override
  String get cloudSyncEncryptionPendingMessage =>
      'A sincronização segura fica desligada até você exportar e confirmar a chave de recuperação do cofre.';

  @override
  String get secureSyncTitle => 'Sincronização segura';

  @override
  String get secureSyncDisabledBody =>
      'Seus dados permanecem locais até você ativar a sincronização criptografada de ponta a ponta.';

  @override
  String get enableSecureSyncAction => 'Ativar sincronização segura';

  @override
  String get recoverySecretTitle => 'Salve sua chave de recuperação';

  @override
  String get recoverySecretBody =>
      'Guarde esta chave em um local seguro. Ela é necessária para abrir o cofre criptografado em um novo dispositivo e a Equis não consegue recuperá-la por você.';

  @override
  String get copyRecoverySecretAction => 'Copiar chave de recuperação';

  @override
  String get recoverySecretCopiedMessage => 'Chave de recuperação copiada';

  @override
  String get confirmRecoverySavedAction => 'Salvei a chave de recuperação';

  @override
  String get syncStatusSynced => 'Sincronizado';

  @override
  String get syncStatusOffline =>
      'Offline — as alterações pendentes continuam seguras neste dispositivo';

  @override
  String get syncStatusError => 'A sincronização precisa de atenção';

  @override
  String get syncStatusReady => 'Pronto para sincronizar';

  @override
  String syncDiagnostics(int pushed, int pulled, int conflicts) {
    return 'Últimas 24 horas: $pushed enviados · $pulled recebidos · $conflicts conflitos';
  }

  @override
  String get retrySyncAction => 'Sincronizar agora';

  @override
  String get syncConflictsTitle => 'Conflitos que exigem revisão';

  @override
  String syncConflictBody(
    String entityType,
    String recordId,
    int localRevision,
    int remoteRevision,
  ) {
    return '$entityType · $recordId · revisão local $localRevision, revisão remota $remoteRevision';
  }

  @override
  String get keepLocalAction => 'Manter local';

  @override
  String get keepRemoteAction => 'Manter remoto';

  @override
  String deviceIdentityLabel(String name, String platform, String identifier) {
    return 'Dispositivo: $name · $platform · $identifier';
  }

  @override
  String get authInvalidCredentialsMessage =>
      'O e-mail ou a senha está incorreto.';

  @override
  String get authEmailNotVerifiedMessage =>
      'Verifique seu e-mail antes de entrar.';

  @override
  String get authWeakPasswordMessage => 'Escolha uma senha mais forte.';

  @override
  String get authAccountExistsMessage =>
      'Já existe uma conta para este e-mail. Tente entrar.';

  @override
  String get authRateLimitedMessage =>
      'Muitas tentativas. Aguarde um momento e tente novamente.';

  @override
  String get authNetworkMessage =>
      'O serviço de nuvem está inacessível. O acesso local não foi afetado.';

  @override
  String get authVaultMismatchMessage =>
      'Este cofre já está vinculado a outra conta na nuvem.';

  @override
  String get authUnknownMessage =>
      'Não foi possível concluir a operação da conta na nuvem.';

  @override
  String get portabilityTitle => 'Backup e exportação';

  @override
  String get portabilitySubtitle =>
      'Backups criptografados e exportações abertas com confirmação';

  @override
  String get createEncryptedBackupAction => 'Criar backup criptografado';

  @override
  String get encryptedBackupDescription =>
      'Cria um arquivo .equis protegido por senha com os dados e anexos do cofre.';

  @override
  String get validateBackupAction => 'Validar um backup';

  @override
  String get validateBackupDescription =>
      'Confere senha, formato, integridade e compatibilidade sem restaurar.';

  @override
  String get restoreBackupAction => 'Restaurar backup';

  @override
  String get restoreBackupDescription =>
      'Reconstrói um cofre e os vínculos dos anexos neste perfil vazio.';

  @override
  String get restoreRequiresCleanProfileMessage =>
      'A restauração só fica disponível antes de criar um cofre neste perfil.';

  @override
  String get exportJsonAction => 'Exportar cofre como JSON';

  @override
  String get exportCsvAction => 'Exportar transações como CSV';

  @override
  String get plaintextExportDescription =>
      'Exporta os dados lógicos do cofre sem criptografia.';

  @override
  String get transactionCsvDescription =>
      'Exporta valores mínimos exatos, moedas, movimentos, divisões, etiquetas e conversões.';

  @override
  String get backupCreatedMessage => 'Backup criptografado criado.';

  @override
  String get backupValidMessage => 'O backup é autêntico e compatível.';

  @override
  String get backupRestoredMessage => 'Backup restaurado com sucesso.';

  @override
  String get restoreBackupConfirmation =>
      'Restaurar este backup no perfil local vazio? Identificadores e relações serão preservados.';

  @override
  String get plaintextPrivacyWarningTitle =>
      'Dados financeiros sem criptografia';

  @override
  String get plaintextPrivacyWarningBody =>
      'Esta exportação não é criptografada. Ela pode conter valores, descrições, contas e outros dados financeiros privados. Guarde-a em local seguro.';

  @override
  String get continueExportAction => 'Exportar mesmo assim';

  @override
  String get exportCompletedMessage => 'Exportação aberta criada.';

  @override
  String get backupPasswordTitle => 'Senha do backup';

  @override
  String get confirmPasswordLabel => 'Confirmar senha';

  @override
  String get backupPasswordValidationMessage =>
      'Use pelo menos 12 caracteres e digite senhas iguais.';

  @override
  String get portabilityErrorMessage =>
      'Não foi possível concluir a operação. Confira o arquivo, a senha e o destino.';

  @override
  String get receiptAttachmentsTitle => 'Comprovantes e anexos';

  @override
  String get addAttachmentAction => 'Anexar comprovante ou arquivo';

  @override
  String get noAttachmentsMessage => 'Nenhum arquivo anexado a esta transação.';

  @override
  String get exportAttachmentAction => 'Descriptografar e salvar uma cópia';

  @override
  String attachmentSizeLabel(int bytes) {
    return '$bytes bytes · criptografado neste dispositivo';
  }

  @override
  String get attachmentAddedMessage => 'O arquivo foi criptografado e anexado.';

  @override
  String get attachmentExportedMessage => 'Cópia descriptografada salva.';

  @override
  String get attachmentErrorMessage =>
      'Não foi possível concluir a operação com o anexo.';

  @override
  String accountNatureLabel(String nature) {
    String _temp0 = intl.Intl.selectLogic(nature, {
      'asset': 'Ativo',
      'liability': 'Passivo',
      'other': 'Conta',
    });
    return '$_temp0';
  }

  @override
  String physicalAssetTypeLabel(String type) {
    String _temp0 = intl.Intl.selectLogic(type, {
      'property': 'Imóvel',
      'vehicle': 'Veículo',
      'collectible': 'Colecionável',
      'equipment': 'Equipamento',
      'valuablePossession': 'Bem valioso',
      'other': 'Outro',
    });
    return '$_temp0';
  }

  @override
  String investmentAssetClassLabel(String assetClass) {
    String _temp0 = intl.Intl.selectLogic(assetClass, {
      'stock': 'Ação',
      'etf': 'ETF',
      'fund': 'Fundo',
      'reit': 'REIT',
      'fii': 'FII',
      'bond': 'Título',
      'fixedIncome': 'Renda fixa',
      'crypto': 'Criptomoeda',
      'commodity': 'Commodity',
      'cashEquivalent': 'Equivalente de caixa',
      'other': 'Outro',
    });
    return '$_temp0';
  }

  @override
  String syncEntityTypeLabel(String entityType) {
    String _temp0 = intl.Intl.selectLogic(entityType, {
      'vault': 'Cofre',
      'account': 'Conta',
      'category': 'Categoria',
      'counterparty': 'Contraparte',
      'tag': 'Etiqueta',
      'transaction': 'Transação',
      'recurring_rule': 'Regra recorrente',
      'installment_plan': 'Plano de parcelas',
      'credit_card_statement': 'Fatura de cartão',
      'budget': 'Orçamento',
      'goal': 'Meta',
      'asset': 'Bem',
      'investment_instrument': 'Instrumento de investimento',
      'manual_fx_rate': 'Câmbio manual',
      'manual_market_price': 'Preço manual',
      'attachment': 'Anexo',
      'other': 'Registro',
    });
    return '$_temp0';
  }

  @override
  String get refreshAction => 'Atualizar';

  @override
  String get clearValueAction => 'Limpar valor';

  @override
  String get lastBackupLabel => 'Último backup';

  @override
  String get spendingByTagTitle => 'Despesas por tag';

  @override
  String get withoutTagsLabel => 'Sem tags';

  @override
  String get tagOverlapMessage =>
      'Cada despesa conta integralmente em cada tag. Os totais das tags podem se sobrepor.';

  @override
  String get syncRunningLabel => 'Sincronizando...';

  @override
  String get syncPendingLabel => 'Alterações pendentes';

  @override
  String get syncAutomaticPolicy =>
      'As alterações sincronizam automaticamente enquanto o app está aberto. Conflitos mantêm a maior revisão; revisões iguais usam a data da edição e, em novo empate, um critério consistente pelo conteúdo.';

  @override
  String get syncLastSuccessLabel => 'Última sincronização concluída';

  @override
  String get syncNeverLabel => 'Ainda não concluída';

  @override
  String get syncNetworkHelp =>
      'Verifique a conexão e tente novamente. Suas alterações continuam neste dispositivo.';

  @override
  String get syncSessionHelp =>
      'Sua sessão expirou. Entre novamente com a mesma conta.';

  @override
  String get syncAccessHelp =>
      'Esta conta ou dispositivo não tem acesso ao cofre na nuvem. Confira se está usando a conta original.';

  @override
  String get syncCompatibilityHelp =>
      'O app e o servidor de sincronização são incompatíveis. Confira a versão do app e as migrações do servidor.';

  @override
  String get syncPayloadHelp =>
      'Um registro pendente não pôde ser processado. Mantenha seus dados e informe o código de diagnóstico.';

  @override
  String get syncCryptoHelp =>
      'Não foi possível descriptografar os dados da nuvem. Guarde sua chave de recuperação e informe o código de diagnóstico.';

  @override
  String get syncLocalHelp =>
      'Uma operação local de sincronização falhou. Tente novamente; se persistir, informe o código de diagnóstico.';

  @override
  String get syncRemoteHelp =>
      'O servidor não conseguiu concluir a solicitação. Tente novamente mais tarde.';

  @override
  String get vaultsTitle => 'Cofres e conta';

  @override
  String get localVaultsLabel => 'Cofres neste aparelho';

  @override
  String get newVaultAction => 'Novo cofre';

  @override
  String get legacyVaultNotice =>
      'Cópia local da versão de testes. Use seu cofre já migrado para sincronizar.';

  @override
  String get vaultKeyLabel => 'Chave do cofre';

  @override
  String get vaultKeyExplanation =>
      'Esta chave abre este cofre. Guarde-a em local seguro. Ela não é a senha da conta nem a senha do backup.';

  @override
  String get showVaultKeyAction => 'Mostrar chave do cofre';

  @override
  String get vaultSyncAction => 'Sincronizar cofre ativo';

  @override
  String get accountCloudVaultsLabel => 'Conta e cofres na nuvem';

  @override
  String get vaultOwnerExplanation =>
      'Você pode abrir backups offline. Para sincronizar, entre na conta proprietária. O primeiro envio vincula permanentemente o cofre à conta.';

  @override
  String get accountEmailLabel => 'E-mail da conta';

  @override
  String get accountPasswordLabel => 'Senha da conta';

  @override
  String get accountSignInAction => 'Entrar na conta';

  @override
  String get accountSignOutAction => 'Sair da conta';

  @override
  String get refreshVaultsAction => 'Atualizar lista de cofres';

  @override
  String get noCloudVaultsMessage =>
      'Nenhum cofre do novo formato nesta conta.';

  @override
  String get restoreCloudVaultAction => 'Restaurar cofre da nuvem';

  @override
  String get vaultOperationFailed =>
      'Não foi possível concluir. Confira a conta proprietária, a chave do cofre, a senha do backup e a conexão. Seus cofres existentes foram preservados.';

  @override
  String get restoreAddsVaultMessage =>
      'Adiciona o cofre do backup sem substituir os cofres locais existentes.';

  @override
  String get legacyBackupUnsupportedMessage =>
      'Use o backup do cofre que você já migrou. Este arquivo antigo pertence à versão de testes.';

  @override
  String get updatesTitle => 'Atualizações do aplicativo';

  @override
  String get updateAvailable => 'Versão disponível';

  @override
  String get updateChecking => 'Verificando atualizações…';

  @override
  String get updateWaitingWifi => 'Aguardando Wi-Fi';

  @override
  String get updateDownloading => 'Baixando atualização…';

  @override
  String get updateReady => 'Atualização verificada e pronta para instalar.';

  @override
  String get updateFailed =>
      'Atualização indisponível ou falha na verificação. Tente novamente; seus dados foram preservados.';

  @override
  String get updateInstalling => 'Preparando instalação…';

  @override
  String get updateCheckHint =>
      'As verificações acontecem com o Equis aberto, a cada seis horas.';

  @override
  String get updateAutomatic => 'Baixar atualizações automaticamente';

  @override
  String get updateCheck => 'Verificar atualizações';

  @override
  String get updateDownloadNow => 'Baixar agora (qualquer conexão)';

  @override
  String get updateInstall => 'Instalar atualização';

  @override
  String get updateInstallConfirm =>
      'Instalar a atualização verificada? No Windows, o Equis será fechado e reaberto. Guarde seu backup; não desinstale o app.';

  @override
  String get updateLater => 'Mais tarde';

  @override
  String get updatePermission =>
      'Permita instalar pelo Equis nas configurações do Android e toque novamente em Instalar atualização.';

  @override
  String get updateRecoveryRequired =>
      'Uma substituição de arquivos do Equis está em andamento ou foi interrompida. Feche esta janela. Se a atualização não concluir, use o auxiliar de recuperação conforme as instruções da versão. Seus cofres não foram abertos.';
}
