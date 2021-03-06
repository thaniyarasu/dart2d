import 'connection.dart';
import 'package:dart2d/sprites/sprites.dart';
import 'package:dart2d/util/gamestate.dart';
import 'package:dart2d/util/fps_counter.dart';
import 'package:dart2d/bindings/annotations.dart';
import 'package:dart2d/net/state_updates.dart';
import 'package:dart2d/net/peer.dart';
import 'package:dart2d/worlds/worm_world.dart';
import 'dart:convert';
import 'package:dart2d/worlds/world.dart';
import 'package:dart2d/util/keystate.dart';
import 'package:dart2d/util/hud_messages.dart';
import 'package:dart2d/js_interop/callbacks.dart';
import 'package:di/di.dart';
import 'dart:math';
import 'package:logging/logging.dart' show Logger, Level, LogRecord;

// Network has 2 keyframes per second.
const KEY_FRAME_DEFAULT = 1.0 / 2;
const PROBLEMATIC_FRAMES_BEHIND = 2;

@Injectable()
class Network {
  final Logger log = new Logger('Network');
  WormWorld world;
  GameState gameState;
  HudMessages _hudMessages;
  SpriteIndex _spriteIndex;
  GaReporter _gaReporter;
  KeyState _localKeyState;
  PeerWrapper peer;
  PacketListenerBindings _packetListenerBindings;
  FpsCounter _drawFps;
  double untilNextKeyFrame = KEY_FRAME_DEFAULT;
  int currentKeyFrame = 0;
  // If we are client, this indicates that the server
  // is unable to ack our data.
  int serverFramesBehind = 0;
  // How many times we trigger a frame while being very slow at doing so.
  // We may choose to give up our commanding role if this happens too much.
  int _slowCommandingFrames = 0;
  String _pendingCommandTransfer = null;

  Network(
      this._gaReporter,
      HudMessages hudMessages,
      this.gameState,
      this._packetListenerBindings,
      @ServerFrameCounter() FpsCounter serverFrameCounter,
      @PeerMarker() Object jsPeer,
      JsCallbacksWrapper peerWrapperCallbacks,
      SpriteIndex spriteIndex,
      @LocalKeyState() KeyState localKeyState) {
    this._hudMessages = hudMessages;
    this._spriteIndex = spriteIndex;
    this._drawFps = serverFrameCounter;
    this._localKeyState = localKeyState;
    peer = new PeerWrapper(this, hudMessages, _packetListenerBindings, jsPeer,
        peerWrapperCallbacks, _gaReporter);

    _packetListenerBindings.bindHandler(GAME_STATE, _handleGameState);
    _packetListenerBindings.bindHandler(FPS,
        (ConnectionWrapper connection, int fps) {
      /// Update the FPS counter. We don't care if commander or not.
      PlayerInfo info = gameState.playerInfoByConnectionId(connection.id);
      if (info != null) {
        info.fps = fps;
      }
    });
    _packetListenerBindings.bindHandler(CONNECTIONS_LIST,
        (ConnectionWrapper connection, List connections) {
      /// Update the list of connections for this player.
      PlayerInfo info = gameState.playerInfoByConnectionId(connection.id);
      if (info != null) {
        List<ConnectionInfo> connectionList = [];
        for (List item in connections) {
          connectionList.add(new ConnectionInfo(item[0], item[1]));
        }
        info.connections = connectionList;
      }
    });
    _packetListenerBindings.bindHandler(SERVER_PLAYER_REJECT,
        (ConnectionWrapper connection, var data) {
      hudMessages.display("Game is full :/");
      gameState.reset();
      connection.close(null);
    });

    _packetListenerBindings.bindHandler(TRANSFER_COMMAND,
        (ConnectionWrapper connection, String data) {
      if (!world.loaderCompleted()) {
        log.warning(
            "Can not transfer command to us before loading has completed. Dropping request.");
        return;
      }
      // Server wants us to take command.
      log.info("Coverting self to commander");
      this.convertToCommander(this.safeActiveConnections());
      _gaReporter.reportEvent("convert_self_to_commander_on_request", "Commander");
    });
  }

