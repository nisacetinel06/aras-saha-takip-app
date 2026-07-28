package com.arasedas.arassaha_flutter

import android.content.Context
import android.content.res.Configuration
import io.flutter.embedding.android.FlutterActivity

/**
 * Native splash ekranı Flutter motoru yüklenmeden ÖNCE çizilir; bu yüzden
 * uygulama içindeki tema tercihini (ThemeProvider, lib/providers/theme_provider.dart)
 * Dart tarafında okuyup splash rengini seçmek mümkün değil. Bunun yerine burada,
 * Flutter'ın `shared_preferences` paketinin yazdığı AYNI SharedPreferences
 * dosyasını native tarafta okuyup, SADECE bu Activity'nin kaynak (resource)
 * çözümlemesini (values/ vs values-night/, drawable/ vs drawable-night/)
 * `applyOverrideConfiguration` ile zorluyoruz. Bu, cihazın sistem geneli
 * karanlık mod ayarını DEĞİŞTİRMEZ — yalnızca bu uygulamanın kendi splash/tema
 * kaynak seçimini etkiler.
 *
 * Kayıtlı tercih yoksa (ilk açılış) her zaman AÇIK (light) splash gösterilir —
 * bkz. ThemeProvider.load() ile aynı varsayılan.
 *
 * ÖNEMLİ: applyOverrideConfiguration() getResources()/getAssets() çağrılmadan
 * ÖNCE yapılmalı. FlutterActivity'nin KENDİ attachBaseContext()'i motor/asset
 * bundle kurulumu için resources'a dokunuyor — bu yüzden override, onCreate()
 * yerine attachBaseContext() içinde, super çağrılmadan ÖNCE yapılıyor.
 */
class MainActivity : FlutterActivity() {
    override fun attachBaseContext(newBase: Context) {
        applyOverrideConfiguration(buildThemeAwareConfiguration(newBase))
        super.attachBaseContext(newBase)
    }

    private fun buildThemeAwareConfiguration(base: Context): Configuration {
        // `this` (Activity) henüz tam bağlanmadığı için tercihi doğrudan
        // parametre olarak gelen `base` Context'ten okuyoruz.
        val prefs = base.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val savedThemeMode = prefs.getString("flutter.theme_mode", null)
        val isDark = savedThemeMode == "dark"

        val override = Configuration()
        override.uiMode = if (isDark) Configuration.UI_MODE_NIGHT_YES else Configuration.UI_MODE_NIGHT_NO
        return override
    }
}
