/*
 * 铁盾OS B5: 鸣谢页(规格=交接清单第三节)
 * SPDX-License-Identifier: Apache-2.0
 */
package com.android.settings.deviceinfo.tiedun;

import android.app.settings.SettingsEnums;
import android.content.Context;

import androidx.annotation.NonNull;

import com.android.settings.R;
import com.android.settings.dashboard.DashboardFragment;

import java.util.List;

/** 四组致敬链(带仓库超链接) + 署名压轴。行项点击经 <intent> 打开浏览器。 */
public class TieDunCreditsFragment extends DashboardFragment {

    private static final String LOG_TAG = "TieDunCreditsFragment";

    @Override
    public int getMetricsCategory() {
        return SettingsEnums.DEVICEINFO;
    }

    @Override
    protected String getLogTag() {
        return LOG_TAG;
    }

    @Override
    protected int getPreferenceScreenResId() {
        return R.xml.tiedun_credits;
    }

    @Override
    protected List<com.android.settingslib.core.AbstractPreferenceController>
            createPreferenceControllers(@NonNull Context context) {
        return null;
    }
}
