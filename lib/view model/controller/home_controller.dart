import 'package:connectivity/connectivity.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/cupertino.dart';
import 'package:get/get.dart';
import 'package:to_do_app/data/network/firebase/firebase_services.dart';
import 'package:to_do_app/data/notifications/notification_service.dart';
import 'package:to_do_app/data/sync/task_sync.dart';
import 'package:to_do_app/data/shared%20pref/shared_pref.dart';
import 'package:to_do_app/utils/utils.dart';
import 'package:to_do_app/view%20model/DbHelper/db_helper.dart';
import 'package:to_do_app/view/home%20page/components/status_update_sheet.dart';
import '../../model/task_filter.dart';
import '../../model/task_model.dart';
import '../../model/task_status.dart';

class HomeController extends GetxController {
  RxMap userData = {}.obs;
  RxString name = ''.obs;
  RxBool focus = false.obs;
  RxBool hasText = false.obs;
  RxInt taskCount = 0.obs;
  RxBool hasData = false.obs;
  final DbHelper db = DbHelper();
  late final TaskSync sync = TaskSync(db, FirebaseTaskRemote());
  RxList list = [].obs;
  Connectivity? connectivity;
  final searchController = TextEditingController().obs;
  // filtros da home: prioridade (All/High/Medium/Low) e status (All/Pending/Completed)
  RxString priorityFilter = 'All'.obs;
  RxString statusFilter = 'All'.obs;
  // espelho reativo do texto de busca (TextEditingController não é reativo p/ Obx)
  RxString searchQuery = ''.obs;
  HomeController() {
    // if name not loaded
    if (userData['NAME'] == null) {
      getUserData();
    }
    // check for set listeners only for one time
    if (connectivity == null) {
      String str = FirebaseService.auth.currentUser!.email.toString();
      String node = FirebaseService.nodeFromEmail(str);
      // listener for changing live database: traz o que ainda não existe local
      FirebaseDatabase.instance
          .ref('Tasks')
          .child(node)
          .onValue
          .listen((event) async {
        for (var element in event.snapshot.children) {
          final task = _taskFromSnapshot(element);
          if (!await db.isRowExists(task.key!, 'Tasks')) {
            await db.saveFromRemote(task);
          }
        }
        getTaskData();
      });

      // o snapshot do evento é a própria task alterada (não a lista)
      FirebaseDatabase.instance
          .ref('Tasks')
          .child(node)
          .onChildChanged
          .listen((event) async {
        await db.saveFromRemote(_taskFromSnapshot(event.snapshot));
        getTaskData();
      });
      connectivity = Connectivity();
      // listener for internet state
      connectivity!.onConnectivityChanged.listen((event) {
        if (event == ConnectivityResult.mobile ||
            event == ConnectivityResult.wifi) {
          syncPending();
        }
      });
      // o que ficou pendente de uma sessão anterior sobe já na abertura
      syncPending();
    }
    getTaskData();
  }

  static TaskModel _taskFromSnapshot(DataSnapshot snapshot) {
    String? field(String name) => snapshot.child(name).value?.toString();
    return TaskModel(
        key: field('key') ?? snapshot.key,
        time: field('time'),
        progress: field('progress'),
        status: field('status'),
        date: field('date'),
        periority: field('periority'),
        description: field('description'),
        category: field('category'),
        title: field('title'),
        image: field('image'),
        show: field('show'));
  }

  /// Envia a fila local (criações, mudanças de status e remoções feitas
  /// offline). Itens só saem da fila depois que o Firebase confirmou.
  Future<bool> syncPending() => sync.run();

  checkData() {
    int count = 0;
    for (int i = 0; i < list.length; i++) {
      if (list[i].show == 'yes') {
        count++;
      }
    }
    if (count > 0) {
      hasData.value = true;
      taskCount.value = count;
    } else {
      hasData.value = false;
      taskCount.value = 0;
    }
  }

  popupMenuSelected(int value, int index, BuildContext context) async {
    if (value == 1) {
      showStatusSheet(index);
    } else if (value == 2) {
      Utils.showWarningDailog(context, () => removeFromList(index));
    }
  }

  showStatusSheet(int index) {
    StatusUpdateSheet.show(
        initialStatus: TaskStatus.from(list[index]),
        onSave: (status) => updateStatus(index, status));
  }

  /// `status` é a fonte da verdade; `progress` continua sendo gravado derivado
  /// (0/50/100) para bases antigas que ainda leem o campo numérico.
  updateStatus(int index, TaskStatus status) async {
    final task = list[index];
    await db.update(TaskModel(
        key: task.key,
        status: status.storageValue,
        progress: status.progressText,
        time: task.time,
        date: task.date,
        periority: task.periority,
        description: task.description,
        category: task.category,
        title: task.title,
        image: task.image,
        show: task.show));
    // offline first: grava local + fila; o Firebase recebe quando der
    getTaskData();
    syncPending();
  }

  getTaskData() async {
    // pendentes também já estão em Tasks: a fila não entra na lista
    list.value = await db.getData();
    checkData();
  }

  Future<List<TaskModel>> getFututeData() {
    return db.getData();
  }

  /// Lista que a UI consome: busca + prioridade + status sobre `list`.
  /// Lida dentro de Obx, reage a list/searchQuery/priorityFilter/statusFilter.
  List<TaskModel> get filteredTasks => TaskFilter.apply(
        list,
        query: searchQuery.value,
        priority: priorityFilter.value,
        status: statusFilter.value,
      );
  setPriorityFilter(String value) {
    priorityFilter.value = value;
  }

  setStatusFilter(String value) {
    statusFilter.value = value;
  }

  onClear(BuildContext context) {
    searchController.value.text = '';
    searchQuery.value = '';
    hasText.value = false;
    onTapOutside(context);
  }

  onTapOutside(BuildContext context) {
    focus.value = false;
    FocusScope.of(context).unfocus();
  }

  checkText() {
    searchQuery.value = searchController.value.text;
    hasText.value = searchController.value.text.toString().isNotEmpty;
  }

  onTapField() {
    focus.value = true;
  }

  getUserData() async {
    userData.value = await UserPref.getUser();
    getName();
  }

  getName() {
    final fullName = userData['NAME'].toString().trim();
    final spaceIndex = fullName.indexOf(' ');
    name.value = spaceIndex >= 0 ? fullName.substring(0, spaceIndex) : fullName;
  }

  removeFromList(int index) {
    NotificationService.cancelTaskReminder(list[index].key);
    db
        .removeFromList(TaskModel(
            key: list[index].key,
            status: list[index].status,
            progress: list[index].progress,
            time: list[index].time,
            date: list[index].date,
            periority: list[index].periority,
            description: list[index].description,
            category: list[index].category,
            title: list[index].title,
            image: list[index].image,
            show: 'no'))
        .then((value) {
      getTaskData();
      syncPending();
    });
  }
}
