import 'package:test/test.dart';
import 'package:dart2d/net/net.dart';
import 'package:dart2d/worlds/byteworld.dart';
import 'package:dart2d/res/imageindex.dart';
import 'package:mockito/mockito.dart';
import 'lib/test_lib.dart';

void main() {
  const String IMAGE_DATA =
      "12345678901234567890123456789012345678901234567890";
  const String BYTE_WORLD_IMAGE_DATA = "abcdefghijklmonpqrstuv";
  const String BYTE_WORLD_IMAGE_DATA2 = "aaaaaaaaaaaaaaaaaaa";
  TestConnectionWrapper connection1;
  TestConnectionWrapper connection2;
  PacketListenerBindings packetListenerBindings;
  ChunkHelper helper;
  ChunkHelper helper2;
  ImageIndex imageIndex;
  ImageIndex imageIndex2;
  ByteWorld byteWorld;
  setUp(() {
    logOutputForTest();
    connection1 = new TestConnectionWrapper("a");
    connection2 = new TestConnectionWrapper("b");
    imageIndex = new MockImageIndex();
    imageIndex2 = new MockImageIndex();
    byteWorld = new MockByteWorld();
    packetListenerBindings = new PacketListenerBindings();
    helper = new ChunkHelper(imageIndex, byteWorld, packetListenerBindings)
      ..setChunkSizeForTest(4);
    helper2 = new ChunkHelper(imageIndex2, byteWorld, packetListenerBindings)
      ..setChunkSizeForTest(4);
  });
  tearDown(() {
    assertNoLoggedWarnings();
  });
  group('Chunk helper tests', () {
    test('Reply with data', () {
      int requestedIndex = 5;
      when(imageIndex.imageIsLoaded(requestedIndex)).thenReturn(true);
      when(imageIndex.getImageDataUrl(requestedIndex)).thenReturn(IMAGE_DATA);
      helper.replyWithImageData({'index': requestedIndex}, connection1);
      // Default chunk size.
      expect(
          connection1.lastDataSent,
          equals({
            '-i': {
              'index': requestedIndex,
              'data': '1234',
              'start': 0,
              'size': IMAGE_DATA.length
            }
          }));
      helper.replyWithImageData(
          {'index': requestedIndex, 'start': 1, 'end': 2}, connection1);
      // Explicit request.
      expect(
          connection1.lastDataSent,
          equals({
            '-i': {
              'index': requestedIndex,
              'data': '2',
              'start': 1,
              'size': IMAGE_DATA.length
            }
          }));
      // Explicit request of final byte.
      helper.replyWithImageData(
          {'index': requestedIndex, 'start': 49, 'end': 900}, connection1);
      expect(
          connection1.lastDataSent,
          equals({
            '-i': {
              'index': requestedIndex,
              'data': '0',
              'start': 49,
              'size': IMAGE_DATA.length
            }
          }));
    });

    test('Test single load', () {
      int requestedIndex = 6;
      when(imageIndex.getImageDataUrl(requestedIndex)).thenReturn(IMAGE_DATA);
      when(imageIndex.imageIsLoaded(requestedIndex)).thenReturn(true);
      when(imageIndex2.imageIsLoaded(requestedIndex)).thenReturn(false);
      // Set image to be loaded.
      when(imageIndex2.addFromImageData(requestedIndex, IMAGE_DATA))
          .thenAnswer((i) {
        when(imageIndex2.imageIsLoaded(requestedIndex)).thenReturn(true);
      });

      Map request = helper2.buildImageChunkRequest(requestedIndex);
      helper.replyWithImageData(request, connection1);
      helper2.parseImageChunkResponse(
          connection1.lastDataSent[IMAGE_DATA_RESPONSE], connection1);

      String fullData = IMAGE_DATA;
      String expectedData = fullData.substring(0, 4);
      expect(helper2.getImageBuffer(), equals({requestedIndex: expectedData}));

      while (helper2.getCompleteRatio(requestedIndex) < 1.0) {
        print("Completed ratio is ${helper2.getCompleteRatio(requestedIndex)}");
        Map request = helper2.buildImageChunkRequest(requestedIndex);
        helper.replyWithImageData(request, connection1);
        helper2.parseImageChunkResponse(
            connection1.lastDataSent[IMAGE_DATA_RESPONSE], connection1);
      }

      expect(IMAGE_DATA, equals(fullData));
    });

    test('Test single load missing server fallback', () {
      int requestedIndex = 6;
      when(imageIndex.imageIsLoaded(requestedIndex)).thenReturn(false);
      Map request = helper.buildImageChunkRequest(requestedIndex);

      try {
        helper.replyWithImageData(request, connection1);
        fail("Should throw!");
      } catch (e, stack) {
        expect(e, isStateError);
      }
      // We triggered the fallback to load from server.
      verify(imageIndex.loadImagesFromServer());
    });

    test('Test end-2-end', () {
      int requestedIndex = 9;
      int requestedIndex2 = 6;
      Map connections = {1: connection1};

      Map map = {"image1.png": requestedIndex, "image2.png": requestedIndex2};
      when(imageIndex.getImageDataUrl(requestedIndex)).thenReturn(IMAGE_DATA);
      when(imageIndex.getImageDataUrl(requestedIndex2)).thenReturn(IMAGE_DATA);
      when(imageIndex2.imageIsLoaded(requestedIndex2)).thenReturn(true);
      when(imageIndex.imageIsLoaded(requestedIndex2)).thenReturn(true);
      when(imageIndex.imageIsLoaded(requestedIndex)).thenReturn(false);
      when(imageIndex.allImagesByName()).thenReturn(map);
      when(imageIndex2.imageIsLoaded(requestedIndex)).thenReturn(true);
      when(imageIndex2.getImageDataUrl(requestedIndex)).thenReturn(IMAGE_DATA);

      // Set image to be loaded.
      when(imageIndex.addFromImageData(requestedIndex, IMAGE_DATA))
          .thenAnswer((i) {
        when(imageIndex.imageIsLoaded(requestedIndex)).thenReturn(true);
      });

      // Loop until completed.
      for (int i = 0; i < 20; i++) {
        if (imageIndex.imageIsLoaded(requestedIndex)) {
          break;
        }
        helper.requestNetworkData(connections, 0.1);
        helper2.replyWithImageData(
            connection1.lastDataSent[IMAGE_DATA_REQUEST], connection1);
        helper.parseImageChunkResponse(
            connection1.lastDataSent[IMAGE_DATA_RESPONSE], connection1);
      }
      // Fully loaded.
      expect(imageIndex.imageIsLoaded(requestedIndex), isTrue);
    });
    test('Test retries', () {
      Map connections = {connection1.id: connection1};
      Map map = {
        "image1.png": 4,
        "image2.png": 6,
        "image3.png": 7,
        "image5.png": 9,
        "image9.png": 91,
        "image99.png": 31
      };
      when(imageIndex.getImageDataUrl(argThat(anything)))
          .thenReturn(IMAGE_DATA);
      when(imageIndex.imageIsLoaded(argThat(anything))).thenReturn(false);
      when(imageIndex.allImagesByName()).thenReturn(map);

      helper.requestNetworkData(connections, 0.01);
      expect(connection1.sendCount, equals(3));
      expect(
          connection1.dataSent,
          equals([
            {
              '_i': {'index': 4, 'start': 0, 'end': 5}
            },
            {
              '_i': {'index': 6, 'start': 0, 'end': 6}
            },
            {
              '_i': {'index': 7, 'start': 0, 'end': 7}
            }
          ]));
      // Should not retry, too soon.
      helper.requestNetworkData(connections, 0.01);
      expect(connection1.sendCount, equals(3));
      // Next trigger is in 3 seconds.
      helper.requestNetworkData(connections, 3.00);
      // Next trigger is in 3 seconds.
      helper.requestNetworkData(connections, 3.00);
      // 3*3
      expect(connection1.sendCount, equals(9));
      expect(helper.failuresByConnection(), equals({"a": 6}));
    });
    test('Test with byteworld state', () {
      int requestedIndex = ImageIndex.WORLD_IMAGE_INDEX;
      Map connections = {1: connection1};

      Map map = {"image2.png": requestedIndex};
      when(byteWorld.asDataUrl()).thenReturn(BYTE_WORLD_IMAGE_DATA);
      when(imageIndex.imageIsLoaded(requestedIndex)).thenReturn(false);
      when(imageIndex.allImagesByName()).thenReturn(map);
      when(imageIndex2.allImagesByName()).thenReturn(map);
      when(imageIndex2.imageIsLoaded(requestedIndex)).thenReturn(false);

      helper.requestNetworkData(connections, 0.01);
      helper.replyWithImageData(
          connection1.lastDataSent[IMAGE_DATA_REQUEST], connection1);
      expect(
          connection1.lastDataSent,
          equals({
            '-i': {
              'index': requestedIndex,
              'data': 'abcde',
              'start': 0,
              'size': BYTE_WORLD_IMAGE_DATA.length
            }
          }));
      expect(
          helper.getByteWorldCache(), equals({'a': 'abcdefghijklmonpqrstuv'}));

      // Another connection comes along.
      when(imageIndex.imageIsLoaded(requestedIndex)).thenReturn(false);
      when(byteWorld.asDataUrl()).thenReturn(BYTE_WORLD_IMAGE_DATA2);
      Map connections2 = {2: connection2};
      helper2.requestNetworkData(connections2, 0.01);
      helper.replyWithImageData(
          connection2.lastDataSent[IMAGE_DATA_REQUEST], connection2);
      // Gets Byteworld 2 data.
      expect(
          connection2.lastDataSent,
          equals({
            IMAGE_DATA_RESPONSE: {
              'index': requestedIndex,
              'data': 'aaaaa',
              'start': 0,
              'size': BYTE_WORLD_IMAGE_DATA2.length
            }
          }));
      // Two versions cached.
      expect(helper.getByteWorldCache(),
          equals({'a': 'abcdefghijklmonpqrstuv', 'b': 'aaaaaaaaaaaaaaaaaaa'}));
      // Trigger a client enter for a.
      packetListenerBindings.handlerFor(CLIENT_PLAYER_ENTER)[0](
          connection1, null);
      // This cleared the cache for a.
      expect(helper.getByteWorldCache(), equals({'b': 'aaaaaaaaaaaaaaaaaaa'}));
    });
  });
}
