package net.olivierluethy.collage

import android.app.Activity
import android.app.DownloadManager
import android.content.ActivityNotFoundException
import android.content.ContentValues
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.DocumentsContract
import android.provider.MediaStore
import android.provider.OpenableColumns
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException
import java.util.concurrent.Executors

/**
 * Where exported collages go on Android, using only what the OS allows:
 *
 *  - a folder the user picked with the system folder picker (Storage Access
 *    Framework), kept with a persistable permission;
 *  - a file the user names in the system "Save as" dialog;
 *  - Download/Collage through MediaStore (no permission needed on 10+).
 *
 * Every saved file is identified by its content:// URI — never by a made-up
 * path — so it can be checked, opened and shared again later.
 *
 * Channel "collage/files":
 *   pickFolder -> {uri, label} | null (cancelled)
 *   releaseFolder {uri}
 *   folderStatus {uri} -> "ok" | "revoked" | "missing"
 *   writeToFolder {tree, name, mime, bytes} -> {uri, name, label}
 *   createDocument {name, mime, bytes} -> {uri, name, label} | null (cancelled)
 *   saveToDownloads {name, mime, bytes} -> {uri, name, label}
 *   status {uri} -> "ok" | "missing" | "noaccess"
 *   open {uri, mime} -> bool
 *   showLocation {kind, uri?} -> bool   (kind: gallery | downloads | folder)
 *   share {uri, mime, text} -> bool
 *
 * Errors: "revoked", "no_space", "write_failed".
 */
class FileBridge(private val activity: Activity) : MethodChannel.MethodCallHandler {
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    private var pending: MethodChannel.Result? = null
    private var pendingBytes: ByteArray? = null

