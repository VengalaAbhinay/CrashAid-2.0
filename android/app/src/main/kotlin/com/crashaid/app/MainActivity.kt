package com.crashaid.app

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.telephony.SmsManager
import android.view.KeyEvent
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        const val SMS_CHANNEL = "com.crashaid/sms"

        fun sendSmsNow(
            context: android.content.Context,
            numbers: List<String>,
            message: String
        ): Boolean {
            return try {
                val hasPerm = ContextCompat.checkSelfPermission(
                    context, Manifest.permission.SEND_SMS
                ) == PackageManager.PERMISSION_GRANTED
                if (!hasPerm) {
                    android.util.Log.e("CrashAid", "SEND_SMS permission not granted")
                    return false
                }

                val smsManager: SmsManager =
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                        context.getSystemService(SmsManager::class.java)
                            ?: @Suppress("DEPRECATION") SmsManager.getDefault()
                    } else {
                        @Suppress("DEPRECATION")
                        SmsManager.getDefault()
                    }

                var allSent = true
                for (number in numbers) {
                    val trimmed = number.trim()
                    if (trimmed.isEmpty()) continue
                    try {
                        val parts = smsManager.divideMessage(message)
                        smsManager.sendMultipartTextMessage(
                            trimmed, null, parts, null, null
                        )
                        android.util.Log.d("CrashAid", "SMS sent to: $trimmed")
                    } catch (e: Exception) {
                        android.util.Log.e("CrashAid", "SMS failed for $trimmed: ${e.message}")
                        allSent = false
                    }
                }
                allSent
            } catch (e: Exception) {
                android.util.Log.e("CrashAid", "sendSmsNow crashed: ${e.message}")
                false
            }
        }
    }

    private val VOICE_CHANNEL = "com.crashaid/voice"
    private val RECORD_AUDIO_CODE = 1001

    // ── Panic button (volume-key hold) ───────────────────────────────────
    private val PANIC_CHANNEL = "com.crashaid/panic"
    private var panicMethodChannel: MethodChannel? = null
    private var volumeDownPressTime: Long = 0L
    private val PANIC_HOLD_MS = 2000L

    private var speechRecognizer: SpeechRecognizer? = null
    private var voiceMethodChannel: MethodChannel? = null
    private var isListening = false
    private var activeLocale: String = "en-IN"
    private val handler = Handler(Looper.getMainLooper())

    private val triggerWords = listOf("help me", "sos", "emergency", "bachao", "help")

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SMS_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "sendSMS" -> {
                        val numbers =
                            call.argument<List<String>>("numbers") ?: emptyList()
                        val message =
                            call.argument<String>("message") ?: ""
                        val sent = sendSmsNow(applicationContext, numbers, message)
                        if (sent) result.success("sent")
                        else result.error(
                            "SEND_FAILED",
                            "SMS failed — check SEND_SMS permission",
                            null
                        )
                    }
                    else -> result.notImplemented()
                }
            }

        voiceMethodChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger, VOICE_CHANNEL
        )
        voiceMethodChannel!!.setMethodCallHandler { call, result ->
            when (call.method) {
                "isAvailable" -> {
                    val available = SpeechRecognizer.isRecognitionAvailable(this)
                    result.success(available)
                }
                "startListening" -> {
                    val locale = call.argument<String>("locale") ?: "en-IN"
                    val hasPermission = ContextCompat.checkSelfPermission(
                        this, Manifest.permission.RECORD_AUDIO
                    ) == PackageManager.PERMISSION_GRANTED
                    if (!hasPermission) {
                        ActivityCompat.requestPermissions(
                            this,
                            arrayOf(Manifest.permission.RECORD_AUDIO),
                            RECORD_AUDIO_CODE
                        )
                        result.success("permission_requested")
                    } else {
                        startVoiceListening(locale)
                        result.success("started")
                    }
                    }
                "stopListening" -> {
                    stopVoiceListening()
                    result.success("stopped")
                }
                else -> result.notImplemented()
            }
        }

        // ── Panic button (volume-key hold) ───────────────────────────────
        panicMethodChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger, PANIC_CHANNEL
        )
        panicMethodChannel!!.setMethodCallHandler { call, result ->
            when (call.method) {
                "startListening" -> result.success("listening")
                "stopListening" -> result.success("stopped")
                else -> result.notImplemented()
            }
        }
    }

    private fun startVoiceListening(locale: String = activeLocale) {
        activeLocale = locale
        if (isListening) return
        isListening = true
        speechRecognizer?.destroy()
        speechRecognizer = SpeechRecognizer.createSpeechRecognizer(this)
        speechRecognizer!!.setRecognitionListener(object : RecognitionListener {
            override fun onReadyForSpeech(params: Bundle?) {}
            override fun onBeginningOfSpeech() {}
            override fun onRmsChanged(rmsdB: Float) {}
            override fun onBufferReceived(buffer: ByteArray?) {}
            override fun onEndOfSpeech() {}
            override fun onEvent(eventType: Int, params: Bundle?) {}
            override fun onPartialResults(partialResults: Bundle?) {
                val words = partialResults
                    ?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                    ?.firstOrNull()?.lowercase() ?: return
                checkTrigger(words)
            }
            override fun onResults(results: Bundle?) {
                val words = results
                    ?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                    ?.firstOrNull()?.lowercase() ?: ""
                checkTrigger(words)
                isListening = false
                handler.postDelayed({ startVoiceListening() }, 400)
            }
            override fun onError(error: Int) {
                isListening = false
                val delay = if (error == SpeechRecognizer.ERROR_NO_MATCH ||
                    error == SpeechRecognizer.ERROR_SPEECH_TIMEOUT) 300L else 1500L
                handler.postDelayed({ startVoiceListening() }, delay)
            }
        })
        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL,
                RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, locale)
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
            putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 3)
            putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_COMPLETE_SILENCE_LENGTH_MILLIS, 3000L)
            putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_POSSIBLY_COMPLETE_SILENCE_LENGTH_MILLIS, 2000L)
            }
        speechRecognizer!!.startListening(intent)
    }

    private fun stopVoiceListening() {
        isListening = false
        handler.removeCallbacksAndMessages(null)
        speechRecognizer?.stopListening()
        speechRecognizer?.cancel()
        speechRecognizer?.destroy()
        speechRecognizer = null
    }

    private fun checkTrigger(words: String) {
        for (trigger in triggerWords) {
            if (words.contains(trigger)) {
                runOnUiThread {
                    voiceMethodChannel?.invokeMethod("onTrigger", words)
                }
                stopVoiceListening()
                break
            }
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == RECORD_AUDIO_CODE &&
            grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED
        ) {
            startVoiceListening()
        }
    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent?): Boolean {
        if (keyCode == KeyEvent.KEYCODE_VOLUME_DOWN) {
            if (volumeDownPressTime == 0L) {
                volumeDownPressTime = System.currentTimeMillis()
            }
            val held = System.currentTimeMillis() - volumeDownPressTime
            if (held >= PANIC_HOLD_MS) {
                volumeDownPressTime = 0L
                panicMethodChannel?.invokeMethod("onPanicTrigger", null)
                return true
            }
            return true // suppress volume change while measuring hold
        }
        volumeDownPressTime = 0L
        return super.onKeyDown(keyCode, event)
    }

    override fun onKeyUp(keyCode: Int, event: KeyEvent?): Boolean {
        if (keyCode == KeyEvent.KEYCODE_VOLUME_DOWN) {
            val held = System.currentTimeMillis() - volumeDownPressTime
            volumeDownPressTime = 0L
            if (held < PANIC_HOLD_MS) {
                // Short press — let the system handle normal volume change
                return super.onKeyUp(keyCode, event)
            }
            return true
        }
        return super.onKeyUp(keyCode, event)
    }

    override fun onDestroy() {
        stopVoiceListening()
        super.onDestroy()
    }
}