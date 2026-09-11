import 'dart:io';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';

/// Publishes completed files; Android content URIs are never treated as paths.
class PlatformFilePublisher {
  PlatformFilePublisher({bool? android})
    : _android = android ?? Platform.isAndroid;
  final bool _android;
  static const channel = MethodChannel('app.saga.equis/files');

  Future<Map<String, String>?> publish(
    File source,
    String name,
    String mime,
  ) async {
    if (_android) {
      final result = await channel.invokeMapMethod<String, String>('publish', {
        'source': source.path,
        'name': name,
        'mime': mime,
      });
      return result;
    }
    final location = await getSaveLocation(suggestedName: name);
    if (location == null) return null;
    await source.copy(location.path);
    return {'uri': location.path, 'location': location.path};
  }

  Future<void> read(String uri, File target) async {
    if (_android && uri.startsWith('content:')) {
      await channel.invokeMethod<void>('read', {
        'uri': uri,
        'target': target.path,
      });
    } else {
      await File(uri).copy(target.path);
    }
  }
}
