import 'dart:async';
import 'dart:convert';

import 'package:eventsource/eventsource.dart';

import '../models/sse_event.dart';
import '../widgets/sse_indicator.dart';

/// Manages a persistent SSE connection to a CACMS event stream endpoint.
///
/// Features:
/// - Sends `Last-Event-ID` header on reconnect so the server can replay
///   missed events.
/// - Exposes [events] as a broadcast [Stream<SseEvent>].
/// - Exposes [connectionState] as a broadcast [Stream<SseConnectionState>]
///   that the [SseIndicator] widget can consume.
/// - On disconnect: transitions to [SseConnectionState.reconnecting] and
///   retries with exponential back-off (1 s → 2 s → 4 s cap).
/// - On successful reconnect: transitions back to [SseConnectionState.live].
class SseClient {
  SseClient({
    required String url,
    Map<String, String>? headers,
  })  : _url = url,
        _extraHeaders = headers ?? {};

  final String _url;
  final Map<String, String> _extraHeaders;

  // ---------------------------------------------------------------------------
  // Public streams
  // ---------------------------------------------------------------------------

  Stream<SseEvent> get events => _eventController.stream;
  Stream<SseConnectionState> get connectionState =>
      _stateController.stream;

  SseConnectionState get currentState => _currentState;

  // ---------------------------------------------------------------------------
  // Internal state
  // ---------------------------------------------------------------------------

  final _eventController = StreamController<SseEvent>.broadcast();
  final _stateController =
      StreamController<SseConnectionState>.broadcast();

  SseConnectionState _currentState = SseConnectionState.disconnected;
  String? _lastEventId;
  bool _disposed = false;

  StreamSubscription<Event>? _subscription;

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  /// Start the SSE connection. Call once after construction.
  Future<void> connect() async {
    if (_disposed) return;
    await _connect();
  }

  /// Permanently close the client and release resources.
  Future<void> dispose() async {
    _disposed = true;
    await _subscription?.cancel();
    await _eventController.close();
    await _stateController.close();
  }

  // ---------------------------------------------------------------------------
  // Connection logic
  // ---------------------------------------------------------------------------

  Future<void> _connect() async {
    if (_disposed) return;

    try {
      final headers = Map<String, String>.from(_extraHeaders);
      if (_lastEventId != null) {
        headers['Last-Event-ID'] = _lastEventId!;
      }

      final es = await EventSource.connect(
        _url,
        headers: headers,
        lastEventId: _lastEventId,
      );

      _emit(SseConnectionState.live);

      _subscription = es.listen(
        _onEvent,
        onError: _onError,
        onDone: _onDone,
        cancelOnError: false,
      );
    } catch (e) {
      _scheduleReconnect(attempt: 0);
    }
  }

  void _onEvent(Event raw) {
    if (_disposed) return;

    // Track last received event id for reconnect.
    if (raw.id != null && raw.id!.isNotEmpty) {
      _lastEventId = raw.id;
    }

    // Parse the data field as JSON.
    final rawData = raw.data ?? '{}';
    Map<String, dynamic> parsed;
    try {
      parsed = jsonDecode(rawData) as Map<String, dynamic>;
    } catch (_) {
      parsed = {'raw': rawData};
    }

    // Build an SseEvent from the raw event fields.
    final sseEvent = SseEvent(
      eventId: raw.id ?? '',
      eventType: raw.event ?? 'message',
      channel: parsed['channel'] as String? ?? '',
      data: parsed,
    );

    _eventController.add(sseEvent);
  }

  void _onError(Object error) {
    if (_disposed) return;
    _scheduleReconnect(attempt: 0);
  }

  void _onDone() {
    if (_disposed) return;
    _scheduleReconnect(attempt: 0);
  }

  // ---------------------------------------------------------------------------
  // Exponential back-off reconnect: 1 s → 2 s → 4 s (cap)
  // ---------------------------------------------------------------------------

  static const _backoffDelays = [
    Duration(seconds: 1),
    Duration(seconds: 2),
    Duration(seconds: 4),
  ];

  Future<void> _scheduleReconnect({required int attempt}) async {
    if (_disposed) return;

    await _subscription?.cancel();
    _subscription = null;

    _emit(SseConnectionState.reconnecting);

    final delay = attempt < _backoffDelays.length
        ? _backoffDelays[attempt]
        : _backoffDelays.last;

    await Future<void>.delayed(delay);

    if (_disposed) return;

    try {
      final headers = Map<String, String>.from(_extraHeaders);
      if (_lastEventId != null) {
        headers['Last-Event-ID'] = _lastEventId!;
      }

      final es = await EventSource.connect(
        _url,
        headers: headers,
        lastEventId: _lastEventId,
      );

      _emit(SseConnectionState.live);

      _subscription = es.listen(
        _onEvent,
        onError: (_) => _scheduleReconnect(attempt: attempt + 1),
        onDone: () => _scheduleReconnect(attempt: attempt + 1),
        cancelOnError: false,
      );
    } catch (_) {
      await _scheduleReconnect(attempt: attempt + 1);
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  void _emit(SseConnectionState state) {
    if (_disposed) return;
    _currentState = state;
    _stateController.add(state);
  }
}
