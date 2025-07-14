#!/bin/bash

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

echo "=== SCP Admin Credentials ==="
echo "Username: admin"

if [ -f "$SCRIPT_DIR/../.admin-password" ]; then
  echo -n "Password: "
  cat "$SCRIPT_DIR/../.admin-password"
else
  echo "Password: Not found - run 'make apply' first"
fi

echo ""
echo "=== API Token ==="
if [ -f "$SCRIPT_DIR/../.api-token" ]; then
  cat "$SCRIPT_DIR/../.api-token"
else
  echo "Not found - run 'make apply' first"
fi

echo ""
echo "=== Access Instructions ==="
echo "1. Run: make port-forward"
echo "2. Browse to: http://localhost:30080"