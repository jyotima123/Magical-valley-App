# run_integration_tests.ps1

Write-Host "?? Running Flutter Integration Tests..." -ForegroundColor Green

Write-Host "?? Getting dependencies..." -ForegroundColor Yellow
flutter pub get

Write-Host "?? Running integration tests..." -ForegroundColor Yellow
flutter test integration_test/app_flow_test.dart

Write-Host "? Integration tests completed!" -ForegroundColor Green
