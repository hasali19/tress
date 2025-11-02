package com.example.tress

import android.util.Log
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import org.unifiedpush.android.connector.FailedReason
import org.unifiedpush.android.connector.PushService
import org.unifiedpush.android.connector.data.PushEndpoint
import org.unifiedpush.android.connector.data.PushMessage

class UnifiedPushService : PushService() {

    private lateinit var flutterEngine: FlutterEngine
    private lateinit var pushChannel: MethodChannel

    override fun onCreate() {
        super.onCreate()

        val flutterLoader = FlutterInjector.instance().flutterLoader()

        flutterEngine = MainActivity.getEngineGroup(this).createAndRunEngine(
            this,
            DartExecutor.DartEntrypoint(flutterLoader.findAppBundlePath(), "pushEntrypoint")
        )

        flutterEngine.plugins.add(NotificationsPlugin())

        val messenger = flutterEngine.dartExecutor.binaryMessenger

        pushChannel = MethodChannel(messenger, "tress.hasali.dev/push")
    }

    override fun onNewEndpoint(
        endpoint: PushEndpoint,
        instance: String
    ) {
        Log.i("UnifiedPushService", "New endpoint: ${endpoint.url}")
        pushChannel.invokeMethod(
            "onNewEndpoint",
            mapOf(
                "url" to endpoint.url,
                "keys" to mapOf(
                    "auth" to endpoint.pubKeySet?.auth,
                    "pub" to endpoint.pubKeySet?.pubKey,
                ),
            ),
        )
    }

    override fun onMessage(
        message: PushMessage,
        instance: String
    ) {
        Log.i("UnifiedPushService", "Received message")
        pushChannel.invokeMethod("onMessage", mapOf("content" to message.content))
    }

    override fun onRegistrationFailed(
        reason: FailedReason,
        instance: String
    ) {
        Log.e("UnifiedPushService", "Registration failed: $reason")
    }

    override fun onUnregistered(instance: String) {
        Log.i("UnifiedPushService", "Unregistered")
    }
}