    companion object {
        const val REQ_PICK_FOLDER = 4711
        const val REQ_CREATE_DOC = 4712
        private const val DOWNLOAD_SUBDIR = "Collage"
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "pickFolder" -> pickFolder(result)
            "releaseFolder" -> {
                val uri = Uri.parse(call.argument<String>("uri"))
                try {
                    activity.contentResolver.releasePersistableUriPermission(
                        uri,
                        Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION,
                    )
                } catch (_: Exception) {
                }
                result.success(null)
            }
            "folderStatus" -> background(result) { folderStatus(Uri.parse(call.argument<String>("uri"))) }
            "writeToFolder" -> background(result) {
                writeToFolder(
                    Uri.parse(call.argument<String>("tree")),
                    call.argument<String>("name")!!,
                    call.argument<String>("mime")!!,
                    call.argument<ByteArray>("bytes")!!,
                )
            }
            "createDocument" -> createDocument(
                call.argument<String>("name")!!,
                call.argument<String>("mime")!!,
                call.argument<ByteArray>("bytes")!!,
                result,
            )
            "saveToDownloads" -> background(result) {
                saveToDownloads(
                    call.argument<String>("name")!!,
                    call.argument<String>("mime")!!,
                    call.argument<ByteArray>("bytes")!!,
                )
            }
            "status" -> background(result) { status(Uri.parse(call.argument<String>("uri"))) }
            "open" -> result.success(open(Uri.parse(call.argument<String>("uri")), call.argument<String>("mime")))
            "showLocation" -> result.success(showLocation(call.argument<String>("kind")!!, call.argument<String>("uri")))
            "share" -> result.success(
                share(Uri.parse(call.argument<String>("uri")), call.argument<String>("mime")!!, call.argument<String>("text")),
            )
            else -> result.notImplemented()
        }
    }

    /** Runs [job] off the UI thread; IOExceptions become typed errors. */
    private fun background(result: MethodChannel.Result, job: () -> Any?) {
        worker.execute {
            try {
                val value = job()
                main.post { result.success(value) }
            } catch (e: SecurityException) {
                main.post { result.error("revoked", e.message, null) }
            } catch (e: IOException) {
                val code = if (isNoSpace(e)) "no_space" else "write_failed"
                main.post { result.error(code, e.message, null) }
            } catch (e: Exception) {
                main.post { result.error("write_failed", e.message, null) }
            }
        }
    }

    private fun isNoSpace(e: Throwable): Boolean {
        val m = (e.message ?: "") + (e.cause?.message ?: "")
        return m.contains("ENOSPC") || m.contains("No space", ignoreCase = true)
    }

    // ---- folder picker -------------------------------------------------------

    private fun pickFolder(result: MethodChannel.Result) {
        if (pending != null) {
            result.error("busy", "Another picker is open", null)
            return
        }
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).addFlags(
            Intent.FLAG_GRANT_READ_URI_PERMISSION or
                Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION,
        )
        pending = result
        try {
            activity.startActivityForResult(intent, REQ_PICK_FOLDER)
        } catch (e: ActivityNotFoundException) {
            pending = null
            result.error("unsupported", "No folder picker on this device", null)
        }
    }

    private fun createDocument(name: String, mime: String, bytes: ByteArray, result: MethodChannel.Result) {
        if (pending != null) {
            result.error("busy", "Another picker is open", null)
            return
        }
        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT)
            .addCategory(Intent.CATEGORY_OPENABLE)
            .setType(mime)
            .putExtra(Intent.EXTRA_TITLE, name)
        pending = result
        pendingBytes = bytes
        try {
            activity.startActivityForResult(intent, REQ_CREATE_DOC)
        } catch (e: ActivityNotFoundException) {
            pending = null
            pendingBytes = null
            result.error("unsupported", "No save dialog on this device", null)
        }
    }

    /** Called from MainActivity.onActivityResult. True when handled. */
    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQ_PICK_FOLDER && requestCode != REQ_CREATE_DOC) return false
        val result = pending ?: return true
        val bytes = pendingBytes
        pending = null
        pendingBytes = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            result.success(null) // cancelled
            return true
        }
        if (requestCode == REQ_PICK_FOLDER) {
            try {
                activity.contentResolver.takePersistableUriPermission(
                    uri,
                    Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION,
                )
            } catch (_: SecurityException) {
            }
            background(result) { mapOf("uri" to uri.toString(), "label" to folderLabel(uri)) }
        } else {
            background(result) {
                activity.contentResolver.openOutputStream(uri, "w")?.use { it.write(bytes) }
                    ?: throw IOException("Could not open the file")
                val name = displayName(uri) ?: ""
                mapOf("uri" to uri.toString(), "name" to name, "label" to providerLabel(uri))
            }
        }
        return true
    }

    // ---- writing ---------------------------------------------------------------

    private fun folderStatus(tree: Uri): String {
        val held = activity.contentResolver.persistedUriPermissions.any {
            it.uri == tree && it.isWritePermission
        }
        if (!held) return "revoked"
        return try {
            val doc = DocumentsContract.buildDocumentUriUsingTree(tree, DocumentsContract.getTreeDocumentId(tree))
            activity.contentResolver.query(doc, arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID), null, null, null)
                ?.use { if (it.moveToFirst()) "ok" else "missing" } ?: "missing"
        } catch (_: SecurityException) {
            "revoked"
        } catch (_: Exception) {
            "missing"
        }
    }

    private fun writeToFolder(tree: Uri, name: String, mime: String, bytes: ByteArray): Map<String, String> {
        when (folderStatus(tree)) {
            "revoked" -> throw SecurityException("Folder access was removed")
            "missing" -> throw SecurityException("Folder no longer exists")
        }
        val parent = DocumentsContract.buildDocumentUriUsingTree(tree, DocumentsContract.getTreeDocumentId(tree))
        val unique = uniqueName(name, childNames(tree))
        val doc = DocumentsContract.createDocument(activity.contentResolver, parent, mime, unique)
            ?: throw IOException("Could not create the file")
        try {
            activity.contentResolver.openOutputStream(doc, "w")?.use { it.write(bytes) }
                ?: throw IOException("Could not open the file")
        } catch (e: IOException) {
            try {
                DocumentsContract.deleteDocument(activity.contentResolver, doc)
            } catch (_: Exception) {
            }
            throw e
        }
        return mapOf("uri" to doc.toString(), "name" to (displayName(doc) ?: unique), "label" to folderLabel(tree))
    }

    private fun childNames(tree: Uri): Set<String> {
        val children = DocumentsContract.buildChildDocumentsUriUsingTree(tree, DocumentsContract.getTreeDocumentId(tree))
        val out = HashSet<String>()
        try {
            activity.contentResolver.query(children, arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME), null, null, null)
                ?.use { c -> while (c.moveToNext()) c.getString(0)?.let { out.add(it.lowercase()) } }
        } catch (_: Exception) {
        }
        return out
    }

    private fun saveToDownloads(name: String, mime: String, bytes: ByteArray): Map<String, String> {
        val label = "Download/$DOWNLOAD_SUBDIR"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val resolver = activity.contentResolver
            val values = ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, name)
                put(MediaStore.MediaColumns.MIME_TYPE, mime)
                put(MediaStore.MediaColumns.RELATIVE_PATH, "${Environment.DIRECTORY_DOWNLOADS}/$DOWNLOAD_SUBDIR")
                put(MediaStore.MediaColumns.IS_PENDING, 1)
            }
            // MediaStore never overwrites: a clashing name gets " (1)" added.
            val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                ?: throw IOException("Could not create the file")
            try {
                resolver.openOutputStream(uri, "w")?.use { it.write(bytes) } ?: throw IOException("Could not open the file")
                values.clear()
                values.put(MediaStore.MediaColumns.IS_PENDING, 0)
                resolver.update(uri, values, null, null)
            } catch (e: IOException) {
                resolver.delete(uri, null, null)
                throw e
            }
            return mapOf("uri" to uri.toString(), "name" to (displayName(uri) ?: name), "label" to label)
        }
        // Android 9 and below: the public Download folder, written directly.
        @Suppress("DEPRECATION")
        val dir = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS), DOWNLOAD_SUBDIR)
        if (!dir.exists() && !dir.mkdirs()) throw SecurityException("Cannot write to Download")
        val existing = dir.list()?.map { it.lowercase() }?.toSet() ?: emptySet()
        val file = File(dir, uniqueName(name, existing))
        file.writeBytes(bytes)
        // Register it with MediaStore so it gets a shareable content:// URI.
        val values = ContentValues().apply {
            @Suppress("DEPRECATION")
            put(MediaStore.MediaColumns.DATA, file.absolutePath)
            put(MediaStore.MediaColumns.DISPLAY_NAME, file.name)
            put(MediaStore.MediaColumns.MIME_TYPE, mime)
        }
        val uri = activity.contentResolver.insert(MediaStore.Files.getContentUri("external"), values)
            ?: throw IOException("Could not register the file")
        return mapOf("uri" to uri.toString(), "name" to file.name, "label" to label)
    }

    /** "Summer.png" -> "Summer (2).png" while the name is taken (case-insensitive). */
    private fun uniqueName(name: String, taken: Set<String>): String {
        if (!taken.contains(name.lowercase())) return name
        val dot = name.lastIndexOf('.')
        val base = if (dot > 0) name.substring(0, dot) else name
        val ext = if (dot > 0) name.substring(dot) else ""
        var i = 2
        while (taken.contains("$base ($i)$ext".lowercase())) i++
        return "$base ($i)$ext"
    }

    // ---- reading back ----------------------------------------------------------

    private fun status(uri: Uri): String = try {
        activity.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
            ?.use { if (it.moveToFirst()) "ok" else "missing" } ?: "missing"
    } catch (_: SecurityException) {
        "noaccess"
    } catch (_: Exception) {
        "missing"
    }

    private fun displayName(uri: Uri): String? = try {
        activity.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
            ?.use { if (it.moveToFirst()) it.getString(0) else null }
    } catch (_: Exception) {
        null
    }

    /**
     * A readable name for a picked folder: "Internal storage/Pictures/Collage",
     * "SD card/Photos", or "<provider>/<folder>" for Drive and other providers.
     */
    private fun folderLabel(tree: Uri): String {
        val id = try {
            DocumentsContract.getTreeDocumentId(tree)
        } catch (_: Exception) {
            null
        }
        if (tree.authority == "com.android.externalstorage.documents" && id != null) {
            val volume = id.substringBefore(':')
            val path = id.substringAfter(':', "").trim('/')
            val root = if (volume == "primary") "Internal storage" else "SD card"
            return if (path.isEmpty()) root else "$root/$path"
        }
        val name = try {
            val doc = DocumentsContract.buildDocumentUriUsingTree(tree, id)
            displayName(doc)
        } catch (_: Exception) {
            null
        }
        val provider = providerLabel(tree)
        return if (name.isNullOrEmpty() || name == provider) provider else "$provider/$name"
    }

    /** The app behind a document URI ("Google Drive", "Files", …). */
    private fun providerLabel(uri: Uri): String {
        val authority = uri.authority ?: return "Files"
        if (authority == "com.android.externalstorage.documents") return "Internal storage"
        if (authority == "com.android.providers.downloads.documents") return "Download"
        return try {
            val info = activity.packageManager.resolveContentProvider(authority, 0)
            info?.loadLabel(activity.packageManager)?.toString() ?: "Files"
        } catch (_: Exception) {
            "Files"
        }
    }

    // ---- handing off to other apps ---------------------------------------------

    private fun open(uri: Uri, mime: String?): Boolean {
        val intent = Intent(Intent.ACTION_VIEW)
            .setDataAndType(uri, mime ?: activity.contentResolver.getType(uri))
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        return start(intent)
    }

    private fun showLocation(kind: String, uri: String?): Boolean = when (kind) {
        "gallery" -> start(Intent.makeMainSelectorActivity(Intent.ACTION_MAIN, Intent.CATEGORY_APP_GALLERY)) ||
            start(Intent(Intent.ACTION_VIEW).setType("image/*"))
        "downloads" -> start(Intent(DownloadManager.ACTION_VIEW_DOWNLOADS))
        "folder" -> {
            if (uri == null) {
                false
            } else {
                val tree = Uri.parse(uri)
                val doc = try {
                    DocumentsContract.buildDocumentUriUsingTree(tree, DocumentsContract.getTreeDocumentId(tree))
                } catch (_: Exception) {
                    tree
                }
                start(
                    Intent(Intent.ACTION_VIEW)
                        .setDataAndType(doc, DocumentsContract.Document.MIME_TYPE_DIR)
                        .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION),
                )
            }
        }
        else -> false
    }

    private fun share(uri: Uri, mime: String, text: String?): Boolean {
        val send = Intent(Intent.ACTION_SEND)
            .setType(mime)
            .putExtra(Intent.EXTRA_STREAM, uri)
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        if (text != null) send.putExtra(Intent.EXTRA_TEXT, text)
        return start(Intent.createChooser(send, null).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION))
    }

    private fun start(intent: Intent): Boolean = try {
        activity.startActivity(intent)
        true
    } catch (_: ActivityNotFoundException) {
        false
    } catch (_: SecurityException) {
        false
    }
}
