class Generation {
  final int? id;
  final String name;
  final DateTime? createdAt;

  Generation({
    this.id,
    required this.name,
    this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'created_at': createdAt?.toIso8601String(),
    };
  }

  factory Generation.fromMap(Map<String, dynamic> map) {
    return Generation(
      id: map['id'],
      name: map['name'],
      createdAt: map['created_at'] != null
          ? DateTime.parse(map['created_at'])
          : null,
    );
  }
}
