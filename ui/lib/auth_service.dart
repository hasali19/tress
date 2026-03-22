import 'package:oidc/oidc.dart';
import 'package:oidc_default_store/oidc_default_store.dart';

final _redirectUri = Uri.parse('dev.hasali.tress://auth/callback');

class AuthService {
  late OidcUserManager _manager;

  Future<void> init({required Uri issuerUri, required String clientId}) async {
    _manager = OidcUserManager.lazy(
      discoveryDocumentUri: OidcUtils.getOpenIdConfigWellKnownUri(issuerUri),
      clientCredentials: OidcClientAuthentication.none(clientId: clientId),
      store: OidcDefaultStore(),
      settings: OidcUserManagerSettings(
        redirectUri: _redirectUri,
        scope: ['openid', 'profile'],
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
