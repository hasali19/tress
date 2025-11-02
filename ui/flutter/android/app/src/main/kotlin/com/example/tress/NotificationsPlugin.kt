package com.example.tress

import android.Manifest
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.PackageManager
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodChannel

class NotificationsPlugin : FlutterPlugin {

    private lateinit var notificationsChannel: MethodChannel

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        val context = binding.applicationContext
        val messenger = binding.binaryMessenger

        notificationsChannel = MethodChannel(messenger, "tress.hasali.dev/notifications").apply {
            setMethodCallHandler { call, result ->
                val title = call.argument<String>("title")
                val subtext = call.argument<String>("subtext")
                val content = call.argument<String>("content")

                // TODO: Open post in browser
                val intent = Intent(context, MainActivity::class.java)

                val pendingIntent =
                    PendingIntent.getActivity(context, 0, intent, PendingIntent.FLAG_IMMUTABLE)

                val builder = NotificationCompat.Builder(context, "new_post")
                    .setSmallIcon(R.mipmap.ic_launcher)
                    .setContentTitle(title)
                    .setSubText(subtext)
                    .setContentText(content)
                    .setStyle(NotificationCompat.BigTextStyle().bigText(content))
                    .setPriority(NotificationCompat.PRIORITY_DEFAULT)
                    .setContentIntent(pendingIntent)
                    .setAutoCancel(true)

                with(NotificationManagerCompat.from(context)) {
                    if (ActivityCompat.checkSelfPermission(
                            context,
                            Manifest.permission.POST_NOTIFICATIONS
                        ) == PackageManager.PERMISSION_GRANTED
                    ) {
                        // TODO: Unique ids
                        notify(1, builder.build())
                    }
                }

                result.success(null)
            }
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        notificationsChannel.setMethodCallHandler(null)
    }
}
