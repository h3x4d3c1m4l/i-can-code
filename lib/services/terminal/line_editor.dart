/// The line discipline that sits between the keyboard and the interpreter.
///
/// A terminal echoes what you type, lets you fix it, and hands over a whole line
/// at once. On a real machine the kernel's tty driver does that, not the program
/// on the other end — and CPython's basic REPL counts on it, which is why it
/// does none of it itself. Nothing here is a stand-in for Python: it is the half
/// of a terminal that Python never had.
///
/// The keys are GNU readline's, in its default emacs mode, because that is what
/// `python3` in a terminal answers to: the basic REPL reads its lines through
/// readline wherever there is one. The wasm32-wasi build has none, so its
/// editing half lives here, history included. Recalling a line re-sends it as
/// if it had been typed, so the interpreter cannot tell the difference.
///
/// Tab is the half that cannot be here. Readline completes a name with it, and
/// that needs the interpreter, which is parked in a read. What is left is what
/// rlcompleter does where there is no name to complete: insert a tab.
///
/// ## How the line is redrawn
///
/// An edit in the middle of a line means repainting everything after the cursor,
/// and the prompt to the left MUST survive it. So the position where input
/// began is saved with DECSC (`ESC 7`) and every repaint starts by restoring it
/// with DECRC (`ESC 8`), erasing to the end of the screen, and writing the line
/// out again. Placing the cursor afterwards is done by restoring the anchor once
/// more and re-writing only the text before it, rather than by counting cursor
/// movements — text advances the cursor across a line wrap and `CSI D` does not.
///
/// The anchor is a screen position, so it goes stale if the screen scrolls under
/// it. That needs a line long enough to scroll the view while it is being typed;
/// the next prompt re-anchors and puts it right.
class LineEditor {

  /// Writes to the terminal. Everything this class shows the student goes
  /// through here, and nothing else writes to the terminal while a line is being
  /// edited without calling [releaseAnchor] first.
  final void Function(String data) echo;

  /// Hands a finished line to the interpreter, newline included.
  final void Function(String line) submit;

  /// Ctrl-D on an empty line: end of input.
  final void Function() endOfInput;

  /// What the interpreter wrote on the line the input starts on. Ctrl-L and
  /// Ctrl-C write it back, since the interpreter never sees either key.
  final String Function() prompt;

  /// Ctrl-C where throwing the line away would not help. A line discipline
  /// cannot interrupt anything — there is no signal to send — so this is the
  /// caller's problem, and the caller MUST decide what it means.
  final void Function() interrupt;

  /// Whether throwing away the typed line is enough to undo Ctrl-C.
  ///
  /// True at a fresh prompt. False while the interpreter is busy, and false
  /// again while it is part way through a block: clearing the line there leaves
  /// the block open, and only the caller can get out of that.
  final bool Function() canDiscardLine;

  LineEditor({
    required this.echo,
    required this.submit,
    required this.endOfInput,
    required this.prompt,
    required this.interrupt,
    required this.canDiscardLine,
  });

  String _line = '';
  int _cursor = 0;
  bool _anchored = false;

  final List<String> _history = <String>[];

  /// Where in [_history] the student is, counting from the oldest. Equal to the
  /// length means "not in the history, editing a fresh line".
  int _historyIndex = 0;

  /// What was being typed before the student started walking back through the
  /// history, so that walking forward again returns it.
  String _draft = '';

  /// The start of an escape sequence whose remaining characters have not
  /// arrived. Held rather than dropped: dropping it made the rest of the
  /// sequence arrive as ordinary text and put `[D` in the line.
  String _partialEscape = '';

  /// The line as it currently stands. For tests, and for a caller that wants to
  /// know whether anything would be lost.
  String get line => _line;

  /// Drops the saved screen position.
  ///
  /// MUST be called by whoever writes interpreter output to the terminal: that
  /// moves the cursor, which leaves the anchor pointing at the wrong place. The
  /// next keystroke anchors again where the cursor now is.
  void releaseAnchor() => _anchored = false;

  /// Longest escape sequence worth waiting for. A keyboard produces nothing
  /// near this; anything longer is a stream that has gone wrong, and holding it
  /// forever would swallow everything typed afterwards.
  static const int _maxEscapeLength = 32;

  /// Where readline's Python completer starts a new word, as `Modules/readline.c`
  /// sets it. Tab inserts a tab after one of these, or at the start of a line.
  static const String _wordBreaks = ' \t\n`~!@#\$%^&*()-=+[{]}\\|;:\'",<>/?';

