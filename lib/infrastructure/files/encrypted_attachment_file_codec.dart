import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../../core/serialization/canonical_json.dart';
import '../security/attachment_cipher.dart';

final class StoredEncryptedAttachment {
  const StoredEncryptedAttachment({
    required this.file,
    required this.clearByteSize,
    required this.clearSha256,
    required this.chunkCount,
  });

  final File file;
  final int clearByteSize;
  final String clearSha256;
  final int chunkCount;
}

final class EncryptedAttachmentFileCodec {
  const EncryptedAttachmentFileCodec({
    required this.cipher,
    this.chunkSize = 256 * 1024,
  }) : assert(chunkSize > 0);

  static final _magic = Uint8List.fromList(utf8.encode('EQUISATT'));
  static const formatVersion = 1;
  static const _maxHeaderBytes = 64 * 1024;

  final AttachmentCipher cipher;
  final int chunkSize;

  Future<StoredEncryptedAttachment> encryptFile({
    required File source,
    required File destination,
    required String vaultId,
    required String attachmentId,
  }) async {
    if (!await source.exists()) throw const AttachmentFileNotFoundException();
    if (await destination.exists()) {
      throw const AttachmentFileAlreadyExistsException();
    }
    final clearByteSize = await source.length();
    final clearSha256 = await _sha256(source);
    final chunkCount = clearByteSize == 0
        ? 0
        : (clearByteSize + chunkSize - 1) ~/ chunkSize;
    final session = await cipher.createEncryptionSession(
      vaultId: vaultId,
      attachmentId: attachmentId,
    );
    final header = CanonicalJson.encodeUtf8({
      'attachment_id': attachmentId,
      'chunk_count': chunkCount,
      'chunk_size': chunkSize,
      'cipher': 'xchacha20-poly1305',
      'cipher_version': 1,
      'clear_byte_size': clearByteSize,
      'clear_sha256': clearSha256,
      'format': 'equis-attachment',
      'format_version': formatVersion,
      'key_nonce': base64UrlEncode(session.wrappedKey.nonce),
      'key_version': session.wrappedKey.keyVersion,
      'vault_id': vaultId,
      'wrapped_key': base64UrlEncode(session.wrappedKey.wrappedKey),
    });
    if (header.length > _maxHeaderBytes) {
      throw const AttachmentFileFormatException();
    }

    await destination.parent.create(recursive: true);
    final temporary = File('${destination.path}.part');
    if (await temporary.exists()) await temporary.delete();
    RandomAccessFile? output;
    RandomAccessFile? input;
    try {
      output = await temporary.open(mode: FileMode.write);
      await output.writeFrom(_magic);
      final prefix = ByteData(6)
        ..setUint16(0, formatVersion, Endian.big)
        ..setUint32(2, header.length, Endian.big);
      await output.writeFrom(prefix.buffer.asUint8List());
      await output.writeFrom(header);
      input = await source.open();
      for (var index = 0; index < chunkCount; index++) {
        final clear = await input.read(chunkSize);
        if (clear.isEmpty) throw const AttachmentFileFormatException();
        final chunk = await session.encryptChunk(
          index: index,
          clearText: clear,
        );
        final encrypted = chunk.toCloudBytes();
        final chunkPrefix = ByteData(8)
          ..setUint32(0, index, Endian.big)
          ..setUint32(4, encrypted.length, Endian.big);
        await output.writeFrom(chunkPrefix.buffer.asUint8List());
        await output.writeFrom(encrypted);
      }
      await output.flush();
      await input.close();
      input = null;
      await output.close();
      output = null;
      await temporary.rename(destination.path);
      return StoredEncryptedAttachment(
        file: destination,
        clearByteSize: clearByteSize,
        clearSha256: clearSha256,
        chunkCount: chunkCount,
      );
    } catch (_) {
      await input?.close();
      await output?.close();
      if (await temporary.exists()) await temporary.delete();
      rethrow;
    }
  }

