package com.hwani1103.shiftbell

import android.content.Context
import android.content.res.AssetFileDescriptor
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.media.audiofx.LoudnessEnhancer
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.Build
import android.util.Log

class AlarmPlayer(private val context: Context) {
    private var mediaPlayer: MediaPlayer? = null
    private var vibrator: Vibrator? = null
    private var loudnessEnhancer: LoudnessEnhancer? = null

    companion object {
        @Volatile
        private var INSTANCE: AlarmPlayer? = null

        fun getInstance(context: Context): AlarmPlayer {
            return INSTANCE ?: synchronized(this) {
                INSTANCE ?: AlarmPlayer(context.applicationContext).also {
                    INSTANCE = it
                }
            }
        }
    }

    // 기존 호환용 (soundType만 받는 경우)
    fun playAlarm(soundType: String) {
        playAlarmWithSettings(soundType, 1.0f, 2)
    }

    // 새로운 메서드: DB에서 읽은 설정 적용
    fun playAlarmWithSettings(soundFile: String, volume: Float, vibrationStrength: Int) {
        Log.d("AlarmPlayer", "🔊 알람 재생 시작")
        Log.d("AlarmPlayer", "  soundFile=$soundFile, volume=$volume, vibrationStrength=$vibrationStrength")

        // 새 회차가 무음이어도 이전 회차의 출력이 남지 않도록 소리와 진동을 모두 정리.
        try {
            mediaPlayer?.apply {
                if (isPlaying) {
                    stop()
                }
                release()
            }
            mediaPlayer = null
            releaseLoudnessEnhancer()
        } catch (e: Exception) {
            Log.e("AlarmPlayer", "MediaPlayer 정리 실패", e)
        }
        try {
            vibrator?.cancel()
        } catch (e: Exception) {
            Log.e("AlarmPlayer", "이전 진동 정리 실패", e)
        } finally {
            vibrator = null
        }

        when {
            // 시스템 기본 알람음
            soundFile == "default" -> {
                Log.d("AlarmPlayer", "  타입: 기본 알람음 + 진동")
                playDefaultSound(volume)
                playVibration(vibrationStrength)
            }
            // alarmbell로 시작하면 커스텀 사운드 재생
            soundFile.startsWith("alarmbell") -> {
                Log.d("AlarmPlayer", "  타입: 커스텀 사운드($soundFile) + 진동")
                playCustomSound(soundFile, volume)
                playVibration(vibrationStrength)  // 소리 타입은 진동 항상 포함
            }
            // 기존 호환용 (loud, soft)
            soundFile == "loud" || soundFile == "soft" -> {
                Log.d("AlarmPlayer", "  타입: $soundFile + 진동")
                playDefaultSound(volume)
                playVibration(vibrationStrength)
            }
            soundFile == "vibrate" -> {
                Log.d("AlarmPlayer", "  타입: 진동만 (세기=$vibrationStrength)")
                playVibration(vibrationStrength)
            }
            soundFile == "silent" -> {
                Log.d("AlarmPlayer", "  타입: 무음 (아무것도 안 함)")
            }
            else -> {
                Log.e("AlarmPlayer", "  ❌ 알 수 없는 soundFile: $soundFile")
            }
        }
    }

