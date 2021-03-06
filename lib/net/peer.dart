import 'network.dart';
import 'connection.dart';
import 'package:di/di.dart';
import 'package:dart2d/bindings/annotations.dart';
import 'package:dart2d/js_interop/callbacks.dart';
import 'package:dart2d/net/net.dart';
import 'package:dart2d/util/util.dart';
import 'package:dart2d/util/hud_messages.dart';
import 'package:logging/logging.dart' show Logger, Level, LogRecord;

@Injectable() // TODO: Make Injectable.
class PeerWrapper {
  final Logger log = new Logger('Peer');
  static const MAX_AUTO_CONNECTIONS = 5;
  static const MAX_CONNECTION = 8;
  Network _network;
  GaReporter _gaReporter;
  HudMessages _hudMessages;
  JsCallbacksWrapper _peerWrapperCallbacks;
  PacketListenerBindings _packetListenerBindings;
  var peer;
  var id = null;
  var _connectedToServer = false;
  Map<String, ConnectionWrapper> connections = {};
  var _error;

  // Store active ids from the server to connect to.
  List<String> _activeIds = null;
  // Peers we've never been able to connect to.
  Set<String> _blackListedIds = new Set();
  // Peers which we have has a connection to, but is now closed.
  Set<String> _closedConnectionPeers = new Set();

  PeerWrapper(this._network, this._hudMessages, this._packetListenerBindings, @PeerMarker() Object jsPeer,
      this._peerWrapperCallbacks, this._gaReporter) {
    this.peer = jsPeer;
    _peerWrapperCallbacks
      ..bindOnFunction(jsPeer, 'open', openPeer)
      ..bindOnFunction(jsPeer, 'receiveActivePeers', receivePeers)
      ..bindOnFunction(jsPeer, 'connection', connectPeer)
      ..bindOnFunction(jsPeer, 'error', error);
  }

  /**
   * Called to establish a connection to another peer.
   */
  ConnectionWrapper connectTo(id) {
    _gaReporter.reportEvent("connection_created", "Connection");
    assert(id != null);
    var connection = _peerWrapperCallbacks.connectToPeer(peer, id);
    var peerId = connection['peer'];
    if (connections.containsKey(id)) {
      log.warning("Already a connection to ${id}!");
    }
    ConnectionWrapper connectionWrapper = new ConnectionWrapper(
        _network, _hudMessages,
        peerId, connection, _packetListenerBindings,
        this._peerWrapperCallbacks);
    connections[peerId] = connectionWrapper;
    return connectionWrapper;
  }

  /**
   * Disconnect this peer from the server.
   */
  void disconnect() {
    _connectedToServer = false;
    this._peerWrapperCallbacks.callJsMethod(this.peer, "disconnect");
  }

  /**
   * Re-connect this peer to the server.
   */
  void reconnect() {
    this._peerWrapperCallbacks.callJsMethod(this.peer, "reconnect");
    _connectedToServer = true;
  }

  void error(unusedThis, e) {
    _error = e;
    _hudMessages.display("Peer error: ${e}");
  }

  void openPeer(unusedThis, id) {
    this.id = id;
    // We blacklist from connection to self.
    _blackListedIds.add(id);
    _connectedToServer = true;
    log.info("Got id ${id}");
  }
  
  /**
   * Receive list of peers from server. Automatically connect. 
   */
  void receivePeers(unusedThis, List<String> ids) {
    ids.remove(this.id);
    log.info("Received active peers of $ids");
    _activeIds = ids;
    autoConnectToPeers();
  }

  bool hasMaxAutoConnections() => connections.length >= MAX_AUTO_CONNECTIONS;

  /**
   * Connect to peers. Maintain connectios.
   */
  bool autoConnectToPeers() {
    bool addedConnection = false;
    for (String id in _activeIds) {
      // Don't connect to too many peers...
      if (connections.length >= MAX_AUTO_CONNECTIONS) {
        return addedConnection;
      }
      if (connections.containsKey(id) ||
          _closedConnectionPeers.contains(id) || _blackListedIds.contains(id)) {
        continue;
      }
      addedConnection = true;
      log.info("Auto connecting to id ${id}");
      connectTo(id);
    }
    return addedConnection;
  }

  bool hasConnections() {
    return connections.length > 0;
  }
  
  bool hasConnectionTo(var id) {
    return this.id == id || connections.containsKey(id);
  }

