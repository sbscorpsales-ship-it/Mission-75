package com.paramitsolutions.gativx

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp

class PermissionsRationaleActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            MaterialTheme {
                Surface(Modifier.fillMaxSize(), color = Color(0xFF0B1115)) {
                    Column(Modifier.padding(24.dp)) {
                        Text("GATIVX · Health Connect", color = Color(0xFFD8FF3E))
                        Text(
                            "GATIVX requests read-only access to daily steps and active calories so it can display your measured activity and, when you choose, back it up to your private GATIVX account. We do not write health records to Health Connect or estimate missing values. You can revoke access at any time in Android Health Connect settings.",
                            color = Color.White,
                            modifier = Modifier.padding(top = 16.dp)
                        )
                    }
                }
            }
        }
    }
}
