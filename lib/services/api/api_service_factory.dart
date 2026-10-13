// lib/services/api/api_service_factory.dart
// Factory to switch between different API implementations

import 'package:mvc_app/services/api/supabase_api_service.dart';
import 'package:mvc_app/services/api_service.dart';

enum ApiProvider { supabase, firebase, custom }

class ApiServiceFactory {
  static ApiService createApiService(ApiProvider provider) {
    switch (provider) {
      case ApiProvider.supabase:
        return SupabaseApiService.instance;
      case ApiProvider.firebase:
        // TODO: Implement FirebaseApiService
        throw UnimplementedError('Firebase API service not implemented yet');
      case ApiProvider.custom:
        // TODO: Implement CustomApiService for your own backend
        throw UnimplementedError('Custom API service not implemented yet');
    }
  }
}
