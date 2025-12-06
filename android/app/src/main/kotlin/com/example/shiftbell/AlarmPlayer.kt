package com.example.shiftbell

import android.content.Context
import android.content.res.AssetFileDescriptor
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.Build
import android.util.Log

class AlarmPlayer(private val context: Context) {
    private var mediaPlayer: MediaPlayer? = null
    private var vibrator: Vibrator? = null

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
        Log.d("AlarmPlayer", "알람 재생: $soundFile, 음량: $volume, 진동: $vibrationStrength")
        stopAlarm() // 기존 알람 정지

        when {
            // 시스템 기본 알람음
            soundFile == "default" -> {
                playDefaultSound(volume)
                playVibration(vibrationStrength)
            }
            // alarmbell로 시작하면 커스텀 사운드 재생
            soundFile.startsWith("alarmbell") -> {
                playCustomSound(soundFile, volume)
                playVibration(vibrationStrength)  // 소리 타입은 진동 항상 포함
            }
            // 기존 호환용 (loud, soft)
            soundFile == "loud" || soundFile == "soft" -> {
                playDefaultSound(volume)
                playVibration(vibrationStrength)
            }
            soundFile == "vibrate" -> playVibration(vibrationStrength)
            soundFile == "silent" -> {} // 아무것도 안 함
        }
    }

    // DB에서 알람 타입 설정 읽어서 재생
    fun playAlarmFromDB(alarmId: Int) {
        try {
            val dbHelper = DatabaseHelper.getInstance(context)
            val db = dbHelper.readableDatabase

            // 알람에서 alarm_type_id 조회
            val alarmCursor = db.query(
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
            alarmCursor.close()

            // alarm_types에서 설정 조회
            val typeCursor = db.query(
                "alarm_types",
                arrayOf("sound_file", "volume", "vibration_strength"),
                "id = ?",
                arrayOf(alarmTypeId.toString()),
                null, null, null
            )

            var soundFile = "alarmbell1"  // 기본값: 알람벨1
            var volume = 0.7f  // 기본값: 70%
            var vibrationStrength = 3  // 기본값: 강하게

            if (typeCursor.moveToFirst()) {
                soundFile = typeCursor.getString(typeCursor.getColumnIndexOrThrow("sound_file"))
                volume = typeCursor.getFloat(typeCursor.getColumnIndexOrThrow("volume"))
                vibrationStrength = typeCursor.getInt(typeCursor.getColumnIndexOrThrow("vibration_strength"))
            }
            typeCursor.close()
            db.close()

            Log.d("AlarmPlayer", "DB 설정: soundFile=$soundFile, volume=$volume, vibration=$vibrationStrength")
            playAlarmWithSettings(soundFile, volume, vibrationStrength)

        } catch (e: Exception) {
            Log.e("AlarmPlayer", "DB 설정 읽기 실패, 기본값 사용", e)
            playAlarmWithSettings("alarmbell1", 0.7f, 3)  // 기본값: 알람벨1, 70%, 강하게
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

            // 리소스 URI 생성
            val soundUri = android.net.Uri.parse("android.resource://${context.packageName}/$resourceId")
            Log.d("AlarmPlayer", "커스텀 사운드 로드: $soundUri")

            mediaPlayer = MediaPlayer().apply {
                setDataSource(context, soundUri)

                // 핵심: STREAM_ALARM 사용!
                setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_ALARM)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build()
                )

                // 음량 설정 (DB에서 읽은 값, 0.0~1.0이 실제 최대 볼륨 기준)
                setVolume(volume, volume)

                isLooping = true
                prepare()
                start()
            }

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
            // 알람 소리 URI
            val alarmUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)

            mediaPlayer = MediaPlayer().apply {
                setDataSource(context, alarmUri)

                // 핵심: STREAM_ALARM 사용!
                setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_ALARM)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build()
                )

                // 음량 설정 (DB에서 읽은 값, 0.0~1.0이 실제 최대 볼륨 기준)
                setVolume(volume, volume)

                isLooping = true
                prepare()
                start()
            }

            Log.d("AlarmPlayer", "기본 알람 소리 재생 시작: 음량 ${(volume * 100).toInt()}%")

        } catch (e: Exception) {
            Log.e("AlarmPlayer", "기본 알람 소리 재생 실패", e)
        }
    }

    private fun playVibration(strength: Int) {
        if (strength == 0) {
            Log.d("AlarmPlayer", "진동 비활성화")
            return
        }

        vibrator = context.getSystemService(Context.VIBRATOR_SERVICE) as Vibrator

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

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val amplitudes = intArrayOf(0, amplitude, 0, amplitude)
            vibrator?.vibrate(
                VibrationEffect.createWaveform(pattern, amplitudes, 0) // 0 = 반복
            )
        } else {
            @Suppress("DEPRECATION")
            vibrator?.vibrate(pattern, 0)
        }

        Log.d("AlarmPlayer", "진동 시작: 세기 $strength")
    }

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
        }

        try {
            vibrator?.cancel()
        } catch (e: Exception) {
            Log.e("AlarmPlayer", "진동 중지 실패", e)
        } finally {
            vibrator = null
        }
    }
}
