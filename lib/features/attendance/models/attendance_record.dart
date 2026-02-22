class AttendanceRecord {
  final int? id;
  final int sessionId;
  final int studentId;
  final String status;

  AttendanceRecord({
    this.id,
    required this.sessionId,
    required this.studentId,
    required this.status,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'session_id': sessionId,
      'student_id': studentId,
      'status': status,
    };
  }

  factory AttendanceRecord.fromMap(Map<String, dynamic> map) {
    return AttendanceRecord(
      id: map['id'],
      sessionId: map['session_id'],
      studentId: map['student_id'],
      status: map['status'],
    );
  }
}
