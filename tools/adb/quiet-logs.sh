#!/usr/bin/env bash
# tools/adb/quiet-logs.sh
#
# Silences third-party log tags that flood `flutter run` on Android.
#
# `flutter run` shows every logcat line emitted by the app's *process*, which
# includes Google Play Services libraries linked into the app. The camera
# presence source in particular re-logs the whole camera list every time the
# system changes camera access priorities — several times a second on some
# devices — which buries the app's own output and can stall the tool's log
# reader.
#
# None of these tags come from Stable's own code; silencing them hides noise,
# not signal. Errors and Flutter's own logging are untouched.
#
# Usage:
#   bash tools/adb/quiet-logs.sh            # silence
#   bash tools/adb/quiet-logs.sh --restore  # back to default verbosity
#
# The properties are set on the device and last until it reboots, so re-run
# this after a restart if the noise comes back.
#
# Required env:
#   DEVICE — adb device serial (default: first connected device)

set -euo pipefail

DEVICE="${DEVICE:-$(adb devices | awk 'NR>1 && $2=="device" {print $1; exit}')}"
if [[ -z "${DEVICE}" ]]; then
  echo "No adb device found. Connect a device or set DEVICE=<serial>." >&2
  exit 1
fi

# CameraX / Play Services camera presence, and the Firebase telemetry
# transport that retries on a backoff whenever the network is unavailable.
NOISY_TAGS=(
  Camera2PresenceSrc
  TransportRuntime.CctTransportBackend
  TransportRuntime.JobInfoScheduler
)

LEVEL="SILENT"
ACTION="Silenced"
if [[ "${1:-}" == "--restore" ]]; then
  # VERBOSE is the default for an untagged property.
  LEVEL="VERBOSE"
  ACTION="Restored"
fi

for tag in "${NOISY_TAGS[@]}"; do
  adb -s "${DEVICE}" shell setprop "log.tag.${tag}" "${LEVEL}"
  actual="$(adb -s "${DEVICE}" shell getprop "log.tag.${tag}" | tr -d '\r')"
  printf '%-40s %s\n' "${tag}" "${actual:-<unset>}"
done

echo "${ACTION} on ${DEVICE}. Restart 'flutter run' to see the difference."
