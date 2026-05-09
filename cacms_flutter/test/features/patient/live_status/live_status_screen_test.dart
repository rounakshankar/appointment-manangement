import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:cacms_flutter/core/api/api_client.dart';
import 'package:cacms_flutter/core/api/sse_client.dart';
import 'package:cacms_flutter/core/widgets/queue_number_display.dart';
import 'package:cacms_flutter/core/widgets/empty_state.dart';
import 'package:cacms_flutter/features/patient/live_status/live_status_screen.dart';

import '../../../helpers/mocks.dart';

// ---------------------------------------------------------------------------
// Fake ApiClient that wraps a MockDio
// ---------------------------------------------------------------------------

class _FakeApiClient extends Fake implements ApiClient {
  _FakeApiClient(this._dio);
  final Dio _dio;

  @override
  Dio get dio => _dio;
}

// ---------------------------------------------------------------------------
// Status JSON builders
// ---------------------------------------------------------------------------

Map<String, dynamic> _noAppointmentJson({Map<String, dynamic>? lastVisit}) => {
      'status': 'no_appointment',
      if (lastVisit != null) 'last_visit': lastVisit,
    };

Map<String, dynamic> _scheduledJson({
  int queueNumber = 5,
  int queuePosition = 5,
  String doctorName = 'Dr. Smith',
}) =>
    {
      'status': 'scheduled',
      'queue_position': queuePosition,
      'doctor_name': doctorName,
      'appointment': {
        'appointment_id': 'appt_001',
        'patient_id': 'pat_001',
        'doctor_id': 'doc_001',
        'scheduled_date': '2024-06-01T09:00:00.000Z',
        'queue_number': queueNumber,
        'visit_type': 'new',
        'status': 'scheduled',
        'created_at': '2024-06-01T08:00:00.000Z',
        'updated_at': '2024-06-01T08:00:00.000Z',
      },
    };

Map<String, dynamic> _inProgressJson({
  String doctorName = 'Dr. Patel',
  String specialization = 'General Medicine',
}) =>
    {
      'status': 'in-progress',
      'doctor_name': doctorName,
      'doctor_specialization': specialization,
    };

Map<String, dynamic> _completedJson() => {
      'status': 'completed',
      'doctor_name': 'Dr. Rao',
      'appointment': {
        'appointment_id': 'appt_002',
        'patient_id': 'pat_001',
        'doctor_id': 'doc_002',
        'scheduled_date': '2024-06-01T09:00:00.000Z',
        'queue_number': 3,
        'visit_type': 'new',
        'status': 'completed',
        'created_at': '2024-06-01T08:00:00.000Z',
        'updated_at': '2024-06-01T10:00:00.000Z',
      },
      'consultation': {
        'consultation_id': 'cons_001',
        'appointment_id': 'appt_002',
        'symptoms': 'Fever, cough',
        'diagnosis': 'Viral fever',
        'notes': 'Rest and fluids',
        'next_visit_date': '2024-06-15T09:00:00.000Z',
        'services': [
          {
            'id': 'cs_001',
            'service_id': 'svc_001',
            'quantity': 1,
            'price_applied': 500.0,
            'total': 500.0,
            'service_name': 'Consultation',
          },
          {
            'id': 'cs_002',
            'service_id': 'svc_002',
            'quantity': 2,
            'price_applied': 150.0,
            'total': 300.0,
            'service_name': 'Blood Test',
          },
        ],
        'created_at': '2024-06-01T10:00:00.000Z',
      },
    };

// ---------------------------------------------------------------------------
// Test setup helper
// ---------------------------------------------------------------------------

Widget _buildScreen(
  ApiClient apiClient, {
  String patientId = 'pat_001',
  VoidCallback? onLogout,
}) {
  return MaterialApp(
    home: PatientLiveStatusScreen(
      patientId: patientId,
      apiClient: apiClient,
      onLogout: onLogout ?? () {},
      // Inject a no-op SSE client so tests don't create real HTTP connections
      // or pending reconnect timers.
      sseClientFactory: (_) => FakeSseClient(),
    ),
  );
}

/// Pumps enough frames for the async _fetchStatus() to complete.
/// Uses pump(Duration.zero) to process microtasks without advancing
/// the animation clock, avoiding pumpAndSettle timeout from infinite
/// animations (pulse controller, SSE reconnect timers).
Future<void> _pumpUntilLoaded(WidgetTester tester) async {
  // Process the initial frame
  await tester.pump();
  // Allow the Future from dio.post to complete
  await tester.pump(const Duration(milliseconds: 100));
  // One more frame to rebuild with the new state
  await tester.pump();
}

