import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../infrastructure/settings/application_licenses.dart';
import '../../l10n/app_localizations.dart';

class LicensesScreen extends StatelessWidget {
  const LicensesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(MaterialLocalizations.of(context).licensesPageTitle),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(l.licensesOverviewBody),
          const SizedBox(height: 16),
          _AssetLicenseTile(
            name: 'Equis',
            asset: 'LICENSE',
            subtitle: 'Saga-SAL-1.0',
          ),
          ExpansionTile(
            title: Text(l.licensesFontsTitle),
            subtitle: const Text('SIL Open Font License 1.1'),
            children: const [
              _AssetLicenseTile(
                name: 'Inter',
                asset: 'assets/licenses/Inter-OFL-1.1.txt',
              ),
              _AssetLicenseTile(
                name: 'JetBrains Mono',
                asset: 'assets/licenses/JetBrainsMono-OFL-1.1.txt',
              ),
              _AssetLicenseTile(
                name: 'Geist Sans',
                asset: 'assets/licenses/Geist-OFL-1.1.txt',
              ),
              _AssetLicenseTile(
                name: 'Space Grotesk',
                asset: 'assets/licenses/SpaceGrotesk-OFL-1.1.txt',
              ),
            ],
          ),
          ExpansionTile(
            title: Text(l.licensesDataTitle),
            children: const [
              _AssetLicenseTile(
                name: 'BCB SGS 11 — Selic',
                asset: 'assets/licenses/BCB-SGS-Selic-ODbL-1.0.txt',
                subtitle: 'Open Database License 1.0',
              ),
            ],
          ),
          ListTile(
            key: const Key('dependency-licenses'),
            title: Text(l.licensesDependenciesTitle),
            subtitle: Text(l.licensesDependenciesBody),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const DependencyLicensesScreen(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AssetLicenseTile extends StatelessWidget {
  const _AssetLicenseTile({
    required this.name,
    required this.asset,
    this.subtitle,
  });
  final String name;
  final String asset;
  final String? subtitle;
  @override
  Widget build(BuildContext context) => ListTile(
    title: Text(name),
    subtitle: subtitle == null ? null : Text(subtitle!),
    trailing: const Icon(Icons.chevron_right),
    onTap: () {
      final text = rootBundle.loadString(asset);
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => _LicenseTextScreen(name: name, text: text),
        ),
      );
    },
  );
}

class DependencyLicensesScreen extends StatefulWidget {
  const DependencyLicensesScreen({super.key, this.load});
  final Future<Map<String, List<LicenseEntry>>> Function()? load;
  @override
  State<DependencyLicensesScreen> createState() =>
      _DependencyLicensesScreenState();
}

class _DependencyLicensesScreenState extends State<DependencyLicensesScreen> {
  late Future<Map<String, List<LicenseEntry>>> _licenses;
  String _query = '';
  @override
  void initState() {
    super.initState();
    _licenses = widget.load?.call() ?? loadApplicationLicenses();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.licensesDependenciesTitle)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              decoration: InputDecoration(
                labelText: l.licensesSearchLabel,
                prefixIcon: const Icon(Icons.search),
              ),
              onChanged: (query) =>
                  setState(() => _query = query.trim().toLowerCase()),
            ),
          ),
          Expanded(
            child: FutureBuilder<Map<String, List<LicenseEntry>>>(
              future: _licenses,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: TextButton(
                      onPressed: () {
                        final licenses =
                            widget.load?.call() ?? loadApplicationLicenses();
                        setState(() {
                          _licenses = licenses;
                        });
                      },
                      child: Text(l.budgetRetryAction),
                    ),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final packages =
                    snapshot.data!.keys
                        .where((name) => name.toLowerCase().contains(_query))
                        .toList()
                      ..sort(
                        (a, b) => a.toLowerCase().compareTo(b.toLowerCase()),
                      );
                if (packages.isEmpty) {
                  return Center(child: Text(l.licensesNoMatches));
                }
                return ListView.builder(
                  itemCount: packages.length,
                  itemBuilder: (context, index) {
                    final name = packages[index];
                    return ListTile(
                      title: Text(name),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => _LicenseTextScreen(
                            name: name,
                            text: Future.value(
                              [
                                for (final entry in snapshot.data![name]!)
                                  entry.paragraphs
                                      .map((paragraph) => paragraph.text)
                                      .join('\n\n'),
                              ].join('\n\n────────────────\n\n'),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _LicenseTextScreen extends StatelessWidget {
  const _LicenseTextScreen({required this.name, required this.text});
  final String name;
  final Future<String> text;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(name)),
    body: FutureBuilder<String>(
      future: text,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Text(AppLocalizations.of(context).licensesLoadFailed),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: SelectableText(snapshot.data!),
        );
      },
    ),
  );
}
