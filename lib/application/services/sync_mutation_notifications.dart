import 'dart:async';

final class SyncMutationNotifications {
  final StreamController<String> _controller =
      StreamController<String>.broadcast(sync: true);

  Stream<String> get vaultIds => _controller.stream;

  void notify(String vaultId) {
    if (!_controller.isClosed) _controller.add(vaultId);
  }

  Future<void> dispose() => _controller.close();
}
