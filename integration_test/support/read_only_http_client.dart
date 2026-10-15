import 'package:http/http.dart' as http;

/// Allow public backend reads during native smoke tests, but prevent writes
/// such as the customer shell's fire-and-forget analytics insertion.
class ReadOnlyHttpClient extends http.BaseClient {
  final http.Client _inner;
  int blockedWrites = 0;
  ReadOnlyHttpClient(this._inner);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (!{'GET', 'HEAD', 'OPTIONS'}.contains(request.method.toUpperCase())) {
      blockedWrites++;
      throw StateError(
        'Backend writes are disabled in this native smoke test.',
      );
    }
    return _inner.send(request);
  }

  @override
  void close() => _inner.close();
}
