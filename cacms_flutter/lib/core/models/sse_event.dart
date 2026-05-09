/// Matches backend SSEEvent schema (common.py).
class SseEvent {
  const SseEvent({
    required this.eventId,
    required this.eventType,
    required this.channel,
    required this.data,
  });

  final String eventId;
  final String eventType;
  final String channel;
  final Map<String, dynamic> data;

  factory SseEvent.fromJson(Map<String, dynamic> json) => SseEvent(
        eventId: json['event_id'] as String,
        eventType: json['event_type'] as String,
        channel: json['channel'] as String,
        data: (json['data'] as Map<String, dynamic>?) ?? {},
      );

  Map<String, dynamic> toJson() => {
        'event_id': eventId,
        'event_type': eventType,
        'channel': channel,
        'data': data,
      };
}
