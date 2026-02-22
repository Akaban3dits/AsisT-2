class AttendanceSession {
  final int? id;
  final int generationId;
  final String date;
  final int isClosed;

  AttendanceSession({
    this.id,
    required this.generationId,
    required this.date,
    this.isClosed = 0,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'generation_id': generationId,
      'date': date,
      'is_closed': isClosed,
    };
  }

  factory AttendanceSession.fromMap(Map<String, dynamic> map) {
    return AttendanceSession(
      id: map['id'],
      generationId: map['generation_id'],
      date: map['date'],
      isClosed: map['is_closed'],
    );
  }
}
