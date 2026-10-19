const _reserved = {
  'abstract', 'assert', 'boolean', 'break', 'byte', 'case', 'catch', 'char',
  'class', 'const', 'continue', 'default', 'do', 'double', 'else', 'enum',
  'extends', 'final', 'finally', 'float', 'for', 'goto', 'if', 'implements',
  'import', 'instanceof', 'int', 'interface', 'long', 'native', 'new',
  'package', 'private', 'protected', 'public', 'return', 'short', 'static',
  'strictfp', 'super', 'switch', 'synchronized', 'this', 'throw', 'throws',
  'transient', 'try', 'void', 'volatile', 'while', 'true', 'false', 'null',
};

final _pkg = RegExp(r'^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$');

bool isValidPackageName(String s) {
  if (s.length > 100 || !_pkg.hasMatch(s)) return false;
  return !s.split('.').any(_reserved.contains);
}

bool isValidVersionCode(String s) {
  final n = int.tryParse(s);
  return n != null && n >= 1 && n <= 2100000000;
}

bool isValidVersionName(String s) =>
    RegExp(r'^[0-9A-Za-z][0-9A-Za-z._-]{0,31}$').hasMatch(s);

bool isValidOutputName(String s) =>
    RegExp(r'^[A-Za-z0-9._-]{1,64}\.apk$').hasMatch(s);

bool isValidAppName(String s) {
  final t = s.trim();
  return t.isNotEmpty && t.length <= 60 && !RegExp(r'[<>"\x00-\x1F]').hasMatch(t);
}

/// True when a ZIP entry path stays inside the extraction folder.
bool isSafeZipPath(String path) {
  final p = path.replaceAll('\\', '/');
  if (p.isEmpty || p.contains('\u0000')) return false;
  if (p.startsWith('/')) return false;
  if (RegExp(r'^[A-Za-z]:').hasMatch(p)) return false;
  return !p.split('/').contains('..');
}
