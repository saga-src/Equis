import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:equis/infrastructure/updates/update_manifest.dart';
import 'package:equis/infrastructure/updates/update_public_key.dart';

Future<void> main(List<String> args) async {
  if (!await runUpdate(args)) exitCode = 1;
}

Future<bool> runUpdate(
  List<String> args, {
  String publicKey = updatePublicKey,
  Future<void> Function(String)? launch,
}) async {
  if (args.length < 5) {
    throw ArgumentError('prepare|apply <cache> <target> <platform> <pid>');
  }
  final cache = Directory(args[1]).absolute;
  final target = Directory(args[2]).absolute;
  final platform = args[3];
  final journal = File(p.join(cache.path, 'installation.json'));
  try {
    await rejectLinks(target.path);
    await rejectLinks(cache.path);
    if (p.isWithin(target.path, cache.path) ||
        p.equals(target.path, cache.path)) {
      throw const FormatException('Helper must be outside installation');
    }
    if (args[0] == 'recover') {
      await recoverInterrupted(cache, target);
      return true;
    }
    if (args[0] == 'prepare') await recoverInterrupted(cache, target);
    final manifest = await UpdateManifest.verify(
      await File(p.join(cache.path, 'manifest.json')).readAsBytes(),
      base64Decode(
        (await File(p.join(cache.path, 'manifest.sig')).readAsString()).trim(),
      ),
      base64Decode(publicKey),
    );
    final package = manifest.packages
        .where((x) => x.platform == platform)
        .single;
    final installed =
        jsonDecode(
              await File(
                p.join(target.path, 'app-version.json'),
              ).readAsString(),
            )
            as Map<String, dynamic>;
    if (manifest.version.compareTo(
          UpdateVersion(
            installed['version'] as String,
            installed['build'] as int,
          ),
        ) <=
        0) {
      throw const FormatException('Update is not newer than installed build');
    }
    final payload = File(p.join(cache.path, package.name));
    await package.validate(payload);
    final stage = Directory(
      p.join(cache.path, 'stage-${manifest.version.build}'),
    );
    final backup = Directory(
      p.join(cache.path, 'previous-${manifest.version.build}'),
    );
    await rejectLinks(stage.path);
    await rejectLinks(backup.path);
    if (args[0] == 'prepare') {
      if (platform == 'windows-portable') {
        if (await stage.exists()) await stage.delete(recursive: true);
        await stage.create(recursive: true);
        final archive = ZipDecoder().decodeBytes(
          await payload.readAsBytes(),
          verify: true,
        );
        final names = <String>{};
        var expanded = 0;
        for (final entry in archive) {
          final name = safeName(entry.name);
          if (!names.add(name.toLowerCase()) || entry.isSymbolicLink) {
            throw const FormatException('Duplicate or link');
          }
          expanded += entry.size;
          if (expanded > 4294967296) {
            throw const FormatException('Expanded package too large');
          }
          final path = p.join(stage.path, name);
          await rejectLinks(p.join(target.path, name));
          if (entry.isFile) {
            await File(path).parent.create(recursive: true);
            await File(path).writeAsBytes(entry.content, flush: true);
          } else {
            await Directory(path).create(recursive: true);
          }
        }
        if (!await File(p.join(stage.path, 'equis.exe')).exists() ||
            !await File(p.join(stage.path, 'app-files.json')).exists()) {
          throw const FormatException('Missing app inventory');
        }
        final inventory = await readInventory(stage);
        final stagedVersion =
            jsonDecode(
                  await File(
                    p.join(stage.path, 'app-version.json'),
                  ).readAsString(),
                )
                as Map<String, dynamic>;
        if (manifest.version.build != stagedVersion['build'] ||
            manifest.version.compareTo(
                  UpdateVersion(
                    stagedVersion['version'] as String,
                    stagedVersion['build'] as int,
                  ),
                ) !=
                0) {
          throw const FormatException('Package version differs from manifest');
        }
        final files = archive
            .where((e) => e.isFile)
            .map((e) => safeName(e.name).toLowerCase())
            .toSet();
        if (inventory
                .map((s) => s.toLowerCase())
                .toSet()
                .difference(files)
                .isNotEmpty ||
            files.difference({
              ...inventory.map((s) => s.toLowerCase()),
              'app-files.json',
            }).isNotEmpty) {
          throw const FormatException('Inventory mismatch');
        }
      }
      await writeJournal(
        journal,
        jsonEncode({
          'state': 'prepared',
          'target': target.path,
          'build': manifest.version.build,
        }),
        flush: true,
      );
      return true;
    }
    if (args[0] != 'apply') throw ArgumentError('Unknown command');
    final previousJournal =
        jsonDecode(await journal.readAsString()) as Map<String, dynamic>;
    if (previousJournal['state'] != 'prepared' ||
        previousJournal['target'] != target.path ||
        previousJournal['build'] != manifest.version.build) {
      throw StateError('Not prepared');
    }
    final pid = int.parse(args[4]);
    var stopped = false;
    for (var attempt = 0; attempt < 600; attempt++) {
      final processes = await Process.run('tasklist.exe', [
        '/FI',
        'PID eq $pid',
        '/FO',
        'CSV',
        '/NH',
      ]);
      if (!processes.stdout.toString().contains('"$pid"')) {
        stopped = true;
        break;
      }
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    if (!stopped) throw StateError('App still running');
    if (platform == 'windows-installed') {
      final install = await Process.run(payload.path, [
        '/VERYSILENT',
        '/SUPPRESSMSGBOXES',
        '/NORESTART',
        '/DIR=${target.path}',
      ]);
      if (install.exitCode != 0) throw StateError('Installer failed');
    } else {
      // Validate staged bytes against the authenticated archive again, before
      // replacing anything. A stale or modified staging tree is not trusted.
      final archive = ZipDecoder().decodeBytes(
        await payload.readAsBytes(),
        verify: true,
      );
      for (final entry in archive.where((e) => e.isFile)) {
        final staged = File(p.join(stage.path, safeName(entry.name)));
        await rejectLinks(staged.path);
        final bytes = await staged.readAsBytes();
        final expected = entry.content;
        if (bytes.length != expected.length) {
          throw const FormatException('Staging changed');
        }
        for (var i = 0; i < bytes.length; i++) {
          if (bytes[i] != expected[i]) {
            throw const FormatException('Staging changed');
          }
        }
      }
      final next = {...await readInventory(stage), 'app-files.json'};
      final old = await File(p.join(target.path, 'app-files.json')).exists()
          ? {...await readInventory(target), 'app-files.json'}
          : <String>{};
      final touched = {...old, ...next};
      final existed = <String>[];
      await backup.create(recursive: true);
      for (final name in touched) {
        await rejectLinks(p.join(target.path, name));
        final file = File(p.join(target.path, name));
        if (await file.exists()) {
          final copy = File(p.join(backup.path, name));
          await copy.parent.create(recursive: true);
          await file.copy(copy.path);
          existed.add(name);
        }
      }
      await writeJournal(
        journal,
        jsonEncode({
          'state': 'replacing',
          'target': target.path,
          'backup': backup.path,
          'files': touched.toList(),
          'existed': existed,
        }),
        flush: true,
      );
      try {
        for (final name in touched) {
          final destination = File(p.join(target.path, name));
          if (next.contains(name)) {
            await destination.parent.create(recursive: true);
            await File(p.join(stage.path, name)).copy(destination.path);
          } else if (await destination.exists()) {
            await destination.delete();
          }
        }
      } catch (_) {
        for (final name in touched) {
          final destination = File(p.join(target.path, name));
          if (existed.contains(name)) {
            await File(p.join(backup.path, name)).copy(destination.path);
          } else if (await destination.exists()) {
            await destination.delete();
          }
        }
        rethrow;
      }
    }
    // Persist before launching: recovery must never roll back a potentially migrated DB.
    await writeJournal(
      journal,
      jsonEncode({
        'state': 'launching',
        'target': target.path,
        'build': manifest.version.build,
      }),
      flush: true,
    );
    if (launch != null) {
      await launch(target.path);
    } else {
      await Process.start(
        p.join(target.path, 'equis.exe'),
        [],
        mode: ProcessStartMode.detached,
        workingDirectory: target.path,
      );
    }
    await writeJournal(
      journal,
      jsonEncode({'state': 'launched', 'build': manifest.version.build}),
      flush: true,
    );
    return true;
  } catch (_) {
    await File(
      p.join(cache.path, 'installation-error.txt'),
    ).writeAsString('update_installation_failed');
    return false;
  }
}

/// Only incomplete file replacement can be rolled back. Once launch has been
/// attempted, the new binary may have migrated the database.
Future<void> recoverInterrupted(Directory cache, Directory target) async {
  final journal = File(p.join(cache.path, 'installation.json'));
  if (!await journal.exists()) return;
  final value =
      jsonDecode(await journal.readAsString()) as Map<String, dynamic>;
  if (value['state'] != 'replacing') return;
  if (value['target'] != target.path) {
    throw const FormatException('Recovery target mismatch');
  }
  final backup = Directory(value['backup'] as String);
  if (!p.isWithin(cache.path, backup.path)) {
    throw const FormatException('Recovery path mismatch');
  }
  await rejectLinks(backup.path);
  final existed = (value['existed'] as List)
      .cast<String>()
      .map(safeName)
      .toSet();
  for (final item in (value['files'] as List).cast<String>()) {
    final name = safeName(item);
    final destination = File(p.join(target.path, name));
    await rejectLinks(destination.path);
    if (existed.contains(name)) {
      final source = File(p.join(backup.path, name));
      await rejectLinks(source.path);
      await destination.parent.create(recursive: true);
      await source.copy(destination.path);
    } else if (await destination.exists()) {
      await destination.delete();
    }
  }
  await writeJournal(
    journal,
    jsonEncode({'state': 'recovered', 'target': target.path}),
    flush: true,
  );
}

String safeName(String value) {
  final normalized = value.replaceAll('\\', '/');
  if (normalized.isEmpty ||
      normalized.startsWith('/') ||
      normalized.contains(':') ||
      normalized
          .split('/')
          .any(
            (s) =>
                s == '..' ||
                s == '.' ||
                s.endsWith(' ') ||
                s.endsWith('.') ||
                RegExp(
                  r'^(con|prn|aux|nul|com[1-9]|lpt[1-9])(?:\.|$)',
                  caseSensitive: false,
                ).hasMatch(s),
          )) {
    throw const FormatException('Unsafe archive path');
  }
  return p.normalize(normalized);
}

Future<List<String>> readInventory(Directory root) async {
  final names =
      (jsonDecode(
                await File(p.join(root.path, 'app-files.json')).readAsString(),
              )
              as List)
          .cast<String>();
  return names.map(safeName).toList();
}

Future<void> rejectLinks(String path) async {
  var current = p.absolute(path);
  while (true) {
    if (await FileSystemEntity.type(current, followLinks: false) ==
        FileSystemEntityType.link) {
      throw const FormatException('Linked installation path');
    }
    final parent = p.dirname(current);
    if (parent == current) break;
    current = parent;
  }
}

Future<void> writeJournal(
  File journal,
  String text, {
  bool flush = true,
}) async {
  final pending = File('${journal.path}.new');
  await pending.writeAsString(text, flush: flush);
  await pending.rename(journal.path);
}
