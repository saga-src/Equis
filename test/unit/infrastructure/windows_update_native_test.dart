import 'dart:ffi';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:equis/infrastructure/updates/windows_update_native.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('WindowsUpdateNative', () {
    test(
      'retains a stable process identity for the current process',
      () {
        final current = WindowsUpdateProcess.current();
        try {
          final reopened = WindowsUpdateProcess.open(
            current.pid,
            createdFiletime: current.createdFiletime,
          );
          try {
            expect(reopened.pid, current.pid);
            expect(reopened.createdFiletime, current.createdFiletime);
            expect(reopened.sid, current.sid);
            expect(reopened.session, current.session);
            expect(reopened.integrityRid, current.integrityRid);
            expect(reopened.isAlive, isTrue);
            expect(reopened.imagePath, isNotEmpty);
            expect(reopened.imageFileId, isNotEmpty);
          } finally {
            reopened.close();
          }
        } finally {
          current.close();
        }
      },
      skip: !Platform.isWindows,
    );

    test(
      'rejects invalid process IDs before making a Win32 call',
      () {
        expect(
          () => WindowsUpdateProcess.open(0),
          throwsA(
            isA<WindowsUpdateNativeException>().having(
              (error) => error.code,
              'code',
              'invalid_pid',
            ),
          ),
        );
      },
      skip: !Platform.isWindows,
    );

    test(
      'file handle verifies bytes and prevents replacement until closed',
      () async {
        final root = await Directory.systemTemp.createTemp(
          'equis update file lock with spaces ',
        );
        addTearDown(() async {
          if (await root.exists()) await root.delete(recursive: true);
        });
        final path = p.join(root.path, 'payload.bin');
        final file = File(path);
        final bytes = List<int>.generate(4096, (index) => index % 251);
        await file.writeAsBytes(bytes, flush: true);
        final expected = await _sha256Hex(bytes);
        final lock = WindowsUpdateFile.open(path);
        try {
          expect(lock.size, bytes.length);
          expect(lock.verifySha256(expected, bytes.length), isTrue);
          expect(
            lock.verifySha256(List.filled(64, '0').join(), bytes.length),
            isFalse,
          );
          expect(lock.verifySha256(expected, bytes.length + 1), isFalse);
          await expectLater(file.rename('$path.replaced'), throwsA(anything));
        } finally {
          lock.close();
        }
        await file.rename('$path.replaced');
        expect(await File('$path.replaced').exists(), isTrue);
      },
      skip: !Platform.isWindows,
    );

    test(
      'target lease excludes a second attempt and releases on close',
      () {
        final target = Directory.systemTemp.path;
        final first = WindowsUpdateMutex.acquire(target);
        try {
          expect(
            () => WindowsUpdateMutex.acquire(target),
            throwsA(
              isA<WindowsUpdateNativeException>().having(
                (error) => error.code,
                'code',
                'update_already_running',
              ),
            ),
          );
        } finally {
          first.close();
        }
        final next = WindowsUpdateMutex.acquire(target);
        next.close();
      },
      skip: !Platform.isWindows,
    );

    test(
      'pipe records the actual same-user client process and exchanges lines',
      () async {
        final owner = WindowsUpdateProcess.current();
        final pipeName =
            r'\\.\pipe\Equis.Update.' +
            List<String>.generate(
              32,
              (index) => (index % 16).toRadixString(16),
            ).join();
        final server = WindowsUpdatePipeServer.create(pipeName, owner.sid);
        final accepting = server.accept();
        int? clientHandle;
        WindowsUpdatePipeConnection? connection;
        try {
          clientHandle = _openPipeClient(pipeName);
          connection = await accepting.timeout(const Duration(seconds: 5));
          expect(connection.process.pid, pid);
          expect(connection.process.sid, owner.sid);
          expect(connection.process.session, owner.session);

          _writePipeBytes(clientHandle, [...'INSTALL_REQUEST\t2\n'.codeUnits]);
          expect(await connection.readLine(), 'INSTALL_REQUEST\t2');
          await connection.writeLine('GO');
          expect(_readPipeLine(clientHandle), 'GO');
          _closePipeClient(clientHandle);
          clientHandle = null;
          await expectLater(
            connection.readLine(),
            throwsA(isA<WindowsUpdateNativeException>()),
          );
        } finally {
          if (connection != null) await connection.close();
          if (clientHandle != null) _closePipeClient(clientHandle);
          await server.close();
          owner.close();
        }
      },
      skip: !Platform.isWindows,
    );

    test(
      'closing a server cancels and drains its pending accept operation',
      () async {
        final owner = WindowsUpdateProcess.current();
        final pipeName =
            r'\\.\pipe\Equis.Update.' +
            List<String>.generate(
              32,
              (index) => ((index + 1) % 16).toRadixString(16),
            ).join();
        final server = WindowsUpdatePipeServer.create(pipeName, owner.sid);
        final accepting = server.accept();
        final cancelled = expectLater(
          accepting,
          throwsA(isA<WindowsUpdateNativeException>()),
        );
        try {
          await server.close();
          await cancelled;
        } finally {
          await server.close();
          owner.close();
        }
      },
      skip: !Platform.isWindows,
    );

    test(
      'pipe rejects names outside the transaction namespace',
      () {
        expect(
          () => WindowsUpdatePipeServer.create(
            r'\\.\pipe\Equis.Update.invalid',
            'S-1-5-18',
          ),
          throwsA(isA<WindowsUpdateNativeException>()),
        );
      },
      skip: !Platform.isWindows,
    );
  });
}

