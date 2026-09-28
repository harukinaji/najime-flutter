import '../lib/data/mini_app_api_policy.dart';

void main() {
  final cases = <(String, String, bool)>[
    ('/api/miniapp/context', 'GET', true),
    ('/api/miniapp/wallet', 'GET', true),
    ('/api/stickers/packs/pack-123?size=10', 'GET', true),
    ('/api/messages/search', 'GET', false),
    ('/api/messages/victim', 'DELETE', false),
    ('/api/me', 'GET', false),
    ('/api/miniapp/../messages/search', 'GET', false),
    ('/api/miniapp/%2e%2e/messages/search', 'GET', false),
    ('/api/stickers/packs/x/../../messages', 'GET', false),
    ('//attacker.invalid/api/stickers/packs', 'GET', false),
    ('/api/stickers/packs', 'DELETE', false),
    ('/api/miniapp/wallet/transfer', 'POST', false),
    ('/api/stickers/packs#ignored', 'GET', false),
    ('/api/stickers/packs\\..\\messages', 'GET', false),
  ];
  for (final (path, method, expected) in cases) {
    if (isMiniAppApiRequestAllowed(path, method) != expected) {
      throw StateError('Unexpected mini-app permission: $method $path');
    }
  }
  print('${cases.length} mini-app API policy checks passed');
}
