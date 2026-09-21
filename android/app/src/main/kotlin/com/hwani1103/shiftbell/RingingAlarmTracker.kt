package com.hwani1103.shiftbell

import android.content.Context
import android.content.SharedPreferences
import android.os.Build
import android.util.Log

/**
 * ⭐ 2026-08-25 추가 - "지금 화면/소리로 응답을 기다리고 있는 알람이 있는가"를 추적함.
 *
 * 배경: 알람 A가 아직 안 꺼진 채로(끄기/스누즈/타임아웃 전) 알람 B의 시각이 되면 무슨
 * 일이 일어나는지 점검한 결과 - AlarmPlayer(싱글턴)는 새 알람이 재생을 시작할 때 이전
 * mediaPlayer/vibrator를 정지시키므로 "소리는 항상 최신 알람 것 하나만" 나는 건 이미
 * 보장돼 있었음. 문제는 그 뒤:
 *  - 잠금화면(AlarmActivity): 알람마다 매번 새 Activity 인스턴스로 교체됨(구 인스턴스는
 *    그냥 destroy) - A의 DB 행/이력이 전혀 정리되지 않고 영구히 "유령 alarms 행"으로
 *    남았음(타임아웃도 dismiss도 한 번도 안 걸림).
 *  - 해제화면(AlarmOverlayService): 같은 Service 인스턴스가 재사용되는데,
 *    showOverlayWindow()가 "이미 표시 중이면 스킵"하는 로직 때문에 새 알람(B)의
 *    시간/근무명으로 뷰가 갱신되지 않고 화면엔 계속 A의 정보가 남아있는 채로
 *    내부 alarmId 필드만 B로 바뀌는 화면-데이터 불일치가 있었음.
 *
 * 해결: CustomAlarmReceiver.onReceive()가 새 알람을 처리하기 직전에 "지금 응답
 * 대기 중인 알람이 있고, 그게 이번 알람과 다르면" 그 알람을 AlarmActionHelper.supersede()로
 * 깔끔하게 마무리(이력 기록 + DB 삭제 + notification 정리)한 뒤 이번 알람을 진행함.
 * AlarmOverlayService도 자기 알람 ID가 바뀌는 걸 감지하면 뷰를 강제로 다시 그림
 * (표시 데이터 불일치 방지) - 두 수정은 독립적이지만 서로를 보완함.
 *
 * ⭐ 2026-09-14 (출시전 감사 #3/#14, G1) - 알람 ID만으로는 "같은 알람의 어느 울림"인지
 * 구분이 안 됐음. 스누즈한 알람은 같은 ID로 다시 울리므로, 이전 울림의 늦게 도착한 종료
 * 신호(화면 타이머·종료 예약·7777 알림 버튼)가 새 울림을 끌 수 있었음. 그래서 두 값을 분리함:
 *  - ring_counter: 누적 회차 번호. 새 울림마다 +1, **절대 지우지 않음**(번호 재사용 없음)
 *  - 활성 울림(ID, 회차): 끄기·스누즈·인계·타임아웃에서만 폐기
 * 종료 경로는 전부 AlarmActionHelper.claimRingEnd(ID, 회차)를 먼저 통과해야 하고, 둘 다
 * 일치할 때만 그 울림을 끝냄(불일치는 무시 + 로그). 증가·설정·폐기·비교는 한 lock 안에서만.
 *
 * 저장은 commit()(동기) + 1회 재시도. 그래도 실패하면 이 프로세스 메모리 값으로 회차 판정을
 * 계속함 - ID만 비교하는 폴백은 위 문제를 되살리므로 쓰지 않음. 리시버·서비스·Activity·
 * MainActivity가 전부 같은 기본 프로세스라 메모리 값이 이 프로세스 안에서는 기준이 됨
 * (android:process를 따로 두게 되면 다시 설계할 것). 프로세스가 죽으면 소리도 같이 멈추고,
 * 다음 프로세스는 마지막으로 저장된 값에서 시작함.
 *
 * Device Protected Storage를 씀(다른 alarm_state 값들과 동일한 이유 - 잠금 해제 전에도
 * CustomAlarmReceiver가 접근 가능해야 함).
 */
object RingingAlarmTracker {
    private const val TAG = "RingingAlarmTracker"
    private const val PREFS_NAME = "alarm_state"
    private const val KEY_RINGING_ID = "currently_ringing_alarm_id"
    private const val KEY_RINGING_ROUND = "currently_ringing_round"
    private const val KEY_RING_COUNTER = "ring_counter"
    private const val NONE = -1

