package com.example.prayer_times_app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Receives SCREEN_ON and USER_PRESENT broadcasts so Flutter can refresh
 * the prayer-countdown notification the moment the user wakes their phone.
 *
 * The actual notification update happens inside Flutter (home_screen.dart).
 * This receiver simply re-delivers stored notification data via the local
 * notifications plugin's existing scheduled notification machinery —
 * or if the app process is alive, Flutter's timer picks it up automatically.
 *
 * For the app's current architecture (timer-driven updates while the app is
 * alive in memory), this receiver is a no-op placeholder that ensures the
 * broadcast wakes the app process if it's been background-killed, allowing
 * Flutter to rebuild its notification on the next engine start.
 */
class ScreenOnReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        // The Flutter engine is already running (IndexedStack keeps HomeScreen
        // mounted), so the 1-second timer will fire within a second of the
        // screen turning on and update the notification automatically.
        // No explicit action needed here.
    }
}
