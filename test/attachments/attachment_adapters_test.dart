import 'dart:async';

import 'package:flutter/services.dart';

import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/domain/attachments.dart';
import 'package:true_grit_vital/platform/attachments.dart';

class WaitingPdfDecoder implements AttachmentPdfDecoder {
  final done = Completer<int>();
  @override
  Future<int> pageCount(Uint8List bytes) => done.future;
  @override
  Future<ui.Image> render(
    Uint8List bytes, {
    required int page,
    required int maxEdge,
  }) => throw UnimplementedError();
}

void main() {
  test(
    'decoder admits one concurrent job and releases the gate after completion',
    () async {
      final pdf = WaitingPdfDecoder();
      final decoder = AttachmentMediaDecoder(pdf: pdf);
      final first = decoder.inspect(Uint8List.fromList([37, 80, 68, 70, 45]));
      await expectLater(
        decoder.inspect(Uint8List.fromList([1, 2, 3])),
        throwsA(
          isA<AttachmentFailure>().having(
            (v) => v.code,
            'code',
            'attachment_busy',
          ),
        ),
      );
      pdf.done.complete(1);
      expect((await first).pageCount, 1);
      expect(
        (await decoder.inspect(Uint8List.fromList([1, 2, 3]))).mediaKind,
        AttachmentMediaKind.other,
      );
    },
  );
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() {
    messenger.setMockMethodCallHandler(AndroidAttachmentGateway.channel, null);
    messenger.setMockMethodCallHandler(AndroidAttachmentHandoff.channel, null);
  });
  test(
    'picker keeps original job across recovery and reads bounded native chunks',
    () async {
      final methods = <String>[];
      final source = Uint8List.fromList([1, 2, 3]);
      messenger.setMockMethodCallHandler(AndroidAttachmentGateway.channel, (
        call,
      ) async {
        methods.add(call.method);
        final arguments = call.arguments as Map;
        expect(arguments['jobId'], 'fixed-job');
        if (call.method == 'pick' || call.method == 'recover') {
          return {
            'jobId': 'fixed-job',
            'state': 'selected',
            'name': '../../Original.pdf',
            'byteCount': 3,
          };
        }
        if (call.method == 'read') {
          return arguments['offset'] == 0 ? source : null;
        }
        return null;
      });
      const gateway = AndroidAttachmentGateway();
      final original = await gateway.pickFile(jobId: 'fixed-job');
      expect(
        original!.name,
        '../../Original.pdf',
      ); // Display metadata never becomes a path.
      final recovered = await gateway.recoverSelection(jobId: 'fixed-job');
      expect(await readAttachmentBytes(recovered!.openRead()), source);
      await gateway.finishSelection('fixed-job');
      expect(methods, ['pick', 'recover', 'read', 'read', 'finish']);
      expect(gateway.capabilities.camera, false);
      expect(gateway.capabilities.share, true);
    },
  );
  test(
    'foreign picker result and oversized stream cannot retarget publication',
    () async {
      messenger.setMockMethodCallHandler(
        AndroidAttachmentGateway.channel,
        (call) async => {
          'jobId': 'other-job',
          'state': 'selected',
          'name': 'Original',
          'byteCount': 3,
        },
      );
      await expectLater(
        const AndroidAttachmentGateway().pickFile(jobId: 'fixed-job'),
        throwsA(isA<AttachmentFailure>()),
      );
      await expectLater(
        readAttachmentBytes(
          Stream.value(Uint8List(AttachmentLimits.maxInputBytes + 1)),
        ),
        throwsA(isA<AttachmentFailure>()),
      );
    },
  );
  test(
    'empty and arbitrary source chunks are bounded without original mutation',
    () async {
      final original = Uint8List(AttachmentLimits.chunkBytes + 1)..[0] = 31;
      final chunks = await boundedAttachmentChunks(Stream.value(original))
          .toList();
      expect(chunks.map((v) => v.length), [AttachmentLimits.chunkBytes, 1]);
      chunks.first[0] = 99;
      expect(original[0], 31);
      await expectLater(
        readAttachmentBytes(const Stream.empty()),
        throwsA(isA<AttachmentFailure>()),
      );
    },
  );
  test('native handoff preserves explicit lifetime and refuses oversized channel writes', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(AndroidAttachmentHandoff.channel, (
      call,
    ) async {
      calls.add(call);
      if (call.method == 'append') return 3;
      if (call.method == 'share') return true;
      if (call.method == 'cancel') return false;
      if (call.method == 'cleanup') return ['expired'];
      return null;
    });
    const gateway = AndroidAttachmentHandoff();
    final expires = DateTime.utc(2026, 10, 20);
    await gateway.begin(
      id: 'handoff',
      name: 'Original.pdf',
      mime: 'application/pdf',
      expiresAt: expires,
    );
    expect(
      (calls.first.arguments as Map)['expiresAt'],
      expires.millisecondsSinceEpoch,
    );
    expect(
      await gateway.append(
        id: 'handoff',
        offset: 0,
        bytes: Uint8List.fromList([1, 2, 3]),
      ),
      3,
    );
    await gateway.publish(id: 'handoff', byteCount: 3, sha256: '0' * 64);
    expect(await gateway.share('handoff'), true);
    expect(await gateway.cancel('handoff'), false); // Receiver may still read.
    expect(await gateway.cleanup(), ['expired']);
    await expectLater(
      gateway.append(
        id: 'handoff',
        offset: 0,
        bytes: Uint8List(AttachmentLimits.chunkBytes + 1),
      ),
      throwsA(isA<AttachmentFailure>()),
    );
  });
  test('missing native handoff cancellation is idempotent without swallowing other failures', () async {
    messenger.setMockMethodCallHandler(AndroidAttachmentHandoff.channel, (
      call,
    ) async {
      throw PlatformException(code: 'attachment_handoff_missing');
    });
    expect(await const AndroidAttachmentHandoff().cancel('missing'), isTrue);
    messenger.setMockMethodCallHandler(AndroidAttachmentHandoff.channel, (
      call,
    ) async {
      throw PlatformException(code: 'attachment_handoff_unavailable');
    });
    await expectLater(
      const AndroidAttachmentHandoff().cancel('missing'),
      throwsA(
        isA<AttachmentFailure>().having(
          (e) => e.code,
          'code',
          'attachment_handoff_unavailable',
        ),
      ),
    );
  });
  test('pending and cancelled picker replies still enforce the captured job identity', () async {
    for (final status in ['pending', 'cancelled']) {
      messenger.setMockMethodCallHandler(
        AndroidAttachmentGateway.channel,
        (call) async => {'jobId': 'foreign', 'state': status},
      );
      await expectLater(
        const AndroidAttachmentGateway().recoverSelection(jobId: 'fixed'),
        throwsA(
          isA<AttachmentFailure>().having(
            (e) => e.code,
            'code',
            'attachment_picker_context',
          ),
        ),
      );
      messenger.setMockMethodCallHandler(
        AndroidAttachmentGateway.channel,
        (call) async => {'jobId': 'fixed', 'state': status},
      );
      expect(
        await const AndroidAttachmentGateway().recoverSelection(jobId: 'fixed'),
        isNull,
      );
    }
  });

  test(
    'inspection accepts unknown files without pretending they have a preview',
    () async {
      const decoder = AttachmentMediaDecoder();
      final bytes = Uint8List.fromList([1, 2, 3]);
      final inspection = await decoder.inspect(bytes);
      expect(inspection.mediaKind, AttachmentMediaKind.other);
      expect(
        AttachmentInspection.fromJson(inspection.toJson()).toJson(),
        inspection.toJson(),
      );
      await expectLater(
        decoder.preview(bytes, inspection: inspection),
        throwsA(isA<AttachmentFailure>()),
      );
    },
  );
}
