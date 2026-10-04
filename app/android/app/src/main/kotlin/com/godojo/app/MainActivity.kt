package com.godojo.app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val io = Executors.newSingleThreadExecutor()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "godojo/engine")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "nativeLibraryDir" -> result.success(applicationInfo.nativeLibraryDir)
                    "installEngineFiles" -> io.execute {
                        try {
                            val dir = installEngineFiles()
                            runOnUiThread { result.success(dir) }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("install", e.message, null) }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * Copies the bundled networks and config (assets/katago) to app storage.
     * Re-copied only after the app is installed or updated.
     */
    private fun installEngineFiles(): String {
        val dir = File(filesDir, "katago")
        dir.mkdirs()
        @Suppress("DEPRECATION")
        val stamp = packageManager.getPackageInfo(packageName, 0).lastUpdateTime.toString()
        val stampFile = File(dir, ".installed")
        if (stampFile.exists() && stampFile.readText() == stamp) return dir.absolutePath
        for (name in assets.list("katago") ?: emptyArray()) {
            val tmp = File(dir, "$name.tmp")
            File(dir, name.removeSuffix(".asset").removeSuffix(".gz")).delete()
            assets.open("katago/$name").use { input ->
                tmp.outputStream().use { output -> input.copyTo(output, 1 shl 20) }
            }
            val out = File(dir, name.removeSuffix(".asset"))
            out.delete()
            tmp.renameTo(out)
        }
        stampFile.writeText(stamp)
        return dir.absolutePath
    }
}
