/// Generic mini-app requests are read-only. Mutations use dedicated UI bridges.
bool isMiniAppApiRequestAllowed(String path, String method) {
  if (method.toUpperCase() != 'GET' ||
      !path.startsWith('/') ||
      path.startsWith('//') ||
      path.contains(RegExp(r'[%\\#\s]')))
    return false;
  final uri = Uri.tryParse(path);
  if (uri == null ||
      uri.hasScheme ||
      uri.hasAuthority ||
      path.split('?').first.split('/').any((s) => s == '.' || s == '..')) {
    return false;
  }
  return const {
        '/api/miniapp/context',
        '/api/miniapp/wallet',
        '/api/stickers/packs',
        '/api/stickers/search',
        '/api/stickers/my-packs',
      }.contains(uri.path) ||
      RegExp(r'^/api/stickers/packs/[A-Za-z0-9_-]+$').hasMatch(uri.path);
}
