import 'package:bonfire/shared/app_info.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test("updates come from the fork's releases, never upstream's", () {
    expect(kGithubLatestReleaseUrl, contains('/repos/idrissgaba/daccord/'));
    expect(kGithubReleaseByTagUrl('1.2.3'), contains('/idrissgaba/daccord/'));
    expect(kGithubLatestReleaseUrl, isNot(contains('DaccordProject')));
  });
}
