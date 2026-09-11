import 'package:equis/domain/entities/category_node.dart';
import 'package:equis/domain/taxonomy/tag.dart';
import 'package:equis/l10n/app_localizations.dart';
import 'package:flutter/widgets.dart';

String categoryLabel(BuildContext context, CategoryNode category) {
  final l10n = AppLocalizations.of(context);
  if (category.systemKey == null) {
    return _localizedCustomName(
      context,
      fallback: category.customName ?? '',
      enUs: category.customNameEnUs,
      ptBr: category.customNamePtBr,
    );
  }
  return switch (category.systemKey) {
    'category.expenses' => l10n.categoryExpensesLabel,
    'category.food' => l10n.categoryFoodLabel,
    'category.housing' => l10n.categoryHousingLabel,
    'category.transport' => l10n.categoryTransportLabel,
    'category.income' => l10n.categoryIncomeLabel,
    'category.salary' => l10n.categorySalaryLabel,
    'category.other_income' => l10n.categoryOtherIncomeLabel,
    _ => category.systemKey!,
  };
}

String tagLabel(BuildContext context, Tag tag) => _localizedCustomName(
  context,
  fallback: tag.name,
  enUs: tag.nameEnUs,
  ptBr: tag.namePtBr,
);

String _localizedCustomName(
  BuildContext context, {
  required String fallback,
  String? enUs,
  String? ptBr,
}) {
  final localized = Localizations.localeOf(context).languageCode == 'pt'
      ? ptBr
      : enUs;
  return localized == null || localized.trim().isEmpty
      ? fallback
      : localized.trim();
}