    /** 이 수정 이전 버전이 ID만 남겨둔 경우의 회차. 새 회차는 1부터라 겹치지 않음. */
    const val LEGACY_ROUND = 0L

    /** 회차 정보가 없는 요청(수정 이전에 만들어진 Intent 등). 어떤 활성 울림과도 일치하지 않음. */
    const val NO_ROUND = -1L

    data class ActiveRing(val alarmId: Int, val round: Long)

    private val lock = Any()
    private var loaded = false
    private var counter = 0L
    private var active: ActiveRing? = null

    // ⭐ 2026-09-14 (출시전 교차 검토 X-04) - 백업 복원 이월 판정용. 메모리 전용(프로세스가 죽으면 복원 작업도 같이 끝남).
    //  - epoch: 울림 시작·종료 관문 통과·끄기/스누즈 DB 반영 완료마다 +1. 복원은 DB 교체 트랜잭션 끝에서 다시 읽어 달라졌으면 롤백 후 재시도.
    //  - ending: 종료 관문은 통과했지만 끄기/스누즈 DB 반영이 아직 안 끝난 알람 ID. 복원이 이 행을 이월 대상에 넣어
    //    "관문 통과 → (복원이 행 교체) → 스누즈 DB 쓰기 실패"로 스누즈가 사라지지 않게 함. Dart 삭제처럼 네이티브가
    //    완료를 모르는 경로가 있어 일정 시간 뒤 자동으로 빠짐.
    private var epoch = 0L
    private val ending = HashMap<Int, Long>()
    private const val ENDING_TTL_MS = 60_000L

    // ⭐ X-03 - 활성 울림이 이 프로세스에서 시작됐는지. 저장값에서 읽어 온 활성 울림은 이전 프로세스의 것이라 소리가 이미 멈춘 상태.
    private var activeStartedHere = false

    /** 테스트 전용 - commit 실패 주입. null이면 실제 commit(). */
    internal var commitOverride: ((SharedPreferences.Editor) -> Boolean)? = null

