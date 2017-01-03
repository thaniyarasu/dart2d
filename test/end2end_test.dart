library dart2d;

import 'package:test/test.dart';
import 'lib/test_lib.dart';
import 'package:dart2d/net/connection.dart';
import 'package:dart2d/sprites/sprites.dart';
import 'package:di/di.dart';
import 'package:dart2d/worlds/worm_world.dart';
import 'package:dart2d/worlds/loader.dart';
import 'package:dart2d/gamestate.dart';
import 'package:dart2d/net/net.dart';
import 'package:dart2d/net/rtc.dart';
import 'package:dart2d/net/state_updates.dart';
import 'package:dart2d/res/imageindex.dart';
import 'package:logging/logging.dart' show Logger, Level, LogRecord;

void main() {
  setUp(() {
    Logger.root.level = Level.ALL;
    Logger.root.onRecord.listen((LogRecord rec) {
      print('${rec.level.name}: ${rec.time}: ${rec.message}');
    });
    clearEnvironment();
    logConnectionData = true;
    remapKeyNamesForTest();
  });

  group('End2End', () {
    test('Resource loading tests p2p', () {
      logConnectionData = false;
      Injector injectorA = createWorldInjector("a", false);
      Injector injectorB = createWorldInjector("b", false);

      WormWorld worldA = injectorA.get(WormWorld);
      TestPeer peerA = injectorA.get(TestPeer);
      Loader loaderA = worldA.loader;
      FakeImageFactory fakeImageFactoryA = injectorA.get(FakeImageFactory);

      WormWorld worldB = injectorB.get(WormWorld);
      Loader loaderB = worldB.loader;
      TestPeer peerB = injectorB.get(TestPeer);

      // WorldA receives no peers.
      worldA.frameDraw();
      expect(loaderA.currentState(), equals(LoaderState.WAITING_FOR_PEER_DATA));
      peerA.receiveActivePeer([]);
      worldA.frameDraw();
      // Completes loading from Server.
      expect(loaderA.currentState(), equals(LoaderState.LOADING_SERVER));
      worldA.frameDraw();
      fakeImageFactoryA.completeAllImages();
      worldA.frameDraw();
      expect(loaderA.currentState(), equals(LoaderState.LOADING_RESOURCES_COMPLETED));
      worldA.frameDraw();
      expect(worldA.network.isServer(), true);

      // WorldB receives worldA as peer.
      worldB.frameDraw();
      expect(loaderB.currentState(), equals(LoaderState.WAITING_FOR_PEER_DATA));
      worldB.frameDraw();
      peerB.receiveActivePeer(['a', 'b']);
      expect(worldB.peer.connections.length, equals(1));
      worldB.frameDraw();
      worldB.frameDraw();
      expect(loaderB.currentState(), equals(LoaderState.LOADING_RESOURCES_COMPLETED));

      // Ideally this does not mean connection to a game.
      // But Game comes underway after a couple of frames.
      logConnectionData = true;
      worldA.frameDraw(KEY_FRAME_DEFAULT);
      worldB.frameDraw(KEY_FRAME_DEFAULT);
      worldA.frameDraw(KEY_FRAME_DEFAULT);
      worldB.frameDraw(KEY_FRAME_DEFAULT);
      expect(loaderB.currentState(), equals(LoaderState.LOADING_GAMESTATE_COMPLETED));

      worldA.frameDraw();
      worldB.frameDraw();

      expect(worldB.network.isServer(), false);
      expect(worldA.network.isServer(), true);

      expect(worldA, hasSpriteWithNetworkId(playerId(0)));
      expect(worldA, hasSpriteWithNetworkId(playerId(1)));
      expect(worldB, hasSpriteWithNetworkId(playerId(0)));
      expect(worldB, hasSpriteWithNetworkId(playerId(1)));
    });

    test('Resource loading failing p2p', () {
      Injector injectorC = createWorldInjector("c", false);
      // Now comes a goofy client, unable to connect to anyone!
      WormWorld worldC = injectorC.get(WormWorld);
      Loader loaderC = worldC.loader;
      TestPeer peerC = injectorC.get(TestPeer);
      // Connections fail big time.
      peerC.failConnectionsTo
        ..add("a")
        ..add("b");
      worldC.frameDraw();
      expect(loaderC.currentState(), equals(LoaderState.WAITING_FOR_PEER_DATA));
      peerC.receiveActivePeer(['a', 'b', 'c']);
      worldC.frameDraw();
      expect(loaderC.currentState(), equals(LoaderState.CONNECTING_TO_PEER));
      peerC.signalErrorAllConnections();
      worldC.frameDraw();
      expect(loaderC.currentState(), equals(LoaderState.LOADING_SERVER));
      FakeImageFactory fakeImageFactoryC = injectorC.get(FakeImageFactory);
      fakeImageFactoryC.completeAllImages();
      worldC.frameDraw(KEY_FRAME_DEFAULT);
      expect(loaderC.currentState(), equals(LoaderState.LOADING_RESOURCES_COMPLETED));
      worldC.frameDraw(KEY_FRAME_DEFAULT);

      expect(worldC, hasSpriteWithNetworkId(playerId(0)));
      expect(worldC.spriteIndex[playerId(0)],
          hasType('LocalPlayerSprite'));
    });
    test('Resource loading partial p2p', () {
      Injector injectorA = createWorldInjector("a", false);
      Injector injectorB = createWorldInjector("b", false);

      WormWorld worldA = injectorA.get(WormWorld);
      TestPeer peerA = injectorA.get(TestPeer);
      Loader loaderA = worldA.loader;
      FakeImageFactory fakeImageFactoryA = injectorA.get(FakeImageFactory);

      WormWorld worldB = injectorB.get(WormWorld);
      Loader loaderB = worldB.loader;
      TestPeer peerB = injectorB.get(TestPeer);

      // WorldA receives no peers.
      worldA.frameDraw();
      expect(loaderA.currentState(), equals(LoaderState.WAITING_FOR_PEER_DATA));
      peerA.receiveActivePeer([]);
      worldA.frameDraw();
      // Completes loading from Server.
      expect(loaderA.currentState(), equals(LoaderState.LOADING_SERVER));
      worldA.frameDraw();
      fakeImageFactoryA.completeAllImages();
      worldA.frameDraw();
      expect(loaderA.currentState(), equals(LoaderState.LOADING_RESOURCES_COMPLETED));

      // WorldB receives worldA as peer.
      worldB.frameDraw();
      expect(loaderB.currentState(), equals(LoaderState.WAITING_FOR_PEER_DATA));
      worldB.frameDraw();
      // Connection works for 5 packets;
      droppedPacketsAfterNextConnection.add(5);
      peerB.receiveActivePeer(['a', 'b']);
      worldB.frameDraw();
      expect(loaderB.currentState(), equals(LoaderState.LOADING_OTHER_CLIENT));
      worldB.frameDraw();
      expect(loaderB.currentState(), equals(LoaderState.LOADING_OTHER_CLIENT));

      // All connections just died.
      peerB.signalCloseOnAllConnections();
      worldB.frameDraw();
      expect(loaderB.currentState(), equals(LoaderState.LOADING_SERVER));

      // Complete me, load from server.
      FakeImageFactory fakeImageFactoryC = injectorB.get(FakeImageFactory);
      fakeImageFactoryC.completeAllImages();

      // Completed loading form server.
      worldB.frameDraw();
      expect(loaderB.currentState(), equals(LoaderState.LOADING_RESOURCES_COMPLETED));
    });
  });
}
