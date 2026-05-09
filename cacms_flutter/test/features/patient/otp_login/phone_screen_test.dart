import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:cacms_flutter/core/api/api_client.dart';
import 'package:cacms_flutter/features/patient/otp_login/phone_screen.dart';

import '../../../helpers/mocks.dart';

void main() {
  late MockDio mockDio;
  late MockApiClient mockApiClient;

  setUp(() {
    mockDio = MockDio();
    mockApiClient = MockApiClient();
    when(() => mockApiClient.dio).thenReturn(mockDio);

    // Register fallback values for Dio
    registerFallbackValue(RequestOptions(path: ''));
  });

  Widget buildSubject({ValueChanged<String>? onOtpSent}) {
    return MaterialApp(
      home: PatientPhoneScreen(
        apiClient: mockApiClient,
        onOtpSent: onOtpSent ?? (_) {},
      ),
    );
  }

  group('PatientPhoneScreen', () {
    testWidgets('renders phone input and SEND OTP button', (tester) async {
      await tester.pumpWidget(buildSubject());

      expect(find.text('SEND OTP'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('SEND OTP button is enabled when 10 digits are entered',
        (tester) async {
      when(() => mockDio.post(
            any(),
            data: any(named: 'data'),
          )).thenAnswer((_) async => fakeResponse({'message': 'OTP sent'}));

      await tester.pumpWidget(buildSubject());

      await tester.enterText(find.byType(TextField), '9876543210');
      await tester.pump();

      final button = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'SEND OTP'),
      );
      expect(button.onPressed, isNotNull);
    });

    testWidgets('SEND OTP button calls API and triggers onOtpSent on success',
        (tester) async {
      String? capturedPhone;

      when(() => mockDio.post(
            any(),
            data: any(named: 'data'),
          )).thenAnswer((_) async => fakeResponse({'message': 'OTP sent'}));

      await tester.pumpWidget(buildSubject(onOtpSent: (p) => capturedPhone = p));

      await tester.enterText(find.byType(TextField), '9876543210');
      await tester.pump();

      await tester.tap(find.widgetWithText(ElevatedButton, 'SEND OTP'));
      await tester.pumpAndSettle();

      expect(capturedPhone, equals('9876543210'));
    });

    testWidgets('shows error when fewer than 10 digits are entered and button tapped',
        (tester) async {
      await tester.pumpWidget(buildSubject());

      // Enter only 5 digits
      await tester.enterText(find.byType(TextField), '98765');
      await tester.pump();

      await tester.tap(find.widgetWithText(ElevatedButton, 'SEND OTP'));
      await tester.pump();

      expect(find.text('Enter a valid 10-digit phone number'), findsOneWidget);
    });

    testWidgets('shows error when phone field is empty and button tapped',
        (tester) async {
      await tester.pumpWidget(buildSubject());

      await tester.tap(find.widgetWithText(ElevatedButton, 'SEND OTP'));
      await tester.pump();

      expect(find.text('Enter a valid 10-digit phone number'), findsOneWidget);
    });

    testWidgets('shows API error message when request fails', (tester) async {
      when(() => mockDio.post(
            any(),
            data: any(named: 'data'),
          )).thenThrow(
        const ApiError(
          errorCode: 'INVALID_PHONE',
          message: 'Phone number not registered.',
        ),
      );

      await tester.pumpWidget(buildSubject());

      await tester.enterText(find.byType(TextField), '9999999999');
      await tester.pump();

      await tester.tap(find.widgetWithText(ElevatedButton, 'SEND OTP'));
      await tester.pumpAndSettle();

      expect(find.text('Phone number not registered.'), findsOneWidget);
    });

    testWidgets('clears error message when user starts typing again',
        (tester) async {
      await tester.pumpWidget(buildSubject());

      // Trigger error
      await tester.tap(find.widgetWithText(ElevatedButton, 'SEND OTP'));
      await tester.pump();
      expect(find.text('Enter a valid 10-digit phone number'), findsOneWidget);

      // Start typing — error should clear
      await tester.enterText(find.byType(TextField), '9');
      await tester.pump();
      expect(find.text('Enter a valid 10-digit phone number'), findsNothing);
    });
  });
}
