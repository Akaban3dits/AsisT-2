import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class AppDatabase {
  static final AppDatabase instance = AppDatabase._init();
  static Database? _database;

  AppDatabase._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('attendance.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);
    
    // Abrir con modo de escritura explícito
    return await openDatabase(
      path,
      version: 1,
      onCreate: _createDB,
      readOnly: false, // Asegurar que NO sea solo lectura
      singleInstance: true, // Una sola instancia
    );
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
    CREATE TABLE generations (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL UNIQUE,
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP
    )
  ''');

    await db.execute('''
    CREATE TABLE students (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      generation_id INTEGER NOT NULL,
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
      FOREIGN KEY (generation_id) REFERENCES generations(id)
    )
  ''');

    await db.execute('''
    CREATE TABLE attendance_sessions (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      generation_id INTEGER NOT NULL,
      date TEXT NOT NULL,
      is_closed INTEGER DEFAULT 0,
      FOREIGN KEY (generation_id) REFERENCES generations(id),
      UNIQUE (generation_id, date)
    )
  ''');

    await db.execute('''
    CREATE TABLE attendance_records (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      session_id INTEGER NOT NULL,
      student_id INTEGER NOT NULL,
      status TEXT NOT NULL CHECK (
        status IN ('present', 'late', 'absent', 'justified')
      ),
      FOREIGN KEY (session_id) REFERENCES attendance_sessions(id),
      FOREIGN KEY (student_id) REFERENCES students(id),
      UNIQUE (session_id, student_id)
    )
  ''');
  }
  
  // Método para cerrar la base de datos si es necesario
  Future close() async {
    final db = _database;
    if (db != null) {
      await db.close();
      _database = null;
    }
  }
}