  /**
   * Our goal is to always have a connection to a commander.
   * This is checked when a connection is dropped.
   * Potentially this method will elect a new commander.
   * returns the id of the new commander, or null if no new commander was needed.
   * TODO(Erik): Consider more factors when electing servers, like number of connected
   *  peers.
   */
  String findNewCommander(Map connections, [bool ignoreSelf = false]) {
    if (!isCommander()) {
      if (!gameState.isInGame(peer.id)) {
        log.info("No active game found for us, no commander role to transfer.");
        return null;
      }
    }
    List<String> validKeys = [];
    for (String key in connections.keys) {
      ConnectionWrapper connection = connections[key];
      if (connection.id == gameState.actingCommanderId) {
        log.info("${peer.id} has a client to server connection using ${key}");
        return null;
      }
      if (connection.isValidGameConnection()) {
        validKeys.add(key);
      }
    }
    // Don't count our own id.
    if (!ignoreSelf) {
      return _naturalOrderPeerId(validKeys);
    } else {
      return _bestCommanderPeerId(validKeys);
    }
  }

  /**
   * When the commander dies unexpectedly we need to make a collective decision on
   * who will be the next commander. The peer ID should be the most consistent item
   * so we pick the remaining host with the highest naturual order peerId.
   * Should this turn out to be unsuitable, it will automatically select a better
   * commander in time.
   */
  String _naturalOrderPeerId(List<String> validKeys) {
    // We always elect the peer with the highest natural order id.
    var maxPeerKey = null;
    if (!validKeys.isEmpty) {
      maxPeerKey = validKeys.reduce(
          (value, element) => value.compareTo(element) < 0 ? value : element);
    }
    if (maxPeerKey != null && maxPeerKey.compareTo(peer.id) < 0) {
      return maxPeerKey;
    } else {
      return peer.id;
    }
  }

  /**
   * Select the best next commander.
   * TODO also count the number of connections?
   */
  String _bestCommanderPeerId(List<String> validKeys) {
    int bestFps = -1;
    String bestFpsKey = null;
    for (String peerId in validKeys) {
      // Pick commander with highest FPS.
      PlayerInfo info = gameState.playerInfoByConnectionId(peerId);
      if (info != null) {
        if (info.fps > bestFps) {
          bestFps = info.fps;
          bestFpsKey = peerId;
        }
      } else {
        log.warning(
            "PlayerInfo for ${peerId} is missing! Odd since connection is marked as in game.");
      }
    }
    log.info(
        "Identified ${bestFpsKey} as best suitable commander with fps ${bestFps}");
    return bestFpsKey;
  }

  /**
   * Set this peer as the commander.
   */
  void convertToCommander(Map connections) {
    _hudMessages.display("Commander role tranferred to you :)");
    gameState.convertToServer(world, this.peer.id);
    for (String id in connections.keys) {
      ConnectionWrapper connection = connections[id];
      connection.sendPing();
      if (connection.isValidGameConnection()) {
        PlayerInfo info = gameState.playerInfoByConnectionId(id);
        // Make it our responsibility to foward data from other players.
        Sprite sprite = _spriteIndex[info.spriteId];
        if (sprite.networkType == NetworkType.REMOTE) {
          sprite.networkType = NetworkType.REMOTE_FORWARD;
        }
      }
    }
    gameState.markAsUrgent();
  }

  PeerWrapper getPeer() => peer;
  GameState getGameState() => gameState;

  bool checkForKeyFrame(double duration) {
    untilNextKeyFrame -= duration;
    if (untilNextKeyFrame < 0) {
      currentKeyFrame++;
      untilNextKeyFrame += KEY_FRAME_DEFAULT;
      // In case last frame was incredibly slow.
      if (untilNextKeyFrame < 0) {
        untilNextKeyFrame = KEY_FRAME_DEFAULT;
      }
      return true;
    }
    return false;
  }

