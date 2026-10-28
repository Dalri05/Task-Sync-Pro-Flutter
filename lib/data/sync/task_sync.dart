import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:to_do_app/model/task_model.dart';

/// Fila local de tasks que ainda não chegaram ao Firebase.
abstract class TaskLocalStore {
  Future<List<TaskModel>> getPendingUploads();
  Future<List<TaskModel>> getPendingDeletes();
  Future<void> removePendingUpload(TaskModel sent);
  Future<void> removePendingDelete(String key);
}

/// Destino remoto. Os métodos só completam quando o servidor confirmou.
abstract class TaskRemote {
  Future<void> push(TaskModel task);
  Future<void> hide(String key);
}

/// Esvazia a fila local enviando para o remoto.
///
/// Regra que evita perda: um item só sai da fila depois que o envio dele
/// completou. Falha ou timeout (sem internet, Firebase fora) mantém tudo
/// pendente para a próxima tentativa — reenviar é seguro, o push é um `set`
/// idempotente da task inteira.
class TaskSync {
  final TaskLocalStore local;
  final TaskRemote remote;
  final Duration timeout;

  TaskSync(this.local, this.remote,
      {this.timeout = const Duration(seconds: 15)});

  Future<bool>? _running;

  /// Retorna true se a fila ficou vazia. Chamadas simultâneas reaproveitam
  /// a execução em andamento (evita enviar a mesma task duas vezes).
  Future<bool> run() {
    return _running ??= _run().whenComplete(() => _running = null);
  }

  Future<bool> _run() async {
    try {
      for (final task in await local.getPendingUploads()) {
        await remote.push(task).timeout(timeout);
        await local.removePendingUpload(task);
      }
      for (final task in await local.getPendingDeletes()) {
        await remote.hide(task.key!).timeout(timeout);
        await local.removePendingDelete(task.key!);
      }
      return true;
    } catch (e) {
      debugPrint('Sync pendente, nova tentativa depois: $e');
      return false;
    }
  }
}
