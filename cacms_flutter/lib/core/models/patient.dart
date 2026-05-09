/// Matches backend PatientOut schema.
class Patient {
  const Patient({
    required this.patientId,
    required this.name,
    required this.phone,
    this.age,
    this.gender,
    this.address,
    required this.consentGiven,
    this.consentDate,
    required this.createdAt,
  });

  final String patientId;
  final String name;
  final String phone;
  final int? age;
  final String? gender;
  final String? address;
  final bool consentGiven;
  final DateTime? consentDate;
  final DateTime createdAt;

  factory Patient.fromJson(Map<String, dynamic> json) => Patient(
        patientId: json['patient_id'] as String,
        name: json['name'] as String,
        phone: json['phone'] as String,
        age: json['age'] as int?,
        gender: json['gender'] as String?,
        address: json['address'] as String?,
        consentGiven: json['consent_given'] as bool,
        consentDate: json['consent_date'] != null
            ? DateTime.parse(json['consent_date'] as String)
            : null,
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  Map<String, dynamic> toJson() => {
        'patient_id': patientId,
        'name': name,
        'phone': phone,
        'age': age,
        'gender': gender,
        'address': address,
        'consent_given': consentGiven,
        'consent_date': consentDate?.toIso8601String(),
        'created_at': createdAt.toIso8601String(),
      };
}
