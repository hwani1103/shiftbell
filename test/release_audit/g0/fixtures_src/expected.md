# 독립 기대값과 T03 검증 설계

상태: **초안 / 전 항목 NOT_RUN**. 근거는 역사 DB 변경 의미, 영구 이력 보존 규칙, 실행계획 §5 G0와 v4 #1/#8/#31/V4이다. G0 구현의 실행 결과나 SQL 자산을 expected로 복사하지 않았다. `manifest.json.input_rows`는 입력 원장이다.

## 데이터 기대값

모든 기존 행의 PK, 문자열(JSON의 공백·키 순서 포함), NULL, 숫자는 아래 명시적 역사 변경을 제외하고 그대로 남아야 한다. 없는 테이블은 새로 생성되지만 과거 이력이나 친구 행을 임의로 만들어 채우지 않는다.

| 시작 버전 | v24 업그레이드 후 기대 |
|---|---|
| 1~9 | 타입 1 sound_file=alarmbell1, volume=0.7, vibration_strength=3, duration=3. 타입 2 vibration_strength=3, duration=3. 타입 3 duration=3. 기타 기존 필드는 보존 |
| 10 | 타입 1 사용자값(volume=0.43, vibration_strength=1, duration=7) 보존. 타입 2 vibration_strength=3, duration=3. 타입 3 duration=3 |
| 11~23 | 프리셋 포함 모든 기존 재생 설정 보존. v11 UPDATE를 repair에서 다시 적용하면 실패 |
| 1~5 | 새 duration의 기본값은 10. custom 타입 41은 10 유지. 타입 3의 새 vibration_strength는 2; preset UPDATE가 변경하는 필드와 구분 |
| 1~6 | 새 vibration_strength 기본값은 2. custom 타입 41은 2 유지 |
| 6~23 / 7~23 | 이미 있는 custom 41의 duration=7 / vibration_strength=1 보존. custom sound_file=alarmbell2, volume=0.35도 보존 |
| 1~2 / 1~3 | 새 assigned_dates / active_shift_types는 NULL. 기존 버전에서 가진 JSON/목록은 그대로 유지 |
| 1~14 / 1~17 | 새 shift_durations / custom_shift_colors는 NULL. 이후 버전의 기존 JSON은 보존 |
| 1~15 | v17 전환이 끝나면 friends는 owner_id 기반이고 빈 테이블 |
| 16 | 옛 friends 701은 역사 v17 전환에서 제거되어 0행. 이력 301·원장 501은 제거되면 안 됨 |
| 17~23 | friends 701/702, owner_id, 캐시 JSON, 702의 NULL 캐시 모두 보존. 두 번째 open/repair에서도 동일 |
| 1~18 | alarms, shift_alarm_templates, alarm_history, alarm_creation_log의 새 day_offset은 기존 행에 0. 새로 생긴 빈 테이블에는 행을 만들지 않음 |
| 19~23 | 기존 day_offset 보존, 특히 템플릿 202의 -1을 0으로 바꾸지 않음 |
| 20~22 | 일정 801의 새 notify_enabled=0, notify_offset_minutes=0. 기존 일정을 알림 켜짐으로 바꾸면 실패 |
| 23 | 일정 801의 notify_enabled=1, notify_offset_minutes=15 그대로 |
| 22~23 | 완료/진행 중 수면 행과 NULL end_time, 미사용 sleep_expected_bedtime 잔존 행 그대로 |
| 모두 | 성공 후 user_version=24, 새 alarm_overrides는 0행. 알람 101/102/103의 ID·시각·타입 불변. 마이그레이션만으로 생성/삭제/OS 예약을 수행하지 않음 |

위 조합은 필드별로 적용한다. 예를 들어 v1의 타입 3은 duration=3, vibration_strength=2이고, v10의 타입 3은 duration=3, vibration_strength=1이다. 새 컬럼 기본값과 기존 컬럼 값의 차이를 지우지 않는다.

## 구조 대조

