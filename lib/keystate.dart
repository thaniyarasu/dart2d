library keystate;

import 'package:dart2d/worlds/world.dart';

class KeyState {
  World world;
  bool debug = false;
  
  Map<int, bool> keysDown = new Map<int, bool>();
  Map<int, List<dynamic>> _listeners = new Map<int, List<dynamic>>();
  List<dynamic> _genericListeners = new List();
  
  KeyState(this.world);
  
  void onKeyDown(var /*KeyboardEvent*/ e) {
    if (e.keyCode == KeyCodeDart.F2) {
      debug = !debug;
    }
    if (e.keyCode == KeyCodeDart.F4) {
      world.freeze = !world.freeze;
    }
    if (!keysDown.containsKey(e.keyCode)) {
      // If this a newly pushed key, send it to the network right away.
      if (world != null) {
        world.network.maybeSendLocalKeyStateUpdate();
      }
      if (_listeners.containsKey(e.keyCode)) {
        _listeners[e.keyCode].forEach((f) { f(); });
      }
      _genericListeners.forEach((f) { f(e.keyCode); });
    }
    keysDown[e.keyCode] = true;
  }
  
  void onKeyUp(var /*KeyboardEvent*/ e) {
    keysDown.remove(e.keyCode);
  }
  
  bool keyIsDown(num key) {
    return keysDown.containsKey(key);
  }

  void setEnabledKeys(Map<String, bool> keysDown) {
    this.keysDown = {};
    for (String key in keysDown.keys) {
      this.keysDown[int.parse(key)] = true;
    }
  }

  Map<String, bool> getEnabledState() {
    Map<String, bool> keys = {};
    for (int key in keysDown.keys) {
      if (keysDown[key]) {
        keys[key.toString()] = true;
      }
    }
    return keys;
  }
  
  registerListener(int key, dynamic f) {
    if (!_listeners.containsKey(key)) {
      _listeners[key] = new List<dynamic>();
    }
    List<dynamic> listeners = _listeners[key];
    listeners.add(f);
  }
  
  registerGenericListener(dynamic f) {
    _genericListeners.add(f);
  }
}

/**
 * Copy paste of KeyCode from the Dart HTML package.
 */
abstract class KeyCodeDart {
  // These constant names were borrowed from Closure's Keycode enumeration
  // class.
  // http://closure-library.googlecode.com/svn/docs/closure_goog_events_keycodes.js.source.html
  static const int WIN_KEY_FF_LINUX = 0;
  static const int MAC_ENTER = 3;
  static const int BACKSPACE = 8;
  static const int TAB = 9;
  /** NUM_CENTER is also NUMLOCK for FF and Safari on Mac. */
  static const int NUM_CENTER = 12;
  static const int ENTER = 13;
  static const int SHIFT = 16;
  static const int CTRL = 17;
  static const int ALT = 18;
  static const int PAUSE = 19;
  static const int CAPS_LOCK = 20;
  static const int ESC = 27;
  static const int SPACE = 32;
  static const int PAGE_UP = 33;
  static const int PAGE_DOWN = 34;
  static const int END = 35;
  static const int HOME = 36;
  static const int LEFT = 37;
  static const int UP = 38;
  static const int RIGHT = 39;
  static const int DOWN = 40;
  static const int NUM_NORTH_EAST = 33;
  static const int NUM_SOUTH_EAST = 34;
  static const int NUM_SOUTH_WEST = 35;
  static const int NUM_NORTH_WEST = 36;
  static const int NUM_WEST = 37;
  static const int NUM_NORTH = 38;
  static const int NUM_EAST = 39;
  static const int NUM_SOUTH = 40;
  static const int PRINT_SCREEN = 44;
  static const int INSERT = 45;
  static const int NUM_INSERT = 45;
  static const int DELETE = 46;
  static const int NUM_DELETE = 46;
  static const int ZERO = 48;
  static const int ONE = 49;
  static const int TWO = 50;
  static const int THREE = 51;
  static const int FOUR = 52;
  static const int FIVE = 53;
  static const int SIX = 54;
  static const int SEVEN = 55;
  static const int EIGHT = 56;
  static const int NINE = 57;
  static const int FF_SEMICOLON = 59;
  static const int FF_EQUALS = 61;
  /**
   * CAUTION: The question mark is for US-keyboard layouts. It varies
   * for other locales and keyboard layouts.
   */
  static const int QUESTION_MARK = 63;
  static const int A = 65;
  static const int B = 66;
  static const int C = 67;
  static const int D = 68;
  static const int E = 69;
  static const int F = 70;
  static const int G = 71;
  static const int H = 72;
  static const int I = 73;
  static const int J = 74;
  static const int K = 75;
  static const int L = 76;
  static const int M = 77;
  static const int N = 78;
  static const int O = 79;
  static const int P = 80;
  static const int Q = 81;
  static const int R = 82;
  static const int S = 83;
  static const int T = 84;
  static const int U = 85;
  static const int V = 86;
  static const int W = 87;
  static const int X = 88;
  static const int Y = 89;
  static const int Z = 90;
  static const int META = 91;
  static const int WIN_KEY_LEFT = 91;
  static const int WIN_KEY_RIGHT = 92;
  static const int CONTEXT_MENU = 93;
  static const int NUM_ZERO = 96;
  static const int NUM_ONE = 97;
  static const int NUM_TWO = 98;
  static const int NUM_THREE = 99;
  static const int NUM_FOUR = 100;
  static const int NUM_FIVE = 101;
  static const int NUM_SIX = 102;
  static const int NUM_SEVEN = 103;
  static const int NUM_EIGHT = 104;
  static const int NUM_NINE = 105;
  static const int NUM_MULTIPLY = 106;
  static const int NUM_PLUS = 107;
  static const int NUM_MINUS = 109;
  static const int NUM_PERIOD = 110;
  static const int NUM_DIVISION = 111;
  static const int F1 = 112;
  static const int F2 = 113;
  static const int F3 = 114;
  static const int F4 = 115;
  static const int F5 = 116;
  static const int F6 = 117;
  static const int F7 = 118;
  static const int F8 = 119;
  static const int F9 = 120;
  static const int F10 = 121;
  static const int F11 = 122;
  static const int F12 = 123;
  static const int NUMLOCK = 144;
  static const int SCROLL_LOCK = 145;
}