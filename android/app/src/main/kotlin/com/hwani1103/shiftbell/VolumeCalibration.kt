package com.hwani1103.shiftbell

import kotlin.math.sqrt

/**
 * ⭐ 알람 음량 calibration
 *
 * 배경: 기존엔 슬라이더 값(0.0~1.0)을 그대로 MediaPlayer.setVolume()에 넣었는데,
 * 사람 청감은 선형이 아니라서 슬라이더 앞쪽 절반은 거의 안 커지는 것처럼 느껴지고,
 * 최대치(1.0)로 올려도 "생각보다 작다"는 문제가 있었음.
 *
 * 적용:
 *  - linearGain: sqrt 커브. 슬라이더 50% → 기존 70%와 비슷한 체감 음량 (sqrt(0.5)≈0.71)
 *  - boostMillibels: MediaPlayer.setVolume()은 1.0(유니티 게인)을 못 넘기 때문에,
 *    LoudnessEnhancer로 슬라이더 값에 비례해 최대 +9dB까지 추가로 키움.
 *    → 예전 최대(1.0, 부스트 없음)보다 새 최대가 실제로 더 커짐.
 *
 * DB에 저장된 slider 값 자체는 건드리지 않음 (기존 사용자 볼륨 설정 그대로 유지되고,
 * 재생 시점에만 이 커브를 적용하므로 기존 70% 사용자도 자동으로 더 큰 소리를 듣게 됨).
 */
object VolumeCalibration {
    private const val MAX_BOOST_MILLIBEL = 900  // +9dB

    fun linearGain(sliderVolume: Float): Float {
        val s = sliderVolume.coerceIn(0f, 1f)
        return sqrt(s)
    }

    fun boostMillibels(sliderVolume: Float): Int {
        val s = sliderVolume.coerceIn(0f, 1f)
        return (s * MAX_BOOST_MILLIBEL).toInt()
    }
}