  Future<StoredEncryptedAttachment> encryptBytes({
    required List<int> clearBytes,
    required File destination,
    required String vaultId,
    required String attachmentId,
  }) async {
    if (await destination.exists()) {
      throw const AttachmentFileAlreadyExistsException();
    }
    final clearByteSize = clearBytes.length;
    final clearSha256 = _hex((await Sha256().hash(clearBytes)).bytes);
    final chunkCount = clearByteSize == 0
        ? 0
        : (clearByteSize + chunkSize - 1) ~/ chunkSize;
    final session = await cipher.createEncryptionSession(
      vaultId: vaultId,
      attachmentId: attachmentId,
    );
    final header = CanonicalJson.encodeUtf8({
      'attachment_id': attachmentId,
      'chunk_count': chunkCount,
      'chunk_size': chunkSize,
      'cipher': 'xchacha20-poly1305',
      'cipher_version': 1,
      'clear_byte_size': clearByteSize,
      'clear_sha256': clearSha256,
      'format': 'equis-attachment',
      'format_version': formatVersion,
      'key_nonce': base64UrlEncode(session.wrappedKey.nonce),
      'key_version': session.wrappedKey.keyVersion,
      'vault_id': vaultId,
      'wrapped_key': base64UrlEncode(session.wrappedKey.wrappedKey),
    });
    await destination.parent.create(recursive: true);
    final temporary = File('${destination.path}.part');
    if (await temporary.exists()) await temporary.delete();
    RandomAccessFile? output;
    try {
      output = await temporary.open(mode: FileMode.write);
      await output.writeFrom(_magic);
      final prefix = ByteData(6)
        ..setUint16(0, formatVersion, Endian.big)
        ..setUint32(2, header.length, Endian.big);
      await output.writeFrom(prefix.buffer.asUint8List());
      await output.writeFrom(header);
      for (var index = 0; index < chunkCount; index++) {
        final start = index * chunkSize;
        final end = (start + chunkSize).clamp(0, clearByteSize);
        final chunk = await session.encryptChunk(
          index: index,
          clearText: clearBytes.sublist(start, end),
        );
        final encrypted = chunk.toCloudBytes();
        final chunkPrefix = ByteData(8)
          ..setUint32(0, index, Endian.big)
          ..setUint32(4, encrypted.length, Endian.big);
        await output.writeFrom(chunkPrefix.buffer.asUint8List());
        await output.writeFrom(encrypted);
      }
      await output.flush();
      await output.close();
      output = null;
      await temporary.rename(destination.path);
      return StoredEncryptedAttachment(
        file: destination,
        clearByteSize: clearByteSize,
        clearSha256: clearSha256,
        chunkCount: chunkCount,
      );
    } catch (_) {
      await output?.close();
      if (await temporary.exists()) await temporary.delete();
      rethrow;
    }
  }

  Future<void> decryptFile({
    required File source,
    required File destination,
    required String vaultId,
    required String attachmentId,
  }) async {
    if (!await source.exists()) throw const AttachmentFileNotFoundException();
    if (await destination.exists()) {
      throw const AttachmentFileAlreadyExistsException();
    }
    await destination.parent.create(recursive: true);
    final temporary = File('${destination.path}.part');
    if (await temporary.exists()) await temporary.delete();
    RandomAccessFile? output;
    try {
      output = await temporary.open(mode: FileMode.write);
      await _decrypt(
        source: source,
        vaultId: vaultId,
        attachmentId: attachmentId,
        onChunk: output.writeFrom,
      );
      await output.flush();
      await output.close();
      output = null;
      await temporary.rename(destination.path);
    } catch (error) {
      await output?.close();
      if (await temporary.exists()) await temporary.delete();
      if (error is AttachmentCipherAuthenticationException) {
        throw const AttachmentFileAuthenticationException();
      }
      rethrow;
    }
  }

  Future<Uint8List> decryptBytes({
    required File source,
    required String vaultId,
    required String attachmentId,
  }) async {
    final builder = BytesBuilder(copy: false);
    await _decrypt(
      source: source,
      vaultId: vaultId,
      attachmentId: attachmentId,
      onChunk: (chunk) async => builder.add(chunk),
    );
    return builder.takeBytes();
  }

