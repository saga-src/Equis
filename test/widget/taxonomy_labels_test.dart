import 'package:equis/domain/entities/category_node.dart';
import 'package:equis/domain/shared/utc_instant.dart';
import 'package:equis/domain/shared/uuid_v7.dart';
import 'package:equis/domain/taxonomy/tag.dart';
import 'package:equis/l10n/app_localizations.dart';
import 'package:equis/presentation/formatting/taxonomy_labels.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('system and user taxonomy labels follow locale with fallback', (
    tester,
  ) async {
    final vaultId = EntityId.generate();
    const now = UtcInstant.fromEpochMicroseconds(1);
    final system = CategoryNode(
      id: EntityId.generate(),
      vaultId: vaultId,
      type: CategoryType.expense,
      systemKey: 'category.food',
      createdAt: now,
      updatedAt: now,
    );
    final custom = CategoryNode(
      id: EntityId.generate(),
      vaultId: vaultId,
      type: CategoryType.expense,
      customName: 'Fallback category',
      customNameEnUs: 'Groceries',
      customNamePtBr: 'Mercado',
      createdAt: now,
      updatedAt: now,
    );
    final fallbackTag = Tag(
      id: EntityId.generate(),
      vaultId: vaultId,
      name: 'Fallback tag',
      nameEnUs: 'Essential',
      createdAt: now,
      updatedAt: now,
    );

    await _pump(tester, const Locale('en', 'US'), system, custom, fallbackTag);
    expect(find.text('Food|Groceries|Essential'), findsOneWidget);

    await _pump(tester, const Locale('pt', 'BR'), system, custom, fallbackTag);
    expect(find.text('Alimentação|Mercado|Fallback tag'), findsOneWidget);
  });
}

Future<void> _pump(
  WidgetTester tester,
  Locale locale,
  CategoryNode system,
  CategoryNode custom,
  Tag tag,
) => tester.pumpWidget(
  MaterialApp(
    locale: locale,
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: Builder(
      builder: (context) => Text(
        '${categoryLabel(context, system)}|'
        '${categoryLabel(context, custom)}|${tagLabel(context, tag)}',
      ),
    ),
  ),
);
