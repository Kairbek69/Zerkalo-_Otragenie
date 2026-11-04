package com.zerkalo.mirror

import android.Manifest
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
import android.util.Base64
import android.util.Log
import android.view.View
import android.view.WindowManager
import android.widget.TextView
import androidx.activity.ComponentActivity
import androidx.activity.result.contract.ActivityResultContracts
import androidx.camera.core.CameraSelector
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.core.content.ContextCompat
import okhttp3.Call
import okhttp3.Callback
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response
import org.json.JSONObject
import java.io.File
import java.io.IOException
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

class MainActivity : ComponentActivity() {

    companion object {
        private const val TAG = "Zerkalo"
        private const val SERVER_URL = "https://zerkalo-6sla.onrender.com/voice"

        private const val SILENCE_MS = 1500L
        private const val MIN_RECORD_MS = 700L
        private const val MAX_RECORD_MS = 30_000L
        private const val POLL_MS = 100L
        private const val SILENCE_THRESHOLD = 600
        private const val RESTART_DELAY_MS = 800L
        private const val TEXT_SHOW_MS = 3000L
        private const val ROLE_TIMEOUT_MS = 30_000L

        private const val PREFS = "zerkalo_prefs"
        private const val KEY_ROLE = "role"
    }

    private enum class Role(val code: String, val label: String) {
        KEEPER("keeper", "Хранитель"),
        BUSINESS("business", "Бизнес"),
        SIMPLE("simple", "Простой"),
    }

    private lateinit var previewView: PreviewView
    private lateinit var waveView: WaveView
    private lateinit var statusText: TextView
    private lateinit var roleOverlay: View

    private var recorder: MediaRecorder? = null
    private var currentFile: File? = null
    private var player: MediaPlayer? = null
    private var recognizer: SpeechRecognizer? = null

    @Volatile private var isRecording = false
    @Volatile private var maxAmplitude = 0
    @Volatile private var roleChosen = false

    private var role: Role = Role.SIMPLE
    private val mainHandler = Handler(Looper.getMainLooper())
    private val executor: ExecutorService = Executors.newSingleThreadExecutor()

    // 60+ сек: Render просыпается, Gemini думает
    private val http = OkHttpClient.Builder()
        .connectTimeout(30, TimeUnit.SECONDS)
        .writeTimeout(60, TimeUnit.SECONDS)
        .readTimeout(60, TimeUnit.SECONDS)
        .callTimeout(75, TimeUnit.SECONDS)
        .build()

    private val requiredPermissions = arrayOf(
        Manifest.permission.CAMERA,
        Manifest.permission.RECORD_AUDIO,
    )

