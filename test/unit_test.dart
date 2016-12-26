import 'package:test/test.dart';
import 'package:dart2d/net/chunk_helper.dart';
import 'package:dart2d/res/imageindex.dart';
import 'package:dart2d/net/state_updates.dart';
import 'package:mockito/mockito.dart';
import 'test_connection.dart';

class MockImageIndex extends Mock implements ImageIndex {}

void main() {
  const String IMAGE_DATA =
      "12345678901234567890123456789012345678901234567890";
  TestConnectionWrapper connection1;
  TestConnectionWrapper connection2;
  ChunkHelper helper;
  ChunkHelper helper2;
  ImageIndex imageIndex;
  ImageIndex imageIndex2;
  setUp(() {
    connection1 = new TestConnectionWrapper("a");
    connection2 = new TestConnectionWrapper("b");
    imageIndex = new MockImageIndex();
    imageIndex2 = new MockImageIndex();
    helper = new ChunkHelper(imageIndex, null)
      ..setChunkSizeForTest(4);
    helper2 = new ChunkHelper(imageIndex, null)
      ..setChunkSizeForTest(4);
  });
  group('Chunk helper tests', () {
    test('Reply with data', () {
      int requestedIndex = 5;
      when(imageIndex.getImageDataUrl(requestedIndex)).thenReturn(IMAGE_DATA);
      helper.replyWithImageData({
        IMAGE_DATA_REQUEST: {'index': requestedIndex}
      }, connection1);
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
      helper.replyWithImageData({
        IMAGE_DATA_REQUEST: {'index': requestedIndex, 'start': 1, 'end': 2}
      }, connection1);
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
      helper.replyWithImageData({
        IMAGE_DATA_REQUEST: {'index': requestedIndex, 'start': 49, 'end': 900}
      }, connection1);
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
      Map request = helper.buildImageChunkRequest(requestedIndex);
      helper.replyWithImageData({IMAGE_DATA_REQUEST: request}, connection1);
      helper.parseImageChunkResponse(connection1.lastDataSent);

      String fullData = IMAGE_DATA;
      String expectedData = fullData.substring(0, helper.chunkSize);
      expect(helper.getImageBuffer(), equals({requestedIndex: expectedData}));

      while (helper.getImageBuffer().containsKey(requestedIndex)) {
        Map request = helper.buildImageChunkRequest(requestedIndex);
        helper.replyWithImageData({IMAGE_DATA_REQUEST: request}, connection1);
        helper.parseImageChunkResponse(connection1.lastDataSent);
      }

      expect(IMAGE_DATA, equals(fullData));
    });
    test('Test end-2-end', () {
      int requestedIndex = 9;
      int requestedIndex2 = 6;
      List connections = new List.filled(1, connection1);

      Map map = {"image1.png":requestedIndex, "image2.png":requestedIndex2};
      when(imageIndex.getImageDataUrl(requestedIndex)).thenReturn(IMAGE_DATA);
      when(imageIndex.getImageDataUrl(requestedIndex2)).thenReturn(IMAGE_DATA);
      when(imageIndex.imageIsLoaded(requestedIndex2)).thenReturn(true);
      when(imageIndex.imageIsLoaded(requestedIndex)).thenReturn(false);
      when(imageIndex.allImagesByName()).thenReturn(map);
      when(imageIndex2.getImageDataUrl(requestedIndex)).thenReturn(IMAGE_DATA);

      // Set image to be loaded.
      when(imageIndex.addFromImageData(requestedIndex, IMAGE_DATA)).thenAnswer((i) {
        when(imageIndex.imageIsLoaded(requestedIndex)).thenReturn(true);
      });

      // Loop until completed.
      for (int i = 0; i < 20; i++) {
        if (imageIndex.imageIsLoaded(requestedIndex)) {
          break;
        }
        helper.requestNetworkData(connections, 0.01);
        helper2.replyWithImageData(connection1.lastDataSent, connection1);
        helper.parseImageChunkResponse(connection1.lastDataSent);
      }
      // Fully loaded.
      expect(imageIndex.imageIsLoaded(requestedIndex), isTrue);
    });
    test('Test retries', () {
      int requestedIndex = 4;
      List connections = new List.filled(1, connection1);
      Map map = {"image1.png":requestedIndex};
      when(imageIndex.getImageDataUrl(requestedIndex)).thenReturn(IMAGE_DATA);
      when(imageIndex.imageIsLoaded(requestedIndex)).thenReturn(false);
      when(imageIndex.allImagesByName()).thenReturn(map);
      when(imageIndex2.getImageDataUrl(requestedIndex)).thenReturn(IMAGE_DATA);

      helper.requestNetworkData(connections, 0.50);
      expect(connection1.sendCount, equals(1));
      // Next trigger is in 3 seconds.
      helper.requestNetworkData(connections, 3.00);
      // Next trigger is in 3 seconds.
      helper.requestNetworkData(connections, 3.00);
      expect(connection1.sendCount, equals(3));
      expect(helper.failuresByConnection(), equals({"a": 2}));
    });
  });
}
