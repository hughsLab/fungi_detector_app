import 'package:html/parser.dart' as html_parser;

String cleanWikipediaHtml(String rawHtml) {
  if (rawHtml.trim().isEmpty) return '';
  final fragment = html_parser.parseFragment(rawHtml);
  for (final selector in const [
    'script',
    'style',
    'noscript',
    'table',
    'sup.reference',
    '.mw-editsection',
    '.navbox',
    '.metadata',
    '.noprint',
  ]) {
    for (final element in fragment.querySelectorAll(selector)) {
      element.remove();
    }
  }

  final blocks = <String>[];
  for (final element in fragment.querySelectorAll('p, li')) {
    final text = _cleanText(element.text);
    if (text.isNotEmpty && !blocks.contains(text)) blocks.add(text);
  }
  if (blocks.isNotEmpty) return blocks.join('\n\n');
  return _cleanText(fragment.text ?? '');
}

String cleanWikipediaPlainText(String rawText) {
  if (rawText.trim().isEmpty) return '';
  if (rawText.contains('<') && rawText.contains('>')) {
    return cleanWikipediaHtml(rawText);
  }
  return _cleanText(rawText);
}

String cleanWikipediaMetadataValue(dynamic value) {
  if (value is Map) {
    return cleanWikipediaHtml(value['value']?.toString() ?? '');
  }
  return cleanWikipediaHtml(value?.toString() ?? '');
}

String _cleanText(String value) => value
    .replaceAll(RegExp(r'\[\s*\d+(?:\s*,\s*\d+)*\s*\]'), '')
    .replaceAll(
      RegExp(r'\[\s*(?:citation needed|edit)\s*\]', caseSensitive: false),
      '',
    )
    .replaceAll(RegExp(r'[ \t]+'), ' ')
    .replaceAll(RegExp(r' *\n *'), '\n')
    .replaceAll(RegExp(r'\n{3,}'), '\n\n')
    .trim();
