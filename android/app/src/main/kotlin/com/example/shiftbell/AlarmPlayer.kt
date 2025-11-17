package com.example.shiftbell

import android.content.Context
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
    
    fun playAlarm(soundType: String) {
        Log.d("AlarmPlayer", "알람 재생: $soundType")
        stopAlarm() // 기존 알람 정지
        
        when(soundType) {
            "loud", "soft" -> playSound(soundType)
            "vibrate" -> playVibration()
            "silent" -> {} // 아무것도 안 함
        }
    }
    
    private fun playSound(soundType: String) {
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
                
                // 볼륨 설정
                val volume = if (soundType == "loud") 1.0f else 0.5f
                setVolume(volume, volume)
                
                isLooping = true
                prepare()
                start()
            }
            
            Log.d("AlarmPlayer", "소리 재생 시작: $soundType")
            
            // 진동도 추가
            playVibration()
            
        } catch (e: Exception) {
            Log.e("AlarmPlayer", "소리 재생 실패", e)
        }
    }
    
    private fun playVibration() {
        vibrator = context.getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
        
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val pattern = longArrayOf(0, 1000, 500, 1000) // 진동 패턴
            vibrator?.vibrate(
                VibrationEffect.createWaveform(pattern, 0) // 0 = 반복
            )
        } else {
            @Suppress("DEPRECATION")
            val pattern = longArrayOf(0, 1000, 500, 1000)
            vibrator?.vibrate(pattern, 0)
        }
        
        Log.d("AlarmPlayer", "진동 시작")
    }
    
    fun stopAlarm() {
        Log.d("AlarmPlayer", "알람 중지")
        
        mediaPlayer?.apply {
            if (isPlaying) {
                stop()
                Log.d("AlarmPlayer", "소리 중지됨")
            }
            release()
        }
        mediaPlayer = null
        
        vibrator?.cancel()
        vibrator = null
    }
}