    // DB에서 알람 타입 설정 읽어서 재생
    fun playAlarmFromDB(alarmId: Int) {
        // ⭐ 2026-09-14 (G4 #19) - 백업 복원이 alarm_types를 바꾸기 전에 저장한 이 알람의 재생 설정이 있으면 그대로 사용
        // (진행 중 알람이 복원 뒤 다른 소리·음량으로 울리지 않게 - RestoreGate 상단 주석 참고)
        RestoreGate.ringSnapshot(context, alarmId)?.let { snap ->
            Log.d("AlarmPlayer", "복원 전 설정 스냅샷으로 재생: alarmId=$alarmId sound=${snap.soundFile}")
            playAlarmWithSettings(snap.soundFile, snap.volume, snap.vibrationStrength)
            return
        }
        var alarmCursor: android.database.Cursor? = null
        var typeCursor: android.database.Cursor? = null
        var db: android.database.sqlite.SQLiteDatabase? = null

        try {
            val dbHelper = DatabaseHelper.getInstance(context)
            // ⭐ DB 파일이 없으면 Native가 만들면 안 됨 (DatabaseHelper.kt 상세 주석 참고) -
            // 아래 catch와 동일한 fail-safe(진동만) 폴백을 타도록 예외로 전환.
            db = dbHelper.getReadableDatabaseWithRetry()
                ?: throw IllegalStateException("DB 파일 없음")
            val database = db

            // 알람에서 alarm_type_id 조회
            alarmCursor = database.query(
                "alarms",
                arrayOf("alarm_type_id"),
                "id = ?",
                arrayOf(alarmId.toString()),
                null, null, null
            )

            var alarmTypeId = 1  // 기본값: 소리
            if (alarmCursor.moveToFirst()) {
                alarmTypeId = alarmCursor.getInt(alarmCursor.getColumnIndexOrThrow("alarm_type_id"))
            }

            // alarm_types에서 설정 조회
            typeCursor = database.query(
                "alarm_types",
                arrayOf("sound_file", "volume", "vibration_strength"),
                "id = ?",
                arrayOf(alarmTypeId.toString()),
                null, null, null
            )

            // ⭐ CRITICAL FIX: 예전엔 이 값을 못 찾으면 "alarmbell1, 70%, 강하게"로
            // 폴백했음 - 즉, DB 조회가 실패하는 그 어떤 이유에서든 사용자가 설정한
            // 것과 무관하게 "가장 시끄러운 쪽"으로 fail-open 되는 구조였음(무음으로
            // 설정해도 이 경로를 타면 소리가 남). 실패 시엔 반대로 fail-safe하게
            // (소리 없이 진동만) 가야 함 - 못 깨우는 것보다야 낫지만, 사용자가
            // 전혀 의도하지 않은 소리로 갑자기 우는 것보다는 안전한 쪽.
            var soundFile = "vibrate"
            var volume = 0.0f
            var vibrationStrength = 3
            var usedFallback = true

            if (typeCursor.moveToFirst()) {
                soundFile = typeCursor.getString(typeCursor.getColumnIndexOrThrow("sound_file"))
                volume = typeCursor.getFloat(typeCursor.getColumnIndexOrThrow("volume"))
                vibrationStrength = typeCursor.getInt(typeCursor.getColumnIndexOrThrow("vibration_strength"))
                usedFallback = false
            }

            if (usedFallback) {
                Log.w("AlarmPlayer", "⚠️ alarm_types에 id=$alarmTypeId 없음 - fail-safe 폴백(진동만) 사용. alarmId=$alarmId")
            }
            Log.d("AlarmPlayer", "DB 설정: soundFile=$soundFile, volume=$volume, vibration=$vibrationStrength")
            playAlarmWithSettings(soundFile, volume, vibrationStrength)

        } catch (e: Exception) {
            Log.e("AlarmPlayer", "DB 설정 읽기 실패, fail-safe 폴백(진동만) 사용", e)
            playAlarmWithSettings("vibrate", 0.0f, 3)
        } finally {
            // ⭐ db.close() 제거 (AlarmActionHelper.kt 상세 주석 참고) - 이런 종류의
            // "no such table" 예외가 바로 이 close() 남용 패턴 때문에 실제로 발생했었음
            alarmCursor?.close()
            typeCursor?.close()
        }
    }

    // res/raw/에서 커스텀 사운드 재생 (flutter run 호환)
    private fun playCustomSound(soundFile: String, volume: Float) {
        try {
            // res/raw 리소스 ID 가져오기 (확장자 제외)
            val resourceId = context.resources.getIdentifier(soundFile, "raw", context.packageName)

            if (resourceId == 0) {
                Log.e("AlarmPlayer", "리소스 못 찾음: res/raw/$soundFile.mp3")
                playDefaultSound(volume)
                return
            }

            // ⭐ 시스템 알람 볼륨을 50%(최소 1단계)로 임시 변경. 원래 볼륨 저장·복원은 AlarmStreamVolume이 미리듣기와 함께
            // 관리함(AUD-06). 겹쳐 울리는 알람이 이미 50%로 낮춘 값을 "원래 볼륨"으로 덮어쓰지 않는 규칙도 거기서 지킴.
            AlarmStreamVolume.acquire(context, AlarmStreamVolume.HOLDER_ALARM)

            // 리소스 URI 생성
            val soundUri = android.net.Uri.parse("android.resource://${context.packageName}/$resourceId")
            Log.d("AlarmPlayer", "커스텀 사운드 로드: $soundUri")

            // ⭐ 2026-09-14 (#23) - 재생까지 성공한 플레이어만 필드에 대입 (startLoopingPlayer 주석 참고)
            val player = startLoopingPlayer(soundUri, volume)
            mediaPlayer = player
            applyLoudnessBoost(player.audioSessionId, volume)

            Log.d("AlarmPlayer", "커스텀 사운드 재생 시작: $soundFile, 음량 ${(volume * 100).toInt()}%")

        } catch (e: Exception) {
            Log.e("AlarmPlayer", "커스텀 사운드 재생 실패, 기본 알람 사용: ${e.message}", e)
            // 실패 시 기본 알람 사운드로 폴백
            playDefaultSound(volume)
        }
    }

