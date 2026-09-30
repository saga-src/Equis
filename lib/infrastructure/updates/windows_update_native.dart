import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:ffi/ffi.dart';

// This module owns local Win32 handles. It does not decide whether a catalog,
// installer, target, or update request is trusted.
const _invalidHandle = -1;
const _synchronize = 0x00100000;
const _processQueryLimitedInformation = 0x1000;
const _tokenQuery = 0x0008;
const _genericRead = 0x80000000;
const _fileShareRead = 1;
const _openExisting = 3;
const _fileFlagOpenReparsePoint = 0x00200000;
const _fileFlagOverlapped = 0x40000000;
const _pipeAccessDuplex = 3;
const _pipeTypeByte = 0;
const _pipeReadmodeByte = 0;
const _pipeWait = 0;
const _pipeRejectRemoteClients = 8;
const _errorIoPending = 997;
const _errorOperationAborted = 995;
const _errorPipeConnected = 535;
const _waitObject0 = 0;
const _waitTimeout = 0x102;
const _pipeLineLimit = 8192;
const _pipePrefix = r'\\.\pipe\Equis.Update.';
final _pipePattern = RegExp(r'^\\\\\.\\pipe\\Equis\.Update\.[0-9a-f]{32}$');
final _sidPattern = RegExp(r'^S-1-(?:[0-9]+-){1,14}[0-9]+$');

final _kernel32 = DynamicLibrary.open('kernel32.dll');
final _advapi32 = DynamicLibrary.open('advapi32.dll');
final _shell32 = DynamicLibrary.open('shell32.dll');

final _getLastError = _kernel32
    .lookupFunction<Uint32 Function(), int Function()>('GetLastError');
final _closeHandle = _kernel32
    .lookupFunction<Int32 Function(IntPtr), int Function(int)>('CloseHandle');
final _getCurrentProcessId = _kernel32
    .lookupFunction<Uint32 Function(), int Function()>('GetCurrentProcessId');
final _openProcess = _kernel32
    .lookupFunction<
      IntPtr Function(Uint32, Int32, Uint32),
      int Function(int, int, int)
    >('OpenProcess');
final _getProcessTimes = _kernel32
    .lookupFunction<
      Int32 Function(
        IntPtr,
        Pointer<_FileTime>,
        Pointer<_FileTime>,
        Pointer<_FileTime>,
        Pointer<_FileTime>,
      ),
      int Function(
        int,
        Pointer<_FileTime>,
        Pointer<_FileTime>,
        Pointer<_FileTime>,
        Pointer<_FileTime>,
      )
    >('GetProcessTimes');
final _getProcessId = _kernel32
    .lookupFunction<Uint32 Function(IntPtr), int Function(int)>('GetProcessId');
final _getExitCodeProcess = _kernel32
    .lookupFunction<
      Int32 Function(IntPtr, Pointer<Uint32>),
      int Function(int, Pointer<Uint32>)
    >('GetExitCodeProcess');
final _waitForSingleObject = _kernel32
    .lookupFunction<Uint32 Function(IntPtr, Uint32), int Function(int, int)>(
      'WaitForSingleObject',
    );
final _openProcessToken = _advapi32
    .lookupFunction<
      Int32 Function(IntPtr, Uint32, Pointer<IntPtr>),
      int Function(int, int, Pointer<IntPtr>)
    >('OpenProcessToken');
final _getTokenInformation = _advapi32
    .lookupFunction<
      Int32 Function(IntPtr, Int32, Pointer<Void>, Uint32, Pointer<Uint32>),
      int Function(int, int, Pointer<Void>, int, Pointer<Uint32>)
    >('GetTokenInformation');
final _convertSidToStringSidW = _advapi32
    .lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Pointer<Uint16>>),
      int Function(Pointer<Void>, Pointer<Pointer<Uint16>>)
    >('ConvertSidToStringSidW');
final _localFree = _kernel32
    .lookupFunction<IntPtr Function(IntPtr), int Function(int)>('LocalFree');
final _isValidSid = _advapi32
    .lookupFunction<Int32 Function(Pointer<Void>), int Function(Pointer<Void>)>(
      'IsValidSid',
    );
final _getSidSubAuthorityCount = _advapi32
    .lookupFunction<
      Pointer<Uint8> Function(Pointer<Void>),
      Pointer<Uint8> Function(Pointer<Void>)
    >('GetSidSubAuthorityCount');
final _getSidSubAuthority = _advapi32
    .lookupFunction<
      Pointer<Uint32> Function(Pointer<Void>, Uint32),
      Pointer<Uint32> Function(Pointer<Void>, int)
    >('GetSidSubAuthority');
