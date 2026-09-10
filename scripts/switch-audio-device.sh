#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# DEVICE IDENTIFIERS
# Primary matching uses stable node name patterns; secondary fallback uses ALSA card integers.
# ==============================================================================
HEADSET_SINK_PATTERN="Arctis_Nova_Pro_Wireless"
SPEAKERS_SINK_PATTERN="Audioengine_2"

HEADSET_SOURCE_PATTERN="Arctis_Nova_Pro_Wireless"
CAMERA_MIC_SOURCE_PATTERN="usb"     # Matches your USB camera mic (card 0)

# Fallback ALSA Card numbers
HEADSET_CARD=3
SPEAKERS_CARD=4
CAMERA_CARD=0
# ==============================================================================

find_node_id() {
    local media_class="$1"
    local name_pattern="$2"
    local card_num="$3"

    pw-dump | jq -r \
        --arg class "$media_class" \
        --arg pat "$name_pattern" \
        --argjson card "$card_num" '
        .[]
        | select(.type == "PipeWire:Interface:Node")
        | select(.info.props["media.class"] == $class)
        | select(
            ((.info.props["node.name"] // "") | test($pat; "i"))
            or
            (.info.props["alsa.card"] == $card)
          )
        | .id
    ' | head -n 1
}

# Resolve active PipeWire node IDs
HEADSET_SINK_ID=$(find_node_id "Audio/Sink" "$HEADSET_SINK_PATTERN" "$HEADSET_CARD")
SPEAKER_SINK_ID=$(find_node_id "Audio/Sink" "$SPEAKERS_SINK_PATTERN" "$SPEAKERS_CARD")
HEADSET_SOURCE_ID=$(find_node_id "Audio/Source" "$HEADSET_SOURCE_PATTERN" "$HEADSET_CARD")
CAM_SOURCE_ID=$(find_node_id "Audio/Source" "$CAMERA_MIC_SOURCE_PATTERN" "$CAMERA_CARD")

# Validate outputs
if [[ -z "$HEADSET_SINK_ID" || -z "$SPEAKER_SINK_ID" ]]; then
    echo "Error resolving sink IDs:" >&2
    echo "  Headset Sink ID: ${HEADSET_SINK_ID:-NOT FOUND}" >&2
    echo "  Speaker Sink ID: ${SPEAKER_SINK_ID:-NOT FOUND}" >&2
    exit 1
fi

# Validate inputs
if [[ -z "$HEADSET_SOURCE_ID" || -z "$CAM_SOURCE_ID" ]]; then
    echo "Error resolving source IDs:" >&2
    echo "  Headset Mic ID:  ${HEADSET_SOURCE_ID:-NOT FOUND}" >&2
    echo "  Camera Mic ID:   ${CAM_SOURCE_ID:-NOT FOUND}" >&2
    exit 1
fi

# Detect current default sink ID (* in wpctl status)
CURRENT_DEFAULT_SINK=$(wpctl status | awk '
    /Audio/ { in_audio=1 }
    in_audio && /Sinks:/ { in_sinks=1; next }
    in_sinks && /\*/ {
        match($0, /[0-9]+/)
        print substr($0, RSTART, RLENGTH)
        exit
    }
    in_sinks && /^ *$/ { exit }
')

# Determine target
ACTION="${1:-}"

case "${ACTION,,}" in
    headset)
        TARGET="headset"
        ;;
    speakers|speaker)
        TARGET="speakers"
        ;;
    "")
        if [[ "$CURRENT_DEFAULT_SINK" == "$HEADSET_SINK_ID" ]]; then
            TARGET="speakers"
        else
            TARGET="headset"
        fi
        ;;
    *)
        echo "Usage: $0 [headset|speakers]" >&2
        exit 1
        ;;
esac

# Perform switch
if [[ "$TARGET" == "headset" ]]; then
    wpctl set-default "$HEADSET_SINK_ID"
    wpctl set-default "$HEADSET_SOURCE_ID"
    echo "Switched to: Arctis Nova Pro (Sink: $HEADSET_SINK_ID, Mic: $HEADSET_SOURCE_ID)"
    notify-send -a "Audio Switcher" -i audio-headset "Audio Profile" "Headset Active" 2>/dev/null || true
else
    wpctl set-default "$SPEAKER_SINK_ID"
    wpctl set-default "$CAM_SOURCE_ID"
    echo "Switched to: Audioengine 2+ & Camera Mic (Sink: $SPEAKER_SINK_ID, Mic: $CAM_SOURCE_ID)"
    notify-send -a "Audio Switcher" -i audio-speakers "Audio Profile" "Speakers & Camera Mic Active" 2>/dev/null || true
fi