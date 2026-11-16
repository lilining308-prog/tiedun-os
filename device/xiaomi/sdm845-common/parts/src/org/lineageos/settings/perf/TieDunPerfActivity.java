/*
 * 铁盾OS B8: 性能档位(均衡/性能/省电) 设置页 — XiaomiParts 集成
 * SPDX-License-Identifier: Apache-2.0
 */
package org.lineageos.settings.perf;

import android.os.Bundle;

import com.android.settingslib.collapsingtoolbar.CollapsingToolbarBaseActivity;

public class TieDunPerfActivity extends CollapsingToolbarBaseActivity {

    private static final String TAG_PERF = "tiedun_perf";

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        getSupportFragmentManager().beginTransaction().replace(
                com.android.settingslib.collapsingtoolbar.R.id.content_frame,
                new TieDunPerfSettingsFragment(), TAG_PERF).commit();
    }
}
