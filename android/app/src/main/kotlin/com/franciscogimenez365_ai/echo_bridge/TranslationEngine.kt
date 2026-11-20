package com.franciscogimenez365_ai.echo_bridge

import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtSession
import org.json.JSONObject
import java.io.File
import java.nio.LongBuffer

class TranslationEngine(
    private val modelsDir: String
) {
    private val ortEnv: OrtEnvironment = OrtEnvironment.getEnvironment()
    private var encoderSession: OrtSession? = null
    private var decoderSession: OrtSession? = null

    private var vocabMap: Map<String, Long> = emptyMap()
    private var idToTokenMap: Map<Long, String> = emptyMap()

    private var padTokenId: Long = 58100L // Estándar en opus-mt-es-en / en-es
    private var eosTokenId: Long = 0L

    /**
     * Carga el par de traducción según la dirección ("es-en" o "en-es")
     */
    fun loadDirection(direction: String): Boolean {
        release()

        val dirPath = "$modelsDir/translation/opus-mt-$direction"
        val encoderFile = File("$dirPath/encoder_model_quantized.onnx")
        val decoderFile = File("$dirPath/decoder_model_quantized.onnx")
        val vocabFile = File("$dirPath/vocab.json")

        if (!encoderFile.exists() || !decoderFile.exists() || !vocabFile.exists()) {
            return false
        }

        // 1. Cargar vocabulario JSON (palabra -> ID)
        val jsonStr = vocabFile.readText(Charsets.UTF_8)
        val jsonObj = JSONObject(jsonStr)
        val tempVocab = mutableMapOf<String, Long>()
        val tempReverse = mutableMapOf<Long, String>()

        val keys = jsonObj.keys()
        while (keys.hasNext()) {
            val token = keys.next()
            val id = jsonObj.getLong(token)
            tempVocab[token] = id
            tempReverse[id] = token
        }
        vocabMap = tempVocab
        idToTokenMap = tempReverse

        padTokenId = vocabMap["<pad>"] ?: 58100L
        eosTokenId = vocabMap["</s>"] ?: 0L

        // 2. Inicializar sesiones de ONNX Runtime
        val sessionOptions = OrtSession.SessionOptions().apply {
            setIntraOpNumThreads(2)
            setOptimizationLevel(OrtSession.SessionOptions.OptLevel.ALL_OPT)
        }

        encoderSession = ortEnv.createSession(encoderFile.absolutePath, sessionOptions)
        decoderSession = ortEnv.createSession(decoderFile.absolutePath, sessionOptions)

        return true
    }

    /**
     * Traduce una frase completa de forma síncrona (llamar desde Coroutine en Dispatchers.Default)
     */
    fun translate(text: String): String {
        val encoder = encoderSession ?: return text
        val decoder = decoderSession ?: return text
        if (text.isBlank()) return ""

        // 1. Tokenización básica estilo SentencePiece (reemplazo de espacios por '▁')
        val inputIds = tokenize(text)
        val seqLen = inputIds.size.toLong()
        val attentionMask = LongArray(inputIds.size) { 1L }

        val inputIdsTensor = OnnxTensor.createTensor(ortEnv, LongBuffer.wrap(inputIds), longArrayOf(1, seqLen))
        val attentionMaskTensor = OnnxTensor.createTensor(ortEnv, LongBuffer.wrap(attentionMask), longArrayOf(1, seqLen))

        // 2. Ejecutar Encoder
        val encoderInputs = mapOf(
            "input_ids" to inputIdsTensor,
            "attention_mask" to attentionMaskTensor
        )
        val encoderOutputs = encoder.run(encoderInputs)
        val encoderHiddenStates = encoderOutputs[0] as OnnxTensor

        // 3. Bucle autorregresivo del Decoder (genera palabra por palabra hasta </s>)
        val generatedIds = mutableListOf(padTokenId)
        val maxTokens = 64

        for (step in 0 until maxTokens) {
            val decInputArray = generatedIds.toLongArray()
            val decInputTensor = OnnxTensor.createTensor(
                ortEnv,
                LongBuffer.wrap(decInputArray),
                longArrayOf(1, decInputArray.size.toLong())
            )

            val decoderInputs = mapOf(
                "input_ids" to decInputTensor,
                "encoder_hidden_states" to encoderHiddenStates,
                "encoder_attention_mask" to attentionMaskTensor
            )

            val decoderOutputs = decoder.run(decoderInputs)
            val logitsTensor = decoderOutputs[0] as OnnxTensor
            val logits = logitsTensor.floatBuffer

            // Tomamos los logits del último token generado y buscamos el ID con mayor probabilidad (ArgMax)
            val vocabSize = vocabMap.size
            val offset = (decInputArray.size - 1) * vocabSize
            var bestId = eosTokenId
            var maxVal = Float.NEGATIVE_INFINITY

            for (v in 0 until vocabSize) {
                val score = logits.get(offset + v)
                if (score > maxVal) {
                    maxVal = score
                    bestId = v.toLong()
                }
            }

            decInputTensor.close()
            decoderOutputs.close()

            if (bestId == eosTokenId) break
            generatedIds.add(bestId)
        }

        // Liberar tensores
        inputIdsTensor.close()
        attentionMaskTensor.close()
        encoderOutputs.close()

        return detokenize(generatedIds)
    }

    private fun tokenize(text: String): LongArray {
        val normalized = "▁" + text.trim().replace(" ", "▁")
        val ids = mutableListOf<Long>()
        var i = 0
        while (i < normalized.length) {
            var matched = false
            // Greedy longest-match sobre el vocabulario SentencePiece
            for (end in normalized.length downTo i + 1) {
                val sub = normalized.substring(i, end)
                val id = vocabMap[sub]
                if (id != null) {
                    ids.add(id)
                    i = end
                    matched = true
                    break
                }
            }
            if (!matched) {
                // Token desconocido (<unk>)
                ids.add(vocabMap["<unk>"] ?: 1L)
                i++
            }
        }
        ids.add(eosTokenId)
        return ids.toLongArray()
    }

    private fun detokenize(ids: List<Long>): String {
        val sb = StringBuilder()
        for (id in ids) {
            if (id == padTokenId || id == eosTokenId) continue
            val token = idToTokenMap[id] ?: ""
            sb.append(token)
        }
        return sb.toString().replace("▁", " ").trim()
    }

    fun release() {
        encoderSession?.close()
        encoderSession = null
        decoderSession?.close()
        decoderSession = null
    }
}
