import 'package:supabase_flutter/supabase_flutter.dart';

class AtlasCloud {
  AtlasCloud._();

  static bool _initialized = false;

  static bool get configured => _initialized;

  static SupabaseClient? get client =>
      _initialized ? Supabase.instance.client : null;

  static Future<void> initialize() async {
    const url = String.fromEnvironment('SUPABASE_URL');
    const publishableKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

    if (url.isEmpty || publishableKey.isEmpty) return;

    await Supabase.initialize(
      url: url,
      publishableKey: publishableKey,
      debug: false,
    );
    _initialized = true;
  }
}
