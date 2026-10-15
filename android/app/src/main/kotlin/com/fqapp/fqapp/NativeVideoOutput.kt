package com.fqapp.fqapp

import androidx.media3.common.Player
import io.flutter.view.TextureRegistry

/** Owns the decoder and its Flutter-managed output surface on the platform thread. */
internal class NativeVideoOutput(
    private val player: Player,
    private val producer: TextureRegistry.SurfaceProducer
) : TextureRegistry.SurfaceProducer.Callback {
    private var released = false
    private var needsSurface = true

    /**
     * True while the decoder renders to the floating overlay instead of the
     * Flutter texture. While floating, producer callbacks must not clear the
     * overlay surface; they only record that the Flutter surface needs a
     * rebind when playback returns.
     */
    private var floating = false

    val textureId: Long get() = producer.id()

    fun attach() {
        if (released) return
        producer.setCallback(this)
        onSurfaceAvailable()
    }

    override fun onSurfaceAvailable() {
        if (released || !needsSurface || floating) return
        // A restored producer may return a different Surface. Never keep the
        // Surface returned before cleanup or bind it back to the decoder.
        player.setVideoSurface(producer.surface)
        needsSurface = false
    }

    override fun onSurfaceCleanup() {
        if (released) return
        val wasNeeding = needsSurface
        needsSurface = true
        if (floating || wasNeeding) return
        player.clearVideoSurface()
    }

    /** Detach the Flutter texture so the decoder can render to the floating overlay. */
    fun detachForFloating() {
        if (released) return
        floating = true
        needsSurface = true
        player.clearVideoSurface()
    }

    /** Bind the decoder to the floating overlay's surface. */
    fun attachFloating(surface: android.view.Surface) {
        if (released) return
        player.setVideoSurface(surface)
    }

    /**
     * Return the decoder to the Flutter texture. If the Flutter surface was
     * cleaned up while floating, [needsSurface] stays true and the next
     * [onSurfaceAvailable] rebinds it; otherwise rebind immediately.
     */
    fun restoreFromFloating() {
        if (released) return
        floating = false
        player.clearVideoSurface()
        if (!needsSurface) {
            player.setVideoSurface(producer.surface)
        }
    }

    fun rotationCorrection(formatRotationDegrees: Int): Int =
        if (!producer.handlesCropAndRotation() &&
            formatRotationDegrees in listOf(90, 180, 270)
        ) formatRotationDegrees else 0

    /** 诊断用：producer 是否已代劳裁剪与旋转（决定上面那条分支）。 */
    fun handlesCropAndRotation(): Boolean = producer.handlesCropAndRotation()

    fun release() {
        if (released) return
        released = true
        try {
            producer.setCallback(null)
        } finally {
            // The decoder must stop writing before Flutter releases the
            // surface. The producer owns Surface.release(), including cleanup.
            try {
                player.release()
            } finally {
                producer.release()
            }
        }
    }
}
