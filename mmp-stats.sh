#!/bin/bash
FPGA_COUNT=$1
LOG_FILE=$2
BASEDIR=$(dirname $0)
cd ${BASEDIR}
. mmp-external.conf


uids=()
hashes=()
temps=()
voltages=()
sclks=()
accepted_shares=()
rejected_shares=()
invalid_shares=()

numSNs=($(cat "$LOG_FILE" |sed -r 's/\x1B\[[0-9;]*[a-zA-Z]//g' |grep -oP 'sn=\K\S+'| sort -u))

for uid in "${numSNs[@]}"; do
    line=$(cat "$LOG_FILE" |sed -r 's/\x1B\[[0-9;]*[a-zA-Z]//g'| grep "sn=$uid" | tail -n 1)

    hash=$(echo "$line" | grep -oP 'hashrate=\K[0-9.]+' | head -1)
    temp=$(echo "$line" | grep -oP 'temp=\K[0-9.]+')
    voltage=$(echo "$line" | grep -oP 'vccint=\K[0-9]+')
    watt=$(echo "$line" | grep -oP 'power=\K[0-9]+' || echo "0")
    sclk=$(echo "$line" | grep -oP 'clock=\K[0-9.]+' | head -1)
    accepted_pair=$(echo "$line" | grep -oP 'accepted=\K[0-9]+/[0-9]+')
    invalid=$(echo "$line" | grep -oP 'invalid=\K[0-9.]+' || echo "0")

    acc=$(echo "$accepted_pair" | cut -d/ -f1)
    total=$(echo "$accepted_pair" | cut -d/ -f2)
    rej=$((total - acc))

    uids+=("$uid")
    hashes+=("$hash")
    temps+=("$temp")
    voltages+=("$voltage")
    watts+=("$watt")
    sclks+=("$sclk")
    accepted_shares+=("$acc")
    rejected_shares+=("$rej")
    invalid_shares+=("$invalid")
done

shares=$(jq -n \
    --argjson accepted "$(printf '%s\n' "${accepted_shares[@]}" | jq -R '. | tonumber' | jq -s .)" \
    --argjson rejected "$(printf '%s\n' "${rejected_shares[@]}" | jq -R '. | tonumber' | jq -s .)" \
    --argjson invalid "$(printf '%s\n' "${invalid_shares[@]}" | jq -R '. | tonumber' | jq -s .)" \
    '{accepted: $accepted, rejected: $rejected, invalid: $invalid}')

total_accepted=$(IFS=+; bc <<< "${accepted_shares[*]}")
total_rejected=$(IFS=+; bc <<< "${rejected_shares[*]}")
total_invalid=$(IFS=+; bc <<< "${invalid_shares[*]}")

jq -n \
    --arg miner_name "$EXTERNAL_NAME" \
    --arg miner_version "$EXTERNAL_VERSION" \
    --arg units "ghs" \
    --argjson uid "$(printf '%s\n' "${uids[@]}" | jq -R . | jq -s .)" \
    --argjson hash "$(printf '%s\n' "${hashes[@]}" | jq -R . | jq -s .)" \
    --argjson temp "$(printf '%s\n' "${temps[@]}" | jq -R . | jq -s .)" \
    --argjson voltage "$(printf '%s\n' "${voltages[@]}" | jq -R . | jq -s .)" \
    --argjson watt "$(printf '%s\n' "${watts[@]}" | jq -R . | jq -s .)" \
    --argjson sclk "$(printf '%s\n' "${sclks[@]}" | jq -R . | jq -s .)" \
    --argjson shares "$shares" \
    --argjson air "[$total_accepted, $total_invalid, $total_rejected]" \
    '{
        uid: $uid,
        hash: $hash,
        temp: $temp,
        voltage: $voltage,
        watt: $watt,
        sclk: $sclk,
        shares: $shares,
        air: $air,
        units: $units,
        miner_name: $miner_name,
        miner_version: $miner_version
    }'