final _createFileW = _kernel32
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
final _readFile = _kernel32
    .lookupFunction<
      Int32 Function(
        IntPtr,
        Pointer<Uint8>,
        Uint32,
        Pointer<Uint32>,
        Pointer<_Overlapped>,
      ),
      int Function(
        int,
        Pointer<Uint8>,
        int,
        Pointer<Uint32>,
        Pointer<_Overlapped>,
      )
    >('ReadFile');
final _writeFile = _kernel32
    .lookupFunction<
      Int32 Function(
        IntPtr,
        Pointer<Uint8>,
        Uint32,
        Pointer<Uint32>,
        Pointer<_Overlapped>,
      ),
      int Function(
        int,
        Pointer<Uint8>,
        int,
        Pointer<Uint32>,
        Pointer<_Overlapped>,
      )
    >('WriteFile');
final _getFileInformationByHandleEx = _kernel32
    .lookupFunction<
      Int32 Function(IntPtr, Int32, Pointer<Void>, Uint32),
      int Function(int, int, Pointer<Void>, int)
    >('GetFileInformationByHandleEx');
final _queryFullProcessImageNameW = _kernel32
    .lookupFunction<
      Int32 Function(IntPtr, Uint32, Pointer<Uint16>, Pointer<Uint32>),
      int Function(int, int, Pointer<Uint16>, Pointer<Uint32>)
    >('QueryFullProcessImageNameW');
final _setFilePointerEx = _kernel32
    .lookupFunction<
      Int32 Function(IntPtr, Int64, Pointer<Int64>, Uint32),
      int Function(int, int, Pointer<Int64>, int)
    >('SetFilePointerEx');
final _createMutexW = _kernel32
    .lookupFunction<
      IntPtr Function(Pointer<Void>, Int32, Pointer<Uint16>),
      int Function(Pointer<Void>, int, Pointer<Uint16>)
    >('CreateMutexW');
final _createNamedPipeW = _kernel32
    .lookupFunction<
      IntPtr Function(
        Pointer<Uint16>,
        Uint32,
        Uint32,
        Uint32,
        Uint32,
        Uint32,
        Uint32,
        Pointer<_SecurityAttributes>,
      ),
      int Function(
        Pointer<Uint16>,
        int,
        int,
        int,
        int,
        int,
        int,
        Pointer<_SecurityAttributes>,
      )
    >('CreateNamedPipeW');
final _connectNamedPipe = _kernel32
    .lookupFunction<
      Int32 Function(IntPtr, Pointer<_Overlapped>),
      int Function(int, Pointer<_Overlapped>)
    >('ConnectNamedPipe');
final _disconnectNamedPipe = _kernel32
    .lookupFunction<Int32 Function(IntPtr), int Function(int)>(
      'DisconnectNamedPipe',
    );
final _getNamedPipeClientProcessId = _kernel32
    .lookupFunction<
      Int32 Function(IntPtr, Pointer<Uint32>),
      int Function(int, Pointer<Uint32>)
    >('GetNamedPipeClientProcessId');
final _createEventW = _kernel32
    .lookupFunction<
      IntPtr Function(Pointer<Void>, Int32, Int32, Pointer<Uint16>),
      int Function(Pointer<Void>, int, int, Pointer<Uint16>)
    >('CreateEventW');
final _getOverlappedResult = _kernel32
    .lookupFunction<
      Int32 Function(IntPtr, Pointer<_Overlapped>, Pointer<Uint32>, Int32),
      int Function(int, Pointer<_Overlapped>, Pointer<Uint32>, int)
    >('GetOverlappedResult');
final _cancelIoEx = _kernel32
    .lookupFunction<
      Int32 Function(IntPtr, Pointer<_Overlapped>),
      int Function(int, Pointer<_Overlapped>)
    >('CancelIoEx');
final _convertStringSecurityDescriptorToSecurityDescriptorW = _advapi32
    .lookupFunction<
      Int32 Function(
        Pointer<Uint16>,
        Uint32,
        Pointer<Pointer<Void>>,
        Pointer<Uint32>,
      ),
      int Function(
        Pointer<Uint16>,
        int,
        Pointer<Pointer<Void>>,
        Pointer<Uint32>,
      )
    >('ConvertStringSecurityDescriptorToSecurityDescriptorW');
final _shellExecuteExW = _shell32
    .lookupFunction<
      Int32 Function(Pointer<_ShellExecuteInfo>),
      int Function(Pointer<_ShellExecuteInfo>)
    >('ShellExecuteExW');

