#!/bin/bash

if [ -z "$1" ]; then
  echo "Usage: ./invoice.sh <client-name> [<invoice-id>]"
  exit 1
fi

CLIENT_SLUG=$1
INVOICE_ID=$2

docker run --rm -v "$(pwd):/app" clientele:latest $CLIENT_SLUG $INVOICE_ID