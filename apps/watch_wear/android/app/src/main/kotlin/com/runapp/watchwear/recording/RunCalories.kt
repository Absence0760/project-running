package com.runapp.watchwear.recording

import kotlin.math.max
import kotlin.math.roundToInt

/// Post-run calorie estimate for a watch-recorded run (persona samsung
/// #34). Kotlin port of the `estimateRunCalories` / coefficient ladder
/// in `apps/web/src/lib/calories.ts` (and its Dart twin
/// `apps/mobile_android/lib/calories.dart`) so the wrist shows the same
/// number the run lands on once it syncs to web / phone.
///
/// Divergence from the phone/web call site: those pass the runner's
/// `user_profiles.gender` to apply the ~5% female calibration. The
/// watch computes the unmodified curve, and that is a deliberate
/// choice, not a missing feature — `gender` is Art 9 special-category
/// data behind explicit `health_data_consent_at` and deny-by-default
/// RLS, so shipping it to another device class to shift an ephemeral,
/// never-persisted glanceable number by ~5% fails data minimisation
/// (GDPR Art 5(1)(c)). Don't plumb it into the prefs bag for this.
/// The run-detail pages recompute with gender once the run syncs, and
/// they own the authoritative figure. See decisions.md § 77.
object RunCalories {
    /// Per-activity energy cost (kcal per kg per km). Mirrors
    /// ACTIVITY_KCAL_PER_KG_PER_KM in calories.ts. The watch only
    /// records the four CHECK-constrained activity types.
    private val KCAL_PER_KG_PER_KM = mapOf(
        "run" to 1.0,
        "walk" to 0.5,
        "hike" to 0.7,
        "cycle" to 0.4,
    )

    /// Median adult-runner body weight used when the runner hasn't set
    /// `body_weight_kg`. Matches DEFAULT_BODY_WEIGHT_KG on web.
    const val DEFAULT_BODY_WEIGHT_KG = 70.0

    /// Estimated kcal for a run, rounded, always non-negative. Unknown /
    /// rogue activity types fall back to the run coefficient.
    fun estimate(distanceM: Double, weightKg: Double?, activityType: String?): Int {
        val distanceKm = max(0.0, distanceM) / 1000.0
        val weight = if (weightKg != null && weightKg > 0) weightKg else DEFAULT_BODY_WEIGHT_KG
        val coef = KCAL_PER_KG_PER_KM[activityType] ?: KCAL_PER_KG_PER_KM.getValue("run")
        return (weight * coef * distanceKm).roundToInt()
    }
}