    private fun prefs(context: Context): SharedPreferences {
        val deviceContext = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            context.createDeviceProtectedStorageContext()
        } else {
            context
        }
        return deviceContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    }

    // lock 안에서만 호출
    private fun ensureLoaded(context: Context) {
        if (loaded) return
        val p = prefs(context)
        counter = p.getLong(KEY_RING_COUNTER, 0L)
        val id = p.getInt(KEY_RINGING_ID, NONE)
        active = if (id == NONE) null else ActiveRing(id, p.getLong(KEY_RINGING_ROUND, LEGACY_ROUND))
        loaded = true
    }

    // lock 안에서만 호출
    private fun persist(context: Context, change: SharedPreferences.Editor.() -> Unit) {
        repeat(2) { attempt ->
            val ok = try {
                val editor = prefs(context).edit()
                editor.change()
                commitOverride?.invoke(editor) ?: editor.commit()
            } catch (e: Exception) {
                Log.e(TAG, "울림 상태 저장 예외 (시도 ${attempt + 1})", e)
                false
            }
            if (ok) return
        }
        Log.e(TAG, "❌ 울림 상태 저장 2회 실패 - 이 프로세스 동안 메모리 회차로 계속 판정: active=$active counter=$counter")
    }

    /** 새 울림 시작 - 회차를 하나 올리고 (ID, 회차)를 활성으로 기록. 이전 활성 값은 덮어씀. */
    fun startRing(context: Context, alarmId: Int): ActiveRing = synchronized(lock) {
        ensureLoaded(context)
        counter += 1
        val ring = ActiveRing(alarmId, counter)
        active = ring
        activeStartedHere = true
        epoch++
        persist(context) {
            putLong(KEY_RING_COUNTER, ring.round)
            putInt(KEY_RINGING_ID, alarmId)
            putLong(KEY_RINGING_ROUND, ring.round)
        }
        ring
    }

    /** 지금 활성인 울림, 없으면 null. */
    fun current(context: Context): ActiveRing? = synchronized(lock) {
        ensureLoaded(context)
        active
    }

    /** 지금 응답 대기 중인 알람 ID, 없으면 null. */
    fun getRingingAlarmId(context: Context): Int? = current(context)?.alarmId

    fun isCurrent(context: Context, alarmId: Int, round: Long): Boolean = synchronized(lock) {
        ensureLoaded(context)
        active == ActiveRing(alarmId, round)
    }

    /** (ID, 회차)가 둘 다 활성 값과 같을 때만 폐기하고 true. 아니면 아무것도 안 바꾸고 false. */
    fun endIfCurrent(context: Context, alarmId: Int, round: Long): Boolean = synchronized(lock) {
        ensureLoaded(context)
        if (active != ActiveRing(alarmId, round)) {
            Log.w(TAG, "⚠️ 지난 회차 종료 요청 무시: 요청=($alarmId, $round) 활성=$active")
            return false
        }
        active = null
        activeStartedHere = false
        epoch++
        ending[alarmId] = android.os.SystemClock.elapsedRealtime()
        persist(context) {
            remove(KEY_RINGING_ID)
            remove(KEY_RINGING_ROUND)
        }
        true
    }

    /**
     * 회차를 모르는 "지금 이 알람" 요청용(예: 앱에서 알람 삭제) - 활성 울림의 ID가 같으면 그
     * 회차를 폐기하고 돌려줌. 판단 시점의 활성 값을 쓰므로 늦게 도착한 옛 신호에는 쓰지 말 것.
     */
    fun endCurrentOf(context: Context, alarmId: Int): ActiveRing? = synchronized(lock) {
        ensureLoaded(context)
        val ring = active?.takeIf { it.alarmId == alarmId } ?: return null
        if (endIfCurrent(context, ring.alarmId, ring.round)) ring else null
    }

    /** 끄기·스누즈의 DB 반영이 끝남(AlarmActionHelper, 성공·실패 무관). 복원 이월 판정 epoch를 올림(X-04). */
    fun finishTransition(alarmId: Int) {
        synchronized(lock) {
            ending.remove(alarmId)
            epoch++
        }
    }

    data class CarryState(val active: ActiveRing?, val endingIds: Set<Int>, val epoch: Long)

    /** 복원 이월 판정용 스냅샷(X-04): 활성 울림 + 종료 처리 중 ID + epoch를 한 lock 안에서. */
    fun carryState(context: Context): CarryState = synchronized(lock) {
        ensureLoaded(context)
        val now = android.os.SystemClock.elapsedRealtime()
        ending.entries.removeAll { now - it.value > ENDING_TTL_MS }
        CarryState(active, ending.keys.toSet(), epoch)
    }

    /** 이 프로세스에서 시작돼 아직 끝나지 않은 울림이 있는지(X-03 - 복원 뒤 앱 재시작을 미룰지 판단). */
    fun isLiveRing(context: Context): Boolean = synchronized(lock) {
        ensureLoaded(context)
        active != null && activeStartedHere
    }

    /**
     * ⭐ 2026-09-15 (출시 적합성 재검토 AUD-02) - 이 프로세스에 살아 있는 울림이 없을 때만 [block](복원 뒤 앱 재시작의 프로세스 종료)을
     * lock 안에서 실행하고 true. 확인과 종료 사이에 [startRing]이 끼어들 수 없게 같은 lock을 잡음. 울리는 중이면 실행하지 않고 false.
     */
    fun runIfNoLiveRing(context: Context, block: () -> Unit): Boolean = synchronized(lock) {
        ensureLoaded(context)
        if (active != null && activeStartedHere) return@synchronized false
        block()
        true
    }

    /**
     * X-12 - 회차 정보가 없는 요청(1.0.22 이하가 게시한 제어 알림·화면 Intent)은, 활성 울림이 같은 ID의 옛 버전 기록
     * ([LEGACY_ROUND])일 때만 그 회차로 취급. 새 회차(1 이상)에는 절대 매핑하지 않음 - 스누즈 후 재울림을 옛 신호가 끄는
     * 문제(#3)가 되살아나지 않게.
     */
    fun normalizeRound(context: Context, alarmId: Int, round: Long): Long = synchronized(lock) {
        ensureLoaded(context)
        val ring = active
        if (round == NO_ROUND && ring != null && ring.alarmId == alarmId && ring.round == LEGACY_ROUND) LEGACY_ROUND else round
    }

    /** 테스트 전용 - 프로세스 재시작처럼 메모리 값을 버림(저장된 값은 유지). */
    internal fun resetMemoryForTest() = synchronized(lock) {
        loaded = false
        counter = 0L
        active = null
        activeStartedHere = false
        epoch = 0L
        ending.clear()
        commitOverride = null
    }
}
