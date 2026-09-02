import 'package:connectivity/connectivity.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/cupertino.dart';
import 'package:get/get.dart';
import 'package:to_do_app/Data/network/firebase/firebase_services.dart';
import 'package:to_do_app/data/notifications/notification_service.dart';
import 'package:to_do_app/Data/shared%20pref/shared_pref.dart';
import 'package:to_do_app/utils/utils.dart';
import 'package:to_do_app/view%20model/DbHelper/db_helper.dart';
import 'package:to_do_app/view/home%20page/components/progress_update_sheet.dart';
import '../../model/task_filter.dart';
import '../../model/task_model.dart';
import '../../model/task_stats.dart';

class HomeController extends GetxController {
  RxMap userData = {}.obs;
  RxString name = ''.obs;
  RxBool focus = false.obs;
  RxBool hasText = false.obs;
  RxInt taskCount = 0.obs;
  RxBool hasData = false.obs;
  final DbHelper db = DbHelper();
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
      // listener for changing live database
      FirebaseDatabase.instance
          .ref('Tasks')
          .child(node)
          .onValue
          .listen((event) async {
        int count = await FirebaseService.childCount();
        // check if live database has more child than local

        getTaskData();
        for (var element in event.snapshot.children) {
          if (!await db.isRowExists(
              element.child('key').value.toString(), 'Tasks')) {
            db
                .insert(
              TaskModel(
                  key: element.child('key').value.toString(),
                  time: element.child('time').value.toString(),
                  progress: element.child('progress').value.toString(),
                  status: element.child('status').value.toString(),
                  date: element.child('date').value.toString(),
                  periority: element.child('periority').value.toString(),
                  description: element.child('description').value.toString(),
                  category: element.child('category').value.toString(),
                  title: element.child('title').value.toString(),
                  image: element.child('image').value.toString(),
                  show: element.child('show').value.toString()),
            )
                .then((value) {
              getTaskData();
            });
          }
        }
      });

      FirebaseDatabase.instance
          .ref('Tasks')
          .child(node)
          .onChildChanged
          .listen((event) async {
        int count = await FirebaseService.childCount();

        // check if live database has more child than local
        getTaskData();
        for (var element in event.snapshot.children) {
          db
              .update(TaskModel(
              progress: element.child('progress').value.toString(),
              status: element.child('status').value.toString(),
                  key: element.child('key').value.toString(),
                  time: element.child('time').value.toString(),
                  date: element.child('date').value.toString(),
                  periority: element.child('periority').value.toString(),
                  description: element.child('description').value.toString(),
                  category: element.child('category').value.toString(),
                  title: element.child('title').value.toString(),
                  image: element.child('image').value.toString(),
                  show: element.child('show').value.toString()))
              .then((value) {
            getTaskData();
          });
        }
      });
      connectivity = Connectivity();
      // listener for internet state
      connectivity!.onConnectivityChanged.listen((event) async {
        if (event == ConnectivityResult.mobile ||
            event == ConnectivityResult.wifi) {
          var list = await db.getPendingUploads();
          for (int i = 0; i < list.length; i++) {
            db.insert(list[i]);
            db.delete(list[i].key!, 'PendingUploads');
          }
          list.clear();
          list = await db.getPendingDeletes();
          for (int i = 0; i < list.length; i++) {
            FirebaseService.update(list[i].key!, 'show', 'no');
            db.delete(list[i].key!, 'PendingDeletes');
          }
          getTaskData();
        }
      });
    }
    getTaskData();
  }
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
      showProgressSheet(index);
    } else if (value == 2) {
      Utils.showWarningDailog(context, () => removeFromList(index));
    }
  }
  showProgressSheet(int index) {
    ProgressUpdateSheet.show(
        initialProgress: TaskStats.parseProgress(list[index].progress),
        onSave: (progress) => updateProgress(index, progress));
  }
  updateProgress(int index, int progress) async {
    final task = list[index];
    final String status =
        progress >= kCompleteProgress ? 'complete' : 'unComplete';
    await db.update(TaskModel(
        key: task.key,
        status: status,
        progress: progress.toString(),
        time: task.time,
        date: task.date,
        periority: task.periority,
        description: task.description,
        category: task.category,
        title: task.title,
        image: task.image,
        show: task.show));
    // offline first: local sempre grava, o Firebase só quando há conexão
    var connection = await Connectivity().checkConnectivity();
    if (connection == ConnectivityResult.wifi ||
        connection == ConnectivityResult.mobile) {
      await FirebaseService.update(task.key!, 'progress', progress.toString());
      await FirebaseService.update(task.key!, 'status', status);
    }
    getTaskData();
  }
  getTaskData() async {
    list.value = await db.getData();
    var tempList = await db.getPendingUploads();
    for (int i = 0; i < tempList.length; i++) {
      list.add(tempList[i]);
    }
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
    });
  }
}
