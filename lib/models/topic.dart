class Topic {
  final String id;
  final String name;
  final String projectId;

  const Topic({
    required this.id,
    required this.name,
    required this.projectId,
  });

  Topic copyWith({
    String? id,
    String? name,
    String? projectId,
  }) {
    return Topic(
      id: id ?? this.id,
      name: name ?? this.name,
      projectId: projectId ?? this.projectId,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'projectId': projectId,
    };
  }

  factory Topic.fromJson(Map<String, dynamic> json) {
    return Topic(
      id: json['id'] as String? ?? '',
      name: (json['name'] ?? '') as String,
      projectId: (json['projectId'] ?? '') as String,
    );
  }
}
