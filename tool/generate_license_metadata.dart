import 'dart:convert';
import 'dart:io';

// Run after flutter pub get when preparing sources or packages.
void main(List<String> arguments) {
  final graph =
      jsonDecode(File('.dart_tool/package_graph.json').readAsStringSync())
          as Map;
  final packages = {
    for (final package in graph['packages'] as List)
      (package as Map)['name'] as String: package,
  };
  final runtime = <String>{};
  void visit(String name) {
    if (!runtime.add(name)) return;
    final package = packages[name];
    if (package == null) throw StateError('Missing dependency $name');
    for (final dependency in package['dependencies'] as List) {
      visit(dependency as String);
    }
  }

  for (final root in graph['roots'] as List) {
    visit(root as String);
  }
  final developmentOnly =
      packages.keys.where((name) => !runtime.contains(name)).toList()..sort();
  final output =
      '${const JsonEncoder.withIndent('  ').convert({'format_version': 1, 'development_only_packages': developmentOnly})}\n';
  final file = File('assets/licenses/package_scopes.json');
  if (arguments.contains('--check')) {
    if (!file.existsSync() || file.readAsStringSync() != output) {
      stderr.writeln(
        'License metadata is stale. Run dart run tool/generate_license_metadata.dart after flutter pub get.',
      );
      exitCode = 1;
      return;
    }
  } else {
    file.writeAsStringSync(output);
  }
  stdout.writeln(
    '${runtime.length} runtime packages retained; ${developmentOnly.length} development-only packages classified.',
  );
}