Native 업그레이드와 Dart 업그레이드 양쪽을 **실제 Dart 신규 onCreate v24**와 대조한다. 테이블 목록, 컬럼 이름/타입/NOT NULL/기본값/PK, 인덱스의 UNIQUE 및 컬럼 순서, foreign_key_list, CHECK 동작을 비교한다. 생성 순서·SQL 공백·자동 인덱스 이름·sqlite_sequence 현재 값의 차이만으로 실패시키지 않는다. sqlite_sequence는 이후 새 ID가 기존 ID를 덮어쓰지 않는지 별도 삽입으로 확인한다.

alarm_overrides는 확정 계약의 슬롯 키 `(time, shift_type, day_offset)` 및 origin 참조를 대조한다. 구체적 API/컬럼명은 통합 담당자 contracts를 따른다. 동일 슬롯의 중복 거부, skip/set_type의 허용/거부 값과 NULL 조합, day_offset 경계는 명세와 구현의 추가 제약을 구분해 시험한다. G0가 추가한 CHECK가 확정된 제품 요구와 충돌하면 구현을 expected로 정당화하지 말고 통합 담당자에게 반환한다.

## 실패·repair·실행 경계

| 케이스 | 입력/주입 | 기대 / 증거 |
|---|---|---|
| MIG-ALL | 23개 SQL 각각 native/Dart 독립 업그레이드 | 위 데이터 표와 구조 대조. 23개 파일 생성 성공만으로 마이그레이션 PASS 금지 |
| ROLLBACK | v12→v24의 중간 SQL에 확정 실패 주입 | 스키마·인덱스·데이터·user_version이 시작 상태와 함께 롤백. 원인 제거 후 재접근 성공 |
| FRIEND-ROLLBACK | v16에서 v17 DROP 뒤 CREATE 실패 주입 | 옛 friends 701 및 옛 스키마도 복원. 재시도 후에만 v17 전환 |
| REOPEN | v17/v18/v23 업그레이드 DB에 두 차례 open | friends/설정/이력 유지, 두 번째 open의 데이터 변화 0 |
| MISSING-COLUMN | 정상 fixture의 복사본에서 버전만 선행한 손상 사례 구성 | 허용 repair 컬럼은 복구; 임의 손상까지 복구한다고 표시하지 않음. 성공 판정 전에 전체 구조 확인 |
| REPAIR-REJECT | 최신 표시 DB의 필수 비허용 테이블/컬럼 누락 | 과거 DROP/UPDATE·전체 onCreate 재실행으로 정상처럼 숨기지 않음. 정의된 실패 전파와 재시도 확인 |
| REPAIR-WHITELIST | 테스트용 repair 구역에 DROP/UPDATE/DELETE/RENAME/INSERT를 각각 주입 | 허용된 CREATE TABLE/INDEX 및 존재 확인 후 ADD COLUMN 이외 문은 실행 전 오류로 거부. friends와 설정/이력 무변경 |
| ALTER-FAIL | 허용 누락 컬럼의 ALTER를 I/O/주입 오류로 실패 | 컬럼 실재 확인 없이 예외를 삼키거나 최신으로 승인하지 않음 |
| NATIVE-NEW | 없는 DB를 Native helper로 열기 | 빈 최신 DB를 생성해 성공하지 않음. 정상 최초 생성은 Dart가 수행 |
| FUTURE-VERSION | user_version=25인 별도 복사본 | 다운그레이드 거부, 데이터·버전 무변경 |
| CONCURRENT | Device Protected 동일 파일을 Dart/native 동시 open 반복 | 한쪽이 구스키마를 최신으로 간주하지 않음. 파일 손상·버전 선행·데이터 유실 없음. 실제 E/D 증적 필요 |
| V4 | DB·날짜·알람·선택 서비스 각각 throw/지연, 재시도 연타 | 필수 실패/선택 실패 구분, 영구 시작 화면 방지, 중복 초기화 방지, release 오류 원문 미노출 |
| S1-DEVICE | 업데이트 후 앱 미실행, 재부팅 첫 잠금 해제 전 | 실제 울림 및 release SQL 자산 접근. 자동 테스트로 대체하지 않고 T04에 별도 기록 |

손상 DB·실패 주입·override 삽입은 T03 테스트 코드에서 정상 fixture의 별도 복사본에 적용한다. 기준 SQL 자체를 덮어쓰지 않는다. 검증 목적의 후속 INSERT도 감사 이력 원장 보존 비교를 마친 별도 DB에서 한다.