final class _FileTime extends Struct {
  @Uint32()
  external int low;
  @Uint32()
  external int high;
}

// The Flutter Windows runner is Win64. Native pointers in OVERLAPPED are 64-bit.
final class _Overlapped extends Struct {
  @IntPtr()
  external int internal;
  @IntPtr()
  external int internalHigh;
  @Uint32()
  external int offset;
  @Uint32()
  external int offsetHigh;
  @IntPtr()
  external int event;
}

final class _SecurityAttributes extends Struct {
  @Uint32()
  external int length;
  external Pointer<Void> descriptor;
  @Int32()
  external int inherit;
}

final class _ShellExecuteInfo extends Struct {
  @Uint32()
  external int cbSize;
  @Uint32()
  external int mask;
  @IntPtr()
  external int hwnd;
  external Pointer<Uint16> verb;
  external Pointer<Uint16> file;
  external Pointer<Uint16> parameters;
  external Pointer<Uint16> directory;
  @Int32()
  external int show;
  @IntPtr()
  external int instApp;
  external Pointer<Void> idList;
  external Pointer<Uint16> className;
  @IntPtr()
  external int classKey;
  @Uint32()
  external int hotKey;
  @IntPtr()
  external int iconOrMonitor;
  @IntPtr()
  external int process;
}

class WindowsUpdateNativeException implements Exception {
  const WindowsUpdateNativeException(this.code, [this.win32]);
  final String code;
  final int? win32;
  @override
  String toString() => 'WindowsUpdateNativeException($code, $win32)';
}

Never _fail(String code) =>
    throw WindowsUpdateNativeException(code, _getLastError());

void _requireWindows() {
  if (!Platform.isWindows || sizeOf<IntPtr>() != 8) {
    throw const WindowsUpdateNativeException('windows_x64_required');
  }
  // Resolve the lazy FFI lookup before a Win32 call sets the thread error.
  // Resolving GetLastError afterwards can overwrite ERROR_ALREADY_EXISTS.
  _getLastError();
}

Pointer<Uint16> _wide(String text) {
  if (text.contains('\u0000')) {
    throw const WindowsUpdateNativeException('embedded_nul');
  }
  final pointer = calloc<Uint16>(text.length + 1);
  pointer.asTypedList(text.length).setAll(0, text.codeUnits);
  return pointer;
}

int _created(int handle) {
  final time = calloc<_FileTime>(4);
  try {
    if (_getProcessTimes(handle, time, time + 1, time + 2, time + 3) == 0) {
      _fail('GetProcessTimes');
    }
    return (time.ref.high << 32) | time.ref.low;
  } finally {
    calloc.free(time);
  }
}

Pointer<Uint8> _tokenInfo(int token, int kind) {
  final length = calloc<Uint32>();
  try {
    _getTokenInformation(token, kind, nullptr, 0, length);
    if (length.value == 0 || length.value > 65536) {
      _fail('GetTokenInformation.length');
    }
    final data = calloc<Uint8>(length.value);
    if (_getTokenInformation(
          token,
          kind,
          data.cast<Void>(),
          length.value,
          length,
        ) ==
        0) {
      calloc.free(data);
      _fail('GetTokenInformation');
    }
    return data;
  } finally {
    calloc.free(length);
  }
}

String _sidString(Pointer<Void> sid) {
  if (sid.address == 0 || _isValidSid(sid) == 0) {
    throw const WindowsUpdateNativeException('invalid_sid');
  }
  final string = calloc<Pointer<Uint16>>();
  try {
    if (_convertSidToStringSidW(sid, string) == 0) {
      _fail('ConvertSidToStringSidW');
    }
    try {
      return string.value.cast<Utf16>().toDartString();
    } finally {
      _localFree(string.value.address);
    }
  } finally {
    calloc.free(string);
  }
}

class WindowsUpdateProcess {
  WindowsUpdateProcess._(
    this._handle,
    this.pid,
    this.createdFiletime,
    this.sid,
    this.session,
    this.integrityRid,
  );

  int _handle;
  final int pid;
  final int createdFiletime;
  final String sid;
  final int session;
  final int integrityRid;

  String get imagePath {
    if (_handle == 0) throw StateError('Process handle is closed');
    final buffer = calloc<Uint16>(32768);
    final length = calloc<Uint32>()..value = 32768;
    try {
      if (_queryFullProcessImageNameW(_handle, 0, buffer, length) == 0 ||
          length.value == 0 ||
          length.value >= 32768) {
        _fail('QueryFullProcessImageNameW');
      }
      return String.fromCharCodes(buffer.asTypedList(length.value));
    } finally {
      calloc.free(buffer);
      calloc.free(length);
    }
  }