  bool hasHadConnectionTo(String id) {
    return _closedConnectionPeers.contains(id);
  }
  /**
   * Callback for a peer connecting to us.
   */
  void connectPeer(unusedThis, connection) {
    _gaReporter.reportEvent("connection_received", "Connection");
    var peerId = connection['peer'];
    assert(peerId != null);
    log.info("Got connection from ${peerId}");
    _hudMessages.display("Got connection from ${peerId}");
    if (connections.containsKey(peerId)) {
      log.warning("Already a connection to ${peerId}!");
    }
    connections[peerId] = new ConnectionWrapper(_network, _hudMessages,
        peerId, connection, _packetListenerBindings,
        this._peerWrapperCallbacks);
    if (!_network.isCommander()
        && _network.gameState.playerInfoByConnectionId(peerId) != null) {
      connections[peerId].markAsClientToClientConnection();
    }
  }

  void sendDataWithKeyFramesToAll(Map data, [var dontSendTo]) {
    List<String> closedConnections = [];
    for (var key in connections.keys) {
      ConnectionWrapper connection = connections[key];
      if (!connection.isValidConnection()) {
        closedConnections.add(key);
        continue;
      }
      if (!connection.opened) {
        continue;
      }
      if (dontSendTo != null && dontSendTo == connection.id) {
        continue;
      }
      connection.sendData(data);
      if (data.containsKey(IS_KEY_FRAME_KEY)) {
        int keyFrame = data[IS_KEY_FRAME_KEY];
        // Send a ping every 6th keyframe to determine connection latency.
        if ((connection.id.hashCode + keyFrame) % 6 == 0) {
          connection.sendPing();
        }
      }
    }
    if (closedConnections.length > 0) {
      for (String id in closedConnections) {
        removeClosedConnection(id);
      }
    }
  }

  /**
   * See if connection with this ID is healthy.
   */
  void healthCheckConnection(String id) {
    ConnectionWrapper wrapper = connections[id];
    if (wrapper != null && !wrapper.isValidConnection()) {
      removeClosedConnection(id);
    }
  }

  /**
   * Remove connection with this ID.
   */
  void removeClosedConnection(String id) {
    // Start with a copy.
    Map connectionsCopy = new Map.from(this.connections);
    ConnectionWrapper wrapper = connectionsCopy[id];
    log.info("Removing connection for ${id}");
    connectionsCopy.remove(id);
    if (_network.isCommander()) {
      log.info("Removing GameState for ${id}");
      _network.gameState.removeByConnectionId(_network.world, id);
      // The crucial step of verifying we still have a server.
    } else {
      String commanderId = _network.findNewCommander(connectionsCopy);
      if (commanderId != null) {
        // We got elected the new server, first task is to remove the old.
        if (commanderId == this.id) {
          log.info("Server: Removing GameState for ${id}");
          _network.gameState.removeByConnectionId(_network.world, id);
          _network.convertToCommander(connectionsCopy);
          _network.gameState.markAsUrgent();
        } else {
          PlayerInfo info = _network.gameState.playerInfoByConnectionId(commanderId);
          // Start treating the other peer as server.
          ConnectionWrapper connection = connections[commanderId];
          _network.gameState.actingCommanderId = commanderId;
          _hudMessages.display("Elected new server ${info.name}");
        }
      } else {
        log.fine("Not switching commander after dropping ${id}");
      }
    }
    // Reconnect peer to server to allow receiving connections yet again.
    if (!connectedToServer()) {
      reconnect();
    }
    // Connection was never open, blacklist the id.
    if (!wrapper.opened) {
      _blackListedIds.add(id);
      _closedConnectionPeers.add(id);
      _gaReporter.reportEvent("closed_never_open", "Connection");
    } else {
      _closedConnectionPeers.add(id);
      _gaReporter.reportEvent("closed_after_open", "Connection");
    }
    // Assign back.
    connections = connectionsCopy;
  }

  /**
   * Return true if we have tried all possible ways of getting a connection
   * and should retort to being server ourselves.
   */
  bool connectionsExhausted() {
    if (_activeIds == null) {
      return false;
    }
    return _closedConnectionPeers.containsAll(_activeIds);
  }

  bool noMoreConnectionsAvailable() {
    Set<String> activeAndClosedConnections = new Set.from(_closedConnectionPeers)
        ..addAll(connections.keys);
    return activeAndClosedConnections.containsAll(_activeIds);
  }

  /**
   * See if we've received a list of active peers.
   */
  bool hasReceivedActiveIds() {
    return _activeIds != null;
  }

  getLastError() => this._error;
  getId() => this.id;

  bool connectedToServer() {
    return _connectedToServer && id != null;
  }
}
