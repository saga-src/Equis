<div align="center">
  <img src="assets/branding/logo.png" width="128" alt="Equis logo" />
  <h1>EQUIS</h1>
  <p><strong>v1.2.1 | Personal Finance for Windows & Android</strong></p>
  <p>
    <a href="#features">Features</a> &middot;
    <a href="#tech-stack">Tech Stack</a> &middot;
    <a href="#getting-started">Getting Started</a> &middot;
    <a href="#backup-and-updates">Backup & Updates</a> &middot;
    <a href="#architecture">Architecture</a>
  </p>
  <p>
    <img src="https://img.shields.io/badge/License-Saga--SAL--1.0-blue?style=flat-square" alt="Saga-SAL-1.0" />
    <img src="https://img.shields.io/badge/Privacy-Local--First-green?style=flat-square" alt="Local First" />
    <img src="https://img.shields.io/badge/Cloud-Opt--In-blue?style=flat-square" alt="Cloud Opt-In" />
    <img src="https://img.shields.io/badge/Built%20with-AI%20Assistance-purple?style=flat-square" alt="Built with AI Assistance" />
  </p>
</div>

---

**Equis** is an offline personal finance app for tracking spending, budgets, goals, and wealth.

Your financial records stay in an encrypted SQLite database on your device. You don't need an account to use local features.

To share a vault between devices, enable optional Supabase synchronization. Records are encrypted, and each vault has one master key. Recovering a vault from the cloud requires its key and a login to the account that owns it.

## Features

### Everyday finances

- Accounts, multiple currencies, income, expenses, transfers, and transaction splits. Quick expenses made from a credit-card account enter its statement as one-time purchases.
- Categories and tags, searchable history, receipts and attachments.
- Credit cards, statements, installments, and recurring transactions.
- Transaction lists use consistent semantic colors and expose the same eligible edit, reconcile, and delete actions in recent activity and full history.
- Accounts and credit cards with history can be archived and restored. Removal checks each pocket's balance and outstanding obligations; an unused account is deleted logically without removing historical records.
- Open transaction details from recent activity or full history, including records older than the latest twenty. Editing remains limited to supported transactions; those linked to archived accounts remain readable until the account is restored.

### Reports and planning

- Available money, cash flow, account balances, and income or spending by category.
- Switch to **Tags** for compact spending bubbles; their area represents each tag's positive amount. Hover, focus, or long press for the full name and exact value; tap to open matching expenses. The home shows up to six largest positive values, with smaller values in the text list and negative adjustments separately. Untagged expenses have their own group. Each tag receives the full expense amount, so totals across tags can overlap.
- Budgets, savings goals, selectable monthly cash-flow projections, assets, net worth, and investments.
- Guided brokerage-account setup, currency-safe portfolio actions, and deletion of investment assets that have never been used.
- Fixed-income terms belong to each purchase lot. Supported simple contracts show a gross estimated balance; a dated manual balance supports other structures. Missing observations remain explicit. These balances are not market quotes or net redemption prices, and tax or guarantee coverage is not inferred from a product name.
- Market prices and required exchange rates refresh when the app opens, at most once per vault every three hours, while manual values keep priority and cached values remain available offline.
- Financial insights calculated locally, without sending transaction history to an external AI service.

### Portability and personalization

- Password-encrypted `.equis` backups with integrity validation and restoration into a separate local vault.
- JSON vault exports and transaction CSV exports. These exports are plaintext.
- English and Brazilian Portuguese interfaces with a persistent language selection, theme and typography settings.
- Sync diagnostics showing pending changes, last completed run, and actionable failure information.
- Sync activity for the last 24 hours, saved separately for each vault on each device. Counts cover confirmed sends, remote versions applied locally, and conflicts, including those resolved automatically.
- Automatic synchronization after edits while the app is open, with retries after reconnection. Conflicts select the higher revision of the complete record; equal revisions use edit time, then canonical content as a deterministic tie-break. Revision priority isn't a guarantee of chronological order across device clocks.

## Tech Stack

