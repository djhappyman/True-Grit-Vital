import '../../app/history.dart';
import '../../domain/records.dart' show FeedScope;

/// Canonical History destination for one event.
///
/// The existing History event filter resolves membership from the saved record
/// linkage. This helper adds no date restriction from the event's planned
/// dates: its existing captured bounds stay authoritative. The single-user
/// scope is carried explicitly and identifiers pass through the shared query
/// encoder rather than string concatenation.
///
/// [returnLocation] is only a canonical in-app location. History validates it
/// before offering the return command, so a changed URL cannot redirect to
/// another site.
String eventHistoryLocation({required String eventId, String? returnLocation}) {
  final location = Uri.parse(
    historyLocation(scope: const FeedScope.me(), eventIds: [eventId]),
  );
  if (returnLocation == null) return location.toString();
  return location
      .replace(
        queryParameters: {
          ...location.queryParameters,
          'return': returnLocation,
        },
      )
      .toString();
}
