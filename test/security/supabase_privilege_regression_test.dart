import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const authenticatedSyncFunctions = {
    'public.register_vault(uuid,uuid,text)',
    'public.apply_sync_batch(uuid,jsonb,text)',
    'public.acknowledge_sync_cursor(uuid,uuid,bigint)',
    'equis_private.register_vault(uuid,uuid,text)',
    'equis_private.apply_sync_batch(uuid,jsonb,text)',
    'equis_private.acknowledge_sync_cursor(uuid,uuid,bigint)',
  };
  late List<File> migrations;
  late String repair;

  setUpAll(() {
    migrations =
        Directory('supabase/migrations')
            .listSync()
            .whereType<File>()
            .where((file) => file.path.endsWith('.sql'))
            .toList()
          ..sort((left, right) => left.path.compareTo(right.path));
    repair = migrations
        .singleWhere(
          (file) =>
              file.path.endsWith('restore_authenticated_sync_schema_usage.sql'),
        )
        .readAsStringSync()
        .toLowerCase();
  });

  test('final migration state preserves the private sync schema boundary', () {
    final explicitUsage = <String, bool>{
      'public': false,
      'anon': false,
      'authenticated': false,
    };
    final authenticatedExecute = <String, bool>{
      for (final function in authenticatedSyncFunctions) function: false,
    };
    final privilegeStatement = RegExp(
      r'\b(grant\s+usage|revoke\s+(?:all|usage))\s+on\s+schema\s+'
      r'equis_private\s+(?:to|from)\s+([^;]+);',
      caseSensitive: false,
    );
    final functionPrivilegeStatement = RegExp(
      r'\b(grant\s+execute|revoke\s+(?:all|execute))\s+on\s+function\s+'
      r'(.+?)\s+(?:to|from)\s+([^;]+);',
      caseSensitive: false,
      dotAll: true,
    );
    final dropFunctionStatement = RegExp(
      r'\bdrop\s+function(?:\s+if\s+exists)?\s+([^;]+);',
      caseSensitive: false,
      dotAll: true,
    );
    final broadPrivateFunctionPrivilege = RegExp(
      r'\b(grant\s+execute|revoke\s+(?:all|execute))\s+on\s+all\s+'
      r'functions\s+in\s+schema\s+equis_private\s+(?:to|from)\s+([^;]+);',
      caseSensitive: false,
    );
    final dropPrivateSchema = RegExp(
      r'\bdrop\s+schema(?:\s+if\s+exists)?\s+equis_private\b',
      caseSensitive: false,
    );

    for (final migration in migrations) {
      final sql = migration.readAsStringSync();
      for (final match in privilegeStatement.allMatches(sql)) {
        final grant = match.group(1)!.toLowerCase().startsWith('grant');
        final roles = match
            .group(2)!
            .toLowerCase()
            .split(',')
            .map((role) => role.trim())
            .toSet();
        for (final role in explicitUsage.keys) {
          if (roles.contains(role)) explicitUsage[role] = grant;
        }
      }

      for (final match in broadPrivateFunctionPrivilege.allMatches(sql)) {
        final grant = match.group(1)!.toLowerCase().startsWith('grant');
        final roles = match
            .group(2)!
            .toLowerCase()
            .split(',')
            .map((role) => role.trim())
            .toSet();
        if (!roles.contains('authenticated')) continue;
        expect(
          grant,
          isFalse,
          reason: '${migration.path} must grant only the explicit allowlist',
        );
        for (final function in authenticatedExecute.keys.where(
          (function) => function.startsWith('equis_private.'),
        )) {
          authenticatedExecute[function] = false;
        }
      }
      for (final match in functionPrivilegeStatement.allMatches(sql)) {
        final grant = match.group(1)!.toLowerCase().startsWith('grant');
        final functions = match
            .group(2)!
            .toLowerCase()
            .replaceAll(RegExp(r'\s+'), '');
        final roles = match
            .group(3)!
            .toLowerCase()
            .split(',')
            .map((role) => role.trim())
            .toSet();
        if (!roles.contains('authenticated')) continue;
        for (final function in authenticatedExecute.keys) {
          if (functions.contains(function)) {
            authenticatedExecute[function] = grant;
          }
        }
      }
      for (final match in dropFunctionStatement.allMatches(sql)) {
        final functions = match
            .group(1)!
            .toLowerCase()
            .replaceAll(RegExp(r'\s+'), '');
        for (final function in authenticatedExecute.keys) {
          if (functions.contains(function)) {
            authenticatedExecute[function] = false;
          }
        }
      }
      if (dropPrivateSchema.hasMatch(sql)) {
        explicitUsage['authenticated'] = false;
        for (final function in authenticatedExecute.keys.where(
          (function) => function.startsWith('equis_private.'),
        )) {
          authenticatedExecute[function] = false;
        }
      }
    }

    expect(explicitUsage['authenticated'], isTrue);
    expect(explicitUsage['anon'], isFalse);
    expect(explicitUsage['public'], isFalse);
    for (final entry in authenticatedExecute.entries) {
      expect(
        entry.value,
        isTrue,
        reason: '${entry.key} must remain executable',
      );
    }
  });

  test('repair migration fails closed when the sync allowlist drifts', () {
    expect(
      repair,
      contains('grant usage on schema equis_private to authenticated'),
    );
    expect(repair, contains("has_schema_privilege("));
    expect(repair, contains("'anon', 'equis_private', 'usage'"));
    for (final function in authenticatedSyncFunctions) {
      expect(repair, contains(function), reason: function);
    }
  });
}
