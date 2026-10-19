import 'package:flutter_test/flutter_test.dart';
import 'package:mango_apk_studio/core/validators.dart';

void main() {
  test('package name validation', () {
    expect(isValidPackageName('com.mango.lens'), isTrue);
    expect(isValidPackageName('com.mango_app.v2'), isTrue);
    expect(isValidPackageName('mango'), isFalse);
    expect(isValidPackageName('Com.Mango.Lens'), isFalse);
    expect(isValidPackageName('com.1mango.lens'), isFalse);
    expect(isValidPackageName('com.class.lens'), isFalse);
    expect(isValidPackageName('com..lens'), isFalse);
  });

  test('version code validation', () {
    expect(isValidVersionCode('1'), isTrue);
    expect(isValidVersionCode('12'), isTrue);
    expect(isValidVersionCode('0'), isFalse);
    expect(isValidVersionCode('-3'), isFalse);
    expect(isValidVersionCode('abc'), isFalse);
    expect(isValidVersionCode('2100000001'), isFalse);
  });

  test('version name and output name', () {
    expect(isValidVersionName('1.2.0'), isTrue);
    expect(isValidVersionName('1.2.0; rm -rf /'), isFalse);
    expect(isValidOutputName('MangoLens.apk'), isTrue);
    expect(isValidOutputName('../x.apk'), isFalse);
    expect(isValidOutputName('x.zip'), isFalse);
  });

  test('zip path traversal detection', () {
    expect(isSafeZipPath('lib/main.dart'), isTrue);
    expect(isSafeZipPath('../evil.sh'), isFalse);
    expect(isSafeZipPath('a/../../evil'), isFalse);
    expect(isSafeZipPath('/etc/passwd'), isFalse);
    expect(isSafeZipPath('C:\\Windows\\x'), isFalse);
    expect(isSafeZipPath('a\\..\\b'), isFalse);
  });
}
