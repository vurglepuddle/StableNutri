import 'package:get_it/get_it.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Food lookup is optional. A local-only build must not initialize an SDK
/// against the example configuration or start an authentication refresh timer.
void registerFoodBackend(
  GetIt services, {
  required String url,
  required String anonKey,
}) {
  final endpoint = Uri.tryParse(url.trim());
  final key = anonKey.trim();
  if (endpoint == null ||
      !{'http', 'https'}.contains(endpoint.scheme) ||
      endpoint.host.isEmpty ||
      endpoint.host.toUpperCase() == 'PROJECT_URL' ||
      key.isEmpty ||
      {
        'ANON_KEY',
        'YOUR_ANON_KEY',
        'YOUR-ANON-KEY',
      }.contains(key.toUpperCase())) {
    return;
  }

  final baseUrl = endpoint.toString().replaceFirst(RegExp(r'/+$'), '');
  services.registerLazySingleton<SupabaseClient>(
    () => SupabaseClient(
      baseUrl,
      key,
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    ),
    dispose: (client) => client.dispose(),
  );
}
