import 'package:sqflite/sqflite.dart';
import '../../../core/database/app_database.dart';
import '../models/student.dart';

class StudentRepository {
  final db = AppDatabase.instance;

  Future<int> insert(Student student) async {
    final database = await db.database;

    return await database.insert(
      'students',
      student.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Student>> getByGeneration(int generationId) async {
    final database = await db.database;

    final result = await database.query(
      'students',
      where: 'generation_id = ?',
      whereArgs: [generationId],
      orderBy: 'name ASC',
    );

    return result.map((e) => Student.fromMap(e)).toList();
  }

  Future<int> delete(int id) async {
    final database = await db.database;

    return await database.delete('students', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> countByGeneration(int generationId) async {
    final database = await db.database;

    final result = await database.rawQuery(
      'SELECT COUNT(*) as total FROM students WHERE generation_id = ?',
      [generationId],
    );

    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<void> bulkInsert(List<Student> students) async {
    final database = await db.database;

    await database.transaction((txn) async {
      for (var student in students) {
        await txn.insert(
          'students',
          student.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }
}
