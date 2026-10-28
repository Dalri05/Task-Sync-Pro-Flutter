import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:to_do_app/data/sync/task_sync.dart';
import 'package:to_do_app/model/task_model.dart';

/// Banco local (fonte da verdade da UI) + fila de envio para o Firebase.
///
/// Toda alteração grava primeiro em `Tasks` e depois enfileira a task inteira
/// em `PendingUploads` (outbox). Quem tira da fila é o [TaskSync], e só depois
/// que o Firebase confirmou a escrita — assim nada se perde se a conexão cair
/// no meio do caminho ou o app for fechado offline.
class DbHelper implements TaskLocalStore {
  // compartilhado: Home e AddTask criam instâncias próprias do helper
  static Database? _db;

  Future<Database?> get db async {
    if (_db != null) {
      return _db;
    }
    final directory = Platform.isAndroid
        ? await getExternalStorageDirectory()
        : await getApplicationSupportDirectory();
    String path = join(directory!.path, 'db');
    _db = await openDatabase(path, version: 1, onCreate: (db, version) async {
      await createSchema(db);
    });
    await _recoverPendingUploads(_db!);
    return _db;
  }

  static Future<void> createSchema(Database db) async {
    await db.execute(
        "CREATE TABLE Tasks(key TEXT PRIMARY KEY,title TEXT,category TEXT,description TEXT,image TEXT,date TEXT,time,periority TEXT,show TEXT,progress TEXT,status,TEXT)");
    await db.execute(
        "CREATE TABLE PendingUploads(key TEXT PRIMARY KEY,title TEXT,category TEXT,description TEXT,image TEXT,date TEXT,time,periority TEXT,show TEXT,progress TEXT,status,TEXT)");
    await db.execute(
        "CREATE TABLE PendingDeletes(key TEXT PRIMARY KEY,title TEXT,category TEXT,description TEXT,image TEXT,date TEXT,time,periority TEXT,show TEXT,progress TEXT,status,TEXT)");
  }

  /// Versões antigas guardavam a task criada offline SÓ em PendingUploads.
  /// Copia para Tasks o que estiver só na fila, para a lista não depender dela.
  static Future<void> _recoverPendingUploads(Database db) async {
    await db
        .execute('INSERT OR IGNORE INTO Tasks SELECT * FROM PendingUploads');
  }

  /// Testes: usa um banco já aberto (ex.: sqflite_common_ffi em memória).
  @visibleForTesting
  static Future<void> useDatabase(Database? database) async {
    _db = database;
    if (database != null) await _recoverPendingUploads(database);
  }

  /// Grava uma task criada/alterada no app: local + fila de envio.
  Future<TaskModel> insert(TaskModel model) async {
    await _saveAndEnqueue(model);
    return model;
  }

  Future<void> update(TaskModel model) => _saveAndEnqueue(model);

  /// Remoção é lógica (show = 'no') e também vai para a fila.
  Future<void> removeFromList(TaskModel model) async {
    var dbClient = await db;
    final rows = await dbClient!
        .query('Tasks', where: 'key = ?', whereArgs: [model.key!]);
    final current = rows.isEmpty ? model : TaskModel.fromMap(rows.first);
    current.show = 'no';
    await _saveAndEnqueue(current);
  }

  Future<void> _saveAndEnqueue(TaskModel model) async {
    var dbClient = await db;
    await dbClient!.transaction((txn) async {
      await txn.insert('Tasks', model.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace);
      await txn.insert('PendingUploads', model.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  /// Task que veio do Firebase: grava só local, sem reenfileirar. Se houver
  /// alteração local ainda não enviada, ela ganha (não sobrescreve).
  Future<bool> saveFromRemote(TaskModel model) async {
    var dbClient = await db;
    if (await isRowExists(model.key!, 'PendingUploads')) return false;
    await dbClient!.insert('Tasks', model.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
    return true;
  }

  Future<int> delete(String id, String table) async {
    var dbClient = await db;
    return await dbClient!.delete(table, where: 'key = ?', whereArgs: [id]);
  }

  Future<List<TaskModel>> getData() async {
    var dbClient = await db;
    final List<Map<String, Object?>> queryResult =
        await dbClient!.query('Tasks');
    return queryResult.map((e) => TaskModel.fromMap(e)).toList();
  }

  @override
  Future<List<TaskModel>> getPendingUploads() async {
    var dbClient = await db;
    final List<Map<String, Object?>> queryResult =
        await dbClient!.query('PendingUploads');
    return queryResult.map((e) => TaskModel.fromMap(e)).toList();
  }

  /// Fila antiga de remoções (só existe em bases de versões anteriores).
  @override
  Future<List<TaskModel>> getPendingDeletes() async {
    var dbClient = await db;
    final List<Map<String, Object?>> queryResult =
        await dbClient!.query('PendingDeletes');
    return queryResult.map((e) => TaskModel.fromMap(e)).toList();
  }

  /// Tira da fila só se a linha ainda for a que foi enviada: se o usuário
  /// mexeu na task durante o envio, a versão nova continua pendente.
  @override
  Future<void> removePendingUpload(TaskModel sent) async {
    var dbClient = await db;
    await dbClient!.transaction((txn) async {
      final rows = await txn
          .query('PendingUploads', where: 'key = ?', whereArgs: [sent.key!]);
      if (rows.isEmpty) return;
      if (!mapEquals(TaskModel.fromMap(rows.first).toMap(), sent.toMap())) {
        return;
      }
      await txn
          .delete('PendingUploads', where: 'key = ?', whereArgs: [sent.key!]);
    });
  }

  @override
  Future<void> removePendingDelete(String key) async {
    await delete(key, 'PendingDeletes');
  }

  Future<bool> isRowExists(String id, String table) async {
    var dbClient = await db;
    var count = await dbClient!.query(table, where: 'key = ?', whereArgs: [id]);

    return count.isNotEmpty;
  }
}