  String get imageFileId {
    final image = WindowsUpdateFile.open(imagePath);
    try {
      return image.fileId;
    } finally {
      image.close();
    }
  }

  factory WindowsUpdateProcess.current() {
    _requireWindows();
    return WindowsUpdateProcess.open(_getCurrentProcessId());
  }

  factory WindowsUpdateProcess.open(int pid, {int? createdFiletime}) {
    _requireWindows();
    if (pid <= 0 || pid > 0xffffffff) {
      throw const WindowsUpdateNativeException('invalid_pid');
    }
    final handle = _openProcess(
      _processQueryLimitedInformation | _synchronize,
      0,
      pid,
    );
    if (handle == 0) _fail('OpenProcess');
    try {
      return WindowsUpdateProcess._fromHandle(
        handle,
        createdFiletime: createdFiletime,
      );
    } catch (_) {
      _closeHandle(handle);
      rethrow;
    }
  }

  static WindowsUpdateProcess _fromHandle(int handle, {int? createdFiletime}) {
    final pid = _getProcessId(handle);
    if (pid == 0) _fail('GetProcessId');
    final created = _created(handle);
    if (createdFiletime != null && created != createdFiletime) {
      throw const WindowsUpdateNativeException('process_replaced');
    }
    final token = calloc<IntPtr>();
    try {
      if (_openProcessToken(handle, _tokenQuery, token) == 0) {
        _fail('OpenProcessToken');
      }
      try {
        Pointer<Uint8> user = nullptr;
        Pointer<Uint8> session = nullptr;
        Pointer<Uint8> label = nullptr;
        try {
          user = _tokenInfo(token.value, 1);
          session = _tokenInfo(token.value, 12);
          label = _tokenInfo(token.value, 25);
          final userSid = Pointer<Void>.fromAddress(user.cast<IntPtr>().value);
          final labelSid = Pointer<Void>.fromAddress(
            label.cast<IntPtr>().value,
          );
          if (_isValidSid(labelSid) == 0) {
            throw const WindowsUpdateNativeException('invalid_integrity_sid');
          }
          final count = _getSidSubAuthorityCount(labelSid).value;
          if (count == 0) {
            throw const WindowsUpdateNativeException('invalid_integrity_sid');
          }
          final result = WindowsUpdateProcess._(
            handle,
            pid,
            created,
            _sidString(userSid),
            session.cast<Uint32>().value,
            _getSidSubAuthority(labelSid, count - 1).value,
          );
          if (_created(handle) != created) {
            throw const WindowsUpdateNativeException('process_replaced');
          }
          return result;
        } finally {
          if (user.address != 0) calloc.free(user);
          if (session.address != 0) calloc.free(session);
          if (label.address != 0) calloc.free(label);
        }
      } finally {
        _closeHandle(token.value);
      }
    } finally {
      calloc.free(token);
    }
  }

  bool get isAlive {
    if (_handle == 0) return false;
    return _waitForSingleObject(_handle, 0) == _waitTimeout;
  }