  void registerDroppedFrames(var data) {
    for (ConnectionWrapper connection in peer.connections.values) {
      connection.registerDroppedKeyFrames(currentKeyFrame - 1);
      if (connection.id == gameState.actingCommanderId) {
        serverFramesBehind = connection.keyFramesBehind(currentKeyFrame - 1);
      }
    }
  }

  /**
   * Return a map of connections garantueed to be active.
   */
  Map<String, ConnectionWrapper> safeActiveConnections() {
    Map<String, ConnectionWrapper> activeConnections = {};
    for (ConnectionWrapper wrapper in new List.from(peer.connections.values)) {
      if (wrapper.isActiveConnection()) {
        activeConnections[wrapper.id] = wrapper;
      } else {
        this.peer.healthCheckConnection(wrapper.id);
      }
    }
    return activeConnections;
  }

  /**
   * Return the connection to the server.
   */
  ConnectionWrapper getServerConnection() {
    if (gameState.actingCommanderId != null &&
        peer.connections.containsKey(gameState.actingCommanderId)) {
      return peer.connections[gameState.actingCommanderId];
    }
    return null;
  }

  _handleGameState(ConnectionWrapper connection, Map data) {
    if (isCommander() && pendingCommandTransfer() == null) {
      log.warning(
          "Not parsing gamestate from ${connection.id} because we are commander!");
      return;
    }
    gameState.updateFromMap(data);
    world.connectToAllPeersInGameState();
    if (peer.connectedToServer() && gameState.isAtMaxPlayers()) {
      peer.disconnect();
    }
  }

  /**
   * Try and find a connection to a server.
   * Returns true once the search is complete.
   */
  bool findServer() {
    Map connections = safeActiveConnections();
    List<String> closeAbleNotServer = [];
    if (gameState.actingCommanderId != null &&
        connections.containsKey(gameState.actingCommanderId)) {
      /// TODO probe if game is full and close connection if it is.
      return true;
    }
    for (ConnectionWrapper connection in connections.values) {
      if (connection.initialPongReceived()) {
        closeAbleNotServer.add(connection.id);
      }
      if (!connection.initialPingSent()) {
        connection.sendPing(true);
      }
    }
    // We examined all connections and found no server. Time to take action.
    if (new Set.from(closeAbleNotServer).containsAll(connections.keys)) {
      if (peer.hasMaxAutoConnections()) {
        for (int i = 0; i < closeAbleNotServer.length; i++) {
          // TODO close by some heuristic here?
          if (i > 1) break;
          ConnectionWrapper connection = connections[closeAbleNotServer[i]];
          log.info("Closing connection $connection in search for server.");
          connection.close(null);

          // Remove right away, so autoConnectToPeers doesn't count this connection.
          // TODO: Should we instead clean connections in autoConnectToPeers?
          peer.removeClosedConnection(connection.id);

          if (!peer.autoConnectToPeers()) {
            // We didn't add any new peers. Bail.
            log.warning(
                "didn't find any servers, and not able to connect to any more peers. Giving up.");
            return true;
          }
        }
      } else if (peer.noMoreConnectionsAvailable()) {
        return true;
      } else {
        peer.autoConnectToPeers();
      }
    }
    if (connections.isEmpty) {
      if (!peer.autoConnectToPeers()) {
        // We didn't add any new peers. Bail.
        return true;
      }
    }
    return false;
  }

  /**
   * Returns true if the network is in such a problemetic state we should notify the user.
   */
  bool hasNetworkProblem() {
    return serverFramesBehind >= PROBLEMATIC_FRAMES_BEHIND && !isCommander();
  }

