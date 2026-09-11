import 'dart:io';
import 'package:equis/infrastructure/portability/platform_file_publisher.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(
    () =>
        messenger.setMockMethodCallHandler(PlatformFilePublisher.channel, null),
  );

  test(
    'Android publishes through native URI storage and reads URI separately',
    () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(PlatformFilePublisher.channel, (
        call,
      ) async {
        calls.add(call);
        return call.method == 'publish'
            ? {
                'uri': 'content://downloads/123',
                'location': 'Downloads/Equis/test.equis',
              }
            : null;
      });
      final publisher = PlatformFilePublisher(android: true);
      final result = await publisher.publish(
        File('private/temp.equis'),
        'test.equis',
        'application/octet-stream',
      );
      expect(result!['uri'], 'content://downloads/123');
      await publisher.read(result['uri']!, File('private/check.equis'));
      expect(calls.map((call) => call.method), ['publish', 'read']);
      expect((calls.last.arguments as Map)['uri'], 'content://downloads/123');
    },
  );

  test('document cancellation does not report success', () async {
    messenger.setMockMethodCallHandler(
      PlatformFilePublisher.channel,
      (_) async => null,
    );
    expect(
      await PlatformFilePublisher(
        android: true,
      ).publish(File('test'), 'test.equis', 'application/octet-stream'),
      isNull,
    );
  });

  test(
    'native write failures propagate without successful publication',
    () async {
      messenger.setMockMethodCallHandler(
        PlatformFilePublisher.channel,
        (_) async => throw PlatformException(code: 'save_failed'),
      );
      await expectLater(
        PlatformFilePublisher(
          android: true,
        ).publish(File('test'), 'test.equis', 'application/octet-stream'),
        throwsA(isA<PlatformException>()),
      );
    },
  );
}
