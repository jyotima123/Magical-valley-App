// Simple test to verify environment configuration
// ignore_for_file: avoid_print

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mvc_app/flavour_config.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Environment Configuration Tests', () {
    testWidgets('Verify QA environment is set correctly', (tester) async {
      // Set flavor to development (which maps to 'qa' environment)
      FlavorConfig.appFlavor = Flavor.development;

      // Verify the configuration
      expect(FlavorConfig.name, equals('development'));
      expect(FlavorConfig.supabaseEnvironment, equals('qa'));
      expect(FlavorConfig.isDevelopment, isTrue);
      expect(FlavorConfig.isProduction, isFalse);

      print('✅ Environment configuration verified:');
      print('   Flavor: ${FlavorConfig.name}');
      print('   Supabase Environment: ${FlavorConfig.supabaseEnvironment}');
      print('   Is Development: ${FlavorConfig.isDevelopment}');
    });
  });
}