    // 시스템 기본 알람 사운드 재생
    private fun playDefaultSound(volume: Float) {
        try {
            // ⭐ 시스템 알람 볼륨을 50%로 임시 변경 - playCustomSound와 같이 AlarmStreamVolume이 관리(AUD-06)
            AlarmStreamVolume.acquire(context, AlarmStreamVolume.HOLDER_ALARM)

            // 알람 소리 URI
            val alarmUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)

            // ⭐ 2026-09-14 (#23) - 재생까지 성공한 플레이어만 필드에 대입 (startLoopingPlayer 주석 참고)
            val player = startLoopingPlayer(alarmUri, volume)
            mediaPlayer = player
            applyLoudnessBoost(player.audioSessionId, volume)

            Log.d("AlarmPlayer", "기본 알람 소리 재생 시작: 음량 ${(volume * 100).toInt()}%")

        } catch (e: Exception) {
            Log.e("AlarmPlayer", "기본 알람 소리 재생 실패", e)
        }
    }

    // ⭐ 2026-09-14 (출시전 감사 #23) - 예전엔 `mediaPlayer = MediaPlayer().apply { ...prepare(); start() }`
    // 형태라 setDataSource/prepare/start 중 하나가 예외를 던지면, 그 MediaPlayer는 필드에 대입되기 전이라
    // 아무도 release()하지 못한 채 새어나갔음(실패가 반복되면 네이티브 재생 자원이 쌓임). 지역 변수로
    // 만들어 실패하면 여기서 바로 해제하고, 재생 시작까지 성공한 것만 돌려줌.
    private fun startLoopingPlayer(uri: android.net.Uri, volume: Float): MediaPlayer {
        val player = MediaPlayer()
        try {
            player.setDataSource(context, uri)

            // 핵심: STREAM_ALARM 사용!
            player.setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ALARM)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build()
            )

            // ⭐ 음량 calibration 적용 (sqrt 커브, 새 50%≈기존 70% 체감)
            val calibrated = VolumeCalibration.linearGain(volume)
            player.setVolume(calibrated, calibrated)

            player.isLooping = true
            player.prepare()
            player.start()
            return player
        } catch (e: Exception) {
            try {
                player.release()
            } catch (releaseError: Exception) {
                Log.e("AlarmPlayer", "실패한 MediaPlayer 해제 실패", releaseError)
            }
            throw e
        }
    }

    // ⭐ setVolume()은 1.0(유니티 게인)을 못 넘으므로, LoudnessEnhancer로 추가 부스트
    private fun applyLoudnessBoost(audioSessionId: Int, sliderVolume: Float) {
        try {
            loudnessEnhancer?.release()
            loudnessEnhancer = LoudnessEnhancer(audioSessionId).apply {
                setTargetGain(VolumeCalibration.boostMillibels(sliderVolume))
                enabled = true
            }
            Log.d("AlarmPlayer", "🔊 LoudnessEnhancer 적용: +${VolumeCalibration.boostMillibels(sliderVolume)}mB")
        } catch (e: Exception) {
            // 일부 기기는 LoudnessEnhancer 미지원 → 부스트 없이 정상 재생만 유지
            Log.w("AlarmPlayer", "⚠️ LoudnessEnhancer 미지원/실패 (부스트 없이 재생)", e)
        }
    }

    private fun releaseLoudnessEnhancer() {
        try {
            loudnessEnhancer?.release()
        } catch (e: Exception) {
            Log.e("AlarmPlayer", "LoudnessEnhancer 해제 실패", e)
        } finally {
            loudnessEnhancer = null
        }
    }

    private fun playVibration(strength: Int) {
        if (strength == 0) {
            Log.d("AlarmPlayer", "진동 비활성화")
            return
        }

        // ⭐ 기존 진동 먼저 취소
        try {
            vibrator?.cancel()
            vibrator = null
            Log.d("AlarmPlayer", "기존 진동 취소됨")
        } catch (e: Exception) {
            Log.e("AlarmPlayer", "진동 취소 실패 (무시)", e)
        }

        // ⭐ 새로운 Vibrator 인스턴스 생성
        vibrator = context.getSystemService(Context.VIBRATOR_SERVICE) as Vibrator

        // ⭐ 진동 가능 여부 확인
        val hasVibrator = vibrator?.hasVibrator() ?: false
        val hasAmplitudeControl = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            vibrator?.hasAmplitudeControl() ?: false
        } else {
            false
        }

        Log.d("AlarmPlayer", "🔍 Vibrator 진단:")
        Log.d("AlarmPlayer", "  - hasVibrator: $hasVibrator")
        Log.d("AlarmPlayer", "  - hasAmplitudeControl: $hasAmplitudeControl")
        Log.d("AlarmPlayer", "  - strength: $strength")

        if (!hasVibrator) {
            Log.e("AlarmPlayer", "❌ 기기에 진동 기능이 없음!")
            return
        }

        // 진동 세기에 따른 패턴 설정 (1=약하게, 3=강하게)
        val pattern = when(strength) {
            1 -> longArrayOf(0, 500, 800, 500)   // 약하게: 짧은 진동
            3 -> longArrayOf(0, 1000, 300, 1000) // 강하게: 긴 진동
            else -> longArrayOf(0, 800, 500, 800)
        }

        // 진동 세기 (amplitude)
        val amplitude = when(strength) {
            1 -> 100  // 약하게
            3 -> 255  // 강하게 (최대)
            else -> 180
        }

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                // API 33+: VibrationAttributes 사용 (권장)
                val amplitudes = intArrayOf(0, amplitude, 0, amplitude)
                val effect = VibrationEffect.createWaveform(pattern, amplitudes, 0)

                val vibrationAttributes = android.os.VibrationAttributes.Builder()
                    .setUsage(android.os.VibrationAttributes.USAGE_ALARM)
                    .build()

                vibrator?.vibrate(effect, vibrationAttributes)
                Log.d("AlarmPlayer", "✅ vibrate() 호출 완료 (API 33+ VibrationAttributes)")

            } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                // API 26-32: AudioAttributes 사용
                val amplitudes = intArrayOf(0, amplitude, 0, amplitude)
                val effect = VibrationEffect.createWaveform(pattern, amplitudes, 0)

                val audioAttributes = AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ALARM)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build()

                vibrator?.vibrate(effect, audioAttributes)
                Log.d("AlarmPlayer", "✅ vibrate() 호출 완료 (API 26+ AudioAttributes)")

            } else {
                // API 25 이하: Deprecated 메서드
                @Suppress("DEPRECATION")
                vibrator?.vibrate(pattern, 0)
                Log.d("AlarmPlayer", "✅ vibrate() 호출 완료 (Legacy)")
            }

            Log.d("AlarmPlayer", "진동 시작: 세기 $strength, 패턴=${pattern.contentToString()}")
        } catch (e: Exception) {
            Log.e("AlarmPlayer", "❌ 진동 시작 실패", e)
        }
    }

    // ⭐ 2026-09-14 (출시전 감사 #14) - isAlarmRinging()(MediaPlayer.isPlaying 기준)은 제거함. 알람 ID를
    // 구분하지 못하고 진동·무음 알람은 항상 false라, 앱에서 다른 알람을 삭제하면 울리는 알람이 멈추는
    // 원인이었음. 대신 AlarmActionHelper.isAlarmRinging(context, alarmId)(활성 울림 회차 기준)을 씀.

    fun stopAlarm() {
        Log.d("AlarmPlayer", "알람 중지")

        try {
            mediaPlayer?.apply {
                if (isPlaying) {
                    stop()
                    Log.d("AlarmPlayer", "소리 중지됨")
                }
            }
        } catch (e: Exception) {
            Log.e("AlarmPlayer", "MediaPlayer 중지 실패", e)
        } finally {
            // 예외 발생해도 반드시 release
            try {
                mediaPlayer?.release()
            } catch (e: Exception) {
                Log.e("AlarmPlayer", "MediaPlayer release 실패", e)
            }
            mediaPlayer = null
            releaseLoudnessEnhancer()
        }

        try {
            vibrator?.cancel()
        } catch (e: Exception) {
            Log.e("AlarmPlayer", "진동 중지 실패", e)
        } finally {
            vibrator = null
        }

        // ⭐ 시스템 알람 볼륨 복원 - 미리듣기가 아직 잡고 있으면 미리듣기가 끝날 때 복원됨(AUD-06)
        AlarmStreamVolume.release(context, AlarmStreamVolume.HOLDER_ALARM)
    }
}
