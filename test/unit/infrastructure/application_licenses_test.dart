import 'dart:convert';
import 'package:equis/infrastructure/settings/application_licenses.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'only exclusive development packages are omitted; mixed and native notices remain',
    () async {
      final entry = LicenseEntryWithLineBreaks([
        'analyzer',
        'sqlite3',
      ], 'Copyright A\n\nLicense A');
      final licenses = await groupApplicationLicenses(
        Stream.fromIterable([
          entry,
          entry,
          LicenseEntryWithLineBreaks(['sqlite3'], 'Copyright B\n\nLicense B'),
          LicenseEntryWithLineBreaks(['build_runner'], 'Build tool notice'),
          LicenseEntryWithLineBreaks([
            'Native engine component',
          ], 'Native notice'),
        ]),
        {'analyzer', 'build_runner'},
      );
      expect(
        licenses.keys,
        unorderedEquals(['sqlite3', 'Native engine component']),
      );
      expect(licenses['sqlite3'], hasLength(2));
      expect(licenses['sqlite3']!.first.paragraphs.map((p) => p.text), [
        'Copyright A',
        'License A',
      ]);
    },
  );
  test(
    'metadata filters development notices and missing/corrupt metadata preserves all',
    () async {
      for (final metadata in [
        '{"format_version":1,"development_only_packages":["drift_dev"]}',
        '{"format_version":2,"development_only_packages":["drift_dev"]}',
        'invalid',
        null,
      ]) {
        final licenses = await loadApplicationLicenses(
          bundle: _Bundle(metadata),
          entries: Stream.fromIterable([
            LicenseEntryWithLineBreaks(['drift', 'drift_dev'], 'Shared notice'),
          ]),
        );
        expect(licenses.containsKey('drift'), isTrue);
        expect(
          licenses.containsKey('drift_dev'),
          metadata?.contains('"format_version":1') != true,
        );
      }
    },
  );
}

class _Bundle extends CachingAssetBundle {
  _Bundle(this.metadata);
  final String? metadata;
  @override
  Future<ByteData> load(String key) async {
    if (metadata == null) throw StateError('Missing asset');
    return ByteData.sublistView(Uint8List.fromList(utf8.encode(metadata!)));
  }
}
