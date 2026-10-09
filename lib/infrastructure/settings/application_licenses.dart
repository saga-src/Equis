import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

Future<Map<String, List<LicenseEntry>>> loadApplicationLicenses({
  AssetBundle? bundle,
  Stream<LicenseEntry>? entries,
}) async {
  Set<String> developmentOnly;
  try {
    final metadata =
        jsonDecode(
              await (bundle ?? rootBundle).loadString(
                'assets/licenses/package_scopes.json',
              ),
            )
            as Map;
    if (metadata['format_version'] != 1) {
      throw const FormatException('License metadata version');
    }
    developmentOnly = (metadata['development_only_packages'] as List)
        .cast<String>()
        .toSet();
  } catch (_) {
    // Missing/corrupt metadata must never hide notices.
    developmentOnly = {};
  }
  return groupApplicationLicenses(
    entries ?? LicenseRegistry.licenses,
    developmentOnly,
  );
}

Future<Map<String, List<LicenseEntry>>> groupApplicationLicenses(
  Stream<LicenseEntry> entries,
  Set<String> developmentOnly,
) async {
  final grouped = <String, List<LicenseEntry>>{};
  final seen = <String, Set<String>>{};
  await for (final entry in entries) {
    final signature = jsonEncode([
      for (final paragraph in entry.paragraphs)
        [paragraph.text, paragraph.indent],
    ]);
    for (final package in entry.packages) {
      if (developmentOnly.contains(package)) continue;
      if (!(seen[package] ??= {}).add(signature)) continue;
      (grouped[package] ??= []).add(entry);
    }
  }
  return grouped;
}
