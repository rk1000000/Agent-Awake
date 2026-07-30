#!/bin/bash

set -euo pipefail

app_binary="/Applications/Agent Awake.app/Contents/MacOS/AgentAwake"
timeout_seconds="${1:-180}"
started_at="$(date '+%Y-%m-%d %H:%M:%S %z')"
baseline_sleep="$(pmset -g log | grep -c 'Clamshell Sleep' || true)"
protection_log_message="sleep protection Purr played after closed lid confirmation"
energy_log_message="energy saving Tink played after brightness and low power confirmation"
baseline_protection_sounds="$(log show --last 1h --style compact --predicate 'subsystem == "com.rodion.agentawake" AND category == "state"' 2>/dev/null | grep -c "$protection_log_message" || true)"
baseline_energy_sounds="$(log show --last 1h --style compact --predicate 'subsystem == "com.rodion.agentawake" AND category == "state"' 2>/dev/null | grep -c "$energy_log_message" || true)"

lid_is_closed() {
    ioreg -r -d 1 -c IOPMrootDomain | grep -q '"AppleClamshellState" = Yes'
}

brightness_percent() {
    "$app_binary" --diagnostics | awk -F': ' '/Built-in display brightness:/ {gsub(/%/, "", $2); print $2}'
}

low_power_value() {
    pmset -g custom | awk '/lowpowermode/ {print $2}' | sort -u | tr -d '\n'
}

echo "Закройте крышку минимум на 15 секунд, затем откройте. Ожидание: ${timeout_seconds} с."

closed=false
for ((second = 0; second < timeout_seconds; second++)); do
    if lid_is_closed; then
        closed=true
        echo "Крышка закрыта: $(date '+%H:%M:%S')"
        break
    fi
    sleep 1
done

if [[ "$closed" != true ]]; then
    echo "BLOCKED: крышка не была закрыта; старт проверки $started_at"
    exit 1
fi

sleep 12
closed_brightness="$(brightness_percent)"
closed_low_power="$(low_power_value)"
closed_confirmation="missing"
if [[ -f /var/run/com.rodion.agentawake.low-power-applied ]]; then
    closed_confirmation="present"
fi
echo "Закрыто 12 с: brightness=${closed_brightness}% lowpowermode=${closed_low_power} confirmation=${closed_confirmation}"

if [[ "$closed_brightness" != "0" || "$closed_low_power" != "1" || "$closed_confirmation" != "present" ]]; then
    echo "BLOCKED: экономия не применилась после 10 секунд"
    exit 1
fi

opened=false
for ((second = 0; second < timeout_seconds; second++)); do
    if ! lid_is_closed; then
        opened=true
        echo "Крышка открыта: $(date '+%H:%M:%S')"
        break
    fi
    sleep 1
done

if [[ "$opened" != true ]]; then
    echo "BLOCKED: крышка не была открыта"
    exit 1
fi

for _ in {1..10}; do
    open_brightness="$(brightness_percent)"
    open_low_power="$(low_power_value)"
    if [[ "$open_brightness" == "50" && "$open_low_power" == "0" ]]; then
        break
    fi
    sleep 1
done

new_sleep="$(pmset -g log | grep -c 'Clamshell Sleep' || true)"
current_protection_sounds="$(log show --last 1h --style compact --predicate 'subsystem == "com.rodion.agentawake" AND category == "state"' 2>/dev/null | grep -c "$protection_log_message" || true)"
current_energy_sounds="$(log show --last 1h --style compact --predicate 'subsystem == "com.rodion.agentawake" AND category == "state"' 2>/dev/null | grep -c "$energy_log_message" || true)"
protection_sound_delta="$((current_protection_sounds - baseline_protection_sounds))"
energy_sound_delta="$((current_energy_sounds - baseline_energy_sounds))"
echo "После открытия: brightness=${open_brightness}% lowpowermode=${open_low_power}"
echo "Звуковых подтверждений за тест: Purr=${protection_sound_delta} Tink=${energy_sound_delta}"

if [[ "$open_brightness" != "50" || "$open_low_power" != "0" ]]; then
    echo "BLOCKED: настройки не восстановились после открытия"
    exit 1
fi
if [[ "$new_sleep" != "$baseline_sleep" ]]; then
    echo "BLOCKED: во время теста появился Clamshell Sleep"
    exit 1
fi
if [[ "$protection_sound_delta" != "1" || "$energy_sound_delta" != "1" ]]; then
    echo "BLOCKED: ожидалось ровно по одному подтверждённому Purr и Tink"
    exit 1
fi

echo "PASS: Purr подтвердил защиту сна; Tink подтвердил 0% + Low Power ON; открытие восстановило 50% + Low Power OFF"
