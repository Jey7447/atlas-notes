import 'package:supabase_flutter/supabase_flutter.dart';

class AtlasCloud {
  AtlasCloud._();

  static bool get configured =>
      Supabase.instance.isInitialized;

  static SupabaseClient? get client =>
      configured ? Supabase.instance.client : null;

  static Future<void> initialize() async {
    const url = String.fromEnvironment('SUPABASE_URL');
    const anonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

    if (url.isEmpty || anonKey.isEmpty) return;

    await Supabase.initialize(
      url: url,
      anonKey: anonKey,
      debug: false,
    );
  }
}
