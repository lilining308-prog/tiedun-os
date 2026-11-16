/*
 * 铁盾OS B8: 性能档位切换(均衡/性能/省电) — 写 persist.tiedun.perf_mode, init 触发调频
 * SPDX-License-Identifier: Apache-2.0
 */
package org.lineageos.settings.perf;

import android.os.Bundle;
import android.os.SystemProperties;

import androidx.preference.ListPreference;
import androidx.preference.Preference;
import androidx.preference.PreferenceFragmentCompat;

import org.lineageos.settings.R;

public class TieDunPerfSettingsFragment extends PreferenceFragmentCompat
        implements Preference.OnPreferenceChangeListener {

    private static final String KEY_PERF_MODE = "tiedun_perf_mode";
    private static final String PROP = "persist.tiedun.perf_mode";

    private ListPreference mPerfMode;

    @Override
    public void onCreatePreferences(Bundle savedInstanceState, String rootKey) {
        addPreferencesFromResource(R.xml.tiedun_perf);
        mPerfMode = findPreference(KEY_PERF_MODE);
        if (mPerfMode != null) {
            mPerfMode.setOnPreferenceChangeListener(this);
            mPerfMode.setValue(SystemProperties.get(PROP, "0"));
        }
    }

    @Override
    public boolean onPreferenceChange(Preference preference, Object newValue) {
        if (KEY_PERF_MODE.equals(preference.getKey())) {
            SystemProperties.set(PROP, (String) newValue);
            return true;
        }
        return false;
    }
}
