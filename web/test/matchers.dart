library matchers;

import 'package:unittest/unittest.dart';
import 'dart:convert';
import '../world.dart';
import '../connection.dart';
import '../gamestate.dart';
import '../sprite.dart';

WorldSpriteMatcher hasSpriteWithNetworkId(int id) {
  return new WorldSpriteMatcher(id);
}

GameStateMatcher isGameStateOf(data) {
  return new GameStateMatcher(data);
}

WorldConnectionMatcher hasSpecifiedConnections(Map connections) {
  return new WorldConnectionMatcher(connections);
}

class GameStateMatcher extends Matcher {
  Map<int, String> _playersWithName;
  
  GameStateMatcher(this._playersWithName);

  bool matches(item, Map matchState) {
    GameState gameState = null;
    if (item is World) {
      gameState = (item as World).network.gameState;
    }
    if (item is GameState) {
      gameState = item;
    }
    if (gameState.playerInfo.length == _playersWithName.length) {
      for (int id in _playersWithName.keys) {
        bool hasMatch = false;
        for (PlayerInfo info in gameState.playerInfo) {
          if (info.spriteId == id && info.name == _playersWithName[id]) {
            hasMatch = true;
          }
        }
        if (!hasMatch) {
          return false;
        }
      }
    }
    return gameState.playerInfo.length == _playersWithName.length;
  }
  
  Description describe(Description description) {
    description.add("GameState of ${_playersWithName}");
  }
}

class WorldSpriteMatcher extends Matcher {
  int _networkId;
  int _imageIndex = null;
  WorldSpriteMatcher(this._networkId);

  WorldSpriteMatcher andSpriteId(int id) {
    _networkId = id;
    return this;
  }
  
  WorldSpriteMatcher andImageIndex(int index) {
    _imageIndex = index;
    return this;
  }

  bool matches(item, Map matchState) {
    if (item is World) {
      Sprite sprite = item.sprites[_networkId];
      if (sprite != null) {
        if (sprite.networkId == _networkId) {
          if (_imageIndex == null) {
            return true;
          } else {
            return sprite.imageIndex == _imageIndex;
          }
        }
      }
    }
    return false;
  }
  
  Description describeMismatch(item, Description mismatchDescription,
                               var matchState, bool verbose) {
    if (item is World) {
      if (!item.sprites.containsKey(_networkId)) {
        mismatchDescription.add("World sprites ${item.sprites} does not contain key ${_networkId}");
      }
    } else {
      mismatchDescription.add("Matched item must be World");
    }
  }
  Description describe(Description description) {
    description.add("World does not contain sprite with networkId ${_networkId}");    
  }
}

class MapKeysMatcher extends Matcher {
  List<String> _keys;
  MapKeysMatcher.containsKeys(this._keys);

  bool matches(item, Map matchState) {
    if (item == null) {
      throw new ArgumentError("Item can not be null");
    }
    Map data = null;
    if (item is String) {
      data = JSON.decode(item);
    } else if (item is Map) {
      data = item;
    }
    for (String key in _keys) {
      if (!data.containsKey(key)) {
        return false;
      }
    }
    return true;
  }

  Description describe(Description description) {
    description.add("Map/Json string not containing all keys ${_keys}");    
  }
}

class MapKeyMatcher extends Matcher {
  MapKeyMatcher.containsKey(this._key) {
    this._value = null;
  }
  MapKeyMatcher.containsKeyWithValue(this._key, this._value);
  final String _key;
  var _value;
  bool matches(item, Map matchState) {
    Map data = null;
    if (item is String) {
      data = JSON.decode(item);
    } else if (item is Map) {
      data = item;
    }
    bool containsKey = data != null && data.containsKey(_key);
    if (containsKey) {
      return _value == null ? true : data[_key] == _value;
    }
    return false;
  }
  Description describe(Description description) {
    if (_value == null) {
      description.add("Map/Json string not containing key ${_key}");
    } else {
      description.add("Map/Json string not containing key ${_key} with value ${_value}");
    }
  }
}

class WorldConnectionMatcher extends Matcher {
  Map<String, ConnectionType> _expectedConnections;
  
  WorldConnectionMatcher(this._expectedConnections);

  bool matches(item, Map matchState) {
    if (item is World) {
      World world = item;
      Map connections = world.network.peer.connections;
      for (String id in _expectedConnections.keys) {
        if (!connections.containsKey(id)) {
          matchState[id] = "Expected but missing! No such key ${id} in ${connections}";
        }
        ConnectionWrapper connection = connections[id];
        if (connection.connectionType != _expectedConnections[id]) {
          matchState[id] = "${connection.connectionType} != ${_expectedConnections[id]}";
        }
      }
      for (String id in connections.keys) {
        if (!_expectedConnections.containsKey(id)) {
          matchState[id] = "wasn't expected";
        }
      }
    }
    return matchState.length == 0;
  }
  
  Description describe(Description description) {
    description.add("World connections of ${_expectedConnections}");
  }
  
  /// This builds a textual description of a specific mismatch.
  Description describeMismatch(item, Description mismatchDescription,
      Map matchState, bool verbose) {
    mismatchDescription.add(matchState);
  }
}

