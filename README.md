<div align="center">
  <img src="assets/branding/logo.png" width="128" alt="Equis logo" />
  <h1>EQUIS</h1>
  <p><strong>v1.0.0 | Personal Finance for Windows & Android</strong></p>
  <p>
    <a href="#features">Features</a> &middot;
    <a href="#tech-stack">Tech Stack</a> &middot;
    <a href="#getting-started">Getting Started</a> &middot;
    <a href="#backup-and-updates">Backup & Updates</a> &middot;
    <a href="#architecture">Architecture</a>
  </p>
  <p>
    <img src="https://img.shields.io/badge/License-GPLv3-blue?style=flat-square" alt="GPLv3" />
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

- Accounts, multiple currencies, income, expenses, transfers, and transaction splits.
- Categories and tags, searchable history, receipts and attachments.
- Credit cards, statements, installments, and recurring transactions.

### Reports and planning

- Available money, cash flow, account balances, and spending by category.
- Switch to **Tags** for horizontal spending bars; tap a tag to open matching expenses. Untagged expenses have their own group. Each tag receives the full expense amount, so totals across tags can overlap.
- Budgets, savings goals, cash-flow projections, assets, net worth, and investments.
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

### Validation

```sh
dart format --output=none --set-exit-if-changed lib test integration_test
flutter analyze
flutter test
flutter build windows --release
flutter build apk --release --dart-define-from-file=.dart-defines.local.json
```

This workspace also supports its ignored local SDK at `.tooling/flutter/bin/flutter.bat`. Live sync acceptance tests require dedicated test credentials; tests that skip for missing credentials don't establish cloud compatibility.

## Backup and Updates

### Save and verify a backup

Open **Settings > Backup and export > Create encrypted backup**. Choose a password of at least 12 characters and keep it separately from the file.

On Android 10 and newer, backups are saved to **Downloads/Equis**. Older Android versions use the native document picker. The screen shows the most recently saved backup and offers validation. Windows lets you select the destination.

Restore a `.equis` backup with its password to add a local vault. Its identity and master key are preserved; an existing copy of the same vault is opened without replacement. Your account password, backup password, and vault key have different purposes.

### Update Android without deleting local data

1. Keep the currently installed APK and create a validated backup when possible.
2. Build the update with the **same application ID and signing key**, and a higher build number.
3. Verify it against the previous APK using `tool/verify_android_update.ps1`.
4. Open the new APK on your phone and choose **Update**. Don't uninstall the existing app or clear its storage.
5. Open Equis and check your accounts, transactions, attachments and settings.

The current version is **1.0.0**, application ID `app.saga.equis`. If Android rejects the update, check the package, build number and signing certificate. Keep the release keystore: future updates need the same signing key.

The Android package uses `app.saga.equis`. If you used the earlier development app, export and validate an encrypted backup there first. Install this app separately, restore the backup, sign in, and check your data before removing the old installation. The two package identifiers cannot update each other in place.

Public releases use one tag per version, such as **v1.0.0**. Internal build numbers remain in package metadata; a new public update requires a higher public version.

Android release signing reads the ignored `android/key.properties` file or the `EQUIS_ANDROID_*` environment variables declared in `android/app/build.gradle.kts`. Windows packaging uses `installer/equis.iss` and `tool/package_windows_release.ps1`.

While open, Equis checks public GitHub releases and downloads verified stable updates. Android waits for Wi-Fi unless you choose to download now. You decide when to install; Settings also lets you turn off automatic downloads. Both installed and portable Windows copies are supported. Install this first updater build manually.

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

Equis is licensed under **GNU GPL version 3 only (`GPL-3.0-only`)**. See [LICENSE](LICENSE) for the complete terms. Third-party components retain their own licenses.
