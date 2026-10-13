import 'dart:math';
import 'package:mvc_app/models/ad_model.dart';
import 'package:mvc_app/services/api/supabase_api_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AdService {
  static AdService? _instance;
  late SupabaseClient _client;

  // Fixed ad size IDs from migration 049_ad_sizes.sql
  // These IDs are constant and seeded in the database
  static const String mediumRectangleId = 'f4e532a9-2102-4a19-b0ab-b59e87d70479'; // 300x250
  static const String leaderboardId = '18ef3f86-c86e-4bf2-91ba-e2129c461b2b'; // 728x90
  static const String halfPageId = '917e56e2-d112-4b8e-9de3-ef40976d8cee'; // 300x600
  static const String largeRectangleId = '4b9b36aa-13bc-4ba7-98b9-635278139d6b'; // 336x280
  static const String wideSkyscraperId = '891f0572-8bb5-4d44-bd0c-2229fae1789a'; // 160x600
  static const String billboardId = 'e7d37997-4855-44da-a47a-d3845bca056d'; // 970x250
  static const String portraitId = '6493b409-04a8-4b26-8871-32846c9ece21'; // 300x1050
  static const String mobileBannerId = '6cd0fdea-585f-4990-b07d-c5e1c7cfa44b'; // 300x50
  static const String largeMobileBannerId = '0ddf463a-0244-49c8-961d-d06a40a91a37'; // 320x100
  static const String mobileLeaderboardId = '427d16fc-b1bc-420f-bf36-bc04d244f4a9'; // 320x50

  AdService._internal() {
    _client = Supabase.instance.client;
  }

  static AdService get instance {
    _instance ??= AdService._internal();
    return _instance!;
  }

  /// Fetches active ads with Medium Rectangle size (300x250)
  /// Returns a random ad from the available ads
  Future<AdModel?> getRandomMediumRectangleAd() async {
    try {
      final now = DateTime.now().toIso8601String();
      print('🎯 Fetching ads for time: $now');

      // Query for active ads with Medium Rectangle size (300x250)
      // Using hardcoded ad size ID from migration
      final response = await _client
          .from('ads')
          .select('''
            *,
            ad_sizes!ad_size_id(id, name, width, height)
          ''')
          .eq('ad_size_id', mediumRectangleId)
          .eq('status', 'active')
          .eq('payment_status', 'succeeded')
          .lte('start_date', now)
          .gte('end_date', now);

      print('📊 Ad query response: ${response?.toString() ?? "null"}');

      if (response == null || response.isEmpty) {
        print('⚠️ No ads found in database');
        return null;
      }

      // Convert to list of AdModel
      final ads = (response as List).map((json) {
        return AdModel.fromJson({
          ...json,
          'width': json['ad_sizes']['width'],
          'height': json['ad_sizes']['height'],
        });
      }).toList();

      print('✅ Found ${ads.length} active Medium Rectangle ads');

      if (ads.isEmpty) {
        return null;
      }

      // Return a random ad
      final random = Random();
      return ads[random.nextInt(ads.length)];
    } catch (e) {
      print('❌ Error fetching ad: $e');
      return null;
    }
  }

  /// Fetches multiple random Medium Rectangle ads (for better variety)
  Future<List<AdModel>> getRandomMediumRectangleAds({int count = 5}) async {
    try {
      final now = DateTime.now().toIso8601String();
      print('🎯 Fetching $count ads for time: $now');

      // Query ads with hardcoded Medium Rectangle ad size ID
      final response = await _client
          .from('ads')
          .select('''
            *,
            ad_sizes!ad_size_id(id, name, width, height)
          ''');
          // .eq('ad_size_id', mediumRectangleId)
          // .eq('status', 'active')
          // .eq('payment_status', 'succeeded')
          // .lte('start_date', now)
          // .gte('end_date', now)
          // .limit(count);

      print('📊 Ads query response length: ${response?.length ?? 0}');

      if (response == null || response.isEmpty) {
        print('⚠️ No ads found in database');
        return [];
      }

      final adsList = (response as List).map((json) {
        return AdModel.fromJson({
          ...json,
          'width': json['ad_sizes']['width'],
          'height': json['ad_sizes']['height'],
        });
      }).toList();

      print('✅ Loaded ${adsList.length} ads successfully');
      return adsList;
    } catch (e) {
      print('❌ Error fetching ads: $e');
      return [];
    }
  }
}
