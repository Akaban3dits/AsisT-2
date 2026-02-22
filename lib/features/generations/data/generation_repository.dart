import 'package:sqflite/sqflite.dart';
import '../../../core/database/app_database.dart';
import '../models/generation.dart';

class GenerationRepository {
  final db = AppDatabase.instance;

  Future<int> insert(Generation generation) async {
    final database = await db.database;

    return await database.insert(
      'generations',
      generation.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Generation>> getAll() async {
    final database = await db.database;

    final result = await database.query(
      'generations',
      orderBy: 'created_at DESC',
    );

    return result.map((e) => Generation.fromMap(e)).toList();
  }

  Future<int> delete(int id) async {
    final database = await db.database;

    return await database.delete(
      'generations',
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
