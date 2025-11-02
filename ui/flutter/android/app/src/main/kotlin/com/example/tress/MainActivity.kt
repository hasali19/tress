package com.example.tress

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.util.Log
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineGroup
import io.flutter.plugin.common.MethodChannel
import org.unifiedpush.android.connector.UnifiedPush

class MainActivity : FlutterActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Log.i("MainActivity", "Creating notification channel")
            val notificationManager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.createNotificationChannel(
                NotificationChannel(
                    "new_post", "New Post",
                    NotificationManager.IMPORTANCE_DEFAULT
                )
            )
        }
    }

    override fun provideFlutterEngine(context: Context): FlutterEngine? {
        return getEngineGroup(context).createAndRunDefaultEngine(context).apply {
            plugins.add(NotificationsPlugin())
        }
    }

    override fun shouldDestroyEngineWithHost(): Boolean {
        return true
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        MethodChannel(messenger, "tress.hasali.dev/push").apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "register" -> {
                        val vapidPublicKey = call.argument<String>("vapid_key")
                        UnifiedPush.tryUseCurrentOrDefaultDistributor(this@MainActivity) { success ->
                            if (success) {
                                UnifiedPush.register(this@MainActivity, vapid = vapidPublicKey)
                            }
                        }
                        result.success(null)
                    }
                }
            }
        }
    }

    companion object {
        private var engineGroup: FlutterEngineGroup? = null

        fun getEngineGroup(context: Context): FlutterEngineGroup {
            return engineGroup ?: FlutterEngineGroup(context.applicationContext)
                .also { engineGroup = it }
        }
    }
}
