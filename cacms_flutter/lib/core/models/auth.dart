class ClinicRegistrationRequest {
  final String clinicName;
  final String ownerUsername;
  final String ownerPassword;
  final String? ownerName;
  final String? ownerEmail;
  final String? ownerPhone;

  ClinicRegistrationRequest({
    required this.clinicName,
    required this.ownerUsername,
    required this.ownerPassword,
    this.ownerName,
    this.ownerEmail,
    this.ownerPhone,
  });

  Map<String, dynamic> toJson() => {
    'clinic_name': clinicName,
    'owner_username': ownerUsername,
    'owner_password': ownerPassword,
    if (ownerName != null) 'owner_name': ownerName,
    if (ownerEmail != null) 'owner_email': ownerEmail,
    if (ownerPhone != null) 'owner_phone': ownerPhone,
  };
}

class ClinicRegistrationResponse {
  final String clinicId;
  final String clinicName;
  final String ownerUserId;
  final String accessToken;

  ClinicRegistrationResponse({
    required this.clinicId,
    required this.clinicName,
    required this.ownerUserId,
    required this.accessToken,
  });

  factory ClinicRegistrationResponse.fromJson(Map<String, dynamic> json) {
    return ClinicRegistrationResponse(
      clinicId: json['clinic_id'] as String,
      clinicName: json['clinic_name'] as String,
      ownerUserId: json['owner_user_id'] as String,
      accessToken: json['access_token'] as String,
    );
  }
}

class ClinicInfo {
  final String clinicId;
  final String name;

  ClinicInfo({required this.clinicId, required this.name});

  factory ClinicInfo.fromJson(Map<String, dynamic> json) {
    return ClinicInfo(
      clinicId: json['clinic_id'] as String,
      name: json['name'] as String,
    );
  }
}