  Future<void> _decrypt({
    required File source,
    required String vaultId,
    required String attachmentId,
    required Future<void> Function(Uint8List) onChunk,
  }) async {
    if (!await source.exists()) throw const AttachmentFileNotFoundException();
    RandomAccessFile? input;
    try {
      input = await source.open();
      final magic = await _readExact(input, _magic.length);
      if (!_bytesEqual(magic, _magic)) {
        throw const AttachmentFileFormatException();
      }
      final prefix = ByteData.sublistView(await _readExact(input, 6));
      if (prefix.getUint16(0, Endian.big) != formatVersion) {
        throw const AttachmentFileUnsupportedVersionException();
      }
      final headerLength = prefix.getUint32(2, Endian.big);
      if (headerLength == 0 || headerLength > _maxHeaderBytes) {
        throw const AttachmentFileFormatException();
      }
      final decoded = jsonDecode(
        utf8.decode(await _readExact(input, headerLength)),
      );
      if (decoded is! Map<String, dynamic>) {
        throw const AttachmentFileFormatException();
      }
      final header = Map<String, Object?>.from(decoded);
      _validateHeader(header, vaultId, attachmentId);
      final wrappedKey = WrappedAttachmentKey(
        vaultId: vaultId,
        attachmentId: attachmentId,
        keyVersion: header['key_version']! as int,
        nonce: _decodeBase64(header['key_nonce']),
        wrappedKey: _decodeBase64(header['wrapped_key']),
      );
      final session = await cipher.createDecryptionSession(wrappedKey);
      final expectedChunks = header['chunk_count']! as int;
      final expectedSize = header['clear_byte_size']! as int;
      final expectedHash = header['clear_sha256']! as String;
      final hashSink = Sha256().newHashSink();
      var clearSize = 0;
      for (var index = 0; index < expectedChunks; index++) {
        final chunkPrefix = ByteData.sublistView(await _readExact(input, 8));
        final storedIndex = chunkPrefix.getUint32(0, Endian.big);
        final encryptedLength = chunkPrefix.getUint32(4, Endian.big);
        if (storedIndex != index ||
            encryptedLength < 40 ||
            encryptedLength > chunkSize + 40) {
          throw const AttachmentFileFormatException();
        }
        final bytes = await _readExact(input, encryptedLength);
        final clear = await session.decryptChunk(
          EncryptedAttachmentChunk(
            index: index,
            nonce: bytes.sublist(0, 24),
            cipherText: bytes.sublist(24, bytes.length - 16),
            mac: bytes.sublist(bytes.length - 16),
          ),
        );
        clearSize += clear.length;
        hashSink.add(clear);
        await onChunk(clear);
      }
      if (await input.position() != await input.length()) {
        throw const AttachmentFileFormatException();
      }
      hashSink.close();
      final hash = _hex((await hashSink.hash()).bytes);
      if (clearSize != expectedSize || hash != expectedHash) {
        throw const AttachmentFileAuthenticationException();
      }
      await input.close();
      input = null;
    } catch (error) {
      await input?.close();
      if (error is AttachmentCipherAuthenticationException) {
        throw const AttachmentFileAuthenticationException();
      }
      rethrow;
    }
  }

  void _validateHeader(
    Map<String, Object?> header,
    String vaultId,
    String attachmentId,
  ) {
    if (header['format'] != 'equis-attachment' ||
        header['format_version'] != formatVersion ||
        header['cipher'] != 'xchacha20-poly1305' ||
        header['cipher_version'] != 1 ||
        header['vault_id'] != vaultId ||
        header['attachment_id'] != attachmentId ||
        header['chunk_count'] is! int ||
        (header['chunk_count']! as int) < 0 ||
        header['chunk_size'] != chunkSize ||
        header['clear_byte_size'] is! int ||
        (header['clear_byte_size']! as int) < 0 ||
        header['clear_sha256'] is! String ||
        !RegExp(
          r'^[0-9a-f]{64}$',
        ).hasMatch(header['clear_sha256']! as String) ||
        header['key_version'] is! int ||
        header['key_nonce'] is! String ||
        header['wrapped_key'] is! String) {
      throw const AttachmentFileFormatException();
    }
  }

  Future<String> _sha256(File file) async {
    final sink = Sha256().newHashSink();
    await for (final chunk in file.openRead()) {
      sink.add(chunk);
    }
    sink.close();
    return _hex((await sink.hash()).bytes);
  }
}

Future<Uint8List> _readExact(RandomAccessFile file, int length) async {
  final bytes = await file.read(length);
  if (bytes.length != length) throw const AttachmentFileFormatException();
  return bytes;
}

List<int> _decodeBase64(Object? value) {
  if (value is! String) throw const AttachmentFileFormatException();
  try {
    return base64Url.decode(base64Url.normalize(value));
  } on FormatException {
    throw const AttachmentFileFormatException();
  }
}

bool _bytesEqual(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  var difference = 0;
  for (var index = 0; index < left.length; index++) {
    difference |= left[index] ^ right[index];
  }
  return difference == 0;
}

String _hex(Iterable<int> bytes) =>
    bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

final class AttachmentFileNotFoundException implements Exception {
  const AttachmentFileNotFoundException();
}

final class AttachmentFileAlreadyExistsException implements Exception {
  const AttachmentFileAlreadyExistsException();
}

final class AttachmentFileFormatException implements Exception {
  const AttachmentFileFormatException();
}

final class AttachmentFileUnsupportedVersionException implements Exception {
  const AttachmentFileUnsupportedVersionException();
}

final class AttachmentFileAuthenticationException implements Exception {
  const AttachmentFileAuthenticationException();
}
