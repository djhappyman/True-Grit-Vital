import '../../domain/supporting/supporting.dart';

/// The canonical saved supporting-record detail route for one exact point.
///
/// The saved record supplies both the owner and record identity. Displayed
/// names, dates and values are never used to find a source. A return location
/// keeps the originating filtered Labs collection available when the detail
/// page is opened without a route to pop.
String supportingSourceLocation(
  SupportingRecordId id, {
  String? returnLocation,
}) => Uri(
  path: '/supporting/${id.personId}/${id.id}',
  queryParameters: {
    if (returnLocation != null && returnLocation.isNotEmpty)
      'return': returnLocation,
  },
).toString();
