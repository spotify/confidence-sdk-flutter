import 'dart:async';
import 'dart:convert';
import 'dart:io';

final class WireResponse {
  const WireResponse(this.status, this.body);
  final int status;
  final String body;
}

abstract interface class JsonTransport {
  Future<WireResponse> post(Uri uri, Map<String, Object?> body);
  void close();
}

/// No retries here: initialization and outbox delivery own their policies.
final class IoTransport implements JsonTransport {
  IoTransport({this.timeout = const Duration(seconds: 10)});
  final Duration timeout;
  final HttpClient _client = HttpClient();

  @override
  Future<WireResponse> post(Uri uri, Map<String, Object?> body) async {
    HttpClientRequest? request;
    var cancelled = false;
    Future<WireResponse> send() async {
      final outgoing = await _client.postUrl(uri);
      request = outgoing;
      if (cancelled) {
        outgoing.abort();
        throw const TransportException();
      }
      outgoing.followRedirects = false;
      outgoing.headers.contentType = ContentType.json;
      outgoing.write(jsonEncode(body));
      final incoming = await outgoing.close();
      final text = await utf8.decoder.bind(incoming).join();
      return WireResponse(incoming.statusCode, text);
    }

    try {
      return await send().timeout(timeout);
    } catch (_) {
      cancelled = true;
      request?.abort();
      // Socket/HTTP/JSON errors may contain URLs, request data, or credentials.
      throw const TransportException();
    }
  }

  @override
  void close() => _client.close(force: true);
}

final class TransportException implements Exception {
  const TransportException();
  @override
  String toString() => 'Confidence transport failed.';
}
