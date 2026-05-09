import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:cacms_flutter/core/api/api_client.dart';
import 'package:cacms_flutter/features/patient/otp_login/otp_screen.dart';

import '../../../helpers/mocks.dart';

void main() {
  late MockDio mockDio;
  late MockApiClient mockApiClient;
  late MockTokenStorage mockTokenStorage;

  setUp(() {
    mockDio = MockDio();
    mockApiClient = MockApiClient();
    mockTokenStorage = MockTokenStorage();

    when(() => mockApiClient.dio).thenReturn(mockDio);
    when(() => mockTokenStorage.saveToken(any())).thenAnswer((_) async {});

    registerFallbackValue(RequestOptions(path: ''));
  });

  Widget buildSubject({
    String phone = '9876543210',
    ValueChanged<String>? onVerified,
    VoidCallback? onBack,
  }) {
    return MaterialApp(
      home: PatientOtpScreen(
        phone: phone,
        apiClient: mockApiClient,
        tokenStorage: mockTokenStorage,
        onVerified: onVerified ?? (_) {},
        onBack: onBack ?? () {},
      ),
    );
  }

  /// Enters one digit per OTP box (6 boxes total).
  Future<void> enterOtp(WidgetTester tester, String otp) async {
    final fields = find.byType(TextField);
    // The first box allows up to 6 chars (for SMS autofill), rest allow 1.
    // Entering into the first field with 6 chars triggers autofill path.
    await tester.enterText(fields.first, otp);
    await tester.pump();
  }

  group('PatientOtpScreen', () {
    testWidgets('renders 6 OTP boxes and VERIFY button', (tester) async {
      await tester.pumpWidget(buildSubject());

      expect(find.byType(TextField), findsNWidgets(6));
      expect(find.text('VERIFY'), findsOneWidget);
    });

    testWidgets('shows masked phone number', (tester) async {
      await tester.pumpWidget(buildSubject(phone: '9876543210'));

      // Masked form: +91 ••••••3210
      expect(find.textContaining('3210'), findsOneWidget);
    });

    testWidgets('shows resend countdown on initial render', (tester) async {
      await tester.pumpWidget(buildSubject());

      // Should show "Resend OTP in 00:45" initially
      expect(find.textContaining('Resend OTP in'), findsOneWidget);
    });

    testWidgets('resend timer counts down', (tester) async {
      await tester.pumpWidget(buildSubject());

      // Advance 3 seconds
      await tester.pump(const Duration(seconds: 3));

      expect(find.textContaining('Resend OTP in 00:42'), findsOneWidget);
    });

    testWidgets('resend label changes to "Resend OTP" after countdown',
        (tester) async {
      await tester.pumpWidget(buildSubject());

      // Advance past the full 45-second countdown
      await tester.pump(const Duration(seconds: 46));

      expect(find.text('Resend OTP'), findsOneWidget);
      expect(find.textContaining('Resend OTP in'), findsNothing);
    });

    testWidgets('VERIFY button calls API and triggers onVerified on success',
        (tester) async {
      String? capturedPatientId;

      when(() => mockDio.post(
            any(),
            data: any(named: 'data'),
          )).thenAnswer((_) async => fakeResponse({
            'access_token': 'tok_abc123',
            'patient_id': 'pat_001',
          }));

      await tester.pumpWidget(
        buildSubject(onVerified: (id) => capturedPatientId = id),
      );

      // Entering 6 digits into the first box triggers autofill path which
      // calls _verify() automatically — no need to tap the button separately.
      await enterOtp(tester, '123456');
      await tester.pumpAndSettle();

      expect(capturedPatientId, equals('pat_001'));
      verify(() => mockTokenStorage.saveToken('tok_abc123')).called(1);
    });

    testWidgets('shows error message when OTP is wrong (API error)',
        (tester) async {
      when(() => mockDio.post(
            any(),
            data: any(named: 'data'),
          )).thenThrow(
        const ApiError(
          errorCode: 'INVALID_OTP',
          message: 'Invalid or expired OTP.',
        ),
      );

      await tester.pumpWidget(buildSubject());

      // Entering 6 digits auto-triggers verify via autofill path
      await enterOtp(tester, '000000');
      await tester.pumpAndSettle();

      expect(find.text('Invalid or expired OTP.'), findsOneWidget);
    });

    testWidgets('shows error when fewer than 6 digits entered and VERIFY tapped',
        (tester) async {
      await tester.pumpWidget(buildSubject());

      // Enter only 3 digits into first box
      await tester.enterText(find.byType(TextField).first, '123');
      await tester.pump();

      await tester.tap(find.widgetWithText(ElevatedButton, 'VERIFY'));
      await tester.pump();

      expect(find.text('Enter all 6 digits'), findsOneWidget);
    });

    testWidgets('VERIFY button is enabled (not loading) initially',
        (tester) async {
      await tester.pumpWidget(buildSubject());

      final button = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'VERIFY'),
      );
      expect(button.onPressed, isNotNull);
    });
  });
}
