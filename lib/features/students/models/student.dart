class Student {
  final int? id;
  final String name;
  final int generationId;
  final DateTime? createdAt;

  Student({
    this.id,
    required this.name,
    required this.generationId,
    this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'generation_id': generationId,
      'created_at': createdAt?.toIso8601String(),
    };
  }

  factory Student.fromMap(Map<String, dynamic> map) {
    return Student(
      id: map['id'],
      name: map['name'],
      generationId: map['generation_id'],
      createdAt: map['created_at'] != null
          ? DateTime.parse(map['created_at'])
          : null,
    );
  }
}
