import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'downloadFileInfo.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  static Database? _database;

  factory DatabaseHelper() => _instance;

  DatabaseHelper._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;

    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final databasesPath = await getDatabasesPath();
    final path = join(databasesPath, 'downloads.db');

    return await openDatabase(
      path,
      version: 1,
      onCreate: (Database db, int version) async {
        await db.execute('''
          CREATE TABLE downloads (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            url TEXT NOT NULL,
            status TEXT,
            progress REAL,
            totalTsFiles INTEGER,
            downloadedTsFiles INTEGER,
            episodeNumber TEXT,
            isPaused INTEGER,
            isDownloading INTEGER,
            episodeFolderPath TEXT,
            date TEXT, 
            activeTime INTEGER, 
            completedDate TEXT, 
            outputMkvPath TEXT,
            addedDate TEXT, 
            size INTEGER, 
            finished INTEGER,
            speed REAL
          )
        ''');
      },
    );
  }

  // CRUD Operations

  // 1. Create (Insert)
  Future<int> insertDownload(DownloadInfo download) async {
    final db = await database;
    return await db.insert('downloads', download.toMap());
  }

  // 2. Read (Get by ID)
  Future<DownloadInfo?> getDownloadById(int id) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'downloads',
      where: 'id = ?',
      whereArgs: [id],
    );

    if (maps.isNotEmpty) {
      return DownloadInfo.fromMap(maps.first);
    } else {
      return null;
    }
  }

  Future<DownloadInfo?> getDownloadByUrl(String url) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'downloads',
      where: 'url  LIKE ?',
      whereArgs: ['$url%'],
    );

    if (maps.isNotEmpty) {
      return DownloadInfo.fromMap(maps.first);
    } else {
      return null;
    }
  }

  // 3. Read (Get All)
  Future<List<DownloadInfo>> getAllDownloads() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('downloads');
    return List.generate(maps.length, (i) {
      return DownloadInfo.fromMap(maps[i]);
    });
  }

  // 4. Update
  Future<int> updateDownload(DownloadInfo download) async {
    final db = await database;
    try {
      int z = await db.update(
        'downloads',
        download.toMap(),
        where: 'id = ?',
        whereArgs: [download.id],
      );
      return z;
    } catch (e) {
      print('Error updating download: $e');
      return 0; // or throw an exception if you prefer
    }
  }

  // 5. Delete
  Future<int> deleteDownload(int id) async {
    final db = await database;
    return await db.delete(
      'downloads',
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
