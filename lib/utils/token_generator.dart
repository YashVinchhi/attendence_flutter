import 'dart:math';

class TokenGenerator {
  static const String _alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';

  static String generate(int length) {
    if (length <= 0) return '';
    final rnd = Random.secure();
    final chars = List.generate(length, (_) => _alphabet[rnd.nextInt(_alphabet.length)]);
    return chars.join();
  }
}

