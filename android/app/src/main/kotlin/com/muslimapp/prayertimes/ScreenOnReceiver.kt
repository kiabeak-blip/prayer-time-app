package com.muslimapp.prayertimes

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class ScreenOnReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        // Flutter timer picks up screen-on and refreshes the countdown notification.
    }
}