| Layer | Technology |
| --- | --- |
| App | Flutter 3.44.7 / Dart 3.12.2 |
| Platforms | Windows and Android |
| State and navigation | Riverpod / GoRouter |
| Local data | Drift / SQLite3MultipleCiphers |
| Charts | FL Chart |
| Security | Device secure storage / XChaCha20-Poly1305 |
| Optional cloud | Supabase Auth, PostgreSQL and Realtime |
| Android exports | MediaStore Downloads / native document picker |

## Getting Started

### Prerequisites

Install Flutter **3.44.7** with Dart **3.12.2**. Windows builds require the Visual Studio C++ desktop workload. Android builds require the Android SDK and a compatible JDK.

```sh
git clone https://github.com/saga-src/Equis.git
cd Equis
flutter pub get
flutter run -d windows
```

For Android, connect a device or start an emulator, then select its identifier from `flutter devices`:

```sh
flutter run -d <device-id>
```

Cloud configuration is optional. For cloud-enabled builds, create an ignored `.dart-defines.local.json`:

```json
{
  "EQUIS_ENVIRONMENT": "development",
  "EQUIS_SUPABASE_URL": "https://YOUR_PROJECT.supabase.co",
  "EQUIS_SUPABASE_ANON_KEY": "YOUR_PUBLIC_CLIENT_KEY"
}
```

```sh
flutter run --dart-define-from-file=.dart-defines.local.json
```

Never include a service-role key in the app. The server schema and guarded synchronization functions are versioned in `supabase/migrations/`.

Automatic market quotes and asset discovery use the Supabase `market-quotes` Edge Function. Configure `BRAPI_API_TOKEN`, `TWELVE_DATA_API_KEY`, and `COINGECKO_API_KEY` only in the Edge Function environment; never add them to Flutter build defines. The client uses the current Supabase user token when available and retries gateway authorization with the configured public key, so a local-only vault does not require a cloud login. Frankfurter exchange rates require no client secret. Missing or temporarily unavailable providers degrade to manual or cached data instead of blocking the app.

The optional central asset catalog is created by `supabase/migrations/20260922164311_central_asset_catalog.sql`. Its tables contain only public asset metadata, anonymous demand counters, provider usage and quotes; portfolio quantities, balances, vault identifiers and user identifiers remain local. RLS blocks `anon` and `authenticated` access, so Flutter continues to use only `market-quotes`. The `sync-market-data` administrative function uses the service role internally and requires `MARKET_SYNC_SECRET` in addition to the provider secrets.

Catalog persistence is disabled by default until the provider storage and redistribution terms have been confirmed. `MARKET_CATALOG_READ_ENABLED` and `MARKET_SCHEDULED_QUOTES_ENABLED` also default to `false`, allowing catalog reads and scheduled prices to be rolled out independently. The Cron dispatcher reads `project_url` and `market_sync_secret` from Vault. `sync-market-data` disables gateway JWT verification because it is an administrative webhook authenticated with a constant-time comparison of that dedicated secret; `market-quotes` continues to require a valid JWT. Deploy in this order: apply the migration, deploy `sync-market-data`, run the initial catalog sync, deploy `market-quotes`, enable catalog reads and heartbeat, then enable scheduled quotes after observing provider errors, quotas and duration. Cron runs catalog sync daily at 04:30 UTC, quote dispatch hourly and five-year history cleanup daily.

### Validation

```sh
dart format --output=none --set-exit-if-changed lib test integration_test
flutter analyze
flutter test
flutter build windows --release
flutter build apk --release --dart-define-from-file=.dart-defines.local.json
```

This workspace also supports its ignored local SDK at `.tooling/flutter/bin/flutter.bat`. Live sync acceptance tests require dedicated test credentials; tests that skip for missing credentials don't establish cloud compatibility.

The source tree targets **1.2.1**, with compact tag bubbles and fixes to automated checks. Its release packages have not been prepared in this workflow. Previous validation results and installer cases waived by the owner are recorded locally in `docs/release/1.2.0/VALIDACAO.md`. Releases are packaged and published manually.

