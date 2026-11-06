package com.zerkalo.mirror

import android.content.Intent
import android.content.pm.PackageManager
import android.media.MediaPlayer
import android.media.MediaRecorder
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.speech.tts.TextToSpeech
import android.util.Base64
import android.util.Log
import android.view.View
import android.view.WindowManager
import android.widget.Button
import android.widget.TextView
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.LifecycleOwner
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

    private lateinit var sendButton: Button
    private lateinit var resultTextView: TextView
    private var textToSpeech: TextToSpeech? = null
    private var isTtsReady = false

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

        sendButton = findViewById(R.id.sendButton)
        resultTextView = findViewById(R.id.resultTextView)

        textToSpeech = TextToSpeech(this, this)

        sendButton.setOnClickListener {
            sendVoiceRequest("Привет, Зеркало!")
        }
    }

    private fun sendVoiceRequest(text: String) {
        sendButton.isEnabled = false
        resultTextView.text = "Отправка запроса..."

        lifecycleScope.launch(Dispatchers.IO) {
            try {
                val request = VoiceRequest(text = text)
                val response = mirrorApi.sendVoice(request)
                
                withContext(Dispatchers.Main) {
                    if (response.success && !response.response.isNullOrBlank()) {
                        resultTextView.text = response.response
                        speakText(response.response)
                    } else {
                        showError("Ошибка сервера: ${response.error ?: "Неизвестно"}")
                    }
                }
            } catch (e: Exception) {
                withContext(Dispatchers.Main) {
                    showError("Сетевая ошибка: ${e.localizedMessage}")
                }
            } finally {
                withContext(Dispatchers.Main) {
                    sendButton.isEnabled = true
                }
            }
        }
    }

    private fun speakText(text: String) {
        if (isTtsReady) {
            textToSpeech?.speak(text, TextToSpeech.QUEUE_FLUSH, null, null)
        }
    }

    private fun showError(message: String) {
        resultTextView.text = message
        Toast.makeText(this, message, Toast.LENGTH_LONG).show()
    }

    override fun onInit(status: Int) {
        if (status == TextToSpeech.SUCCESS) {
            textToSpeech?.language = Locale("ru", "RU")
            isTtsReady = true
        } else {
            showError("Инициализация TTS не удалась")
        }
    }

    override fun onDestroy() {
        textToSpeech?.stop()
        textToSpeech?.shutdown()
        super.onDestroy()
    }
}
