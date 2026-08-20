/// Secure in-memory store for sensitive auth credentials passed between screens.
/// Avoids passing passwords through GoRouter extras.
class AuthCredentials {
  AuthCredentials._();
  static String? password;
  static String? authTicket;
  static String? pollSecret;

  static void clear() {
    password = null;
    authTicket = null;
    pollSecret = null;
  }
}
