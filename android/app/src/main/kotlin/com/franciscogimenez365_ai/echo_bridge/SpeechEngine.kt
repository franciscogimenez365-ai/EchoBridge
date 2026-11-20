package com.franciscogimenez365_ai.echo_bridge

import android.content.Context
import android.speech.tts.TextToSpeech
import com.k2fsa.sherpa.onnx.*
import kotlinx.coroutines.*
import java.io.File
import java.util.Locale

class SpeechEngine(
    private val context: Context,
    private val modelsDir: String,
    private val onTranscriptionResult: (String) -> Unit
) {
    private var recognizer: OfflineRecognizer? = null
    private var androidTts: TextToSpeech? = null
    private var isTtsReady = false

    private val recordedSamples = mutableListOf<Float>()
    private val engineScope = CoroutineScope(Dispatchers.Default + SupervisorJob())

    fun initModels(sourceLang: String, targetLang: String): Boolean {
        release()

        val whisperEncoder = "$modelsDir/whisper/base-encoder.int8.onnx"
        val whisperDecoder = "$modelsDir/whisper/base-decoder.int8.onnx"
        val whisperTokens = "$modelsDir/whisper/base-tokens.txt"

        if (!File(whisperEncoder).exists()) {
            return false
        }

        val recognizerConfig = OfflineRecognizerConfig(
            featConfig = FeatureConfig(sampleRate = 16000, featureDim = 80),
            modelConfig = OfflineModelConfig(
                whisper = OfflineWhisperModelConfig(
                    encoder = whisperEncoder,
                    decoder = whisperDecoder,
                    language = sourceLang,
                    task = "transcribe"
                ),
                tokens = whisperTokens,
                numThreads = 2,
                modelType = "whisper"
            )
        )
        recognizer = OfflineRecognizer(config = recognizerConfig)

        val locale = if (targetLang == "es") Locale("es", "ES") else Locale.US
        androidTts = TextToSpeech(context) { status ->
            if (status == TextToSpeech.SUCCESS) {
                androidTts?.language = locale
                isTtsReady = true
            }
        }

        return true
    }

    fun startNewRecordingBuffer() {
        synchronized(recordedSamples) {
            recordedSamples.clear()
        }
    }

    fun appendAudioChunk(samples: FloatArray) {
        synchronized(recordedSamples) {
            for (s in samples) {
                recordedSamples.add(s)
            }
        }
    }

    fun stopAndTranscribe() {
        val audioArray: FloatArray
        synchronized(recordedSamples) {
            if (recordedSamples.isEmpty()) return
            audioArray = recordedSamples.toFloatArray()
            recordedSamples.clear()
        }

        engineScope.launch {
            transcribeSegment(audioArray)
        }
    }

    private fun transcribeSegment(audioSamples: FloatArray) {
        val currentRecognizer = recognizer ?: return
        val stream = currentRecognizer.createStream()
        stream.acceptWaveform(audioSamples, 16000)
        currentRecognizer.decode(stream)
        val text = currentRecognizer.getResult(stream).text.trim()
        stream.release()

        if (text.isNotEmpty()) {
            onTranscriptionResult(text)
        }
    }

    fun speak(text: String) {
        if (text.isBlank() || !isTtsReady) return
        androidTts?.speak(text, TextToSpeech.QUEUE_ADD, null, "echo_utterance")
    }

    fun release() {
        recognizer?.release()
        recognizer = null
        androidTts?.stop()
        androidTts?.shutdown()
        androidTts = null
        isTtsReady = false
        synchronized(recordedSamples) {
            recordedSamples.clear()
        }
    }
}
