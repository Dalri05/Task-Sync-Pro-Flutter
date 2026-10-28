import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:to_do_app/data/sync/task_sync.dart';
import 'package:to_do_app/model/task_model.dart';

TaskModel makeTask(String key, {String status = 'todo'}) => TaskModel(
      key: key,
      title: 'Task $key',
      category: 'Work',
      description: 'desc',
      image: 'img.png',
      periority: 'Low',
      time: '10:00 AM',
      date: '5 Sep 2026',
      show: 'yes',
      progress: '0',
      status: status,
    );

class FakeStore implements TaskLocalStore {
  final Map<String, TaskModel> uploads = {};
  final Map<String, TaskModel> deletes = {};

  @override
  Future<List<TaskModel>> getPendingUploads() async => uploads.values.toList();

  @override
  Future<List<TaskModel>> getPendingDeletes() async => deletes.values.toList();

  @override
  Future<void> removePendingUpload(TaskModel sent) async {
    if (identical(uploads[sent.key], sent)) uploads.remove(sent.key);
  }

  @override
  Future<void> removePendingDelete(String key) async => deletes.remove(key);
}

class FakeRemote implements TaskRemote {
  final List<String> pushed = [];
  final List<String> hidden = [];
  Set<String> failOn = {};
  Completer<void>? gate;

  @override
  Future<void> push(TaskModel task) async {
    if (gate != null) await gate!.future;
    if (failOn.contains(task.key)) throw Exception('offline');
    pushed.add(task.key!);
  }

  @override
  Future<void> hide(String key) async {
    if (failOn.contains(key)) throw Exception('offline');
    hidden.add(key);
  }
}

void main() {
  late FakeStore store;
  late FakeRemote remote;
  late TaskSync sync;

  setUp(() {
    store = FakeStore();
    remote = FakeRemote();
    sync = TaskSync(store, remote, timeout: const Duration(milliseconds: 50));
  });

  test('envio confirmado tira da fila', () async {
    store.uploads['1'] = makeTask('1');
    store.deletes['2'] = makeTask('2');

    expect(await sync.run(), isTrue);
    expect(remote.pushed, ['1']);
    expect(remote.hidden, ['2']);
    expect(store.uploads, isEmpty);
    expect(store.deletes, isEmpty);
  });

  test('falha no envio mantém a task pendente', () async {
    store.uploads['1'] = makeTask('1');
    store.uploads['2'] = makeTask('2');
    remote.failOn = {'1'};

    expect(await sync.run(), isFalse);
    expect(store.uploads.keys, containsAll(['1', '2']));

    remote.failOn = {};
    expect(await sync.run(), isTrue);
    expect(store.uploads, isEmpty);
  });

  test('timeout (Firebase sem resposta) mantém a task pendente', () async {
    store.uploads['1'] = makeTask('1');
    remote.gate = Completer<void>();

    expect(await sync.run(), isFalse);
    expect(store.uploads.keys, ['1']);
  });

  test('task alterada durante o envio continua na fila', () async {
    store.uploads['1'] = makeTask('1');
    remote.gate = Completer<void>();
    sync = TaskSync(store, remote);

    final running = sync.run();
    await Future<void>.delayed(Duration.zero);
    store.uploads['1'] = makeTask('1', status: 'complete');
    remote.gate!.complete();

    expect(await running, isTrue);
    expect(store.uploads['1']!.status, 'complete');
  });

  test('chamadas simultâneas não enviam duas vezes', () async {
    store.uploads['1'] = makeTask('1');
    remote.gate = Completer<void>();
    sync = TaskSync(store, remote);

    final a = sync.run();
    final b = sync.run();
    remote.gate!.complete();
    await Future.wait([a, b]);

    expect(remote.pushed, ['1']);
  });
}