  /// What readline's word movements count as a word: letters and digits.
  static final RegExp _wordCharacter = RegExp(r'[\p{L}\p{N}]', unicode: true);

  /// Feeds keystrokes in, exactly as the terminal reports them.
  ///
  /// [data] is a stream: it may hold several keys, a pasted block, or the
  /// beginning of an escape sequence whose rest is still to come. A partial
  /// sequence is held until it completes, and a complete one that means nothing
  /// here is dropped rather than typed.
  void write(String data) {
    final input = _partialEscape.isEmpty ? data : _partialEscape + data;
    _partialEscape = '';

    var index = 0;
    while (index < input.length) {
      final char = input[index];

      if (char == '\x1b') {
        final consumed = _handleEscape(input, index);
        if (consumed == 0) {
          final tail = input.substring(index);
          if (tail.length <= _maxEscapeLength) _partialEscape = tail;
          return;
        }
        index += consumed;
        continue;
      }

      index += 1;
      switch (char) {
        case '\r':
        case '\n':
          _submitLine();
        case '\x7f':
        case '\b':
          _backspace();
        case '\x03':
          _cancelLine();
        case '\x04':
          _line.isEmpty ? endOfInput() : _delete();
        case '\x01':
          _moveTo(0);
        case '\x05':
          _moveTo(_line.length);
        case '\x15':
          _replaceLine(_line.substring(_cursor), cursor: 0);
        case '\x0b':
          _replaceLine(_line.substring(0, _cursor), cursor: _cursor);
        case '\x17':
          _deleteWord();
        case '\x0c':
          // Clear screen, then put the prompt and the line back under a fresh
          // anchor.
          echo('\x1b[2J\x1b[H${prompt()}');
          _anchored = false;
          _redraw();
        case '\t':
          if (_cursor == 0 || _wordBreaks.contains(_line[_cursor - 1])) _insert('\t');
        default:
          // Anything else printable, including a pasted block's contents.
          if (char.codeUnitAt(0) >= 0x20) _insert(char);
      }
    }
  }

  /// Returns how many characters of [data] the sequence at [start] used, or 0
  /// when it is not complete yet.
  int _handleEscape(String data, int start) {
    // CSI: ESC [ params final. The only ones a keyboard produces are cursor
    // keys, Home, End and Delete.
    if (start + 1 >= data.length) return 0;
    if (data[start + 1] != '[') {
      switch (data[start + 1]) {
        // ESC O A and friends, sent by some terminals in application mode. Two
        // more characters, and the last one is what matters.
        case 'O':
          if (start + 2 >= data.length) return 0;
          _cursorKey(data[start + 2]);
          return 3;
        // Meta-B and Meta-F. Option+arrow on a Mac arrives as these.
        case 'b' || 'B':
          _moveTo(_previousWordStart());
        case 'f' || 'F':
          _moveTo(_nextWordEnd());
      }
      return 2;
    }

    var index = start + 2;
    while (index < data.length && !_isFinalByte(data[index])) {
      index += 1;
    }
    if (index >= data.length) return 0;

    final parameters = data.substring(start + 2, index);
    final finalByte = data[index];

    if (finalByte == '~') {
      if (parameters == '3') _delete();
    } else {
      _cursorKey(finalByte, byWord: _isWordModifier(parameters));
    }
    return index - start + 1;
  }

  /// Ctrl or Alt held with an arrow, as in `CSI 1;5C`. Readline setups move a
  /// word at a time for both.
  static bool _isWordModifier(String parameters) => parameters.endsWith(';3') || parameters.endsWith(';5');

  static bool _isFinalByte(String char) {
    final code = char.codeUnitAt(0);
    return code >= 0x40 && code <= 0x7e;
  }

  void _cursorKey(String finalByte, {bool byWord = false}) {
    switch (finalByte) {
      case 'A':
        _recall(-1);
      case 'B':
        _recall(1);
      case 'C' when byWord:
        _moveTo(_nextWordEnd());
      case 'D' when byWord:
        _moveTo(_previousWordStart());
      case 'C':
        if (_cursor < _line.length) _moveTo(_cursor + 1);
      case 'D':
        if (_cursor > 0) _moveTo(_cursor - 1);
      case 'H':
        _moveTo(0);
      case 'F':
        _moveTo(_line.length);
    }
  }

