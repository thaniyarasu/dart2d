library dart2d;

import 'sprite.dart';
import 'movingsprite.dart';
import 'playersprite.dart';
import 'connection.dart';
import 'gamestate.dart';
import 'state_updates.dart';
import 'dart2d.dart';
import 'rtc.dart';
import 'vec2.dart';
import 'world.dart';
import 'keystate.dart';
import 'dart:math';
import 'package:logging/logging.dart' show Logger, Level, LogRecord;

final Logger log = new Logger('Network');
// Network has 2 keyframes per second.
const KEY_FRAME_DEFAULT = 1.0/2;

class Client extends Network {
  Client(world, peer) : super(world, peer) {
    _server = false;
  }
}

class Server extends Network {
  Server(world, peer) : super(world, peer) {
    _server = true;
  }
}

abstract class Network {
  GameState gameState;
  World world;
  String localPlayerName;
  PeerWrapper peer;
  double untilNextKeyFrame = KEY_FRAME_DEFAULT;
  int currentKeyFrame = 0;
  bool _server = false;

  Network(this.world, this.peer) {
    gameState = new GameState(world);
  }

  /**
   * Ensures that we have a connection to all clients in the game.
   * This is to be able to elect a new server in case the current server dies.
   * 
   * We also ensure the sprites in the world have consitent owners.
   */
  void connectToAllPeersInGameState() {
    for (PlayerInfo info in gameState.playerInfo) {
      Sprite sprite = world.sprites[info.spriteId];
      if (sprite != null) {
        // Make sure the ownerId is consistent with the connectionId.
        sprite.ownerId = info.connectionId;
      }
      if (!peer.hasConnectionTo(info.connectionId)) {
        world.hudMessages.display("Creating neighbour connection to ${info.name}");
        peer.connectTo(info.connectionId, ConnectionType.CLIENT_TO_CLIENT);
      }
    }
  }
  
  /**
   * Our goal is to always have a connection to a server.
   * This is checked when a connection is dropped. 
   * Potentially this method will elect a new server.
   * returns true if we became the new server.
   * TODO(Erik): Conside more factors when electing servers, like number of connected
   *  peers.
   */
  bool verifyOrTransferServerRole(Map connections) {
    for (var key in connections.keys) {
      ConnectionWrapper connection = connections[key];
      if (connection.connectionType == ConnectionType.CLIENT_TO_SERVER) {
        print("${peer.id} has a client to server connection using ${key}");
        return false;  
      }
    }
    // We don't have a server connection. We need to elect a new one.
    // We always elect the peer with the highest natural order id.
    var maxPeerKey = connections.keys.reduce(
        (value, element) => value.compareTo(element) < 0 ? value : element);
    if (maxPeerKey.compareTo(peer.id) < 0) {
      PlayerInfo info = gameState.playerInfoByConnectionId(maxPeerKey);
      // Start treating the other peer as server.
      ConnectionWrapper connection = connections[maxPeerKey];
      connection.connectionType = ConnectionType.CLIENT_TO_SERVER;
      world.hudMessages.display("Elected new server ${info.name}");
    } else {
      // We are becoming server. Gosh.
      _server = true;
      for (var id in connections.keys) {
        ConnectionWrapper connection = connections[id];
        connection.connectionType = ConnectionType.SERVER_TO_CLIENT;
        // TODO(Erik): Change sprite types for players.
      }
      world.hudMessages.display("Server role tranferred to you :)");
      return true;
    }
    return false;
  }

  bool checkForKeyFrame(bool forceKeyFrame, double duration) {
    untilNextKeyFrame -= duration;
    if (forceKeyFrame) {
      currentKeyFrame++;
      untilNextKeyFrame = KEY_FRAME_DEFAULT;
      return true;
    }
    if (untilNextKeyFrame < 0) {
      currentKeyFrame++;
      untilNextKeyFrame += KEY_FRAME_DEFAULT;
      return true;
    }
    return false;
  }

  void registerDroppedFrames(var data) {
    for (ConnectionWrapper connection in peer.connections.values) {
      connection.registerDroppedKeyFrames(currentKeyFrame - 1);
    }
  }

  void sendMessage(String message) {
    Map data = {
      MESSAGE_KEY: [message],
      IS_KEY_FRAME_KEY: world.network.currentKeyFrame};
    peer.sendDataWithKeyFramesToAll(data);    
  }

