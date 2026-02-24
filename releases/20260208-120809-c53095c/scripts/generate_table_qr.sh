#!/bin/bash
# ================================================
# QR Code Generator for Table Ordering
# Usage: ./generate_table_qr.sh <phone_number> <num_tables>
# Example: ./generate_table_qr.sh 213555123456 10
# ================================================

set -euo pipefail

PHONE="${1:?Usage: $0 <phone_number> <num_tables>}"
NUM_TABLES="${2:-10}"
OUTPUT_DIR="./qr_codes"

# Check for qrencode
if ! command -v qrencode &> /dev/null; then
    echo "Installing qrencode..."
    apt-get update && apt-get install -y qrencode || {
        echo "Please install qrencode: brew install qrencode (Mac) or apt install qrencode (Linux)"
        exit 1
    }
fi

mkdir -p "$OUTPUT_DIR"

echo "Generating QR codes for $NUM_TABLES tables..."
echo "Phone: $PHONE"
echo ""

for i in $(seq 1 $NUM_TABLES); do
    TABLE_NUM=$(printf "%02d" $i)
    WA_LINK="https://wa.me/${PHONE}?text=TABLE_${TABLE_NUM}"
    OUTPUT_FILE="${OUTPUT_DIR}/table_${TABLE_NUM}.png"
    
    qrencode -o "$OUTPUT_FILE" -s 10 -l H "$WA_LINK"
    echo "✅ Table $TABLE_NUM -> $OUTPUT_FILE"
done

echo ""
echo "🎉 Done! QR codes saved in $OUTPUT_DIR"
echo "Print these and place on each table."
