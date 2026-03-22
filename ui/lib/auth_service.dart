import 'package:oidc/oidc.dart';
import 'package:oidc_default_store/oidc_default_store.dart';

class AuthService {
  late OidcUserManager _manager;

  Future<void> init({
    required String issuerUrl,
    required String clientId,
  }) async {
    _manager = OidcUserManager.lazy(
      discoveryDocumentUri: OidcUtils.getOpenIdConfigWellKnownUri(
        Uri.parse(issuerUrl),
      ),
      clientCredentials: OidcClientAuthentication.none(clientId: clientId),
      store: OidcDefaultStore(),
      settings: OidcUserManagerSettings(
        redirectUri: Uri.parse('dev.hasali.tress://auth/callback'),
        scopes: ['openid', 'profile'],
      ),
    );

    await _manager.init();
  }

  bool get isAuthenticated => _manager.currentUser != null;

  String? get idToken => _manager.currentUser?.token.idToken;

  Stream<OidcUser?> get userChanges => _manager.userChanges();

  Future<void> login() async {
    await _manager.loginAuthorizationCodeFlow();
  }

  Future<void> logout() async {
    await _manager.logout();
  }
}