Future<String> _sha256Hex(List<int> bytes) async {
  // The expected hash is derived independently from the native verifier.
  final digest = await Sha256().hash(bytes);
  return digest.bytes
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
}

int _openPipeClient(String name) {
  final kernel32 = DynamicLibrary.open('kernel32.dll');
  final createFile = kernel32
      .lookupFunction<
        IntPtr Function(
          Pointer<Uint16>,
          Uint32,
          Uint32,
          Pointer<Void>,
          Uint32,
          Uint32,
          IntPtr,
        ),
        int Function(Pointer<Uint16>, int, int, Pointer<Void>, int, int, int)
      >('CreateFileW');
  final path = name.toNativeUtf16(allocator: calloc);
  try {
    final handle = createFile(
      path.cast<Uint16>(),
      0xC0000000,
      0,
      nullptr,
      3,
      0,
      0,
    );
    if (handle == -1) throw StateError('Could not connect test pipe client');
    return handle;
  } finally {
    calloc.free(path);
  }
}

void _writePipeBytes(int handle, List<int> bytes) {
  final kernel32 = DynamicLibrary.open('kernel32.dll');
  final writeFile = kernel32
      .lookupFunction<
        Int32 Function(
          IntPtr,
          Pointer<Uint8>,
          Uint32,
          Pointer<Uint32>,
          Pointer<Void>,
        ),
        int Function(int, Pointer<Uint8>, int, Pointer<Uint32>, Pointer<Void>)
      >('WriteFile');
  final buffer = calloc<Uint8>(bytes.length);
  final written = calloc<Uint32>();
  try {
    buffer.asTypedList(bytes.length).setAll(0, bytes);
    if (writeFile(handle, buffer, bytes.length, written, nullptr) == 0 ||
        written.value != bytes.length) {
      throw StateError('Could not write test pipe bytes');
    }
  } finally {
    calloc.free(written);
    calloc.free(buffer);
  }
}

String _readPipeLine(int handle) {
  final kernel32 = DynamicLibrary.open('kernel32.dll');
  final readFile = kernel32
      .lookupFunction<
        Int32 Function(
          IntPtr,
          Pointer<Uint8>,
          Uint32,
          Pointer<Uint32>,
          Pointer<Void>,
        ),
        int Function(int, Pointer<Uint8>, int, Pointer<Uint32>, Pointer<Void>)
      >('ReadFile');
  final buffer = calloc<Uint8>();
  final read = calloc<Uint32>();
  final bytes = <int>[];
  try {
    while (true) {
      if (readFile(handle, buffer, 1, read, nullptr) == 0 || read.value != 1) {
        throw StateError('Could not read test pipe line');
      }
      if (buffer.value == 10) return String.fromCharCodes(bytes);
      bytes.add(buffer.value);
      if (bytes.length > 8192) throw StateError('Test pipe line too long');
    }
  } finally {
    calloc.free(read);
    calloc.free(buffer);
  }
}

void _closePipeClient(int handle) {
  DynamicLibrary.open(
    'kernel32.dll',
  ).lookupFunction<Int32 Function(IntPtr), int Function(int)>('CloseHandle')(
    handle,
  );
}
