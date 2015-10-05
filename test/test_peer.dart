library test_peer;

import 'test_connection.dart';
import 'package:dart2d/hud_messages.dart';
import 'package:dart2d/worlds/world.dart';
import 'package:dart2d/worlds/worm_world.dart';
import 'package:dart2d/worlds/byteworld.dart';
import 'package:dart2d/res/imageindex.dart';
import 'package:dart2d/phys/vec2.dart';

World testWorld(var id) {
  TestPeer peer = new TestPeer(id);
  WormWorld w = new WormWorld(400, 600);
  w.connectOnOpenConnection = true;
  w.byteWorld = new ByteWorld(imageByName['world.png'], new Vec2(400 * 1.0,  600 * 1.0));
  w.setJsPeer(peer);
  w.hudMessages = new TestHudMessage(w);
  w.loader.completed_ = true;
  return w;
}

Map testPeers = {};

class TestPeer {
  var id;
  var eventHandlers = {};

  TestPeer(this.id) {
    assert(!testPeers.containsKey(id));
    testPeers[id] = this;
  }

  callMethod(String methodName, var jsonObject) {
    if ("connect" == methodName) {
      var otherId = jsonObject[0];
      if (!testPeers.containsKey(otherId)) {
        throw new ArgumentError("No peer with id ${otherId}");
      }
      TestConnection localConnection = new TestConnection(otherId);
      TestConnection remoteConnection = new TestConnection(id);
      remoteConnection.otherEnd = localConnection;
      localConnection.otherEnd = remoteConnection;
      testPeers[otherId].eventHandlers["connection"].apply([remoteConnection]);
      return localConnection;
    }
    if (methodName == "on" && bindOnHandler(jsonObject[0], jsonObject[1])) {
      return "OK";
    }
    print("TestPeer Can't handle ${jsonObject}");
    return "Not supported";
  }

  bool bindOnHandler(String methodName, var jsFunction) {
    eventHandlers[methodName] = jsFunction;
    if (methodName == "open") {
      // Signal an open connection right away.
      jsFunction.apply([id]);
    }
    return true;
  }
}

class TestHudMessage extends HudMessages {
  
  TestHudMessage(World w) : super(w);

  void displayAndSendToNetwork(String message, [double period]) {
     print("HUD(${world.peer.id})_NET: $message");
     world.network.sendMessage(message);
   }

   void display(String message, [double period]) {
     print("HUD(${world.peer.id}): $message");
   }
}
