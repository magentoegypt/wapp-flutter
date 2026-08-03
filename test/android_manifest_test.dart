import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The release manifest must declare INTERNET.
///
/// This is not a style check. Flutter generates `android/app/src/debug/` and
/// `android/app/src/profile/` manifests that declare INTERNET so the tool can
/// reach a running app for hot reload — so **a debug build has network access
/// whether or not the main manifest asks for it, and a release build does
/// not**.
///
/// The failure that follows is total and silent in exactly the wrong
/// direction: every device test during development passes, then the release
/// build cannot open a single socket. Every request fails as a connection
/// error, so the only thing the app can say is "No connection. Check your
/// network and try again." — on a phone with working wifi, against a server
/// that is up. It shipped to Loadly six times before anyone tried to sign in
/// on one of those builds rather than on a debug build.
///
/// A unit test is the right place for it because the compiler cannot see the
/// manifest, the analyzer cannot see it, and no widget test exercises it.
void main() {
  test('the main manifest declares INTERNET', () {
    final File manifest =
        File('android/app/src/main/AndroidManifest.xml');
    expect(
      manifest.existsSync(),
      isTrue,
      reason: 'run from the package root',
    );

    final String xml = manifest.readAsStringSync();
    expect(
      xml.contains('android.permission.INTERNET'),
      isTrue,
      reason: 'Without this, release builds have no network at all. '
          'debug/ and profile/ declare it for hot reload, so the gap is '
          'invisible until a release build is installed.',
    );
  });

  test('the permissions the app actually needs are all present', () {
    final String xml =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();

    // Calling needs the microphone and the Bluetooth route; everything needs
    // the network. Listed together so a plugin removal cannot quietly take one
    // with it.
    for (final String p in <String>[
      'android.permission.INTERNET',
      'android.permission.RECORD_AUDIO',
      'android.permission.MODIFY_AUDIO_SETTINGS',
    ]) {
      expect(xml.contains(p), isTrue, reason: '$p is missing');
    }
  });
}
