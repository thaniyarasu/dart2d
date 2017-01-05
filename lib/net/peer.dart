import 'package:dart2d/worlds/worm_world.dart';
import 'network.dart';
import 'connection.dart';
import 'package:di/di.dart';
import 'package:dart2d/bindings/annotations.dart';
import 'package:dart2d/js_interop/callbacks.dart';
import 'package:dart2d/net/chunk_helper.dart';
import 'package:dart2d/hud_messages.dart';

@Injectable() // TODO: Make Injectable.
class PeerWrapper {
  // TODO make private.
  Network network;
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

  PeerWrapper(this.network, this._hudMessages, this._packetListenerBindings, @PeerMarker() Object jsPeer,
      this._peerWrapperCallbacks) {
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
  void connectTo(id, [ConnectionType connectionType = ConnectionType.BOOTSTRAP]) {
    assert(id != null);
    var connection = _peerWrapperCallbacks.connectToPeer(peer, id);
    var peerId = connection['peer'];
    if (connections.containsKey(id)) {
      log.warning("Already a connection to ${id}!");
    }
    ConnectionWrapper connectionWrapper = new ConnectionWrapper(
        network, _hudMessages,
        peerId, connection, connectionType, _packetListenerBindings,
        this._peerWrapperCallbacks);
    connections[peerId] = connectionWrapper;
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
    ids.forEach((String id) {
      // Don't connect to self...
      if (id != this.id) {
        log.info("Auto connecting to id ${id}");

        connectTo(id);
        // TODO: Add logic here instead. How many to connect to and why?
        return;
      }
    });
  }

  bool hasConnections() {
    return connections.length > 0;
  }
  
  bool hasConnectionTo(var id) {
    return this.id == id || connections.containsKey(id);
  }

  /**
   * Callback for a peer connecting to us.
   */
  void connectPeer(unusedThis, connection) {
    var peerId = connection['peer'];
    assert(peerId != null);
    _hudMessages.display("Got connection from ${peerId}");
    ConnectionType type;
    if (network.isServer()) {
      type = ConnectionType.SERVER_TO_CLIENT;
    } else {
      if (network.gameState.playerInfoByConnectionId(peerId) != null) {
        // We know this connection as a player.
        type = ConnectionType.CLIENT_TO_CLIENT;
      } else {
        // We are not server. Assume generic bootstrap connection.
        type = ConnectionType.BOOTSTRAP;
      }
    }
    if (connections.containsKey(peerId)) {
      log.warning("Already a connection to ${peerId}!");
    }
    connections[peerId] = new ConnectionWrapper(network, _hudMessages,
        peerId, connection,  type, _packetListenerBindings,
        this._peerWrapperCallbacks);
  }

  void sendDataWithKeyFramesToAll(data, [var dontSendTo]) {
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
    print("${this.id}: Removing connection for $id");
    connectionsCopy.remove(id);
    if (wrapper.connectionType == ConnectionType.SERVER_TO_CLIENT) {
      print("Removing Gamestate for $id");
      network.gameState.removeByConnectionId(network.world, id);
      // The crucial step of verifying we still have a server.
    } else if (network.verifyOrTransferServerRole(connectionsCopy)) {
      // We got elected the new server, first task is to remove the old.
      print("Removing Gamestate for $id");
      network.gameState.removeByConnectionId(network.world, id);
      network.gameState.convertToServer(network.world, this.id);
    }
    // Reconnect peer to server to allow receiving connections yet again.
    if (!connectedToServer()) {
      reconnect();
    }
    // Connection was never open, blacklist the id.
    if (!wrapper.opened) {
      _blackListedIds.add(id);
      _closedConnectionPeers.add(id);
    } else {
      _closedConnectionPeers.add(id);
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

  /**
   * See if we've received a list of active peers.
   */
  bool hasReceivedActiveIds() {
    return _activeIds != null;
  }

  getLastError() => this._error;

  bool connectedToServer() {
    return _connectedToServer && id != null;
  }
}