void main() {
  late MockDio mockDio;
  late _FakeApiClient fakeApiClient;

  setUp(() {
    mockDio = MockDio();
    // Provide a base URL so SseClient can build its URL
    when(() => mockDio.options).thenReturn(
      BaseOptions(baseUrl: 'http://localhost:8000'),
    );
    fakeApiClient = _FakeApiClient(mockDio);

    registerFallbackValue(RequestOptions(path: ''));
  });

  group('PatientLiveStatusScreen — no appointment state', () {
    testWidgets('shows "No appointment today" and EmptyState widget',
        (tester) async {
      when(() => mockDio.post(
            any(),
            data: any(named: 'data'),
          )).thenAnswer((_) async => fakeResponse(_noAppointmentJson()));

      await tester.pumpWidget(_buildScreen(fakeApiClient));
      await _pumpUntilLoaded(tester);

      expect(find.byType(EmptyState), findsOneWidget);
      expect(find.text('No appointment today'), findsOneWidget);
    });

    testWidgets('shows LAST VISIT card when last_visit data is present',
        (tester) async {
      when(() => mockDio.post(
            any(),
            data: any(named: 'data'),
          )).thenAnswer((_) async => fakeResponse(_noAppointmentJson(
            lastVisit: {
              'date': '2024-05-15',
              'doctor_name': 'Dr. Kumar',
              'diagnosis': 'Hypertension',
              'next_visit_date': '2024-06-15',
            },
          )));

      await tester.pumpWidget(_buildScreen(fakeApiClient));
      await _pumpUntilLoaded(tester);

      expect(find.text('LAST VISIT'), findsOneWidget);
      expect(find.text('Dr. Kumar'), findsOneWidget);
      expect(find.text('Hypertension'), findsOneWidget);
    });

    testWidgets('does not show LAST VISIT card when no last_visit data',
        (tester) async {
      when(() => mockDio.post(
            any(),
            data: any(named: 'data'),
          )).thenAnswer((_) async => fakeResponse(_noAppointmentJson()));

      await tester.pumpWidget(_buildScreen(fakeApiClient));
      await _pumpUntilLoaded(tester);

      expect(find.text('LAST VISIT'), findsNothing);
    });
  });

  group('PatientLiveStatusScreen — scheduled state', () {
    testWidgets('shows QueueNumberDisplay with correct queue number',
        (tester) async {
      when(() => mockDio.post(
            any(),
            data: any(named: 'data'),
          )).thenAnswer((_) async =>
          fakeResponse(_scheduledJson(queueNumber: 7, queuePosition: 7)));

      await tester.pumpWidget(_buildScreen(fakeApiClient));
      await _pumpUntilLoaded(tester);

      expect(find.byType(QueueNumberDisplay), findsOneWidget);
      // Queue number 7 is displayed as "007"
      expect(find.text('007'), findsOneWidget);
    });

    testWidgets('shows doctor name in subtitle', (tester) async {
      when(() => mockDio.post(
            any(),
            data: any(named: 'data'),
          )).thenAnswer((_) async =>
          fakeResponse(_scheduledJson(doctorName: 'Dr. Smith')));

      await tester.pumpWidget(_buildScreen(fakeApiClient));
      await _pumpUntilLoaded(tester);

      expect(find.textContaining('Dr. Smith'), findsOneWidget);
    });

    testWidgets('shows "Your Queue #" label', (tester) async {
      when(() => mockDio.post(
            any(),
            data: any(named: 'data'),
          )).thenAnswer((_) async => fakeResponse(_scheduledJson()));

      await tester.pumpWidget(_buildScreen(fakeApiClient));
      await _pumpUntilLoaded(tester);

      expect(find.text('Your Queue #'), findsOneWidget);
    });

    testWidgets('shows wait message', (tester) async {
      when(() => mockDio.post(
            any(),
            data: any(named: 'data'),
          )).thenAnswer((_) async => fakeResponse(_scheduledJson()));

      await tester.pumpWidget(_buildScreen(fakeApiClient));
      await _pumpUntilLoaded(tester);

      expect(find.textContaining('Please wait'), findsOneWidget);
    });
  });

  group('PatientLiveStatusScreen — in-progress state', () {
    testWidgets('shows "You are being seen now" card', (tester) async {
      when(() => mockDio.post(
            any(),
            data: any(named: 'data'),
          )).thenAnswer((_) async => fakeResponse(_inProgressJson()));

      await tester.pumpWidget(_buildScreen(fakeApiClient));
      await _pumpUntilLoaded(tester);

      expect(find.textContaining('You are being seen now'), findsOneWidget);
    });

    testWidgets('shows doctor name in in-progress card', (tester) async {
      when(() => mockDio.post(
            any(),
            data: any(named: 'data'),
          )).thenAnswer((_) async =>
          fakeResponse(_inProgressJson(doctorName: 'Dr. Patel')));

      await tester.pumpWidget(_buildScreen(fakeApiClient));
      await _pumpUntilLoaded(tester);

      expect(find.text('Dr. Patel'), findsOneWidget);
    });

    testWidgets('shows doctor specialization in in-progress card',
        (tester) async {
      when(() => mockDio.post(
            any(),
            data: any(named: 'data'),
          )).thenAnswer((_) async => fakeResponse(_inProgressJson(
            specialization: 'Cardiology',
          )));

      await tester.pumpWidget(_buildScreen(fakeApiClient));
      await _pumpUntilLoaded(tester);

      expect(find.text('Cardiology'), findsOneWidget);
    });
  });

  group('PatientLiveStatusScreen — completed state', () {
    testWidgets('shows "Visit complete ✓" heading', (tester) async {
      when(() => mockDio.post(
            any(),
            data: any(named: 'data'),
          )).thenAnswer((_) async => fakeResponse(_completedJson()));

      await tester.pumpWidget(_buildScreen(fakeApiClient));
      await _pumpUntilLoaded(tester);

      expect(find.text('Visit complete ✓'), findsOneWidget);
    });

    testWidgets('shows VISIT SUMMARY card', (tester) async {
      when(() => mockDio.post(
            any(),
            data: any(named: 'data'),
          )).thenAnswer((_) async => fakeResponse(_completedJson()));

      await tester.pumpWidget(_buildScreen(fakeApiClient));
      await _pumpUntilLoaded(tester);

      expect(find.text('VISIT SUMMARY'), findsOneWidget);
    });

    testWidgets('shows diagnosis in visit summary', (tester) async {
      when(() => mockDio.post(
            any(),
            data: any(named: 'data'),
          )).thenAnswer((_) async => fakeResponse(_completedJson()));

      await tester.pumpWidget(_buildScreen(fakeApiClient));
      await _pumpUntilLoaded(tester);

      expect(find.text('Viral fever'), findsOneWidget);
    });

    testWidgets('shows service line items with prices', (tester) async {
      when(() => mockDio.post(
            any(),
            data: any(named: 'data'),
          )).thenAnswer((_) async => fakeResponse(_completedJson()));

      await tester.pumpWidget(_buildScreen(fakeApiClient));
      await _pumpUntilLoaded(tester);

      expect(find.text('Consultation'), findsOneWidget);
      expect(find.text('Blood Test'), findsOneWidget);
    });

    testWidgets('shows total amount', (tester) async {
      when(() => mockDio.post(
            any(),
            data: any(named: 'data'),
          )).thenAnswer((_) async => fakeResponse(_completedJson()));

      await tester.pumpWidget(_buildScreen(fakeApiClient));
      await _pumpUntilLoaded(tester);

      // Total = 500 + 300 = 800
      expect(find.text('₹800.00'), findsOneWidget);
    });

    testWidgets('shows next visit date', (tester) async {
      when(() => mockDio.post(
            any(),
            data: any(named: 'data'),
          )).thenAnswer((_) async => fakeResponse(_completedJson()));

      await tester.pumpWidget(_buildScreen(fakeApiClient));
      await _pumpUntilLoaded(tester);

      expect(find.textContaining('Next Visit'), findsOneWidget);
      expect(find.textContaining('15 Jun 2024'), findsOneWidget);
    });
  });

  group('PatientLiveStatusScreen — loading and error states', () {
    testWidgets('shows loading indicator while fetching', (tester) async {
      final completer = Completer<Response<dynamic>>();
      when(() => mockDio.post(
            any(),
            data: any(named: 'data'),
          )).thenAnswer((_) => completer.future);

      await tester.pumpWidget(_buildScreen(fakeApiClient));
      await tester.pump(); // one frame — still loading

      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Complete to avoid pending timers
      completer.complete(fakeResponse(_noAppointmentJson()));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();
    });

    testWidgets('shows error EmptyState when API call fails', (tester) async {
      when(() => mockDio.post(
            any(),
            data: any(named: 'data'),
          )).thenThrow(Exception('Network error'));

      await tester.pumpWidget(_buildScreen(fakeApiClient));
      await _pumpUntilLoaded(tester);

      expect(find.text('Unable to load status'), findsOneWidget);
    });
  });
}
