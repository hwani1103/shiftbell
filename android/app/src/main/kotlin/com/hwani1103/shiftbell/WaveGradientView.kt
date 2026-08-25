// android/app/src/main/kotlin/com/hwani1103/shiftbell/WaveGradientView.kt
//
// ⭐ 2026-08-25 추가 - 알람이 울리는 동안(=이 뷰가 화면에 붙어있는 동안) 배경
// 그라데이션이 천천히 회전하며 "파도치는" 효과를 내는 커스텀 뷰. 잠금화면
// (AlarmActivity)과 홈 화면 오버레이(AlarmOverlayService) 양쪽에서 공용으로 씀.
//
// 왜 XML <shape><gradient angle=".../></shape>를 못 쓰나: GradientDrawable의
// orientation은 8방향(TOP_BOTTOM/TL_BR/...) 중 하나로만 고정되고 부드러운 연속
// 회전을 지원하지 않음. 그래서 android.graphics.LinearGradient를 직접 매 프레임
// 다른 각도로 새로 만들어서 그림(뷰 하나 크기의 셰이더 재생성이라 비용은 작음).
//
// 생명주기: onAttachedToWindow에서 애니메이터 시작, onDetachedFromWindow에서
// 반드시 cancel - 안 하면 Activity/Service가 알람 화면을 내린 뒤에도 애니메이터가
// 계속 돌면서 이 View(=그 Context)를 붙잡고 있게 됨(메모리 누수 + 불필요한 배터리
// 소모). AlarmActivity.finish()/AlarmOverlayService의 오버레이 제거 모두 결국 이
// 뷰를 windowManager/뷰 트리에서 떼어내는 동작이라 onDetachedFromWindow가 반드시
// 불리므로, 별도로 액티비티/서비스 쪽에 정리 코드를 추가할 필요가 없음.
package com.hwani1103.shiftbell

import android.animation.ValueAnimator
import android.content.Context
import android.graphics.Canvas
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Path
import android.graphics.Shader
import android.util.AttributeSet
import android.view.View
import android.view.animation.LinearInterpolator
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.sin

class WaveGradientView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
) : View(context, attrs) {

    // "오로라 페일" 그라데이션(라벤더 → 스카이 → 민트)과 동일한 색 -
    // alarm_gradient_bg.xml/overlay_card_gradient.xml과 같은 값.
    private val gradientColors = intArrayOf(
        0xFFDACEF9.toInt(),
        0xFFCEDEFC.toInt(),
        0xFFBFF5F1.toInt(),
    )
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val bottomCornerRadiusPx: Float

    // 315도(기존 angle=315 정적 그라데이션과 동일한 시작 각도)에서 시작.
    private var angleDeg = 315f
    private var animator: ValueAnimator? = null

    init {
        val a = context.obtainStyledAttributes(attrs, R.styleable.WaveGradientView)
        bottomCornerRadiusPx = a.getDimension(R.styleable.WaveGradientView_bottomCornerRadius, 0f)
        a.recycle()
        setWillNotDraw(false)
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        if (animator == null) {
            // ⭐ 360도를 18초에 걸쳐 한 바퀴 도는 "적당한 속도" - 너무 빠르면
            // 알람 화면치고 산만하고, 너무 느리면 움직이는 게 거의 안 보임.
            animator = ValueAnimator.ofFloat(315f, 315f + 360f).apply {
                duration = 18_000L
                repeatCount = ValueAnimator.INFINITE
                interpolator = LinearInterpolator()
                addUpdateListener {
                    angleDeg = it.animatedValue as Float
                    invalidate()
                }
                start()
            }
        }
    }

    override fun onDetachedFromWindow() {
        animator?.cancel()
        animator = null
        super.onDetachedFromWindow()
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val w = width.toFloat()
        val h = height.toFloat()
        if (w <= 0f || h <= 0f) return

        if (bottomCornerRadiusPx > 0f) {
            val path = Path()
            val radii = floatArrayOf(
                0f, 0f, // top-left
                0f, 0f, // top-right
                bottomCornerRadiusPx, bottomCornerRadiusPx, // bottom-right
                bottomCornerRadiusPx, bottomCornerRadiusPx, // bottom-left
            )
            path.addRoundRect(0f, 0f, w, h, radii, Path.Direction.CW)
            canvas.save()
            canvas.clipPath(path)
        }

        val rad = Math.toRadians(angleDeg.toDouble())
        // 뷰 중심에서 각도 방향으로 대각선 절반 길이만큼 뻗어나가는 두 점을
        // 시작/끝점으로 씀 - 회전 각도와 무관하게 그라데이션이 뷰 전체를
        // 항상 완전히 덮도록 대각선 길이 기준으로 반지름을 잡음.
        val radius = hypot(w, h) / 2f
        val cx = w / 2f
        val cy = h / 2f
        val dx = (cos(rad) * radius).toFloat()
        val dy = (sin(rad) * radius).toFloat()

        paint.shader = LinearGradient(
            cx - dx, cy - dy, cx + dx, cy + dy,
            gradientColors, null, Shader.TileMode.CLAMP,
        )
        canvas.drawRect(0f, 0f, w, h, paint)

        if (bottomCornerRadiusPx > 0f) {
            canvas.restore()
        }
    }
}
