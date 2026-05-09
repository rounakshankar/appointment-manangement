/// Matches backend ServiceOut schema.
class Service {
  const Service({
    required this.serviceId,
    required this.name,
    required this.category,
    required this.basePrice,
    required this.active,
  });

  final String serviceId;
  final String name;
  final String category;
  final double basePrice;
  final bool active;

  factory Service.fromJson(Map<String, dynamic> json) => Service(
        serviceId: json['service_id'] as String,
        name: json['name'] as String,
        category: json['category'] as String,
        basePrice: (json['base_price'] as num).toDouble(),
        active: json['active'] as bool,
      );

  Map<String, dynamic> toJson() => {
        'service_id': serviceId,
        'name': name,
        'category': category,
        'base_price': basePrice,
        'active': active,
      };
}
