import 'dart:convert';
import 'dart:io';

import 'package:equis/infrastructure/files/encrypted_attachment_file_codec.dart';
import 'package:equis/infrastructure/files/equis_file_layout.dart';
import 'package:equis/infrastructure/security/attachment_cipher.dart';
import 'package:equis/infrastructure/security/secure_string_store.dart';
import 'package:equis/infrastructure/security/vault_key_manager.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const vaultId = '018f47c2-9b72-7cc1-8b83-5d0fead0a001';
  const attachmentId = '018f47c2-9b72-7cc1-8b83-5d0fead0a002';
  late Directory temporary;
  late EncryptedAttachmentFileCodec codec;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('equis-attachment-');
    codec = EncryptedAttachmentFileCodec(cipher: _cipher(7), chunkSize: 64);
  });

  tearDown(() async {
    if (await temporary.exists()) await temporary.delete(recursive: true);
  });

  test(
    'streams a multi-chunk round trip without exposing clear data',
    () async {
      final clear = List<int>.generate(257, (index) => (index * 31) % 256);
      final source = File(
        '${temporary.path}${Platform.pathSeparator}receipt.pdf',
      );
      final encrypted = File(
        '${temporary.path}${Platform.pathSeparator}stored.enc',
      );
      final restored = File(
        '${temporary.path}${Platform.pathSeparator}restored.pdf',
      );
      await source.writeAsBytes(clear);

      final result = await codec.encryptFile(
        source: source,
        destination: encrypted,
        vaultId: vaultId,
        attachmentId: attachmentId,
      );
      await codec.decryptFile(
        source: encrypted,
        destination: restored,
        vaultId: vaultId,
        attachmentId: attachmentId,
      );

      expect(result.chunkCount, 5);
      expect(result.clearByteSize, clear.length);
      expect(await restored.readAsBytes(), clear);
      final stored = await encrypted.readAsBytes();
      expect(stored, isNot(containsAll(clear)));
      expect(
        utf8.decode(stored, allowMalformed: true),
        isNot(contains('receipt.pdf')),
      );
    },
  );

  test(
    'fails closed after ciphertext tampering and removes partial output',
    () async {
      final source = File('${temporary.path}${Platform.pathSeparator}source');
      final encrypted = File(
        '${temporary.path}${Platform.pathSeparator}stored.enc',
      );
      final restored = File(
        '${temporary.path}${Platform.pathSeparator}restored',
      );
      await source.writeAsBytes(List<int>.generate(180, (index) => index));
      await codec.encryptFile(
        source: source,
        destination: encrypted,
        vaultId: vaultId,
        attachmentId: attachmentId,
      );
      final bytes = await encrypted.readAsBytes();
      bytes[bytes.length - 20] ^= 1;
      await encrypted.writeAsBytes(bytes, flush: true);

      await expectLater(
        codec.decryptFile(
          source: encrypted,
          destination: restored,
          vaultId: vaultId,
          attachmentId: attachmentId,
        ),
        throwsA(isA<AttachmentFileAuthenticationException>()),
      );
      expect(await restored.exists(), isFalse);
      expect(await File('${restored.path}.part').exists(), isFalse);
    },
  );

  test('binds the encrypted file to its vault and attachment ids', () async {
    final source = File('${temporary.path}${Platform.pathSeparator}source');
    final encrypted = File(
      '${temporary.path}${Platform.pathSeparator}stored.enc',
    );
    await source.writeAsString('private receipt');
    await codec.encryptFile(
      source: source,
      destination: encrypted,
      vaultId: vaultId,
      attachmentId: attachmentId,
    );

    await expectLater(
      codec.decryptFile(
        source: encrypted,
        destination: File('${temporary.path}${Platform.pathSeparator}restored'),
        vaultId: vaultId,
        attachmentId: '018f47c2-9b72-7cc1-8b83-5d0fead0a003',
      ),
      throwsA(isA<AttachmentFileFormatException>()),
    );
  });

  test('uses independent keys and supports empty files', () async {
    final source = File('${temporary.path}${Platform.pathSeparator}empty');
    final first = File('${temporary.path}${Platform.pathSeparator}first.enc');
    final second = File('${temporary.path}${Platform.pathSeparator}second.enc');
    final restored = File('${temporary.path}${Platform.pathSeparator}restored');
    await source.writeAsBytes(const []);

    final firstResult = await codec.encryptFile(
      source: source,
      destination: first,
      vaultId: vaultId,
      attachmentId: attachmentId,
    );
    await codec.encryptFile(
      source: source,
      destination: second,
      vaultId: vaultId,
      attachmentId: attachmentId,
    );
    await codec.decryptFile(
      source: first,
      destination: restored,
      vaultId: vaultId,
      attachmentId: attachmentId,
    );

    expect(firstResult.chunkCount, 0);
    expect(await restored.readAsBytes(), isEmpty);
    expect(await first.readAsBytes(), isNot(await second.readAsBytes()));
  });

  test('creates the locked attachment file layout', () async {
    final layout = EquisFileLayout(
      Directory('${temporary.path}${Platform.pathSeparator}Equis'),
    );
    await layout.ensureCreated();

    expect(await layout.attachments.exists(), isTrue);
    expect(await layout.cache.exists(), isTrue);
    expect(await layout.backups.exists(), isTrue);
    expect(await layout.exports.exists(), isTrue);
    expect(
      layout
          .encryptedAttachment(vaultId: vaultId, attachmentId: attachmentId)
          .path,
      endsWith(
        '${Platform.pathSeparator}$vaultId${Platform.pathSeparator}'
        '$attachmentId.equisatt',
      ),
    );
  });
}

AttachmentCipher _cipher(int seed) => AttachmentCipher(
  keys: VaultKeyManager(
    store: _Store(base64UrlEncode(List<int>.generate(32, (i) => i + seed))),
  ),
);

final class _Store implements SecureStringStore {
  _Store(String master) : values = {'equis.vault_master_key.v1': master};

  final Map<String, String> values;

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}
