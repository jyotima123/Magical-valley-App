import 'package:ads_admin_panel/config/supabase_config.dart';
import 'package:ads_admin_panel/models/ad_size_model.dart';

class AdSizeService {
  final _supabase = SupabaseConfig.client;

  Future<List<AdSizeModel>> getAdSizes() async {
    try {
      final response = await _supabase
          .from('ad_sizes')
          .select()
          .eq('is_active', true)
          .order('display_order', ascending: true)
          .order('name', ascending: true);

      return (response as List)
          .map((json) => AdSizeModel.fromJson(json))
          .toList();
    } catch (e) {
      throw Exception('Failed to fetch ad sizes: $e');
    }
  }

  Future<AdSizeModel?> getAdSizeById(String id) async {
    try {
      final response = await _supabase
          .from('ad_sizes')
          .select()
          .eq('id', id)
          .single();

      return AdSizeModel.fromJson(response);
    } catch (e) {
      throw Exception('Failed to fetch ad size: $e');
    }
  }
}