  void sendMessage(String message) {
    Map data = {
      MESSAGE_KEY: [message],
      IS_KEY_FRAME_KEY: currentKeyFrame
    };
    peer.sendDataWithKeyFramesToAll(data);
  }

  void maybeSendLocalKeyStateUpdate() {
    if (!isCommander()) {
      Map data = {};
      data[KEY_STATE_KEY] = _localKeyState.getEnabledState();
      peer.sendDataWithKeyFramesToAll(data);
    }
  }

  void frame(double duration, List<int> removals) {
    if (!hasReadyConnection()) {
      serverFramesBehind = 0;
      return;
    }
    if (isCommander()) {
      if (_drawFps.fps() > 0.0 &&
          _drawFps.fps() < (TARGET_SERVER_FRAMES_PER_SECOND / 2)) {
        // We are running at a very low server framerate. Are we really suitable
        // as commander?
        log.fine(
            "Commander ${peer.id} below FPS threshold! Is ${_drawFps.fps()}");
        _slowCommandingFrames++;
      } else {
        _slowCommandingFrames = 0;
      }
    } else {
      // Command transfer successful.
      if (gameState.actingCommanderId == _pendingCommandTransfer) {
        log.info(
            "Succcesfully transfered command to ${gameState.actingCommanderId}");
        _pendingCommandTransfer = null;
      }
    }
    // This doesnät make sense.
    bool keyFrame = checkForKeyFrame(duration);
    Map data = stateBundle(keyFrame);
    // A keyframe indicates that we are sending data with garantueed delivery.
    if (keyFrame) {
      registerDroppedFrames(data);
      data[IS_KEY_FRAME_KEY] = currentKeyFrame;
      data[CONNECTIONS_LIST] = [];
      for (ConnectionWrapper wrapper in safeActiveConnections().values) {
        data[CONNECTIONS_LIST].add([wrapper.id, wrapper.expectedLatency().inMilliseconds]);
        JSON.encode(data[CONNECTIONS_LIST]);
      }
      peer.connections.keys.toList();
    }
    if (removals.length > 0) {
      data[REMOVE_KEY] = removals;
    }
    if (!isCommander()) {
      data[KEY_STATE_KEY] = _localKeyState.getEnabledState();
      if (keyFrame) {
        data[FPS] = _drawFps.fps().toInt();
      }
    } else if (keyFrame || gameState.retrieveAndResetUrgentData()) {
      gameState.playerInfoByConnectionId(peer.id).fps = _drawFps.fps().toInt();
      data[GAME_STATE] = gameState.toMap();
    }
    if (data.length > 0) {
      peer.sendDataWithKeyFramesToAll(data);
    }

    // Transfer our commanding role to someone else!
    if (isCommander() && isTooSlowForCommanding()) {
      Map connections = safeActiveConnections();
      String newCommander = findNewCommander(connections, true);
      if (newCommander != null) {
        ConnectionWrapper connection = connections[newCommander];
        connection.sendCommandTransfer();
        _slowCommandingFrames = 0;
        log.info(
            "Attempting to transfer command rule due to slow framerate from us");
        _pendingCommandTransfer = newCommander;
      }
    }
  }

  String pendingCommandTransfer() => _pendingCommandTransfer;

  bool isCommander() {
    return gameState.actingCommanderId == this.peer.id;
  }

  void setAsActingCommander() {
    log.info("Setting ${peer.id} as acting commander.");
    if (gameState.playerInfoByConnectionId(peer.id) == null) {
      throw new StateError(
          "${peer.id} can not be commander is it's not part of the gamestate! ${gameState.playerInfoList()}");
    }
    gameState.actingCommanderId = peer.id;
    gameState.markAsUrgent();
    this.gameState.mapName = null;
    // If we have any connections, consider them to be SERVER_TO_CLIENT now.
    for (ConnectionWrapper connection in safeActiveConnections().values) {
      // Announce change in GameState.
      connection.sendPing();
    }
  }

