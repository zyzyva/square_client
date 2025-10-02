#!/bin/bash

# Script to create templates from contacts4us for the square_client installer

CONTACTS4US_DIR="/Users/joshuahunter/Desktop/projects/contacts_ecosystem/contacts4us"
TEMPLATE_DIR="/Users/joshuahunter/Desktop/projects/contacts_ecosystem/square_client/priv/templates"

mkdir -p "$TEMPLATE_DIR"

echo "Creating templates from contacts4us..."

# Copy Payments context
cp "$CONTACTS4US_DIR/lib/contacts4us/payments.ex" \
   "$TEMPLATE_DIR/payments.ex.eex"

# Copy LiveView index
cp "$CONTACTS4US_DIR/lib/contacts4us_web/live/subscription_live/index.ex" \
   "$TEMPLATE_DIR/subscription_live_index.ex.eex"

# Copy LiveView manage
cp "$CONTACTS4US_DIR/lib/contacts4us_web/live/subscription_live/manage.ex" \
   "$TEMPLATE_DIR/subscription_live_manage.ex.eex"

# Copy Square payment hook
cp "$CONTACTS4US_DIR/assets/js/hooks/square_payment.js" \
   "$TEMPLATE_DIR/square_payment.js.eex"

echo "Templates created in $TEMPLATE_DIR"
echo "Now replacing placeholders with {{}} syntax..."

# Use {{MODULE}} and {{APP}} as placeholders to avoid EEx conflicts
# These will be replaced by the installer, not by EEx

for file in "$TEMPLATE_DIR"/*.eex; do
  # Use perl for in-place editing (works on macOS)
  perl -i -pe 's/Contacts4us/{{MODULE}}/g' "$file"
  perl -i -pe 's/:contacts4us/:{{APP}}/g' "$file"
  perl -i -pe 's/for your business card scanning needs/for your application/g' "$file"
  perl -i -pe 's/to get the most out of Contacts4us/with premium features/g' "$file"
  echo "  ✓ Processed $(basename $file)"
done

echo "✅ All templates created and processed!"
