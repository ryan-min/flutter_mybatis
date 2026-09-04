/// Removal of SQL comments from mapper text.
///
/// This runs while parsing, on each XML text node, **before** the node is
/// trimmed and before sibling nodes are joined. Doing it later does not work:
/// once the newline after a `-- note` is gone, the comment swallows whatever
/// followed it — including a `<where>` element, which turns a guarded UPDATE
/// into one that touches every row.
library;

const Map<String, String> _closers = {"'": "'", '"': '"', '`': '`', '[': ']'};

/// Strips `--` line comments and `/* ... */` block comments from [sql].
///
/// Quoted strings and quoted identifiers are left alone, so `'--not a comment'`
/// survives intact. A removed comment leaves a newline behind (line comments)
/// or a space (block comments), so tokens on either side stay separated.
String stripSqlComments(String sql) {
  if (!sql.contains('--') && !sql.contains('/*')) return sql;

  final out = StringBuffer();
  String? closer; // set while inside a literal or quoted identifier

  for (var i = 0; i < sql.length; i++) {
    final c = sql[i];

    if (closer != null) {
      out.write(c);
      if (c == closer) closer = null;
      continue;
    }

    if (c == '-' && i + 1 < sql.length && sql[i + 1] == '-') {
      while (i < sql.length && sql[i] != '\n') {
        i++;
      }
      out.write('\n'); // keep the line break the comment was hiding
      continue;
    }

    if (c == '/' && i + 1 < sql.length && sql[i + 1] == '*') {
      final end = sql.indexOf('*/', i + 2);
      i = end == -1 ? sql.length : end + 1;
      out.write(' ');
      continue;
    }

    if (_closers.containsKey(c)) {
      out.write(c);
      closer = _closers[c];
      continue;
    }

    out.write(c);
  }

  return out.toString();
}
