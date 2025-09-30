import 'dart:io';
import 'dart:typed_data';

import 'package:elgin/components/enums.dart';
import 'package:elgin/components/exceptions/elgin_exception.dart';
import 'package:flutter/services.dart';

/// Mutex simples para serializar chamadas assíncronas.
class _AsyncMutex {
  Future<void> _tail = Future.value();

  Future<T> run<T>(Future<T> Function() task) {
    final next = _tail.then((_) => task());
    _tail = next.catchError((_) {}); // não deixa a fila travar em caso de erro
    return next;
  }
}

///* Printer com fila (mutex) + feed(1) automático no printString
class Printer {
  static MethodChannel? platform;
  static Printer? _instance;
  Printer._();

  final _AsyncMutex _mutex = _AsyncMutex();

  // Helper centralizado para invocar o channel de forma serializada
  Future<T?> _invoke<T>(String method, [dynamic args]) {
    if (platform == null) {
      return Future.error(
        StateError('Printer.platform (MethodChannel) não foi inicializado.'),
      );
    }
    return _mutex.run<T?>(() async {
      final res = await platform!.invokeMethod<T>(method, args);
      return res;
    });
  }

  int _normInt(int? v) => v ?? 9999;

  // ---------------------------------------------------------------------------
  // Sessão
  // ---------------------------------------------------------------------------

  /// Conecta e faz um reset inicial uma única vez para padronizar estado.
  Future<int> connect({required ElginPrinter driver}) async {
    final mapParam = <String, dynamic>{
      'type': driver.type.value,
      'model': driver.model?.value ?? 'M8',
      'connection': driver.connection ?? '',
      'param': driver.parameter ?? 0,
    };

    final code = _normInt(await _invoke<int>('startInternalPrinter', {
      'printerArgs': mapParam,
    }));
    if (code < 0) throw ElginException(code);

    final r = await reset(); // estado inicial
    if (r < 0) throw ElginException(r);

    return code;
  }

  Future<int> disconnect() async {
    final ok = await _invoke<bool>('stopPrinter') ?? false;
    final code = ok ? 9999 : -1;
    if (code < 0) throw ElginException(code);
    return code;
  }

  /// Reset de estado (não limpa buffer). Use com parcimônia.
  Future<int> reset() async {
    final code = _normInt(await _invoke<int>('reset'));
    if (code < 0) throw ElginException(code);
    return code;
  }

  // ---------------------------------------------------------------------------
  // Utilidades de “job”
  // ---------------------------------------------------------------------------

  /// Executa um bloco de impressão “atômico”, com reset opcional no início,
  /// e feed/cut automáticos no final.
  Future<T> withJob<T>(
    Future<T> Function() body, {
    bool resetAtStart = true,
    int feedAtEnd = 0,
    bool cutAtEnd = false,
  }) {
    return _mutex.run(() async {
      if (resetAtStart) {
        final r = await reset();
        if (r < 0) throw ElginException(r);
      }
      try {
        return await body();
      } finally {
        if (feedAtEnd > 0) {
          final f = await feed(feedAtEnd);
          if (f < 0) throw ElginException(f);
        }
        if (cutAtEnd) {
          final c = await cut();
          if (c < 0) throw ElginException(c);
        }
      }
    });
  }

  // ---------------------------------------------------------------------------
  // Comandos de impressão / periféricos
  // ---------------------------------------------------------------------------

  Future<int> beep(int times, int st, int ft) async {
    final mapParam = {'times': times, 'st': st, 'ft': ft};
    final code = _normInt(await _invoke<int>("beep", {'beepArgs': mapParam}));
    if (code < 0) throw ElginException(code);
    return code;
  }

  Future<int?> printSAT(String xml, {int param = 0}) async {
    final mapParam = {'xmlSAT': xml, 'param': param};
    final code = _normInt(await _invoke<int>("printSAT", {'satArgs': mapParam}));
    if (code < 0) throw ElginException(code);
    return code;
  }

  Future<int?> printNFCE(String xml, String csc, int cscId, {int param = 0}) async {
    final mapParam = {
      'xmlNFCe': xml,
      'indexcsc': cscId,
      'csc': csc,
      'param': param,
    };
    final code = _normInt(await _invoke<int>("printNFCE", {'nfceArgs': mapParam}));
    if (code < 0) throw ElginException(code);
    return code;
  }

  Future<int?> printTEF(String cupomTEF) async {
    final code = _normInt(await _invoke<int>("printTEF", {'cupomTEF': cupomTEF}));
    if (code < 0) throw ElginException(code);
    return code;
  }

  Future<int> customCashier(int pin, int it, int dp) async {
    final mapParam = {'pin': pin, 'it': it, 'dp': dp};
    final code = _normInt(await _invoke<int>("customCashier", {'cashierArgs': mapParam}));
    if (code < 0) throw ElginException(code);
    return code;
  }

