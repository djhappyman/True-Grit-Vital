import '../../domain/supporting/supporting.dart';

/// The canonical saved supporting-record detail route for one exact point.
///
/// The saved record supplies both the owner and record identity. Displayed
/// names, dates and values are never used to find a source. A return location
/// keeps the originating filtered Labs collection available when the detail
/// page is opened without a route to pop.
///
/// Path segments and query values are built by [Uri], so reserved characters
/// cannot change the route shape. [revision] pins the exact saved version that
/// was inspected; omitting it requests the current version.
String supportingSourceLocation(
  SupportingRecordId id, {
  int? revision,
  String? returnLocation,
}) => Uri(
  pathSegments: ['', 'supporting', id.personId, id.id],
  queryParameters: {
    if (revision != null) 'revision': '$revision',
    if (returnLocation != null && returnLocation.isNotEmpty)
      'return': returnLocation,
  },
).toString();

/// The canonical trend comparison route for the exact query and browsing
/// position that produced a source list.
///
/// A pushed source keeps the mounted trend page. This location is the return
/// context for a directly opened detail page, so Back still restores the same
/// applied range, date basis, comparison group and table pages instead of a
/// default Labs view.
String supportingTrendsLocation({
  required String personId,
  required String metricId,
  required CivilDate from,
  required CivilDate before,
  SupportingDateBasis basis = SupportingDateBasis.collection,
  String? group,
  int groupPage = 0,
  int tablePage = 0,
  int undatedPage = 0,
}) {
  // The trend screen compares collection and report dates only. Accepting an
  // entry basis here would silently return a collection view instead.
  if (basis == SupportingDateBasis.entry) {
    throw ArgumentError.value(basis, 'basis', 'trend view has no entry basis');
  }
  return Uri(
    pathSegments: ['', 'supporting', personId, 'trends'],
    queryParameters: {
      'metric': metricId,
      'from': from.toString(),
      'before': before.toString(),
      if (basis == SupportingDateBasis.report) 'basis': basis.name,
      if (group != null && group.isNotEmpty) 'group': group,
      if (groupPage > 0) 'groupPage': '$groupPage',
      if (tablePage > 0) 'table': '$tablePage',
      if (undatedPage > 0) 'undated': '$undatedPage',
    },
  ).toString();
}
