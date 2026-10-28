import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:to_do_app/model/task_model.dart';
import 'package:to_do_app/view%20model/DbHelper/db_helper.dart';

TaskModel makeTask(String key, {String status = 'todo', String show = 'yes'}) =>
    TaskModel(
      key: key,
      title: 'Task $key',
      category: 'Work',
      description: 'desc',
      image: 'img.png',
      periority: 'Low',
      time: '10:00 AM',
      date: '5 Sep 2026',
      show: show,
      progress: '0',
      status: status,
    );

void main() {
  late Database database;
  final db = DbHelper();

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    database = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath,
        options: OpenDatabaseOptions(
            version: 1,
            singleInstance: false,
            onCreate: (db, _) => DbHelper.createSchema(db)));
    await DbHelper.useDatabase(database);
  });

  tearDown(() async {
    await DbHelper.useDatabase(null);
    await database.close();
  });

  test('task criada offline aparece na lista e fica na fila', () async {
    await db.insert(makeTask('1'));

    expect((await db.getData()).map((t) => t.key), ['1']);
    expect((await db.getPendingUploads()).map((t) => t.key), ['1']);
  });

  test('mudança de status de task criada offline não se perde', () async {
    await db.insert(makeTask('1'));
    await db.update(makeTask('1', status: 'complete'));

    expect((await db.getData()).single.status, 'complete');
    expect((await db.getPendingUploads()).single.status, 'complete');
  });

  test('remoção offline vai para a fila com show = no', () async {
    await db.insert(makeTask('1'));
    await db.removeFromList(makeTask('1', show: 'no'));

    expect((await db.getData()).single.show, 'no');
    expect((await db.getPendingUploads()).single.show, 'no');
  });

  test('só tira da fila a versão que foi enviada', () async {
    final sent = makeTask('1');
    await db.insert(sent);
    await db.update(makeTask('1', status: 'complete'));

    await db.removePendingUpload(sent);
    expect((await db.getPendingUploads()).single.status, 'complete');

    await db.removePendingUpload(makeTask('1', status: 'complete'));
    expect(await db.getPendingUploads(), isEmpty);
    expect((await db.getData()).single.status, 'complete');
  });

  test('dado do Firebase não sobrescreve alteração local pendente', () async {
    await db.insert(makeTask('1', status: 'complete'));

    expect(await db.saveFromRemote(makeTask('1')), isFalse);
    expect((await db.getData()).single.status, 'complete');

    expect(await db.saveFromRemote(makeTask('2')), isTrue);
    expect(await db.getPendingUploads(), hasLength(1));
  });

  test('task antiga só na fila (versão anterior) é recuperada para a lista',
      () async {
    await database.insert('PendingUploads', makeTask('old').toMap());
    await DbHelper.useDatabase(database);

    expect((await db.getData()).map((t) => t.key), ['old']);
  });
}
