import 'package:confidence_flutter_sdk/confidence_flutter_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

// Only the rewrite's events transport is redirected. The baseline helper uses
// the unmodified native SDK and leaves its tracked event on disk before exit.
ConfidenceFlutterSdk createUpgradeSdk(Uri server) {
  final client = _LocalEventsClient(server);
  addTearDown(client.close);
  return ConfidenceFlutterSdk(
      confidenceFactory: (secret, {resolveBaseUrl}) => ConfidenceFlutter.create(
          clientSecret: secret,
          region: ConfidenceRegion.eu,
          resolveBaseUrl: resolveBaseUrl,
          httpClient: client));
}

class _LocalEventsClient extends http.BaseClient {
  final Uri server;
  final http.Client inner = http.Client();
  _LocalEventsClient(this.server);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final url = request.url.path.endsWith('events:publish')
        ? server.resolve(request.url.path)
        : request.url;
    final redirected = http.StreamedRequest(request.method, url)
      ..headers.addAll(request.headers);
    final response = inner.send(redirected);
    await redirected.sink.addStream(request.finalize());
    await redirected.sink.close();
    return response;
  }

  @override
  void close() => inner.close();
}
