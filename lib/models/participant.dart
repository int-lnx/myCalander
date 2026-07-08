class Participant {
  final String id;
  final String name;
  final String? email;

  const Participant({
    required this.id,
    required this.name,
    this.email,
  });

  Participant copyWith({
    String? id,
    String? name,
    String? email,
    bool clearEmail = false,
  }) {
    return Participant(
      id: id ?? this.id,
      name: name ?? this.name,
      email: clearEmail ? null : (email ?? this.email),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'email': email,
    };
  }

  factory Participant.fromJson(Map<String, dynamic> json) {
    return Participant(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      email: json['email'] as String?,
    );
  }
}
