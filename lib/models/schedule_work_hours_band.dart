// lib/models/schedule_work_hours_band.dart
//
// ⭐ 2026-09-22 - 일정관리 탭 세로 시간축 위에 "지금 근무 중인 시간대"를
// 반투명 영역으로 표시하는 기능(디자인 실험실에서 검증 후 확정, dev_lab/ 삭제됨).
// 이 날짜 축(0~1440분) 기준 구간 하나 = 밴드 하나. 자정을 넘기는 근무(예:
// 19:00~07:00)는 schedule_work_hours_band_resolver.dart가 이미 "오늘 몫"/
// "어제 몫" 두 밴드로 쪼개서 넘기므로, 이 모델 자체는 항상 하루 안에서
// 끝나는 단순 구간만 표현한다.
import 'package:flutter/material.dart';

class ScheduleWorkHoursBand {
  final int startMinutes; // 0~1440
  final int endMinutes; // 0~1440, startMinutes보다 큼
  final String shiftName;
  final Color color;

  const ScheduleWorkHoursBand({
    required this.startMinutes,
    required this.endMinutes,
    required this.shiftName,
    required this.color,
  });
}