  void _submitLine() {
    final line = _line;
    echo('\r\n');
    _anchored = false;

    // A line only enters the history if there is something to recall, and a
    // repeat of the one before it is not.
    if (line.trim().isNotEmpty && (_history.isEmpty || _history.last != line)) {
      _history.add(line);
    }
    _historyIndex = _history.length;
    _draft = '';
    _line = '';
    _cursor = 0;

    submit('$line\n');
  }

  /// Ctrl-C. At a fresh prompt this throws away what has been typed, which is
  /// all a line discipline can do — there is no signal to raise, so the
  /// interpreter never learns that anything happened and no `KeyboardInterrupt`
  /// is printed. Claiming one would be a lie about what Python did.
  void _cancelLine() {
    if (!canDiscardLine()) {
      interrupt();
      return;
    }
    // The interpreter never saw the line, so it prints no new prompt.
    echo('^C\r\n${prompt()}');
    _anchored = false;
    _line = '';
    _cursor = 0;
    _historyIndex = _history.length;
    _draft = '';
    _redraw();
  }

  void _insert(String text) {
    _line = _line.substring(0, _cursor) + text + _line.substring(_cursor);
    _cursor += text.length;
    _redraw();
  }

  void _backspace() {
    if (_cursor == 0) return;
    _line = _line.substring(0, _cursor - 1) + _line.substring(_cursor);
    _cursor -= 1;
    _redraw();
  }

  void _delete() {
    if (_cursor >= _line.length) return;
    _line = _line.substring(0, _cursor) + _line.substring(_cursor + 1);
    _redraw();
  }

  void _deleteWord() {
    if (_cursor == 0) return;
    var start = _cursor;
    while (start > 0 && _line[start - 1] == ' ') {
      start -= 1;
    }
    while (start > 0 && _line[start - 1] != ' ') {
      start -= 1;
    }
    _line = _line.substring(0, start) + _line.substring(_cursor);
    _cursor = start;
    _redraw();
  }

  /// Readline's `forward-word`: past any gap, then to the end of the word.
  int _nextWordEnd() {
    var index = _cursor;
    while (index < _line.length && !_isWordCharacter(index)) {
      index += 1;
    }
    while (index < _line.length && _isWordCharacter(index)) {
      index += 1;
    }
    return index;
  }

  /// Readline's `backward-word`: back past any gap, then to the start of the
  /// word.
  int _previousWordStart() {
    var index = _cursor;
    while (index > 0 && !_isWordCharacter(index - 1)) {
      index -= 1;
    }
    while (index > 0 && _isWordCharacter(index - 1)) {
      index -= 1;
    }
    return index;
  }

  bool _isWordCharacter(int index) => _wordCharacter.hasMatch(_line[index]);

  void _moveTo(int cursor) {
    _cursor = cursor.clamp(0, _line.length);
    _redraw();
  }

  void _replaceLine(String line, {required int cursor}) {
    _line = line;
    _cursor = cursor.clamp(0, line.length);
    _redraw();
  }

  /// Walks the history by [delta]. Stepping forward past the newest entry
  /// returns whatever was being typed when the walk began.
  void _recall(int delta) {
    if (_history.isEmpty) return;
    if (_historyIndex == _history.length) _draft = _line;

    final next = (_historyIndex + delta).clamp(0, _history.length);
    if (next == _historyIndex) return;

    _historyIndex = next;
    final line = next == _history.length ? _draft : _history[next];
    _replaceLine(line, cursor: line.length);
  }

  void _redraw() {
    if (!_anchored) {
      echo('\x1b7');
      _anchored = true;
    }
    // Restore, wipe, write. Then restore again and walk forward with real text,
    // because that is the only cursor move that survives a line wrap.
    echo('\x1b8\x1b[0J$_line\x1b8${_line.substring(0, _cursor)}');
  }

}

/// Translates the interpreter's line endings for a screen.
///
/// A program writing to a real terminal has its `\n` turned into `\r\n` by the
/// tty driver — ONLCR. Nothing does that here, so without it every line after
/// the first would start under the end of the one before, stepping across the
/// screen. CPython emits a bare `\n`; a `\r\n` that is already there MUST NOT be
/// doubled, which is what the lookbehind is for.
String cookOutput(String text) => text.replaceAll(_bareNewline, '\r\n');

final RegExp _bareNewline = RegExp(r'(?<!\r)\n');
