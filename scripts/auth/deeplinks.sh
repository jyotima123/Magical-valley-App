#!/bin/bash

#adb shell am start -d com.magicvalleycentral.mvc://reset-password
#adb shell am start -d https://yavxzgcgoasicjprzfcv.supabase.co/auth/v1/verify?token=pkce_0300df8d880ff6bc89f1992ac07feb5c4ce1ed55d38f1207d5472335&type=recovery&redirect_to=https://yavxzgcgoasicjprzfcv.supabase.co/
#adb shell am start -d com.magicvalleycentral.mvc://reset-password/auth/v1/verify?token=pkce_0300df8d880ff6bc89f1992ac07feb5c4ce1ed55d38f1207d5472335&type=recovery&redirect_to=https://yavxzgcgoasicjprzfcv.supabase.co/
adb shell am start -a android.intent.action.VIEW -d "com.magicvalleycentral.mvc://reset-password/auth/v1/verify?token=pkce_3f354eedc63cc3b588bb6a9c5afaf9a8b7c93ef832d95ed2351f83cf&type=recovery&code=572984" com.magicvalleycentral.mvc

