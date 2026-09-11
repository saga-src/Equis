abstract interface class NetworkReachability {
  Future<bool> get isOnline;

  Stream<bool> get changes;
}
