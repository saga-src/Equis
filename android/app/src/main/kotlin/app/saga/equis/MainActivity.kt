package app.saga.equis

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.app.Activity
import android.content.ContentValues
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import java.io.File

class MainActivity : FlutterActivity() {
    private var pending: Pair<File, MethodChannel.Result>? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app.saga.equis/updates")
            .setMethodCallHandler { call, result ->
                if (call.method != "install") { result.notImplemented(); return@setMethodCallHandler }
                try {
                    val source = File(call.argument<String>("path")!!).canonicalFile
                    val root = File(filesDir, "updates").canonicalFile
                    check(source.parentFile == root && source.isFile)
                    val flags = if (Build.VERSION.SDK_INT >= 28) android.content.pm.PackageManager.GET_SIGNING_CERTIFICATES else android.content.pm.PackageManager.GET_SIGNATURES
                    val incoming = packageManager.getPackageArchiveInfo(source.path, flags) ?: error("Invalid APK")
                    val installed = packageManager.getPackageInfo(packageName, flags)
                    check(incoming.packageName == packageName)
                    val nextBuild = if (Build.VERSION.SDK_INT >= 28) incoming.longVersionCode else incoming.versionCode.toLong()
                    val currentBuild = if (Build.VERSION.SDK_INT >= 28) installed.longVersionCode else installed.versionCode.toLong()
                    check(nextBuild > currentBuild)
                    val nextSigners = if (Build.VERSION.SDK_INT >= 28) incoming.signingInfo!!.apkContentsSigners else incoming.signatures
                    val currentSigners = if (Build.VERSION.SDK_INT >= 28) installed.signingInfo!!.apkContentsSigners else installed.signatures
                    check(nextSigners!!.map { it.toCharsString() }.toSet() == currentSigners!!.map { it.toCharsString() }.toSet())
                    if (Build.VERSION.SDK_INT >= 26 && !packageManager.canRequestPackageInstalls()) {
                        startActivity(Intent(android.provider.Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                            Uri.parse("package:$packageName")))
                        result.success("permission"); return@setMethodCallHandler
                    }
                    val uri = androidx.core.content.FileProvider.getUriForFile(this, "app.saga.equis.updates", source)
                    startActivity(Intent(Intent.ACTION_VIEW).apply {
                        setDataAndType(uri, "application/vnd.android.package-archive")
                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    })
                    result.success("opened")
                } catch (_: Exception) { result.error("invalid_update", "Unable to install update", null) }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app.saga.equis/files")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "publish" -> {
                        val source = File(call.argument<String>("source")!!)
                        val name = call.argument<String>("name")!!
                        val mime = call.argument<String>("mime")!!
                        if (pending != null) {
                            result.error("busy", "A save is already in progress.", null)
                        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                            Thread {
                                var uri: Uri? = null
                                try {
                                    uri = contentResolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI,
                                        ContentValues().apply {
                                            put(MediaStore.MediaColumns.DISPLAY_NAME, name)
                                            put(MediaStore.MediaColumns.MIME_TYPE, mime)
                                            put(MediaStore.MediaColumns.RELATIVE_PATH, "Download/Equis")
                                            put(MediaStore.MediaColumns.IS_PENDING, 1)
                                        }) ?: error("Unable to create download")
                                    copy(source, uri)
                                    check(contentResolver.update(uri, ContentValues().apply {
                                        put(MediaStore.MediaColumns.IS_PENDING, 0)
                                    }, null, null) == 1)
                                    val savedUri = uri.toString()
                                    runOnUiThread { result.success(mapOf("uri" to savedUri, "location" to "Downloads/Equis/$name")) }
                                } catch (_: Exception) {
                                    uri?.let { try { contentResolver.delete(it, null, null) } catch (_: Exception) {} }
                                    runOnUiThread { result.error("save_failed", "Unable to save download.", null) }
                                }
                            }.start()
                        } else {
                            pending = Pair(source, result)
                            try {
                                startActivityForResult(Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                                    addCategory(Intent.CATEGORY_OPENABLE)
                                    type = mime
                                    putExtra(Intent.EXTRA_TITLE, name)
                                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
                                }, 7401)
                            } catch (_: Exception) {
                                pending = null
                                result.error("save_failed", "Unable to open document picker.", null)
                            }
                        }
                    }
                    "read" -> {
                        val uri = Uri.parse(call.argument<String>("uri")!!)
                        val target = File(call.argument<String>("target")!!)
                        Thread {
                            try {
                                contentResolver.openInputStream(uri)!!.use { input -> target.outputStream().use { input.copyTo(it) } }
                                runOnUiThread { result.success(null) }
                            } catch (_: Exception) {
                                target.delete()
                                runOnUiThread { result.error("read_failed", "Unable to read document.", null) }
                            }
                        }.start()
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun copy(source: File, uri: Uri) {
        contentResolver.openOutputStream(uri, "w")!!.use { output ->
            source.inputStream().use { input -> check(input.copyTo(output) == source.length()) }
            output.flush()
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != 7401) return
        val (source, result) = pending ?: return
        pending = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            result.success(null)
            return
        }
        Thread {
            try {
                copy(source, uri)
                try {
                    contentResolver.takePersistableUriPermission(uri, data.flags and
                        (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION))
                } catch (_: SecurityException) { /* Provider may not offer persistent access. */ }
                runOnUiThread { result.success(mapOf("uri" to uri.toString(), "location" to uri.toString())) }
            } catch (_: Exception) {
                try { android.provider.DocumentsContract.deleteDocument(contentResolver, uri) } catch (_: Exception) {}
                runOnUiThread { result.error("save_failed", "Unable to save document.", null) }
            }
        }.start()
    }
}
