#!/bin/bash
# Prints profiler-context.json (written at deploy) merged with export accounting, for the data
# integrity, thread count and delivery checks. Run on the instance (or in the local test container)
# from the directory holding the app logs and pid files: bash profiler-accounting.sh [window_seconds]
#
# Per app (main, cpu, unsampled, none), from the agent's "Processed rotated JFR file
# profiler-jfr-<yyyyMMdd-HHmmss>.jfr: <N> samples" log lines:
#   <app>Samples        samples the agent exported over its processed windows
#   <app>ExpectedNanos  their total time for cpu profiles (samples x the 10 ms interval), which the
#                       backend's flame-graph total over the same windows must equal
#   <app>WallExpectedNanos  the expected total of a wall profile over those windows: live threads x
#                       the windows' duration. Wall samples are weighted to cover every thread, so a
#                       wall total is about thread count x elapsed time, not samples x interval.
#                       Only approximate (85-98% observed), so the wall checks using it are report-only.
#                       TODO(ADOT Java agent change needed): once the agent logs each window's total
#                       wall time on its "Processed rotated JFR file" line, sum that here instead.
#   <app>StartMs/EndMs  the time range those windows cover (start of the first, end of the last)
#   <app>Threads/ThreadsMin  live JVM threads now, and 70% of that (the minimum distinct thread names
#                       its wall samples must carry)
# From the collector's own metrics (127.0.0.1:8888):
#   collectorSentSamples / collectorFailedSamples  profile samples exported / failed to export
set -o errexit -o nounset -o pipefail
WINDOW_SECONDS=${1:-60}
INTERVAL_NANOS=10000000

out=$(sed 's/}[[:space:]]*$//' profiler-context.json)
for entry in main:nohup.out cpu:nohup-cpu.out unsampled:nohup-unsampled.out none:nohup-none.out; do
  app=${entry%%:*}
  log=${entry#*:}
  [ -f "$log" ] && [ -f "$app.pid" ] || continue
  windows=$(grep -o 'Processed rotated JFR file profiler-jfr-[0-9]*-[0-9]*\.jfr: [0-9]* samples' "$log" \
    | sed -E 's/.*profiler-jfr-([0-9]{8})-([0-9]{6})\.jfr: ([0-9]+) samples/\1 \2 \3/' || true)
  [ -n "$windows" ] || continue
  samples=$(echo "$windows" | awk '{s += $3} END {print s}')
  first=$(echo "$windows" | head -n 1)
  last=$(echo "$windows" | tail -n 1)
  epoch() { date -u -d "${1:0:4}-${1:4:2}-${1:6:2} ${2:0:2}:${2:2:2}:${2:4:2}" +%s; }
  start_ms=$(( $(epoch $first) * 1000 ))
  end_ms=$(( ($(epoch $last) + WINDOW_SECONDS) * 1000 - 1 ))
  threads=$(ls "/proc/$(cat "$app.pid")/task" | wc -l)
  out+=$(printf ',"%sSamples":"%s","%sExpectedNanos":"%s","%sWallExpectedNanos":"%s","%sStartMs":"%s","%sEndMs":"%s","%sThreads":"%s","%sThreadsMin":"%s"' \
    "$app" "$samples" "$app" "$((samples * INTERVAL_NANOS))" \
    "$app" "$((threads * (end_ms - start_ms + 1) * 1000000))" "$app" "$start_ms" "$app" "$end_ms" \
    "$app" "$threads" "$app" "$((threads * 70 / 100))")
done

metrics=$(curl -s --max-time 5 http://127.0.0.1:8888/metrics || true)
sum_metric() { echo "$metrics" | awk -v m="$1" '$1 ~ "^"m"(\\{|$)" {s += $NF} END {printf "%d", s}'; }
out+=$(printf ',"collectorSentSamples":"%s","collectorFailedSamples":"%s","accountedAtMs":"%s"}' \
  "$(sum_metric otelcol_exporter_sent_profile_samples_total)" \
  "$(sum_metric otelcol_exporter_send_failed_profile_samples_total)" "$(( $(date +%s) * 1000 ))")
echo "$out"
