import '../../core/serialization/canonical_json.dart';

/// Revision is the user's primary priority. Ties use the edit timestamp, then
/// canonical content so the decision does not depend on which device is local.
int compareSyncRevisions({
  required int localRevision,
  required int remoteRevision,
  required Map<String, Object?> local,
  required Map<String, Object?> remote,
}) {
  final revision = localRevision.compareTo(remoteRevision);
  if (revision != 0) return revision;
  int timestamp(Map<String, Object?> payload) {
    final root = payload['root'];
    final value = root is Map ? root['updated_at'] : payload['updated_at'];
    return value is int ? value : 0;
  }

  final time = timestamp(local).compareTo(timestamp(remote));
  if (time != 0) return time;
  return CanonicalJson.encode(local).compareTo(CanonicalJson.encode(remote));
}