  int slowCommandingFrames() => _slowCommandingFrames;
  bool isTooSlowForCommanding() => _slowCommandingFrames > 4;

  bool hasReadyConnection() {
    if (peer != null && peer.connections.length > 0) {
      return true;
    }
    return false;
  }

  bool hasOpenConnection() {
    if (hasReadyConnection()) {
      return safeActiveConnections().length > 0;
    }
    return false;
  }

  String keyFrameDebugData() {
    if (!hasReadyConnection()) {
      return "No connections";
    }
    String debugString = "";
    for (ConnectionWrapper connection in peer.connections.values) {
      debugString +=
          "${connection.id} ${connection.expectedLatency().inMilliseconds}ms R/X/D: ${connection.lastLocalPeerKeyFrameVerified}/${currentKeyFrame}/${connection.droppedKeyFrames}";
    }
    return debugString;
  }

  void parseBundle(ConnectionWrapper connection, Map<String, dynamic> bundle) {
    dataReceived();
    for (String networkId in bundle.keys) {
      if (!SPECIAL_KEYS.contains(networkId)) {
        int parsedNetworkId = int.parse(networkId);
        List data = bundle[networkId];
        if (data[0] & Sprite.FLAG_COMMANDER_DATA ==
            Sprite.FLAG_COMMANDER_DATA) {
          // parse as commander data update.
          MovingSprite sprite = world.spriteIndex[parsedNetworkId];
          if (sprite == null) {
            log.warning(
                "Not creating sprite from update ${networkId}, unable to add commander data.");
            continue;
          }
          if (isCommander()) {
            log.warning("Warning: Attempt to update local sprite ${sprite
                .networkId} from network ${connection.id}.");
            continue;
          }
          List data = bundle[networkId];
          sprite.parseServerToOwnerData(data, 1);
        } else {
          // Parse as generic update.
          SpriteConstructor constructor = SpriteConstructor.DO_NOT_CREATE;
          // Only try and construct sprite if this is a full frame - we have all
          // the data.
          if (data[0] & Sprite.FLAG_FULL_FRAME == Sprite.FLAG_FULL_FRAME) {
            constructor = SpriteConstructor.values[data[6]];
          }
          MovingSprite sprite =
              world.getOrCreateSprite(parsedNetworkId, constructor, connection);
          if (sprite == null) {
            log.info(
                "Not creating sprite from update ${networkId}, constructor is ${constructor}");
            continue;
          }
          intListToSpriteProperties(bundle[networkId], sprite);
          // Forward sprite to others.
          if (sprite.networkType == NetworkType.REMOTE_FORWARD) {
            Map data = {networkId: bundle[networkId]};
            peer.sendDataWithKeyFramesToAll(data, connection.id);
          }
        }
      }
    }
  }

  Map<String, List<int>> stateBundle(bool keyFrame) {
    Map<String, List<int>> allData = {};
    for (int networkId in _spriteIndex.spriteIds()) {
      Sprite sprite = _spriteIndex[networkId];
      if (sprite.networkType == NetworkType.LOCAL) {
        List<int> dataAsList = propertiesToIntList(sprite, keyFrame);
        allData[sprite.networkId.toString()] = dataAsList;
      } else if (isCommander() && sprite.hasServerToOwnerData()) {
        List dataAsList = [Sprite.FLAG_COMMANDER_DATA];
        sprite.addServerToOwnerData(dataAsList);
        allData[sprite.networkId.toString()] = dataAsList;
      }
    }
    return allData;
  }
}

DateTime lastNetworkFrameReceived = new DateTime.now();
FpsCounter networkFps = new FpsCounter();

void dataReceived() {
  DateTime now = new DateTime.now();
  int millis = now.millisecondsSinceEpoch -
      lastNetworkFrameReceived.millisecondsSinceEpoch;
  networkFps.timeWithFrames(millis / 1000.0, 1);
  lastNetworkFrameReceived = now;
}
