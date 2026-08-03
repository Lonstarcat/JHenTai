bool hasDownloadSearchOperators(String query) {
  return query.contains('|') || RegExp(r'(^|\s)[+-]').hasMatch(query);
}

bool matchesDownloadSimpleQuery({
  required Iterable<String> fields,
  required String query,
  required bool caseSensitive,
}) {
  String normalizedQuery = _normalize(query, caseSensitive);
  List<String> normalizedFields =
      fields.map((field) => _normalize(field, caseSensitive)).toList();

  if (!hasDownloadSearchOperators(normalizedQuery)) {
    return normalizedFields.any((field) => field.contains(normalizedQuery));
  }

  String searchableText = normalizedFields.join('\n');
  for (String token in normalizedQuery.trim().split(RegExp(r'\s+'))) {
    if (token.isEmpty) {
      continue;
    }

    bool excluded = token.startsWith('-');
    String condition =
        token.startsWith('+') || excluded ? token.substring(1) : token;
    List<String> alternatives =
        condition.split('|').where((term) => term.isNotEmpty).toList();
    if (alternatives.isEmpty) {
      continue;
    }

    bool hasMatch = alternatives.any(searchableText.contains);
    if (excluded ? hasMatch : !hasMatch) {
      return false;
    }
  }

  return true;
}

RegExp buildDownloadSearchRegExp({
  required String query,
  required bool caseSensitive,
}) {
  return RegExp(query, dotAll: true, caseSensitive: caseSensitive);
}

String _normalize(String value, bool caseSensitive) {
  return caseSensitive ? value : value.toLowerCase();
}
