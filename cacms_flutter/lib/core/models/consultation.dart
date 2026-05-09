import 'service.dart';

/// A single service line item within a consultation.
class ConsultationService {
  const ConsultationService({
    required this.id,
    required this.serviceId,
    required this.quantity,
    required this.priceApplied,
    this.total,
    this.serviceName,
  });

  final String id;
  final String serviceId;
  final int quantity;
  final double priceApplied;
  final double? total;
  final String? serviceName;

  factory ConsultationService.fromJson(Map<String, dynamic> json) =>
      ConsultationService(
        id: json['id'] as String,
        serviceId: json['service_id'] as String,
        quantity: json['quantity'] as int,
        priceApplied: (json['price_applied'] as num).toDouble(),
        total: json['total'] != null ? (json['total'] as num).toDouble() : null,
        serviceName: json['service_name'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'service_id': serviceId,
        'quantity': quantity,
        'price_applied': priceApplied,
        'total': total,
        'service_name': serviceName,
      };
}

/// Matches backend ConsultationOut schema.
class Consultation {
  const Consultation({
    required this.consultationId,
    required this.appointmentId,
    required this.symptoms,
    required this.diagnosis,
    this.notes,
    this.nextVisitDate,
    required this.services,
    required this.createdAt,
  });

  final String consultationId;
  final String appointmentId;
  final String symptoms;
  final String diagnosis;
  final String? notes;
  final DateTime? nextVisitDate;
  final List<ConsultationService> services;
  final DateTime createdAt;

  factory Consultation.fromJson(Map<String, dynamic> json) => Consultation(
        consultationId: json['consultation_id'] as String,
        appointmentId: json['appointment_id'] as String,
        symptoms: json['symptoms'] as String,
        diagnosis: json['diagnosis'] as String,
        notes: json['notes'] as String?,
        nextVisitDate: json['next_visit_date'] != null
            ? DateTime.parse(json['next_visit_date'] as String)
            : null,
        services: (json['services'] as List<dynamic>? ?? [])
            .map((e) => ConsultationService.fromJson(e as Map<String, dynamic>))
            .toList(),
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  Map<String, dynamic> toJson() => {
        'consultation_id': consultationId,
        'appointment_id': appointmentId,
        'symptoms': symptoms,
        'diagnosis': diagnosis,
        'notes': notes,
        'next_visit_date': nextVisitDate?.toIso8601String(),
        'services': services.map((s) => s.toJson()).toList(),
        'created_at': createdAt.toIso8601String(),
      };
}
