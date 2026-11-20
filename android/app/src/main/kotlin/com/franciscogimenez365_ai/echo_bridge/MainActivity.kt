package com.franciscogimenez365_ai.echo_bridge

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.*

class MainActivity : FlutterActivity() {
    private val METHOD_CHANNEL = "com.franciscogimenez365_ai.echo_bridge/methods"
    private val EVENT_CHANNEL = "com.franciscogimenez365_ai.echo_bridge/events"

    private var eventSink: EventChannel.EventSink? = null
    private var audioRecorder: AudioRecorderHelper? = null
    private var speechEngine: SpeechEngine? = null
    private var translationEngine: TranslationEngine? = null

    private val mainScope = CoroutineScope(Dispatchers.Main + SupervisorJob())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // 1. Canal de eventos en tiempo real (Kotlin -> Flutter)
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            })

        // 2. Canal de comandos (Flutter -> Kotlin)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "initModels" -> {
                        val modelsDir = call.argument<String>("modelsDir") ?: ""
                        val sourceLang = call.argument<String>("sourceLang") ?: "es"
                        val targetLang = call.argument<String>("targetLang") ?: "en"

                        mainScope.launch(Dispatchers.Default) {
                            val ok = setupPipeline(modelsDir, sourceLang, targetLang)
                            withContext(Dispatchers.Main) {
                                result.success(ok)
                            }
                        }
                    }

                    "startListening" -> {
                        speechEngine?.startNewRecordingBuffer()
                        audioRecorder?.startRecording()
                        sendEvent("status", "listening")
                        result.success(true)
                    }

                    "stopListening" -> {
                        audioRecorder?.stopRecording()
                        speechEngine?.stopAndTranscribe()
                        sendEvent("status", "idle")
                        result.success(true)
                    }

                    "speakText" -> {
                        val text = call.argument<String>("text") ?: ""
                        speechEngine?.speak(text)
                        result.success(true)
                    }

                    else -> result.notImplemented()
                }
            }
    }

    private fun setupPipeline(modelsDir: String, sourceLang: String, targetLang: String): Boolean {
        translationEngine?.release()
        speechEngine?.release()
        audioRecorder?.stopRecording()

        translationEngine = TranslationEngine(modelsDir)
        val transOk = translationEngine?.loadDirection("$sourceLang-$targetLang") ?: false

        speechEngine = SpeechEngine(this, modelsDir) { transcribedText ->
            // Cuando Whisper termina de transcribir una frase:
            sendEvent("transcription", transcribedText)

            mainScope.launch(Dispatchers.Default) {
                val translated = translationEngine?.translate(transcribedText) ?: ""
                if (translated.isNotEmpty()) {
                    sendEvent("translation", translated)
                    speechEngine?.speak(translated)
                }
            }
        }
        val speechOk = speechEngine?.initModels(sourceLang, targetLang) ?: false

        audioRecorder = AudioRecorderHelper { audioChunk ->
            speechEngine?.appendAudioChunk(audioChunk)
        }

        return transOk && speechOk
    }

    private fun sendEvent(type: String, data: String) {
        mainScope.launch(Dispatchers.Main) {
            eventSink?.success(mapOf("type" to type, "data" to data))
        }
    }

    override fun onDestroy() {
        audioRecorder?.stopRecording()
        speechEngine?.release()
        translationEngine?.release()
        mainScope.cancel()
        super.onDestroy()
    }
}
