library dart2d;

import 'dart:html';
import 'world.dart';

class KeyState {
  World world;
  bool debug = false;
  
  Map<int, bool> keysDown = new Map<int, bool>();
  
  KeyState(this.world);
  
  void onKeyDown(KeyboardEvent e) {
    if (e.keyCode == KeyCode.F2) {
      debug = !debug;
    }
    // If this a newly pushed key, send it to the network right away.
    if (world != null && !keysDown.containsKey(e.keyCode)) {
      world.network.maybeSendLocalKeyStateUpdate();
    }
    keysDown[e.keyCode] = true;
  }
  
  void onKeyUp(KeyboardEvent e) {
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
}