    private val permissionLauncher = registerForActivityResult(
        ActivityResultContracts.RequestMultiplePermissions()
    ) { result ->
        if (result.all { it.value }) {
            onPermissionsReady()
        } else {
            setStatus("Нужны разрешения: камера и микрофон.", WaveView.Mode.IDLE)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        setContentView(R.layout.activity_main)

        previewView = findViewById(R.id.previewView)
        waveView = findViewById(R.id.waveView)
        statusText = findViewById(R.id.statusText)
        roleOverlay = findViewById(R.id.roleOverlay)

        findViewById<View>(R.id.roleKeeper).setOnClickListener { chooseRole(Role.KEEPER) }
        findViewById<View>(R.id.roleBusiness).setOnClickListener { chooseRole(Role.BUSINESS) }
        findViewById<View>(R.id.roleSimple).setOnClickListener { chooseRole(Role.SIMPLE) }

        // Возвращающийся пользователь: роль уже выбрана
        getSharedPreferences(PREFS, MODE_PRIVATE).getString(KEY_ROLE, null)
            ?.let { saved ->
                Role.values().find { it.code == saved }?.let {
                    role = it
                    roleChosen = true
                }
            }

        if (hasPermissions()) {
            onPermissionsReady()
        } else {
            permissionLauncher.launch(requiredPermissions)
        }
    }

    private fun onPermissionsReady() {
        startCamera()
        if (!roleChosen) {
            beginRoleSelection()
        } else {
            setStatus("Роль: ${role.label}. Слушаю...", WaveView.Mode.LISTENING)
            startListening()
        }
    }

    override fun onStart() {
        super.onStart()
        if (::previewView.isInitialized && hasPermissions() && roleChosen) {
            startListening()
        }
    }

    override fun onStop() {
        super.onStop()
        isRecording = false
        try { recorder?.stop() } catch (_: Exception) {}
        recorder?.release()
        recorder = null
        player?.let {
            try { it.stop() } catch (_: Exception) {}
            it.release()
        }
        player = null
        stopRecognizer()
    }

    override fun onDestroy() {
        super.onDestroy()
        executor.shutdown()
        stopRecognizer()
    }

    private fun hasPermissions() = requiredPermissions.all {
        ContextCompat.checkSelfPermission(this, it) ==
            PackageManager.PERMISSION_GRANTED
    }

    private fun setStatus(text: String, mode: WaveView.Mode) {
        statusText.text = text
        waveView.setMode(mode)
    }

    // ---------------------------------------------------------------
    // РОЛИ
    // ---------------------------------------------------------------

    private fun beginRoleSelection() {
        roleOverlay.visibility = View.VISIBLE
        setStatus("Кто ты? Скажи или коснись: Хранитель / Бизнес / Простой",
            WaveView.Mode.LISTENING)
        startRecognizer()
        mainHandler.postDelayed({
            if (!roleChosen) {
                Log.w(TAG, "роль не выбрана за 30 сек — Простой")
                chooseRole(Role.SIMPLE)
            }
        }, ROLE_TIMEOUT_MS)
    }

    private fun startRecognizer() {
        if (!SpeechRecognizer.isRecognitionAvailable(this)) {
            Log.w(TAG, "SpeechRecognizer недоступен — выбор тапом")
            return
        }
        stopRecognizer()
        val r = SpeechRecognizer.createSpeechRecognizer(this)
        recognizer = r
        r.setRecognitionListener(object : RecognitionListener {
            override fun onReadyForSpeech(params: Bundle?) {}
            override fun onBeginningOfSpeech() {}
            override fun onRmsChanged(rmsdB: Float) {}
            override fun onBufferReceived(buffer: ByteArray?) {}
            override fun onEndOfSpeech() {}

            override fun onError(error: Int) {
                if (roleChosen) return
                Log.w(TAG, "recognizer error=$error — слушаю снова")
                mainHandler.postDelayed({ if (!roleChosen) startRecognizer() }, 400)
            }

            override fun onResults(results: Bundle?) {
                if (roleChosen) return
                val heard = results
                    ?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                    ?.firstOrNull().orEmpty()
                Log.d(TAG, "роль услышано: $heard")
                matchRole(heard)?.let { chooseRole(it) }
                    ?: mainHandler.postDelayed({ if (!roleChosen) startRecognizer() }, 400)
            }

            override fun onPartialResults(partialResults: Bundle?) {
                if (roleChosen) return
                val heard = partialResults
                    ?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                    ?.firstOrNull().orEmpty()
                matchRole(heard)?.let { chooseRole(it) }
            }

            override fun onEvent(eventType: Int, params: Bundle?) {}
        })
        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL,
                RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, "ru-RU")
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
            putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 3)
        }
        try {
            r.startListening(intent)
        } catch (e: Exception) {
            Log.e(TAG, "startListening", e)
        }
    }

    private fun stopRecognizer() {
        recognizer?.let {
            try { it.stopListening() } catch (_: Exception) {}
            try { it.cancel() } catch (_: Exception) {}
            it.destroy()
        }
        recognizer = null
    }

    private fun matchRole(text: String): Role? {
        val t = text.lowercase()
        return when {
            "хранитель" in t || "каирбек" in t -> Role.KEEPER
            "бизнес" in t -> Role.BUSINESS
            "простой" in t || "просто" in t || "работа" in t -> Role.SIMPLE
            else -> null
        }
    }

    private fun chooseRole(newRole: Role) {
        if (roleChosen) return
        roleChosen = true
        role = newRole
        getSharedPreferences(PREFS, MODE_PRIVATE).edit()
            .putString(KEY_ROLE, newRole.code).apply()
        stopRecognizer()
        roleOverlay.visibility = View.GONE
        setStatus("Роль: ${newRole.label}. Слушаю...", WaveView.Mode.LISTENING)
        startListening()
    }

    // ---------------------------------------------------------------
    // Камера
    // ---------------------------------------------------------------

    private fun startCamera() {
        val future = ProcessCameraProvider.getInstance(this)
        future.addListener({
            try {
                val provider = future.get()
                val preview = Preview.Builder().build().also {
                    it.surfaceProvider = previewView.surfaceProvider
                }
                val selector = CameraSelector.Builder()
                    .requireLensFacing(CameraSelector.LENS_FACING_FRONT)
                    .build()
                provider.unbindAll()
                provider.bindToLifecycle(this, selector, preview)
            } catch (e: Exception) {
                Log.e(TAG, "Камера не запустилась", e)
                setStatus("Ошибка камеры: ${e.message}", WaveView.Mode.IDLE)
            }
        }, ContextCompat.getMainExecutor(this))
    }

    // ---------------------------------------------------------------
    // Запись и детекция тишины
    // ---------------------------------------------------------------

    private fun startListening() {
        if (isRecording || !roleChosen) return
        val file = File(cacheDir, "voice_${System.currentTimeMillis()}.m4a")
        currentFile = file
        setStatus("Слушаю...", WaveView.Mode.LISTENING)
        try {
            val rec = newRecorder()
            rec.setAudioSource(MediaRecorder.AudioSource.MIC)
            rec.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
            rec.setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
            rec.setAudioSamplingRate(44100)
            rec.setAudioEncodingBitRate(96000)
            rec.setAudioChannels(1)
            rec.setOutputFile(file.absolutePath)
            rec.prepare()
            rec.start()
            recorder = rec
            isRecording = true
            maxAmplitude = 0
            executor.execute { watchSilence(SystemClock.elapsedRealtime()) }
        } catch (e: Exception) {
            Log.e(TAG, "Не удалось начать запись", e)
            releaseRecorder()
            setStatus("Ошибка микрофона: ${e.message}", WaveView.Mode.IDLE)
            statusText.postDelayed({ startListening() }, 2000)
        }
    }

    @Suppress("DEPRECATION")
    private fun newRecorder(): MediaRecorder =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) MediaRecorder(this)
        else MediaRecorder()

    private fun watchSilence(startedAt: Long) {
        var lastLoudAt = startedAt
        while (isRecording) {
            Thread.sleep(POLL_MS)
            val rec = recorder ?: break
            val amp = try { rec.maxAmplitude } catch (e: Exception) { break }
            val now = SystemClock.elapsedRealtime()
            if (amp > SILENCE_THRESHOLD) {
                lastLoudAt = now
                if (amp > maxAmplitude) maxAmplitude = amp
            }
            val elapsed = now - startedAt
            val silentFor = now - lastLoudAt
            if ((elapsed >= MIN_RECORD_MS && silentFor >= SILENCE_MS) ||
                elapsed >= MAX_RECORD_MS) break
        }
        if (isRecording) runOnUiThread { finishRecordingAndSend() }
    }

    private fun releaseRecorder() {
        try { recorder?.release() } catch (_: Exception) {}
        recorder = null
    }

    private fun finishRecordingAndSend() {
        isRecording = false
        val rec = recorder
        recorder = null
        val file = currentFile
        val heardSomething = maxAmplitude > SILENCE_THRESHOLD &&
                file != null && file.length() > 400
        try { rec?.stop() } catch (e: Exception) { Log.w(TAG, "stop()", e) }
        try { rec?.release() } catch (_: Exception) {}

        if (!heardSomething) {
            file?.delete()
            startListening()
            return
        }
        setStatus("Думаю...", WaveView.Mode.ACTIVE)
        sendToServer(file)
    }

    // ---------------------------------------------------------------
    // Сеть
    // ---------------------------------------------------------------

    private fun sendToServer(file: File) {
        executor.execute {
            try {
                val audioB64 = Base64.encodeToString(file.readBytes(),
                    Base64.NO_WRAP)
                val json = JSONObject()
                    .put("audio", audioB64)
                    .put("mime", "audio/mp4")
                    .put("role", role.code)
                    .toString()
                val body = json.toRequestBody(
                    "application/json; charset=utf-8".toMediaType())
                val request = Request.Builder()
                    .url(SERVER_URL).post(body).build()
                http.newCall(request).enqueue(object : Callback {
                    override fun onFailure(call: Call, e: IOException) {
                        Log.e(TAG, "Сеть", e)
                        showErrorAndRestart(
                            "Ошибка сети: ${e.message ?: "сервер не отвечает"}")
                    }

                    override fun onResponse(call: Call, response: Response) {
                        response.use { resp ->
                            if (!resp.isSuccessful) {
                                showErrorAndRestart(
                                    "Сервер ответил кодом ${resp.code}")
                                return
                            }
                            val respJson = JSONObject(resp.body.string())
                            if (respJson.optString("status") != "ok") {
                                showErrorAndRestart(
                                    "Ошибка сервера: ${
                                        respJson.optString("reply",
                                            "status != ok")}")
                                return
                            }
                            handleReply(respJson)
                        }
                    }
                })
            } catch (e: Exception) {
                showErrorAndRestart("Ошибка отправки: ${e.message}")
            }
        }
    }

    private fun showErrorAndRestart(msg: String) {
        runOnUiThread {
            setStatus(msg, WaveView.Mode.IDLE)
            statusText.postDelayed({ startListening() }, 3000)
        }
    }

    // ---------------------------------------------------------------
    // Ответ: аудио или текст
    // ---------------------------------------------------------------

    private fun handleReply(respJson: JSONObject) {
        val audioB64 = respJson.optString("audio")
        val replyText = respJson.optString("reply", "")
        val stopped = respJson.optBoolean("stopped", false)

        if (audioB64.isBlank()) {
            // Голоса нет — показываем текст 3 секунды и слушаем дальше
            runOnUiThread {
                setStatus(replyText.ifBlank { "(пустой ответ)" },
                    WaveView.Mode.IDLE)
                statusText.postDelayed(
                    { if (!stopped) startListening() else
                        setStatus(replyText.ifBlank { "Остановлено." },
                            WaveView.Mode.IDLE) },
                    TEXT_SHOW_MS)
            }
            return
        }

        try {
            val mp3 = File(cacheDir, "reply_${System.currentTimeMillis()}.mp3")
            mp3.writeBytes(Base64.decode(audioB64, Base64.DEFAULT))
            runOnUiThread {
                setStatus("Говорю...", WaveView.Mode.ACTIVE)
                val mp = MediaPlayer()
                player = mp
                try {
                    mp.setDataSource(mp3.absolutePath)
                    mp.setOnCompletionListener {
                        it.release()
                        player = null
                        mp3.delete()
                        if (!stopped) {
                            statusText.postDelayed({ startListening() },
                                RESTART_DELAY_MS)
                        } else {
                            setStatus("Остановлено по команде «Аман».",
                                WaveView.Mode.IDLE)
                        }
                    }
                    mp.setOnErrorListener { m, what, _ ->
                        m.release()
                        player = null
                        setStatus("Ошибка воспроизведения ($what)",
                            WaveView.Mode.IDLE)
                        statusText.postDelayed({ startListening() }, 3000)
                        true
                    }
                    mp.prepare()
                    mp.start()
                } catch (e: Exception) {
                    mp.release()
                    player = null
                    setStatus("Ошибка аудио: ${e.message}", WaveView.Mode.IDLE)
                    statusText.postDelayed({ startListening() }, 3000)
                }
            }
        } catch (e: Exception) {
            showErrorAndRestart("Ошибка декодирования аудио: ${e.message}")
        }
    }
}
