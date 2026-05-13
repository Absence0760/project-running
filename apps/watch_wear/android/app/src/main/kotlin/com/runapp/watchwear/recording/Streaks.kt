package com.runapp.watchwear.recording

import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter

/// Pure run-streak computation. A "streak" is a sequence of
/// consecutive local days that each contain at least one run.
///
/// Strava-style grace rule: a missing today does not break the streak —
/// the streak continues to count as long as yesterday had a run. The
/// streak only resets when a full day goes by without one.
///
/// Mirrors `apps/web/src/lib/streaks.ts` and
/// `apps/mobile_android/lib/streaks.dart`. Keep all three in lockstep —
/// the shared-library-syncer agent watches the pair (Wear isn't in
/// the agent's pair-list yet; add it when the watch UI lands).
///
/// **Not wired yet.** This module exists so a future glanceable
/// streak tile or watchface complication can be built without
/// designing a fetchRecentRuns path on the watch in the same PR.
object Streaks {

    data class Result(val current: Int, val best: Int) {
        companion object {
            val EMPTY = Result(current = 0, best = 0)
        }
    }

    private val DAY_FMT = DateTimeFormatter.ISO_LOCAL_DATE

    /// Computes `Result(current, best)` from a list of run-start
    /// epoch-millis values.
    ///
    /// @param runStartsEpochMillis UTC millis for each run's started_at.
    ///   Order doesn't matter — bucketed by local day and deduped.
    /// @param todayEpochMillis "Today" anchor (usually
    ///   `System.currentTimeMillis()`). Local date is what counts.
    /// @param zone Local time zone used to bucket runs into days.
    fun compute(
        runStartsEpochMillis: List<Long>,
        todayEpochMillis: Long,
        zone: ZoneId = ZoneId.systemDefault(),
    ): Result {
        if (runStartsEpochMillis.isEmpty()) return Result.EMPTY

        val todayKey = localDayKey(todayEpochMillis, zone)
        val dayKeys = HashSet<String>()
        for (ms in runStartsEpochMillis) {
            val k = localDayKey(ms, zone)
            if (k <= todayKey) dayKeys.add(k)
        }
        if (dayKeys.isEmpty()) return Result.EMPTY

        val sortedKeys = dayKeys.sorted()

        // Best streak — increment on consecutive days, reset on gap.
        var best = 1
        var run = 1
        for (i in 1 until sortedKeys.size) {
            val prev = LocalDate.parse(sortedKeys[i - 1], DAY_FMT)
            val here = sortedKeys[i]
            if (here == prev.plusDays(1).format(DAY_FMT)) {
                run += 1
                if (run > best) best = run
            } else {
                run = 1
            }
        }

        // Current streak — walk back from today with the 1-day grace.
        var anchor = LocalDate.parse(todayKey, DAY_FMT)
        if (anchor.format(DAY_FMT) !in dayKeys) {
            anchor = anchor.minusDays(1)
            if (anchor.format(DAY_FMT) !in dayKeys) {
                return Result(current = 0, best = best)
            }
        }
        var current = 0
        while (anchor.format(DAY_FMT) in dayKeys) {
            current += 1
            anchor = anchor.minusDays(1)
        }
        return Result(current = current, best = best)
    }

    private fun localDayKey(epochMillis: Long, zone: ZoneId): String =
        java.time.Instant.ofEpochMilli(epochMillis)
            .atZone(zone)
            .toLocalDate()
            .format(DAY_FMT)
}
