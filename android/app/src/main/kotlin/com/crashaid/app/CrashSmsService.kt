package com.crashaid.app

import android.content.Context
import android.content.Intent
import androidx.core.app.JobIntentService

/**
 * Modern JobIntentService that sends the crash SMS.
 * Replaces deprecated IntentService.
 * Works even when the Flutter engine / MainActivity is not running.
 */
class CrashSmsService : JobIntentService() {

    companion object {
        const val EXTRA_NUMBERS = "numbers"
        const val EXTRA_MESSAGE = "message"
        private const val JOB_ID = 1001

        fun start(context: Context, numbers: ArrayList<String>, message: String) {
            val intent = Intent().apply {
                putStringArrayListExtra(EXTRA_NUMBERS, numbers)
                putExtra(EXTRA_MESSAGE, message)
            }
            enqueueWork(context, CrashSmsService::class.java, JOB_ID, intent)
        }
    }

    override fun onHandleWork(intent: Intent) {
        val numbers = intent.getStringArrayListExtra(EXTRA_NUMBERS) ?: return
        val message = intent.getStringExtra(EXTRA_MESSAGE) ?: return
        MainActivity.sendSmsNow(applicationContext, numbers, message)
    }
}