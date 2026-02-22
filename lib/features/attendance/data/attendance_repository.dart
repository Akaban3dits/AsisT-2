import 'package:sqflite/sqflite.dart';
import '../../../core/database/app_database.dart';
import '../models/attendance_session.dart';
import '../models/attendance_record.dart';

class AttendanceRepository {
  final db = AppDatabase.instance;
  
  // =========================
  // ATTENDANCE STATUSES
  // =========================
  // Supported statuses: 'present', 'late', 'absent', 'justified'
  
  // =========================
  // FORMAT DATE
  // =========================
  String _formatDate(DateTime date) {
    return "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
  }
  
  // =========================
  // SESSION
  // =========================
  Future<int> createOrGetSessionByDate(int generationId, DateTime date) async {
    final database = await db.database;
    final formattedDate = _formatDate(date);
    
    final result = await database.query(
      'attendance_sessions',
      where: 'generation_id = ? AND date = ?',
      whereArgs: [generationId, formattedDate],
    );
    
    if (result.isNotEmpty) return result.first['id'] as int;
    
    return await database.insert(
      'attendance_sessions',
      AttendanceSession(
        generationId: generationId,
        date: formattedDate,
      ).toMap(),
    );
  }
  
  // =========================
  // RECORDS
  // =========================
  Future<void> saveRecord(int sessionId, int studentId, String status) async {
    final database = await db.database;
    
    await database.insert(
      'attendance_records',
      AttendanceRecord(
        sessionId: sessionId,
        studentId: studentId,
        status: status,
      ).toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
  
  /// ⚡ UNA sola query
  Future<Map<int, String>> getSessionStatuses(int sessionId) async {
    final database = await db.database;
    
    final result = await database.query(
      'attendance_records',
      where: 'session_id = ?',
      whereArgs: [sessionId],
    );
    
    return {
      for (var row in result) row['student_id'] as int: row['status'] as String,
    };
  }
  
  // =========================
  // EXCEL IMPORT (NO ANR)
  // =========================
  Future<void> importExcelStudents(List<Map<String, dynamic>> rows) async {
    final database = await db.database;
    
    await database.transaction((txn) async {
      final batch = txn.batch();
      for (final row in rows) {
        batch.insert(
          'students',
          row,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    });
  }
  
  Future<List<Map<String, dynamic>>> getStudentReport(int studentId) async {
    final database = await db.database;
    
    // Primero obtener los registros
    final records = await database.query(
      'attendance_records',
      where: 'student_id = ?',
      whereArgs: [studentId],
    );
    
    // Luego obtener las sesiones correspondientes
    final result = <Map<String, dynamic>>[];
    for (final record in records) {
      final sessionId = record['session_id'] as int;
      final sessions = await database.query(
        'attendance_sessions',
        where: 'id = ?',
        whereArgs: [sessionId],
      );
      
      if (sessions.isNotEmpty) {
        result.add({
          'date': sessions.first['date'],
          'status': record['status'],
          'session_id': sessionId,
        });
      }
    }
    
    // Ordenar por fecha descendente
    result.sort((a, b) => (b['date'] as String).compareTo(a['date'] as String));
    
    return result;
  }
  
  // =========================
  // UPDATE RECORD STATUS
  // =========================
  Future<void> updateRecordStatus({
    required int sessionId,
    required int studentId,
    required String newStatus,
  }) async {
    final database = await db.database;
    
    final count = await database.update(
      'attendance_records',
      {'status': newStatus},
      where: 'session_id = ? AND student_id = ?',
      whereArgs: [sessionId, studentId],
    );
    
    if (count == 0) {
      throw Exception('No record found to update');
    }
  }
}