  Future<int> waitForExit({Duration? timeout}) async {
    if (_handle == 0) throw StateError('Process handle is closed');
    if (timeout != null && timeout.isNegative) {
      throw ArgumentError.value(timeout, 'timeout');
    }
    final deadline = timeout == null ? null : DateTime.now().add(timeout);
    while (true) {
      final wait = _waitForSingleObject(_handle, 0);
      if (wait == _waitObject0) {
        final code = calloc<Uint32>();
        try {
          if (_getExitCodeProcess(_handle, code) == 0) {
            _fail('GetExitCodeProcess');
          }
          return code.value;
        } finally {
          calloc.free(code);
        }
      }
      if (wait != _waitTimeout) _fail('WaitForSingleObject.process');
      if (deadline != null && !DateTime.now().isBefore(deadline)) {
        throw const WindowsUpdateNativeException('process_wait_timeout');
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  void close() {
    if (_handle != 0) {
      _closeHandle(_handle);
      _handle = 0;
    }
  }
}

class _FileSnapshot {
  const _FileSnapshot(this.id, this.size);
  final String id;
  final int size;
}

String _hexBytes(List<int> bytes) =>
    bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

_FileSnapshot _inspectFile(int handle) {
  final tag = calloc<Uint8>(8);
  final standard = calloc<Uint8>(24);
  final id = calloc<Uint8>(24);
  try {
    if (_getFileInformationByHandleEx(handle, 9, tag.cast<Void>(), 8) == 0 ||
        _getFileInformationByHandleEx(handle, 1, standard.cast<Void>(), 24) ==
            0 ||
        _getFileInformationByHandleEx(handle, 18, id.cast<Void>(), 24) == 0) {
      _fail('GetFileInformationByHandleEx');
    }
    final attrs = tag.cast<Uint32>().value;
    final bytes = ByteData.sublistView(standard.asTypedList(24));
    final size = bytes.getInt64(8, Endian.little);
    final links = bytes.getUint32(16, Endian.little);
    if ((attrs & 0x400) != 0 ||
        (attrs & 0x10) != 0 ||
        links != 1 ||
        (standard + 20).value != 0 ||
        size < 0 ||
        size > 2147483648) {
      throw const WindowsUpdateNativeException('unsafe_file');
    }
    return _FileSnapshot(_hexBytes(id.asTypedList(24)), size);
  } finally {
    calloc.free(tag);
    calloc.free(standard);
    calloc.free(id);
  }
}

class WindowsUpdateFile {
  WindowsUpdateFile._(this.path, this._handle, this._snapshot);
  final String path;
  int _handle;
  final _FileSnapshot _snapshot;

  int get size => _snapshot.size;
  String get fileId => _snapshot.id;

  factory WindowsUpdateFile.open(String path) {
    _requireWindows();
    if (path.isEmpty || path.length >= 32768 || path.contains('\u0000')) {
      throw const WindowsUpdateNativeException('invalid_file_path');
    }
    final wide = _wide(path);
    try {
      final handle = _createFileW(
        wide,
        _genericRead,
        _fileShareRead,
        nullptr,
        _openExisting,
        _fileFlagOpenReparsePoint,
        0,
      );
      if (handle == _invalidHandle) _fail('CreateFileW.file');
      try {
        return WindowsUpdateFile._(path, handle, _inspectFile(handle));
      } catch (_) {
        _closeHandle(handle);
        rethrow;
      }
    } finally {
      calloc.free(wide);
    }
  }

  void revalidate() {
    if (_handle == 0) throw StateError('File handle is closed');
    final now = _inspectFile(_handle);
    if (now.id != fileId || now.size != size) {
      throw const WindowsUpdateNativeException('file_changed');
    }
    // The retained handle blocks rename/delete, but re-open the path to reject
    // a distinct name or replacement caused by unsupported filesystem behavior.
    final wide = _wide(path);
    try {
      final duplicate = _createFileW(
        wide,
        _genericRead,
        _fileShareRead,
        nullptr,
        _openExisting,
        _fileFlagOpenReparsePoint,
        0,
      );
      if (duplicate == _invalidHandle) _fail('CreateFileW.file_revalidate');
      try {
        final named = _inspectFile(duplicate);
        if (named.id != fileId || named.size != size) {
          throw const WindowsUpdateNativeException('file_path_changed');
        }
      } finally {
        _closeHandle(duplicate);
      }
    } finally {
      calloc.free(wide);
    }
  }

  bool verifySha256(String expectedSha256, int expectedSize) {
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(expectedSha256) ||
        expectedSize < 0 ||
        expectedSize != size) {
      return false;
    }
    revalidate();
    if (_setFilePointerEx(_handle, 0, nullptr, 0) == 0) {
      _fail('SetFilePointerEx');
    }
    final buffer = calloc<Uint8>(65536);
    final transferred = calloc<Uint32>();
    try {
      final sink = Sha256().toSync().newHashSink();
      var remaining = size;
      while (remaining > 0) {
        final requested = math.min(remaining, 65536);
        if (_readFile(_handle, buffer, requested, transferred, nullptr) == 0 ||
            transferred.value == 0 ||
            transferred.value > requested) {
          _fail('ReadFile.sha256');
        }
        sink.add(buffer.asTypedList(transferred.value));
        remaining -= transferred.value;
      }
      sink.close();
      revalidate();
      return _hexBytes(sink.hashSync().bytes) == expectedSha256;
    } finally {
      calloc.free(buffer);
      calloc.free(transferred);
    }
  }

  void close() {
    if (_handle != 0) {
      _closeHandle(_handle);
      _handle = 0;
    }
  }
}

/// A process-wide lease represented by the existence of a named object.
/// There is deliberately no thread-owned WaitForSingleObject/ReleaseMutex:
/// Dart async continuations need not resume on the acquiring OS thread.
class WindowsUpdateMutex {
  WindowsUpdateMutex._(this._handle);
  int _handle;

  static WindowsUpdateMutex acquire(String target) {
    _requireWindows();
    if (!RegExp(r'^[A-Za-z]:\\').hasMatch(target) ||
        target.length >= 32768 ||
        target.contains('\u0000')) {
      throw const WindowsUpdateNativeException('invalid_target');
    }
    final current = WindowsUpdateProcess.current();
    try {
      final sink = Sha256().toSync().newHashSink()
        ..add(
          utf8.encode(
            '${current.sid.toLowerCase()}\u0000${target.toLowerCase()}',
          ),
        )
        ..close();
      final name = _wide(
        'Local\\Equis.Update.${_hexBytes(sink.hashSync().bytes)}',
      );
      try {
        final handle = _createMutexW(nullptr, 0, name);
        if (handle == 0) _fail('CreateMutexW');
        if (_getLastError() == 183) {
          _closeHandle(handle);
          throw const WindowsUpdateNativeException(
            'update_already_running',
            183,
          );
        }
        return WindowsUpdateMutex._(handle);
      } finally {
        calloc.free(name);
      }
    } finally {
      current.close();
    }
  }

  void close() {
    if (_handle != 0) {
      _closeHandle(_handle);
      _handle = 0;
    }
  }
}

class WindowsUpdatePipeServer {
  WindowsUpdatePipeServer._(
    this.pipeName,
    this.sid,
    this._session,
    this._handle,
  );
  final String pipeName;
  final String sid;
  final int _session;
  int _handle;
  bool _closing = false;
  Pointer<_Overlapped>? _active;
  Future<WindowsUpdatePipeConnection>? _accepting;

  static WindowsUpdatePipeServer create(String pipeName, String sid) {
    _requireWindows();
    if (!_pipePattern.hasMatch(pipeName) ||
        !pipeName.startsWith(_pipePrefix) ||
        !_sidPattern.hasMatch(sid)) {
      throw const WindowsUpdateNativeException('invalid_pipe_identity');
    }
    final current = WindowsUpdateProcess.current();
    try {
      if (current.sid != sid) {
        throw const WindowsUpdateNativeException('pipe_sid_mismatch');
      }
      final sddl = _wide('D:P(A;;GA;;;SY)(A;;GA;;;BA)(A;;GA;;;$sid)');
      final descriptor = calloc<Pointer<Void>>();
      final attrs = calloc<_SecurityAttributes>();
      final name = _wide(pipeName);
      try {
        if (_convertStringSecurityDescriptorToSecurityDescriptorW(
              sddl,
              1,
              descriptor,
              nullptr,
            ) ==
            0) {
          _fail('ConvertStringSecurityDescriptorToSecurityDescriptorW');
        }
        attrs.ref.length = sizeOf<_SecurityAttributes>();
        attrs.ref.descriptor = descriptor.value;
        attrs.ref.inherit = 0;
        final handle = _createNamedPipeW(
          name,
          _pipeAccessDuplex | _fileFlagOverlapped | 0x00080000,
          _pipeTypeByte |
              _pipeReadmodeByte |
              _pipeWait |
              _pipeRejectRemoteClients,
          1,
          _pipeLineLimit,
          _pipeLineLimit,
          0,
          attrs,
        );
        if (handle == _invalidHandle) _fail('CreateNamedPipeW');
        return WindowsUpdatePipeServer._(
          pipeName,
          sid,
          current.session,
          handle,
        );
      } finally {
        if (descriptor.value.address != 0) _localFree(descriptor.value.address);
        calloc.free(name);
        calloc.free(attrs);
        calloc.free(descriptor);
        calloc.free(sddl);
      }
    } finally {
      current.close();
    }
  }

  Future<WindowsUpdatePipeConnection> accept() {
    if (_closing || _handle == 0 || _accepting != null) {
      throw StateError('Pipe server is closed or accepting');
    }
    final future = _acceptOne();
    _accepting = future;
    future.then(
      (_) => _accepting = null,
      onError: (Object _, StackTrace _) => _accepting = null,
    );
    return future;
  }

  Future<WindowsUpdatePipeConnection> _acceptOne() async {
    final event = _createEventW(nullptr, 1, 0, nullptr);
    if (event == 0) _fail('CreateEventW.accept');
    final ov = calloc<_Overlapped>()..ref.event = event;
    final transferred = calloc<Uint32>();
    try {
      _active = ov;
      final immediate = _connectNamedPipe(_handle, ov);
      if (immediate == 0) {
        final error = _getLastError();
        if (error != _errorPipeConnected) {
          if (error != _errorIoPending) {
            throw WindowsUpdateNativeException('ConnectNamedPipe', error);
          }
          await _completeOverlapped(
            _handle,
            ov,
            transferred,
            null,
            () => _closing,
          );
        }
      }
      if (_closing) {
        throw const WindowsUpdateNativeException('pipe_closed');
      }
      final clientPid = calloc<Uint32>();
      try {
        if (_getNamedPipeClientProcessId(_handle, clientPid) == 0 ||
            clientPid.value == 0) {
          _fail('GetNamedPipeClientProcessId');
        }
        final process = WindowsUpdateProcess.open(clientPid.value);
        try {
          if (process.sid != sid ||
              process.session != _session ||
              !process.isAlive) {
            throw const WindowsUpdateNativeException('pipe_client_identity');
          }
          final connection = WindowsUpdatePipeConnection._(_handle, process);
          _handle = 0;
          return connection;
        } catch (_) {
          process.close();
          rethrow;
        }
      } finally {
        calloc.free(clientPid);
      }
    } catch (_) {
      if (_handle != 0) _disconnectNamedPipe(_handle);
      rethrow;
    } finally {
      _active = null;
      _closeHandle(event);
      calloc.free(ov);
      calloc.free(transferred);
    }
  }

  Future<void> close() async {
    if (_closing) {
      if (_accepting != null) {
        try {
          await _accepting;
        } catch (_) {}
      }
      return;
    }
    _closing = true;
    if (_active != null && _handle != 0) _cancelIoEx(_handle, _active!);
    if (_accepting != null) {
      try {
        await _accepting;
      } catch (_) {}
    }
    if (_handle != 0) {
      _closeHandle(_handle);
      _handle = 0;
    }
  }
}

Future<void> _completeOverlapped(
  int handle,
  Pointer<_Overlapped> ov,
  Pointer<Uint32> transferred,
  DateTime? deadline,
  bool Function() closing,
) async {
  var cancelled = false;
  while (true) {
    final wait = _waitForSingleObject(ov.ref.event, 0);
    if (wait == _waitObject0) break;
    if (wait != _waitTimeout ||
        closing() ||
        (deadline != null && !DateTime.now().isBefore(deadline))) {
      cancelled = true;
      _cancelIoEx(handle, ov);
      break;
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  // CancelIoEx does not finish an operation. Keep OVERLAPPED and buffers alive
  // until GetOverlappedResult has observed its terminal completion.
  if (_getOverlappedResult(handle, ov, transferred, 1) == 0) {
    final error = _getLastError();
    if (cancelled && error == _errorOperationAborted) {
      throw const WindowsUpdateNativeException('pipe_io_cancelled');
    }
    throw WindowsUpdateNativeException('GetOverlappedResult', error);
  }
  if (cancelled) {
    throw const WindowsUpdateNativeException('pipe_io_timeout');
  }
}

class WindowsUpdatePipeConnection {
  WindowsUpdatePipeConnection._(this._handle, this.process);
  int _handle;
  final WindowsUpdateProcess process;
  bool _closing = false;
  Pointer<_Overlapped>? _active;
  Future<void>? _operation;

  Future<String> readLine({
    Duration timeout = const Duration(seconds: 30),
  }) async {
    if (timeout <= Duration.zero) {
      throw ArgumentError.value(timeout, 'timeout');
    }
    final deadline = DateTime.now().add(timeout);
    final bytes = <int>[];
    return _exclusive(() async {
      while (bytes.length < _pipeLineLimit) {
        final one = Uint8List(1);
        await _transfer(one, false, deadline);
        if (one[0] == 10) {
          try {
            return utf8.decode(bytes, allowMalformed: false);
          } on FormatException {
            throw const WindowsUpdateNativeException('pipe_invalid_utf8');
          }
        }
        if (one[0] == 0 || one[0] == 13) {
          throw const WindowsUpdateNativeException('pipe_invalid_line');
        }
        bytes.add(one[0]);
      }
      throw const WindowsUpdateNativeException('pipe_line_too_long');
    });
  }

  Future<void> writeLine(
    String line, {
    Duration timeout = const Duration(seconds: 30),
  }) {
    if (timeout <= Duration.zero ||
        line.contains('\n') ||
        line.contains('\r') ||
        line.contains('\u0000')) {
      throw const WindowsUpdateNativeException('pipe_invalid_line');
    }
    final bytes = Uint8List.fromList(utf8.encode('$line\n'));
    if (bytes.length > _pipeLineLimit) {
      throw const WindowsUpdateNativeException('pipe_line_too_long');
    }
    final deadline = DateTime.now().add(timeout);
    return _exclusive(() => _transfer(bytes, true, deadline));
  }

  Future<T> _exclusive<T>(Future<T> Function() action) async {
    if (_closing || _handle == 0 || _operation != null) {
      throw StateError('Pipe is closed or busy');
    }
    final completion = Completer<void>();
    _operation = completion.future;
    try {
      if (!process.isAlive) {
        throw const WindowsUpdateNativeException('pipe_client_exited');
      }
      return await action();
    } finally {
      completion.complete();
      _operation = null;
    }
  }

  Future<void> _transfer(
    Uint8List bytes,
    bool writing,
    DateTime deadline,
  ) async {
    var offset = 0;
    while (offset < bytes.length) {
      if (_closing || !process.isAlive || !DateTime.now().isBefore(deadline)) {
        throw const WindowsUpdateNativeException('pipe_io_timeout');
      }
      final amount = math.min(8192, bytes.length - offset);
      final buffer = calloc<Uint8>(amount);
      final transferred = calloc<Uint32>();
      final event = _createEventW(nullptr, 1, 0, nullptr);
      if (event == 0) {
        calloc.free(buffer);
        calloc.free(transferred);
        _fail('CreateEventW.pipe');
      }
      final ov = calloc<_Overlapped>()..ref.event = event;
      try {
        _active = ov;
        if (writing) {
          buffer.asTypedList(amount).setRange(0, amount, bytes, offset);
        }
        final immediate = writing
            ? _writeFile(_handle, buffer, amount, transferred, ov)
            : _readFile(_handle, buffer, amount, transferred, ov);
        if (immediate == 0) {
          final error = _getLastError();
          if (error != _errorIoPending) {
            throw WindowsUpdateNativeException(
              writing ? 'WriteFile.pipe' : 'ReadFile.pipe',
              error,
            );
          }
          await _completeOverlapped(
            _handle,
            ov,
            transferred,
            deadline,
            () => _closing,
          );
        }
        if (transferred.value == 0 || transferred.value > amount) {
          throw const WindowsUpdateNativeException('pipe_short_transfer');
        }
        if (!writing) {
          bytes.setRange(
            offset,
            offset + transferred.value,
            buffer.asTypedList(transferred.value),
          );
        }
        offset += transferred.value;
      } finally {
        _active = null;
        _closeHandle(event);
        calloc.free(ov);
        calloc.free(transferred);
        calloc.free(buffer);
      }
    }
  }

  Future<void> close() async {
    if (_closing) {
      if (_operation != null) await _operation;
      return;
    }
    _closing = true;
    if (_active != null && _handle != 0) _cancelIoEx(_handle, _active!);
    if (_operation != null) await _operation;
    if (_handle != 0) {
      _disconnectNamedPipe(_handle);
      _closeHandle(_handle);
      _handle = 0;
    }
    process.close();
  }
}

class WindowsUpdateNative {
  static Future<WindowsUpdateProcess> launchSetup({
    required String executable,
    required String arguments,
    required String workingDirectory,
    required bool elevate,
  }) async {
    _requireWindows();
    if (!RegExp(r'^[A-Za-z]:\\').hasMatch(executable) ||
        !RegExp(r'^[A-Za-z]:\\').hasMatch(workingDirectory) ||
        executable.length >= 32768 ||
        workingDirectory.length >= 32768 ||
        arguments.length >= 32768 ||
        arguments.contains('\u0000')) {
      throw const WindowsUpdateNativeException('invalid_setup_launch');
    }
    final verb = _wide(elevate ? 'runas' : 'open');
    final file = _wide(executable);
    final parameters = _wide(arguments);
    final directory = _wide(workingDirectory);
    final info = calloc<_ShellExecuteInfo>();
    try {
      info.ref.cbSize = sizeOf<_ShellExecuteInfo>();
      info.ref.mask = 0x00000040 | 0x00000100; // NOCLOSEPROCESS | NOASYNC
      info.ref.verb = verb;
      info.ref.file = file;
      info.ref.parameters = parameters;
      info.ref.directory = directory;
      info.ref.show = 1;
      if (_shellExecuteExW(info) == 0) {
        final error = _getLastError();
        throw WindowsUpdateNativeException(
          error == 1223 ? 'uac_cancelled' : 'ShellExecuteExW',
          error,
        );
      }
      final handle = info.ref.process;
      if (handle == 0 || handle == _invalidHandle) {
        throw const WindowsUpdateNativeException(
          'setup_process_handle_missing',
        );
      }
      try {
        return WindowsUpdateProcess._fromHandle(handle);
      } catch (_) {
        _closeHandle(handle);
        rethrow;
      }
    } finally {
      calloc.free(info);
      calloc.free(directory);
      calloc.free(parameters);
      calloc.free(file);
      calloc.free(verb);
    }
  }
}
