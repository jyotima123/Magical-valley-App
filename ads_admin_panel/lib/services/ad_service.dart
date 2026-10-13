import 'dart:io';
import 'package:ads_admin_panel/config/supabase_config.dart';
import 'package:ads_admin_panel/models/ad_model.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AdService {
  final SupabaseClient _client = SupabaseConfig.client;

  Future<List<AdModel>> getAllAds() async {
    try {
      final response = await _client
          .from('ads')
          .select()
          .order('created_at', ascending: false);

      return (response as List).map((ad) => AdModel.fromJson(ad)).toList();
    } catch (e) {
      throw Exception('Failed to fetch ads: $e');
    }
  }

  Future<List<AdModel>> getMyAds() async {
    try {
      final userId = SupabaseConfig.currentUser?.id;
      if (userId == null) {
        throw Exception('User not authenticated');
      }

      final response = await _client
          .from('ads')
          .select()
          .eq('creator_id', userId)
          .order('created_at', ascending: false);

      return (response as List).map((ad) => AdModel.fromJson(ad)).toList();
    } catch (e) {
      throw Exception('Failed to fetch my ads: $e');
    }
  }

  Future<AdModel> getAdById(String id) async {
    try {
      final response = await _client.from('ads').select().eq('id', id).single();

      return AdModel.fromJson(response);
    } catch (e) {
      throw Exception('Failed to fetch ad: $e');
    }
  }

  Future<AdModel> createAd(AdModel ad) async {
    try {
      final userId = SupabaseConfig.currentUser?.id;
      if (userId == null) {
        throw Exception('User not authenticated');
      }

      final adData = ad.copyWith(creatorId: userId).toJson();
      final response = await _client.from('ads').insert(adData).select().single();

      return AdModel.fromJson(response);
    } catch (e) {
      throw Exception('Failed to create ad: $e');
    }
  }

  Future<AdModel> updateAd(AdModel ad) async {
    try {
      if (ad.id == null) {
        throw Exception('Ad ID is required for update');
      }

      final response = await _client
          .from('ads')
          .update(ad.toJson())
          .eq('id', ad.id!)
          .select()
          .single();

      return AdModel.fromJson(response);
    } catch (e) {
      throw Exception('Failed to update ad: $e');
    }
  }

  Future<void> deleteAd(String id) async {
    try {
      await _client.from('ads').delete().eq('id', id);
    } catch (e) {
      throw Exception('Failed to delete ad: $e');
    }
  }

  Future<String> uploadAdImage(File imageFile, String userId) async {
    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = 'ad_${timestamp}_${imageFile.path.split('/').last}';
      final filePath = '$userId/$fileName';

      await _client.storage.from('ads').upload(
            filePath,
            imageFile,
            fileOptions: const FileOptions(
              cacheControl: '3600',
              upsert: false,
            ),
          );

      final publicUrl = _client.storage.from('ads').getPublicUrl(filePath);

      return publicUrl;
    } catch (e) {
      throw Exception('Failed to upload image: $e');
    }
  }

  Future<void> deleteAdImage(String imageUrl) async {
    try {
      final uri = Uri.parse(imageUrl);
      final path = uri.pathSegments.skip(uri.pathSegments.indexOf('ads') + 1).join('/');

      await _client.storage.from('ads').remove([path]);
    } catch (e) {
      throw Exception('Failed to delete image: $e');
    }
  }

  Future<AdModel> approveAd(String adId) async {
    try {
      final userId = SupabaseConfig.currentUser?.id;
      if (userId == null) {
        throw Exception('User not authenticated');
      }

      final response = await _client
          .from('ads')
          .update({
            'status': 'approved',
            'approved_by': userId,
            'approved_at': DateTime.now().toIso8601String(),
          })
          .eq('id', adId)
          .select()
          .single();

      return AdModel.fromJson(response);
    } catch (e) {
      throw Exception('Failed to approve ad: $e');
    }
  }

  Future<AdModel> rejectAd(String adId, String reason) async {
    try {
      final response = await _client
          .from('ads')
          .update({
            'status': 'rejected',
            'rejection_reason': reason,
          })
          .eq('id', adId)
          .select()
          .single();

      return AdModel.fromJson(response);
    } catch (e) {
      throw Exception('Failed to reject ad: $e');
    }
  }

  Future<Map<String, dynamic>> getUserRole() async {
    try {
      final userId = SupabaseConfig.currentUser?.id;
      if (userId == null) {
        throw Exception('User not authenticated');
      }

      final response = await _client
          .from('user_profiles')
          .select('role, email')
          .eq('id', userId)
          .single();

      return response;
    } catch (e) {
      throw Exception('Failed to fetch user role: $e');
    }
  }
}
