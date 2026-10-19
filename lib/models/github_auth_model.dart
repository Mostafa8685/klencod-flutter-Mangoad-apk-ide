enum GithubAuthStatus { disconnected, starting, pending, connected, expired, denied, error }

/// "Connected" is reachable ONLY through a server reply saying `connected`.
GithubAuthStatus nextGithubStatus(GithubAuthStatus current, String serverStatus) {
  switch (serverStatus) {
    case 'pending':
    case 'slow_down':
      return GithubAuthStatus.pending;
    case 'connected':
      return GithubAuthStatus.connected;
    case 'expired':
      return GithubAuthStatus.expired;
    case 'denied':
      return GithubAuthStatus.denied;
    case 'none':
      return GithubAuthStatus.disconnected;
    default:
      return GithubAuthStatus.error;
  }
}

class DeviceCode {
  final String userCode;
  final String verificationUri;
  final int expiresIn;
  final int interval;
  const DeviceCode(this.userCode, this.verificationUri, this.expiresIn, this.interval);

  factory DeviceCode.fromJson(Map<String, dynamic> j) => DeviceCode(
        j['user_code'] as String,
        j['verification_uri'] as String,
        (j['expires_in'] as num).toInt(),
        (j['interval'] as num? ?? 5).toInt(),
      );
}
