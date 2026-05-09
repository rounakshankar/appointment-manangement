/// Matches backend AppointmentOut schema.
class Appointment {
  const Appointment({
    required this.appointmentId,
    required this.patientId,
    required this.doctorId,
    required this.scheduledDate,
    required this.queueNumber,
    required this.visitType,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.patientName,
  });

  final String appointmentId;
  final String patientId;
  final String doctorId;
  final DateTime scheduledDate;
  final int queueNumber;
  final String visitType;
  final String status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? patientName;

  factory Appointment.fromJson(Map<String, dynamic> json) => Appointment(
        appointmentId: json['appointment_id'] as String,
        patientId: json['patient_id'] as String,
        doctorId: json['doctor_id'] as String,
        scheduledDate: DateTime.parse(json['scheduled_date'] as String),
        queueNumber: json['queue_number'] as int,
        visitType: json['visit_type'] as String,
        status: json['status'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
        updatedAt: DateTime.parse(json['updated_at'] as String),
        patientName: json['patient_name'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'appointment_id': appointmentId,
        'patient_id': patientId,
        'doctor_id': doctorId,
        'scheduled_date': scheduledDate.toIso8601String(),
        'queue_number': queueNumber,
        'visit_type': visitType,
        'status': status,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
        'patient_name': patientName,
      };
}
