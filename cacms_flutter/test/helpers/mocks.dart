import 'package:dio/dio.dart';
import 'package:mocktail/mocktail.dart';
import 'package:cacms_flutter/core/api/api_client.dart';
import 'package:cacms_flutter/core/api/sse_client.dart';
import 'package:cacms_flutter/core/auth/token_storage.dart';
import 'package:cacms_flutter/core/models/sse_event.dart';
import 'package:cacms_flutter/core/widgets/sse_indicator.dart';

// ---------------------------------------------------------------------------
// Mock classes
// ---------------------------------------------------------------------------

class MockDio extends Mock implements Dio {}

class MockApiClient extends Mock implements ApiClient {}

class MockTokenStorage extends Mock implements TokenStorage {}

// ---------------------------------------------------------------------------
// Fake SSE client — does nothing, emits no events, creates no timers
// ---------------------------------------------------------------------------

class FakeSseClient extends SseClient {
  FakeSseClient() : super(url: 'http://fake');

  @override
  Stream<SseEvent> get events => const Stream.empty();

  @override
  Stream<SseConnectionState> get connectionState => const Stream.empty();

  @override
  Future<void> connect() async {}

  @override
  Future<void> dispose() async {}
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Creates a [Response] with the given [data] and [statusCode].
Response<dynamic> fakeResponse(dynamic data, {int statusCode = 200}) {
  return Response(
    data: data,
    statusCode: statusCode,
    requestOptions: RequestOptions(path: ''),
  );
}
