#!/bin/bash
# run_tests_on_device.sh

DEVICE_ID=${1:-""}

if [ -z "$DEVICE_ID" ]; then
    echo "?? Running on default device..."
    flutter test integration_test/app_flow_test.dart
else
    echo "?? Running on device: $DEVICE_ID"
    flutter test integration_test/app_flow_test.dart -d $DEVICE_ID
fi

