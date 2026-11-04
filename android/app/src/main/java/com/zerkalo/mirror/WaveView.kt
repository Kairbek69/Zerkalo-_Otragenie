package com.zerkalo.mirror

import android.animation.ValueAnimator
import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.util.AttributeSet
import android.view.View
import android.view.animation.LinearInterpolator

/**
 * Анимация «волн» поверх камеры.
 * LISTENING — медленные кольца, ACTIVE — быстрые (думает/говорит), IDLE — тихо.
 */
class WaveView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
    defStyleAttr: Int = 0,
) : View(context, attrs, defStyleAttr) {

    enum class Mode { IDLE, LISTENING, ACTIVE }

    private var mode = Mode.IDLE
    private var phase = 0f

    private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.WHITE
        style = Paint.Style.STROKE
        strokeWidth = 6f
    }

    private val animator = ValueAnimator.ofFloat(0f, 1f).apply {
        duration = 1600
        repeatCount = ValueAnimator.INFINITE
        interpolator = LinearInterpolator()
        addUpdateListener { animation ->
            phase = animation.animatedValue as Float
            invalidate()
        }
    }

    fun setMode(newMode: Mode) {
        if (mode == newMode) return
        mode = newMode
        when (mode) {
            Mode.IDLE -> if (animator.isStarted) animator.pause()
            else -> animator.resume()
        }
        invalidate()
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        animator.start()
        if (mode == Mode.IDLE) animator.pause()
    }

    override fun onDetachedFromWindow() {
        animator.cancel()
        super.onDetachedFromWindow()
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        if (mode == Mode.IDLE) return
        val cx = width / 2f
        val cy = height / 2f
        val maxR = (minOf(width, height) / 2f) * 0.9f
        val rings = if (mode == Mode.ACTIVE) 5 else 3
        for (i in 0 until rings) {
            val p = (phase + i.toFloat() / rings) % 1f
            paint.alpha = ((1f - p) * 90).toInt().coerceIn(0, 255)
            canvas.drawCircle(cx, cy, maxR * p, paint)
        }
        paint.alpha = 70
        canvas.drawCircle(cx, cy, maxR * 0.12f, paint)
    }
}
