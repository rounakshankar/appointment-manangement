/// Matches backend PaymentOut schema.
class Payment {
  const Payment({
    required this.paymentId,
    required this.consultationId,
    required this.totalAmount,
    required this.paymentMode,
    required this.status,
    required this.createdAt,
  });

  final String paymentId;
  final String consultationId;
  final double totalAmount;
  final String paymentMode;
  final String status;
  final DateTime createdAt;

  factory Payment.fromJson(Map<String, dynamic> json) => Payment(
        paymentId: json['payment_id'] as String,
        consultationId: json['consultation_id'] as String,
        totalAmount: (json['total_amount'] as num).toDouble(),
        paymentMode: json['payment_mode'] as String,
        status: json['status'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  Map<String, dynamic> toJson() => {
        'payment_id': paymentId,
        'consultation_id': consultationId,
        'total_amount': totalAmount,
        'payment_mode': paymentMode,
        'status': status,
        'created_at': createdAt.toIso8601String(),
      };
}
