/// Whether [text] holds an unpaired UTF-16 surrogate.
///
/// UTF-8 cannot encode such a code unit: `utf8.encode` replaces it with
/// U+FFFD, so the bytes written for [text] would read back as another string.
bool hasUnpairedSurrogate(String text) {
  for (var index = 0; index < text.length; index++) {
    final unit = text.codeUnitAt(index);
    if ((unit & 0xF800) != 0xD800) {
      continue;
    }
    if (unit <= 0xDBFF &&
        index + 1 < text.length &&
        (text.codeUnitAt(index + 1) & 0xFC00) == 0xDC00) {
      index++;
      continue;
    }
    return true;
  }
  return false;
}
