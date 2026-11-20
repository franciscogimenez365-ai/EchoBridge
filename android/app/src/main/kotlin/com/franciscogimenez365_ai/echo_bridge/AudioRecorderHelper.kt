package com.franciscogimenez365_ai.echo_bridge

import android.annotation.SuppressLint
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import kotlinx.coroutines.*

class AudioRecorderHelper(
    private val onAudioChunk: (FloatArray) -> Unit
) {
    private var audioRecord: AudioRecord? = null
    private var recordingJob: Job? = null
    private var isRecording = false

    companion object {
        const val SAMPLE_RATE = 16000
        const val CHANNEL_CONFIG = AudioFormat.CHANNEL_IN_MONO
        const val AUDIO_FORMAT = AudioFormat.ENCODING_PCM_16BIT
    }

    @SuppressLint("MissingPermission")
    fun startRecording() {
        if (isRecording) return

        val minBufferSize = AudioRecord.getMinBufferSize(SAMPLE_RATE, CHANNEL_CONFIG, AUDIO_FORMAT)
        // Usamos un buffer cómodo para leer bloques sin perder muestras
        val bufferSize = maxOf(minBufferSize, 4096)

        audioRecord = AudioRecord(
            MediaRecorder.AudioSource.VOICE_RECOGNITION, // Optimizado por Android para voz
            SAMPLE_RATE,
            CHANNEL_CONFIG,
            AUDIO_FORMAT,
            bufferSize
        )

        if (audioRecord?.state != AudioRecord.STATE_INITIALIZED) {
            return
        }

        audioRecord?.startRecording()
        isRecording = true

        // Corrutina en hilo secundario (IO) para no congelar la interfaz
        recordingJob = CoroutineScope(Dispatchers.IO).launch {
            val shortBuffer = ShortArray(512) // Bloques de 512 muestras (32ms a 16kHz), ideal para Silero VAD

            while (isActive && isRecording) {
                val readCount = audioRecord?.read(shortBuffer, 0, shortBuffer.size) ?: 0
                if (readCount > 0) {
                    // Convertimos de PCM 16-bit (Short) a Float (-1.0 a 1.0)
                    val floatBuffer = FloatArray(readCount)
                    for (i in 0 until readCount) {
                        floatBuffer[i] = shortBuffer[i] / 32768.0f
                    }
                    // Enviamos el paquete de audio listo al motor de IA
                    onAudioChunk(floatBuffer)
                }
            }
        }
    }

    fun stopRecording() {
        isRecording = false
        recordingJob?.cancel()
        audioRecord?.apply {
            if (state == AudioRecord.STATE_INITIALIZED) {
                stop()
            }
            release()
        }
        audioRecord = null
    }
}
