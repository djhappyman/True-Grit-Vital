import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/domain/privacy/licences.dart';

void main() {
  test('splits marked notices in order and trims the section edge', () {
    final notices = decodeLicenceNotices(
      'preamble\n'
      '===== alpha 1.0: LICENSE =====\n\nMIT text\n\n'
      '===== beta 2.0: NOTICE =====\nApache text\n',
    );
    expect(notices, hasLength(2));
    expect(notices.first.title, 'alpha 1.0: LICENSE');
    expect(notices.first.body, 'MIT text');
    expect(notices.last.title, 'beta 2.0: NOTICE');
    expect(notices.last.body, 'Apache text');
  });

  test('drops empty sections and tolerates CRLF', () {
    final notices = decodeLicenceNotices(
      '===== empty =====\r\n===== real =====\r\nText\r\n',
    );
    expect(notices.single.title, 'real');
    expect(notices.single.body, 'Text');
  });

  test('unmarked or oversized input is rejected rather than guessed', () {
    expect(decodeLicenceNotices(''), isEmpty);
    expect(decodeLicenceNotices('MIT licence text without markers'), isEmpty);
    expect(decodeLicenceNotices('x' * (maxLicenceNoticeBytes + 1)), isEmpty);
  });

  test('notice count is bounded', () {
    final raw = StringBuffer();
    for (var index = 0; index < maxLicenceNotices + 25; index++) {
      raw
        ..writeln('===== package $index =====')
        ..writeln('Licence $index');
    }
    expect(decodeLicenceNotices(raw.toString()), hasLength(maxLicenceNotices));
  });
}
