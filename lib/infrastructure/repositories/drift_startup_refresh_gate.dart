import 'package:drift/drift.dart';

import '../../application/ports/startup_refresh_gate.dart';
import '../../domain/shared/utc_instant.dart';
import '../../domain/shared/uuid_v7.dart';
import '../persistence/database/equis_database.dart';

final class DriftStartupRefreshGate implements StartupRefreshGate {
  const DriftStartupRefreshGate(this.database);
  final EquisDatabase database;

  @override
  Future<UtcInstant?> lastAttempt(EntityId vaultId) async {
    final row = await database
        .customSelect(
          'SELECT value FROM device_preferences WHERE "key"=?',
          variables: [Variable<String>(_key(vaultId))],
          readsFrom: {database.devicePreferences},
        )
        .getSingleOrNull();
    final micros = row == null ? null : int.tryParse(row.read<String>('value'));
    return micros == null ? null : UtcInstant.fromEpochMicroseconds(micros);
  }

  @override
  Future<void> recordAttempt(EntityId vaultId, UtcInstant at) =>
      database.customStatement(
        'INSERT INTO device_preferences ("key",value) VALUES (?,?) '
        'ON CONFLICT("key") DO UPDATE SET value=excluded.value',
        [_key(vaultId), at.epochMicroseconds.toString()],
      );

  String _key(EntityId vaultId) =>
      'startup_refresh.last_attempt.${vaultId.value}';
}