  Future<int> elginCashier() async {
    final code = _normInt(await _invoke<int>('elginCashier'));
    if (code < 0) throw ElginException(code);
    return code;
  }

  Future<int> cut({int lines = 0}) async {
    final code = _normInt(await _invoke<int>("cutPaper", {'lines': lines}));
    if (code < 0) throw ElginException(code);
    return code;
  }

  Future<int> feed(int lines) async {
    final code = _normInt(await _invoke<int>('feedLine', {'lines': lines}));
    if (code < 0) throw ElginException(code);
    return code;
  }

  /// Versão da lib do driver
  Future<String> get libVersion async {
    final v = await _invoke<String>('libVersion');
    return v ?? '';
  }

  /// Linha separadora simples
  Future<void> line({String ch = '-', int len = 31}) async {
    await printString(List.filled(len, ch[0]).join());
  }

  Future<int> printBarCode(
    String text, {
    EliginBarcodeType barcodeType = EliginBarcodeType.JAN8,
    ElginAlign align = ElginAlign.RIGHT,
    int height = 50,
    int width = 6,
    ElginBarcodeTextPosition textPosition = ElginBarcodeTextPosition.NO_TEXT,
  }) async {
    final mapParam = {
      'barCodeType': barcodeType.value,
      'text': text,
      'height': height,
      'align': align.value,
      'width': width,
      'textPosition': textPosition.value,
    };
    final code = _normInt(await _invoke<int>("printBarCode", {'barcodeArgs': mapParam}));
    if (code < 0) throw ElginException(code);
    return code;
  }

  Future<int> printImage(File image, bool isBase64) async {
    final mapParam = {'path': image.path, 'isBase64': isBase64};
    final code = _normInt(await _invoke<int>('printImage', {'imageArgs': mapParam}));
    if (code < 0) throw ElginException(code);

    // Se seu hardware precisar, micro pausa pós-imagem:
    // await Future.delayed(const Duration(milliseconds: 120));

    return code;
  }

  Future<int> printQRCode(
    String text, {
    ElginQrcodeSize size = ElginQrcodeSize.SIZE4,
    ElginAlign align = ElginAlign.CENTER,
    ElginQrcodeCorrection correction = ElginQrcodeCorrection.LEVEL_M,
  }) async {
    final mapParam = {
      'size': size.value,
      'align': align.value,
      'correction': correction.value,
      'text': text,
    };
    final code = _normInt(await _invoke<int>("printQrcode", {'qrcodeArgs': mapParam}));
    if (code < 0) throw ElginException(code);

    // Pausa opcional pós-QR:
    // await Future.delayed(const Duration(milliseconds: 80));

    return code;
  }

  Future<int> printRaw(List<int> rawList) async {
    final data = Uint8List.fromList(rawList);
    final mapParam = {'data': data, 'bytes': data.lengthInBytes};
    final code = _normInt(await _invoke<int>('printRaw', {'rawArgs': mapParam}));
    if (code < 0) throw ElginException(code);
    return code;
  }

  /// printString com feed(1) automático **dentro do mesmo lock**.
  Future<int> printString(
    String text, {
    ElginAlign align = ElginAlign.LEFT,
    bool isBold = false,
    bool isUnderline = false,
    ElginFont font = ElginFont.FONTA,
    ElginSize fontSize = ElginSize.MD,
  }) async {
    return _mutex.run(() async {
      // 1) printText
      final mapParam = {
        'text': text,
        'align': align.value,
        'isBold': isBold,
        'isUnderline': isUnderline,
        'font': font.value,
        'fontSize': fontSize.value,
      };

      final code = _normInt(
        await platform!.invokeMethod<int>('printText', {"textArgs": mapParam}),
      );
      if (code < 0) throw ElginException(code);

      // 2) feed(1) automático, na MESMA seção crítica
      final f = _normInt(
        await platform!.invokeMethod<int>('feedLine', {'lines': 1}),
      );
      if (f < 0) throw ElginException(f);

      return code;
    });
  }

  // ---------------------------------------------------------------------------
  // Status
  // ---------------------------------------------------------------------------

  Future<int> statusCashier() async {
    final code = _normInt(await _invoke<int>('statusCashier'));
    if (code < 0) throw ElginException(code);
    return code;
  }

  Future<int> statusEjetor() async {
    final code = _normInt(await _invoke<int>('statusEjector'));
    if (code < 0) throw ElginException(code);
    return code;
  }

  Future<int> statusSensor() async {
    final code = _normInt(await _invoke<int>('statusSensor'));
    if (code < 0) throw ElginException(code);
    return code;
  }

  // ---------------------------------------------------------------------------
  // Singleton
  // ---------------------------------------------------------------------------

  /// Inicializa e retorna instância única
  static Printer instance(MethodChannel methodChannel) {
    platform = methodChannel;
    _instance ??= Printer._();
    return _instance!;
  }
}
