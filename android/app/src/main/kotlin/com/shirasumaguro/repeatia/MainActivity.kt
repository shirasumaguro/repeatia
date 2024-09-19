package com.shirasumaguro.repeatia

import android.os.Bundle
import android.content.Context
import android.view.inputmethod.InputMethodManager
import android.view.inputmethod.InputMethodSubtype
import android.media.AudioManager
import android.media.ToneGenerator
import android.util.Log
import android.text.InputType
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.shirasumaguro.repeatia/beep"
    private val TAG = "MainActivity"
    // private var editText: EditText? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // setContentView(R.layout.activity_main)  // activity_main.xml をロード
        // editText = findViewById(R.id.editText)  // EditText を取得
    }

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        Log.d(TAG, "configureFlutterEngine called")
        // Register the platform view
        // flutterEngine.platformViewsController.registry.registerViewFactory("native-edittext-view", NativeEditTextFactory())

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            Log.d(TAG, "Method call received: ${call.method}")
            when (call.method) {
                "setJapaneseInputMode" -> {
                    setJapaneseInputMode()
                    result.success(null)
                }
                "playBeepok" -> {
                    Log.i(TAG, "playBeep method called")
                    playBeepok()
                    result.success(null)
                }
                "playBeepng" -> {
                    Log.d(TAG, "playBeep method called")
                    playBeepng()
                    result.success(null)
                }
                else -> {
                    Log.d(TAG, "Method not implemented: ${call.method}")
                    result.notImplemented()
                }
            }
        }
    }

    private fun setJapaneseInputMode() {
        Log.d(TAG, "AAA setJapaneseInputMode called 6")
        // editText?.let {
        //     it.inputType = InputType.TYPE_CLASS_TEXT
        //     val imm = getSystemService(INPUT_METHOD_SERVICE) as InputMethodManager
        //     imm.showSoftInput(it, InputMethodManager.SHOW_IMPLICIT)
        // } ?: run {
        //     Log.e(TAG, "EditText is null")
        // }
    }

    private fun playBeepok() {
        Log.d(TAG, "playBeep called")
        val toneGen = ToneGenerator(AudioManager.STREAM_ALARM, 100)
        // 低くて短いトーンを選択
        toneGen.startTone(ToneGenerator.TONE_PROP_BEEP, 100)  // 持続時間を短く設定（100ms）
        Log.d(TAG, "Beep sound played")
    }

    private fun playBeepng() {
        Log.d(TAG, "playBeep called")
        val toneGen = ToneGenerator(AudioManager.STREAM_ALARM, 100)
        toneGen.startTone(ToneGenerator.TONE_CDMA_ALERT_CALL_GUARD, 200)
        Log.d(TAG, "Beep sound played")
    }
}
