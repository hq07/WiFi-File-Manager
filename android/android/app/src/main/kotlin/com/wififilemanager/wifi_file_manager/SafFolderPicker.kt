package com.wififilemanager.wifi_file_manager

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class SafFolderPicker(private val activity: Activity) {

    companion object {
        private const val REQUEST_CODE = 9876
    }

    private var pendingResult: MethodChannel.Result? = null

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
            val docUri = DocumentsContract.buildDocumentUriUsingTree(
                treeUri,
                DocumentsContract.getTreeDocumentId(treeUri)
            )
            val folderName = queryDisplayName(docUri) ?: "folder"
            val cacheDir = File(activity.cacheDir, "wfm_upload_cache")
            if (cacheDir.exists()) cacheDir.deleteRecursively()
            cacheDir.mkdirs()

            val cachedPaths = mutableListOf<String>()
            enumerateAndCopy(treeUri, treeUri, cacheDir, "", cachedPaths)

            if (cachedPaths.isEmpty()) {
                result.success(emptyMap<String, Any>())
                return true
            }

            result.success(mapOf(
                "folderName" to folderName,
                "dirPath" to cacheDir.absolutePath,
                "paths" to cachedPaths
            ))
        } catch (e: Exception) {
            result.error("saf_error", e.message, null)
        }
        return true
    }

    private fun enumerateAndCopy(
        treeUri: Uri,
        parentDocUri: Uri,
        destDir: File,
        relativePrefix: String,
        paths: MutableList<String>
    ) {
        val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(
            treeUri,
            DocumentsContract.getDocumentId(parentDocUri)
        )

        activity.contentResolver.query(
            childrenUri,
            arrayOf(
                DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                DocumentsContract.Document.COLUMN_MIME_TYPE
            ),
            null, null, null
        )?.use { cursor ->
            val idCol = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_DOCUMENT_ID)
            val nameCol = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_DISPLAY_NAME)
            val mimeCol = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_MIME_TYPE)

            while (cursor.moveToNext()) {
                val docId = cursor.getString(idCol) ?: continue
                val name = cursor.getString(nameCol) ?: continue
                val mimeType = cursor.getString(mimeCol) ?: ""
                val childRelative = if (relativePrefix.isEmpty()) name
                    else "$relativePrefix${File.separator}$name"
                val childDocUri = DocumentsContract.buildDocumentUriUsingTree(treeUri, docId)

                if (mimeType == DocumentsContract.Document.MIME_TYPE_DIR) {
                    enumerateAndCopy(treeUri, childDocUri, destDir, childRelative, paths)
                } else {
                    val cachedFile = File(destDir, childRelative)
                    cachedFile.parentFile?.mkdirs()
                    try {
                        activity.contentResolver.openInputStream(childDocUri)?.use { input ->
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
