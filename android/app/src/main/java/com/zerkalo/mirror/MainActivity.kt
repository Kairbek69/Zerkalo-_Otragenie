package com.zerkalo.mirror

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import android.util.Log
import android.widget.TextView
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import retrofit2.Retrofit
import retrofit2.converter.gson.GsonConverterFactory
import retrofit2.http.Body
import retrofit2.http.POST
import java.util.Locale

data class VoiceRequest(
    val text: String,
    val session_id: String? = null
)

data class VoiceResponse(
    val success: Boolean,
    val response: String?,
    val error: String?
)

interface MirrorApi {
    @POST("voice")
    suspend fun sendVoice(@Body request: VoiceRequest): VoiceResponse
}

class MainActivity : AppCompatActivity(), TextToSpeech.OnInitListener {

    private lateinit var resultTextView: TextView
    
    private var textToSpeech: TextToSpeech? = null
    private var isTtsReady = false

    private var speechRecognizer: SpeechRecognizer? = null
    private var speechRecognizerIntent: Intent? = null
    
    private val handler = Handler(Looper.getMainLooper())
    private var isListening = false
    private var hasGreeted = false // Флаг, чтобы не здороваться дважды

    private val retrofit by lazy {
        Retrofit.Builder()
            .baseUrl("https://zerkalo-6sla.onrender.com/")
            .addConverterFactory(GsonConverterFactory.create())
            .build()
    }

    private val mirrorApi by lazy {
        retrofit.create(MirrorApi::class.java)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        resultTextView = findViewById(R.id.resultTextView)

        // 1. Запрашиваем разрешение на микрофон
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.RECORD_AUDIO), 1)
        }

        // 2. Инициализируем TTS (голос)
        textToSpeech = TextToSpeech(this, this)

        // 3. Настраиваем распознаватель (уши)
        setupSpeechRecognizer()
    }

    private fun setupSpeechRecognizer() {
        if (!SpeechRecognizer.isRecognitionAvailable(this)) {
            showError("Распознавание речи недоступно")
            return
        }

        speechRecognizer = SpeechRecognizer.createSpeechRecognizer(this)
        speechRecognizerIntent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, "ru-RU")
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, false)
        }

        speechRecognizer?.setRecognitionListener(object : RecognitionListener {
            override fun onReadyForSpeech(params: Bundle?) {
                resultTextView.text = "Слушаю..."
            }

            override fun onBeginningOfSpeech() {}
            override fun onRmsChanged(rmsdB: Float) {}
            override fun onBufferReceived(buffer: ByteArray?) {}

            override fun onEndOfSpeech() {
                resultTextView.text = "Думаю..."
            }

            override fun onError(error: Int) {
                isListening = false
                // Если тишина или ошибка — перезапускаем слух через 2 сек
                handler.postDelayed({ startListening() }, 2000)
            }

            override fun onResults(results: Bundle?) {
                isListening = false
                val matches = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                if (!matches.isNullOrEmpty()) {
                    val text = matches[0]
                    resultTextView.text = "Вы: $text"
                    sendVoiceRequest(text)
                } else {
                    handler.postDelayed({ startListening() }, 1000)
                }
            }

            override fun onPartialResults(partialResults: Bundle?) {}
            override fun onEvent(eventType: Int, params: Bundle?) {}
        })
    }

    private fun startListening() {
        if (!isListening && isTtsReady) {
            isListening = true
            try {
                speechRecognizer?.startListening(speechRecognizerIntent)
            } catch (e: Exception) {
                isListening = false
                Log.e("Mirror", "Ошибка слуха: ${e.message}")
            }
        }
    }

    private fun sendVoiceRequest(text: String) {
        lifecycleScope.launch(Dispatchers.IO) {
            try {
                val request = VoiceRequest(text = text)
                val response = mirrorApi.sendVoice(request)

                withContext(Dispatchers.Main) {
                    if (response.success && !response.response.isNullOrBlank()) {
                        resultTextView.text = "Зеркало: ${response.response}"
                        speakText(response.response)
                    } else {
                        val errorMsg = response.error ?: "Пустой ответ"
                        resultTextView.text = "Ошибка сервера: $errorMsg"
                        handler.postDelayed({ startListening() }, 2000)
                    }
                }
            } catch (e: retrofit2.HttpException) {
                val errorBody = e.response()?.errorBody()?.string()
                withContext(Dispatchers.Main) {
                    resultTextView.text = "HTTP Ошибка ${e.code()}:\n$errorBody"
                    handler.postDelayed({ startListening() }, 3000)
                }
            } catch (e: Exception) {
                withContext(Dispatchers.Main) {
                    resultTextView.text = "Сетевая ошибка: ${e.localizedMessage}"
                    handler.postDelayed({ startListening() }, 3000)
                }
            }
        }
    }

    private fun speakText(text: String) {
        if (isTtsReady) {
            textToSpeech?.speak(text, TextToSpeech.QUEUE_FLUSH, null, "MirrorUtterance")
        }
    }

    private fun showError(message: String) {
        Toast.makeText(this, message, Toast.LENGTH_LONG).show()
        resultTextView.text = message
    }

    override fun onInit(status: Int) {
        if (status == TextToSpeech.SUCCESS) {
            val result = textToSpeech?.setLanguage(Locale("ru", "RU"))
            if (result == TextToSpeech.LANG_MISSING_DATA || result == TextToSpeech.LANG_NOT_SUPPORTED) {
                showError("Ошибка TTS: Русский не поддерживается")
            } else {
                isTtsReady = true

                // Настраиваем, что делать, когда Зеркало ЗАКОНЧИЛО говорить
                textToSpeech?.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                    override fun onStart(utteranceId: String?) {}
                    
                    override fun onDone(utteranceId: String?) {
                        // Как только речь закончилась — Зеркало начинает СЛУШАТЬ
                        handler.postDelayed({ startListening() }, 500)
                    }
                    
                    override fun onError(utteranceId: String?) {
                        handler.postDelayed({ startListening() }, 1000)
                    }
                })

                // ЗАПУСКАЕМ ПЕРВОЕ ПРИВЕТСТВИЕ
                if (!hasGreeted) {
                    hasGreeted = true
                    val greeting = "Привет, Хранитель. Я — Зеркало. Я здесь, чтобы отражать твои мысли, автоматизировать твои действия и помогать тебе. Чем я могу помочь тебе сегодня?"
                    resultTextView.text = "Зеркало: $greeting"
                    // Немного ждем, чтобы TTS точно прогрузился, и говорим
                    handler.postDelayed({ speakText(greeting) }, 800)
                }
            }
        } else {
            showError("Инициализация TTS не удалась")
        }
    }

    override fun onDestroy() {
        handler.removeCallbacksAndMessages(null)
        speechRecognizer?.destroy()
        textToSpeech?.stop()
        textToSpeech?.shutdown()
        super.onDestroy()
    }
}
