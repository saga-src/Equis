import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/providers/app_providers.dart';
import '../../l10n/app_localizations.dart';

class VaultHubScreen extends ConsumerStatefulWidget {
  const VaultHubScreen({super.key});
  @override
  ConsumerState<VaultHubScreen> createState() => _VaultHubScreenState();
}

class _VaultHubScreenState extends ConsumerState<VaultHubScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  List<Map<String, dynamic>> _cloud = [];
  bool _busy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = AppLocalizations.of(context).vaultOperationFailed,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _load() => _run(() async {
    final workspace = ref.read(vaultWorkspaceProvider)!;
    await workspace.refresh();
    final rows = await workspace.discover();
    if (mounted) setState(() => _cloud = rows);
  });
  Future<String?> _askKey() async {
    var key = '';
    final l = AppLocalizations.of(context);
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.vaultKeyLabel),
        content: TextField(
          onChanged: (value) => key = value,
          obscureText: true,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(labelText: l.vaultKeyLabel),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, key.trim()),
            child: Text(l.restoreCloudVaultAction),
          ),
        ],
      ),
    );
  }

  Future<void> _showKey() => _run(() async {
    final workspace = ref.read(vaultWorkspaceProvider)!;
    final vaultId = workspace.selected?.vaultId;
    if (vaultId == null || workspace.legacy) return;
    final identity = await workspace.active!.vaultKeys.requireVault(vaultId);
    if (!mounted) return;
    final l = AppLocalizations.of(context);
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.vaultKeyLabel),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l.vaultKeyExplanation),
            const SizedBox(height: 16),
            SelectableText(identity.exportKey()),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(MaterialLocalizations.of(context).closeButtonLabel),
          ),
        ],
      ),
    );
  });
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final workspace = ref.watch(vaultWorkspaceProvider)!;
    final auth = workspace.active!.cloudAccounts.auth;
    final signedIn = auth?.currentIdentity != null;
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Image.asset(
              'assets/branding/logo.png',
              width: 32,
              height: 32,
              cacheWidth: 64,
            ),
            const SizedBox(width: 12),
            Text(l.vaultsTitle),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          if (_busy) const LinearProgressIndicator(),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          Text(
            l.localVaultsLabel,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          for (final entry in workspace.entries)
            ListTile(
              leading: Icon(
                entry == workspace.selected
                    ? Icons.check_circle
                    : Icons.lock_outline,
              ),
              title: Text(entry.name.isEmpty ? l.newVaultAction : entry.name),
              subtitle: Text(
                entry.legacy
                    ? l.legacyVaultNotice
                    : entry.vaultId ?? l.newVaultAction,
              ),
              onTap: _busy ? null : () => _run(() => workspace.select(entry)),
            ),
          FilledButton.icon(
            onPressed: _busy ? null : () => _run(workspace.create),
            icon: const Icon(Icons.add),
            label: Text(l.newVaultAction),
          ),
          OutlinedButton(
            onPressed: _busy ? null : () => context.push('/portability'),
            child: Text(l.portabilityTitle),
          ),
          if (!workspace.legacy && workspace.selected?.vaultId != null) ...[
            OutlinedButton(
              onPressed: _busy ? null : _showKey,
              child: Text(l.showVaultKeyAction),
            ),
            OutlinedButton(
              onPressed: _busy ? null : () => context.push('/vault-sync'),
              child: Text(l.vaultSyncAction),
            ),
          ],
          const Divider(height: 32),
          Text(
            l.accountCloudVaultsLabel,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          Text(l.vaultOwnerExplanation),
          if (!signedIn) ...[
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(labelText: l.accountEmailLabel),
            ),
            TextField(
              controller: _password,
              obscureText: true,
              enableSuggestions: false,
              autocorrect: false,
              decoration: InputDecoration(labelText: l.accountPasswordLabel),
            ),
            FilledButton(
              onPressed: _busy || auth == null
                  ? null
                  : () => _run(() async {
                      await auth.signIn(
                        email: _email.text.trim(),
                        password: _password.text,
                      );
                      _password.clear();
                      final rows = await workspace.discover();
                      if (mounted) setState(() => _cloud = rows);
                    }),
              child: Text(l.accountSignInAction),
            ),
          ] else ...[
            Text(auth!.currentIdentity!.email),
            TextButton(
              onPressed: _busy
                  ? null
                  : () => _run(() async {
                      await workspace.active?.syncCoordinator?.stop();
                      await auth.signOut();
                      if (mounted) setState(() => _cloud = []);
                    }),
              child: Text(l.accountSignOutAction),
            ),
            OutlinedButton(
              onPressed: _busy ? null : _load,
              child: Text(l.refreshVaultsAction),
            ),
            if (_cloud.isEmpty) Text(l.noCloudVaultsMessage),
            for (final row in _cloud)
              ListTile(
                leading: const Icon(Icons.cloud_outlined),
                title: Text(row['id'] as String),
                subtitle: Text(row['created_at'].toString()),
                onTap: _busy
                    ? null
                    : () async {
                        final key = await _askKey();
                        if (key == null || !mounted) return;
                        await _run(() => workspace.restoreCloud(row, key));
                      },
              ),
          ],
        ],
      ),
    );
  }

  @override
  void dispose() {
    _email.dispose();
    _password.clear();
    _password.dispose();
    super.dispose();
  }
}
