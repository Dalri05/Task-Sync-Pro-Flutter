import 'package:to_do_app/model/task_model.dart';
import 'package:to_do_app/model/task_stats.dart';

/// Filtro puro de tasks (sem banco, rede ou UI) para a home page.
/// Combina busca por texto + prioridade + status de conclusão.
class TaskFilter {
  static const List<String> priorities = ['All', 'High', 'Medium', 'Low'];
  static const List<String> statuses = ['All', 'Pending', 'Completed'];

  /// Concluída = progresso 100 (fonte da verdade) ou status 'complete'
  /// (gravado por updateProgress ao chegar em 100).
  static bool isCompleted(TaskModel task) {
    if (TaskStats.parseProgress(task.progress) >= kCompleteProgress) {
      return true;
    }
    return (task.status ?? '').trim().toLowerCase() == 'complete';
  }

  /// Prioridade vazia/null/'null' cai em 'Low', consistente com TaskStats.
  static String effectivePriority(String? raw) {
    final text = (raw ?? '').trim();
    return (text.isEmpty || text == 'null') ? 'Low' : text;
  }

  /// Aplica busca + filtros sobre a lista crua do controller.
  /// Tasks soft-deletadas (show != 'yes') ficam de fora, como no resto do app.
  static List<TaskModel> apply(
    List<dynamic> tasks, {
    String query = '',
    String priority = 'All',
    String status = 'All',
  }) {
    final q = query.trim().toLowerCase();

    bool matchesQuery(TaskModel task) {
      if (q.isEmpty) return true;
      bool has(String? field) => (field ?? '').toLowerCase().contains(q);
      return has(task.title) || has(task.category) || has(task.description);
    }

    bool matchesPriority(TaskModel task) =>
        priority == 'All' || effectivePriority(task.periority) == priority;

    bool matchesStatus(TaskModel task) {
      if (status == 'Completed') return isCompleted(task);
      if (status == 'Pending') return !isCompleted(task);
      return true;
    }

    return tasks
        .whereType<TaskModel>()
        .where((task) =>
            task.show == 'yes' &&
            matchesPriority(task) &&
            matchesStatus(task) &&
            matchesQuery(task))
        .toList();
  }
}
