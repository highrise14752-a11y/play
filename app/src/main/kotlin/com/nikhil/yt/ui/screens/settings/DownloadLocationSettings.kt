package com.nikhil.yt.ui.screens.settings

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.nikhil.yt.R
import com.nikhil.yt.playback.DownloadUtil
import kotlinx.coroutines.launch

@Composable
fun DownloadLocationSettings(downloadUtil: DownloadUtil) {
    val context = LocalContext.current
    val storage = downloadUtil.storage
    val location by storage.location.collectAsState()
    val busy by storage.busy.collectAsState()
    val error by storage.error.collectAsState()
    val scope = rememberCoroutineScope()
    var choosing by remember { mutableStateOf(false) }
    var confirmMove by remember { mutableStateOf(false) }
    val picker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocumentTree()) { uri ->
        if (uri != null) scope.launch {
            runCatching { storage.selectFolder(uri) }.onFailure {
                storage.error.value = context.getString(R.string.download_choose_failed)
            }
        }
    }

    Column(modifier = Modifier.fillMaxWidth().padding(horizontal = 4.dp)) {
        Text(stringResource(R.string.download_location), style = MaterialTheme.typography.titleSmall)
        Text(location.label, style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant)
        Spacer(Modifier.height(8.dp))
        Text(stringResource(R.string.download_location_new_only), style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant)
        TextButton(onClick = { choosing = true }, enabled = !busy) {
            Text(stringResource(R.string.download_change_location))
        }
        TextButton(onClick = { confirmMove = true }, enabled = !busy) {
            Text(stringResource(R.string.download_move_existing))
        }
        if (busy) {
            LinearProgressIndicator(modifier = Modifier.fillMaxWidth())
            Text(stringResource(R.string.download_saving_files), style = MaterialTheme.typography.bodySmall)
        }
        error?.let { Text(it, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall) }
    }

    if (choosing) {
        val privateLocations = remember { storage.privateLocations() }
        AlertDialog(
            onDismissRequest = { choosing = false },
            title = { Text(stringResource(R.string.download_location)) },
            text = {
                Column {
                    Text(stringResource(R.string.download_location_description), style = MaterialTheme.typography.bodySmall)
                    Spacer(Modifier.height(12.dp))
                    privateLocations.forEach { option ->
                        Row(
                            modifier = Modifier.fillMaxWidth().clickable {
                                choosing = false
                                scope.launch {
                                    runCatching { storage.selectPrivate(option) }.onFailure {
                                        storage.error.value = context.getString(R.string.download_choose_failed)
                                    }
                                }
                            }.padding(vertical = 8.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            RadioButton(selected = location.id == option.id, onClick = null)
                            Spacer(Modifier.width(8.dp))
                            Text(option.label)
                        }
                    }
                    if (privateLocations.size == 1) {
                        Text(stringResource(R.string.download_no_sd_card), style = MaterialTheme.typography.bodySmall)
                    }
                    TextButton(onClick = {
                        choosing = false
                        runCatching { picker.launch(null) }.onFailure {
                            storage.error.value = context.getString(R.string.download_choose_failed)
                        }
                    }) { Text(stringResource(R.string.download_choose_folder)) }
                }
            },
            confirmButton = { TextButton(onClick = { choosing = false }) { Text(stringResource(android.R.string.cancel)) } },
        )
    }

    if (confirmMove) {
        AlertDialog(
            onDismissRequest = { confirmMove = false },
            title = { Text(stringResource(R.string.download_move_existing)) },
            text = { Text(stringResource(R.string.download_move_confirm, location.label)) },
            confirmButton = {
                TextButton(onClick = {
                    confirmMove = false
                    downloadUtil.moveDownloadsToSelectedLocation()
                }) { Text(stringResource(R.string.download_move_existing)) }
            },
            dismissButton = { TextButton(onClick = { confirmMove = false }) { Text(stringResource(android.R.string.cancel)) } },
        )
    }
}
