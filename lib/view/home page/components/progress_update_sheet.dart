import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../res/app_color.dart';

class ProgressUpdateSheet extends StatelessWidget {
  final int initialProgress;
  final ValueChanged<int> onSave;

  ProgressUpdateSheet(
      {super.key, required this.initialProgress, required this.onSave})
      : progress = initialProgress.toDouble().obs;

  final RxDouble progress;

  static void show(
      {required int initialProgress, required ValueChanged<int> onSave}) {
    Get.bottomSheet(
      ProgressUpdateSheet(initialProgress: initialProgress, onSave: onSave),
      backgroundColor: black,
      isScrollControlled: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
      decoration: const BoxDecoration(
          color: black,
          borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              height: 4,
              width: 45,
              decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(10)),
            ),
          ),
          const SizedBox(
            height: 20,
          ),
          Text(
            'task_update_progress'.tr,
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17),
          ),
          const SizedBox(
            height: 20,
          ),
          Row(
            children: [
              Text(
                'task_progress'.tr,
                style: const TextStyle(
                    color: Colors.white70, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              Obx(
                () => Text(
                  '${progress.value.toInt()}%',
                  style: const TextStyle(
                      color: Colors.white70, fontWeight: FontWeight.bold),
                ),
              )
            ],
          ),
          Obx(() => Slider(
                min: 0.0,
                max: 100.0,
                divisions: 100,
                activeColor: Colors.pinkAccent,
                inactiveColor: Colors.white24,
                value: progress.value,
                onChanged: (value) {
                  progress.value = value;
                },
              )),
          const SizedBox(
            height: 10,
          ),
          GestureDetector(
            onTap: () {
              Get.back();
              onSave(progress.value.toInt());
            },
            child: Container(
              height: 55,
              width: double.infinity,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(15),
                  gradient: const LinearGradient(
                      colors: [Colors.pinkAccent, Colors.purpleAccent])),
              child: Text(
                'task_save'.tr,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold),
              ),
            ),
          )
        ],
      ),
    );
  }
}