## Backup and Updates

### Save and verify a backup

Open **Settings > Backup and export > Create encrypted backup**. Choose a password of at least 12 characters and keep it separately from the file.

If cloud sync has pending local changes or an unresolved conflict, finish syncing and resolve the conflict before creating a portable backup. The app postpones the backup so a later restore cannot lose those changes. If you are offline, keep the current installation and create the backup after reconnecting.

On Android 10 and newer, backups are saved to **Downloads/Equis**. Older Android versions use the native document picker. The screen shows the most recently saved backup and offers validation. Windows lets you select the destination.

Restore a `.equis` backup with its password to add a local vault. Its identity and master key are preserved; an existing copy of the same vault is opened without replacement. Your account password, backup password, and vault key have different purposes.

### Update Android without deleting local data

1. Keep the currently installed APK and create a validated backup when possible.
2. Build the update with the **same application ID and signing key**, and a higher build number.
3. Verify it against the previous APK using `tool/verify_android_update.ps1`.
4. Open the new APK on your phone and choose **Update**. Don't uninstall the existing app or clear its storage.
5. Open Equis and check your accounts, transactions, attachments and settings.

The version prepared in source is **1.2.1**, application ID `app.saga.equis`. This does not indicate a published package. If Android rejects the update, check the package metadata and signing certificate. Keep the release keystore: future updates need the same signing key.

The Android package uses `app.saga.equis`. If you used the earlier development app, export and validate an encrypted backup there first. Install this app separately, restore the backup, sign in, and check your data before removing the old installation. The two package identifiers cannot update each other in place.

Public releases use one tag per version. The planned tag for this delivery is **v1.2.1**, which has not been created by this workflow. A new public update requires a higher public version; previous tags and packages remain unchanged.

Android release signing reads the ignored `android/key.properties` file or the `EQUIS_ANDROID_*` environment variables declared in `android/app/build.gradle.kts`. Windows packaging uses `installer/equis.iss` and `tool/package_windows_release.ps1`.

While open, Equis checks public GitHub releases and downloads verified stable updates. Android waits for Wi-Fi unless you choose to download now. You decide when to install; Settings also lets you turn off automatic downloads. Android and portable Windows keep their existing update routes.

The redesigned installed-Windows route is enabled in the 1.2.0 packages and uses an unelevated helper with a visible Inno installer. In the isolated tests, Equis stayed open through UAC and the initial wizard pages, closed at **Install**, and reopened after verified success. The first catalog-bearing package must be installed manually over the existing installation, preserving its folder and install mode. See the [Windows packaging and diagnostics guide](docs/PACKAGING-1.2.0.pt-BR.md).

## Architecture

Equis separates financial rules from platform and cloud integration:

- `lib/domain/`: ledger, money, reporting and financial models.
- `lib/application/`: use cases, synchronization engine and repository interfaces.
- `lib/infrastructure/`: encrypted database, repositories, cryptography, backups and cloud adapters.
- `lib/presentation/`: screens, controllers, charts and accessible UI.
- `lib/app/`: application wiring, routes, providers and themes.
- `test/` and `integration_test/`: financial, database, security and UI validation.
- `supabase/`: server migrations and optional cloud infrastructure.

## AI Transparency

AI tools help with implementation, investigation, documentation and testing. You can inspect the source and run the automated tests that check financial behavior. The app calculates financial insights locally; it doesn't send your ledger to an AI service.

## License

Equis is licensed under the **Saga Source-Available License Version 1.0 (`Saga-SAL-1.0`)**. This is a source-available license, not an open-source license. See [LICENSE](LICENSE) for the complete terms. Third-party components retain their own licenses.

### Additional permissions

The license permits individual noncommercial use and private modifications, with express exceptions for technical research and contributions. Redistribution, shared deployment, and commercial or organizational use generally require separate written permission. Contact [Carlos N. Marinho (HalfWesen)](https://github.com/HalfWesen) for licensing requests.
