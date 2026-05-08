package com.wififilemanager.wifi_file_manager

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.atomic.AtomicBoolean

class SafFolderPicker(private val activity: Activity) {

    companion object {
        private const val REQUEST_CODE = 9876
    }

    private var pendingResult: MethodChannel.Result? = null
    private var pendingTreeUri: Uri? = null
    private var pendingFolderName: String? = null
    private var copying = AtomicBoolean(false)
    @Volatile private var cancelled = false

    fun pickFolderSaf(result: MethodChannel.Result) {
        if (pendingResult != null) {
            result.error("already_active", "Already picking a folder", null)
            return
        }
        pendingResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE)
        activity.startActivityForResult(intent, REQUEST_CODE)
    }

    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST_CODE) return false
        val result = pendingResult ?: return false
        pendingResult = null

        if (resultCode != Activity.RESULT_OK || data?.data == null) {
            result.success(null)
            return true
        }

        val treeUri = data.data!!
        try {
            activity.contentResolver.takePersistableUriPermission(
                treeUri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION
            )
        } catch (_: Exception) {}

        try {
            val treeDocId = DocumentsContract.getTreeDocumentId(treeUri)
            val docUri = DocumentsContract.buildDocumentUriUsingTree(treeUri, treeDocId)
            pendingFolderName = queryDisplayName(docUri) ?: "folder"
            pendingTreeUri = treeUri
            result.success(mapOf("folderName" to pendingFolderName!!))
        } catch (e: Exception) {
            result.error("saf_error", e.message, null)
        }
        return true
    }

    fun startCopy(result: MethodChannel.Result) {
        val treeUri = pendingTreeUri
        val folderName = pendingFolderName
        if (treeUri == null || folderName == null) {
            result.error("no_folder", "No folder selected", null)
            return
        }
        if (!copying.compareAndSet(false, true)) {
            result.error("already_copying", "Copy already in progress", null)
            return
        }

        cancelled = false
        Thread {
            try {
                val cacheDir = File(activity.cacheDir, "wfm_upload_cache")
                if (cacheDir.exists()) cacheDir.deleteRecursively()
                cacheDir.mkdirs()

                val paths = mutableListOf<String>()
                copySubtree(treeUri, treeUri, cacheDir, "", paths)

                activity.runOnUiThread {
                    copying.set(false)
                    sendProgress("", 1.0)
                    if (cancelled) {
                        result.success(mapOf("cancelled" to true))
                    } else {
                        result.success(mapOf(
                            "folderName" to folderName,
                            "dirPath" to cacheDir.absolutePath,
                            "paths" to paths
                        ))
                    }
                }
            } catch (e: Exception) {
                activity.runOnUiThread {
                    copying.set(false)
                    result.error("copy_error", e.message, null)
                }
            }
        }.start()
    }

    fun cancelCopy() {
        cancelled = true
    }

    private fun sendProgress(current: String, progress: Double) {
        MainActivity.channel?.invokeMethod("onCopyProgress", mapOf(
            "current" to current,
            "progress" to progress
        ))
    }

    private fun copySubtree(
        docUri: Uri,
        treeUri: Uri,
        destDir: File,
        relativePrefix: String,
        paths: MutableList<String>
    ) {
        if (cancelled) return
        val docId = DocumentsContract.getDocumentId(docUri)
        val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(treeUri, docId)

        activity.contentResolver.query(
            childrenUri,
            arrayOf(
                DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                DocumentsContract.Document.COLUMN_MIME_TYPE,
                DocumentsContract.Document.COLUMN_SIZE
            ),
            null, null, null
        )?.use { cursor ->
            val idCol = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_DOCUMENT_ID)
            val nameCol = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_DISPLAY_NAME)
            val mimeCol = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_MIME_TYPE)

            while (cursor.moveToNext() && !cancelled) {
                val childId = cursor.getString(idCol) ?: continue
                val name = cursor.getString(nameCol) ?: continue
                val mimeType = cursor.getString(mimeCol) ?: ""
                val childRelative = if (relativePrefix.isEmpty()) name
                    else "$relativePrefix${File.separator}$name"
                val childUri = DocumentsContract.buildDocumentUriUsingTree(treeUri, childId)

                if (mimeType == DocumentsContract.Document.MIME_TYPE_DIR) {
                    copySubtree(childUri, treeUri, destDir, childRelative, paths)
                } else {
                    sendProgress(childRelative, -1.0)
                    val cachedFile = File(destDir, childRelative)
                    cachedFile.parentFile?.mkdirs()
                    try {
                        activity.contentResolver.openInputStream(childUri)?.use { input ->
                            FileOutputStream(cachedFile).use { output ->
                                input.copyTo(output, bufferSize = 8192)
                            }
                        }
                        paths.add(cachedFile.absolutePath)
                    } catch (_: Exception) {}
                }
            }
        }
    }

    private fun queryDisplayName(uri: Uri): String? {
        return activity.contentResolver.query(
            uri,
            arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME),
            null, null, null
        )?.use { cursor ->
            if (cursor.moveToFirst()) cursor.getString(0) else null
        }
    }
}