  void maybeSendLocalKeyStateUpdate() {
    if (!isServer()) {
      Map data = {};
      data[KEY_STATE_KEY] = world.localKeyState.getEnabledState();
      peer.sendDataWithKeyFramesToAll(data);
    }
  }

  void frame(double duration, List<int> removals) {
    if (!hasReadyConnection()) {
      return;
    }
    bool keyFrame = checkForKeyFrame(!removals.isEmpty, duration);
    Map data = stateBundle(world.sprites, keyFrame);
    // A keyframe indicates that we are sending data with garantueed delivery.
    if (keyFrame) {
      registerDroppedFrames(data);
      data[IS_KEY_FRAME_KEY] = currentKeyFrame;
    }
    if (removals.length > 0) {
      data[REMOVE_KEY] = new List.from(removals, growable:false);
      removals.clear();
    }
    if (!isServer()) {
      data[KEY_STATE_KEY] = world.localKeyState.getEnabledState();
    } else if (keyFrame) {
      data[GAME_STATE] = gameState.toMap();
    }

    if (data.length > 0) {
      peer.sendDataWithKeyFramesToAll(data);
    }
  }

  bool isServer() {
    return _server;
  }

  bool hasReadyConnection() {
    if (peer != null && peer.connections.length > 0) {
      return true;
    }
    return false;
  }
  
  String keyFrameDebugData() {
    if (!hasReadyConnection()) {
      return "No connections";
    }
    String debugString = "";
    for (ConnectionWrapper connection in peer.connections.values) {
      debugString += "${connection.id} R/X/D: ${connection.lastLocalPeerKeyFrameVerified}/${currentKeyFrame}/${connection.droppedKeyFrames}";
    }
    return debugString;
  }
}

Map<String, List<int>> stateBundle(Map<int, Sprite> sprites, bool keyFrame) {
  Map<String, List<int>> allData = {};
  for (int networkId in sprites.keys) {
    Sprite sprite = sprites[networkId];
    if (sprite.networkType == NetworkType.LOCAL) {
      List<int> dataAsList = propertiesToIntList(sprite, keyFrame);
      allData[sprite.networkId.toString()] = dataAsList; 
    }
  }
  return allData;
}

DateTime lastNetworkFrameReceived = new DateTime.now();
FpsCounter networkFps = new FpsCounter();

void dataReceived() {
  DateTime now = new DateTime.now();
  int millis = now.millisecondsSinceEpoch - lastNetworkFrameReceived.millisecondsSinceEpoch;
  networkFps.timeWithFrames(millis / 1000.0, 1);
  lastNetworkFrameReceived = now;
}

void parseBundle(World world,
    ConnectionWrapper connection, Map<String, List<int>> bundle) {
  dataReceived();
  for (String networkId in bundle.keys) {
    if (!SPECIAL_KEYS.contains(networkId)) {
      int parsedNetworkId = int.parse(networkId);
      // TODO(erik) Prio data for the owner of the sprite instead.
      Sprite sprite = world.getOrCreateSprite(parsedNetworkId, bundle[networkId][0], connection);
      if (!sprite.networkType.remoteControlled()) {
        log.warning("Warning: Attempt to update local sprite ${sprite.networkId} from network ${connection.id}.");
        continue;
      }
      intListToSpriteProperties(bundle[networkId], sprite);
      // Forward sprite to others.
      if (sprite.networkType == NetworkType.REMOTE_FORWARD) {
        log.fine("Forwarding update of ${networkId} from ${connection.id}");
        Map data = {networkId: bundle[networkId]};
        world.network.peer.sendDataWithKeyFramesToAll(data, connection.id);
      }
    }
  }
  if (bundle.containsKey(REMOVE_KEY)) {
    assert(world.network.isServer());
    List<int> removals = bundle[REMOVE_KEY];
    for (int id in removals) {
      world.removeSprite(id);
    }
  }
  if (bundle.containsKey(MESSAGE_KEY)) {
    for (String message in bundle[MESSAGE_KEY]) {
      world.hudMessages.display(message);
    }
  }
  if (bundle.containsKey(GAME_STATE)) {
    assert(!world.network.isServer());
    Map gameStateMap = bundle[GAME_STATE];
    world.network.gameState = new GameState.fromMap(world, gameStateMap);
    world.network.connectToAllPeersInGameState();
  }
}
