#!/usr/bin/env bash
# TEMPORARY: reshape dstack-mr GCP measurements (make measure-gcp ->
# build/gcp_measurements.json) into attested-tls-proxy's dcap-tdx
# --measurements-file format. Drop once attested-tls-proxy accepts the
# condensed dstack-mr output directly.
#
# dstack-mr emits mrtd[] (one per known GCP firmware) and rtmr0[] (equal-size
# per-firmware chunks: firmware x machine-type-ACPI x boot variants), while
# attested-tls-proxy wants flat measurement sets it ORs over. We pair mrtd[i]
# with its rtmr0 chunk; a genuine quote matches exactly one set.
#
# Usage: scripts/gcp_measurements_to_dcap.sh [gcp_measurements.json] > out.json
set -euo pipefail
jq '
  (.mrtd | length) as $m
  | (((.rtmr0 | length) / $m) | floor) as $c
  | [ range(0; $m) as $i
    | range(0; $c) as $j
    | { measurement_id: "local fw\($i)-v\($j)",
        attestation_type: "dcap-tdx",
        measurements: {
          "0": { expected: .mrtd[$i] },
          "1": { expected: .rtmr0[$i*$c + $j] },
          "2": { expected: .rtmr1 },
          "3": { expected: .rtmr2 },
          "4": { expected: .rtmr3 }
        } } ]
' "${1:-build/gcp_measurements.json}"
