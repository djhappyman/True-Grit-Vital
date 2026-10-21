// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'True Grit: Vital';

  @override
  String get today => 'Today';

  @override
  String get substances => 'Substances';

  @override
  String get events => 'Events';

  @override
  String get history => 'History';

  @override
  String get appearance => 'Appearance';

  @override
  String get preview => 'Development preview';

  @override
  String get previewBody =>
      'Recording and profiles are not available in this build.';

  @override
  String get todayEmpty => 'Your daily view';

  @override
  String get todayBody => 'Planned doses and recorded use will appear here.';

  @override
  String get substancesEmpty => 'Your substances';

  @override
  String get substancesBody =>
      'Medicines, supplements and other substances will appear here.';

  @override
  String get eventsEmpty => 'Your events';

  @override
  String get eventsBody =>
      'Events are not available in this build. Actual use can be recorded in Substances.';

  @override
  String get historyEmpty => 'Your history';

  @override
  String get historyBody => 'Recorded doses and corrections will appear here.';

  @override
  String get appearanceBody => 'Appearance choices are saved on this device.';

  @override
  String get colourMode => 'Colour mode';

  @override
  String get system => 'System';

  @override
  String get light => 'Light';

  @override
  String get dark => 'Dark';

  @override
  String get opaqueSurfaces => 'Opaque surfaces';

  @override
  String get opaqueHelper => 'Use solid backgrounds for decorative surfaces.';

  @override
  String get reduceMotion => 'Reduce motion';

  @override
  String get motionHelper =>
      'Limit optional movement. System settings also apply.';

  @override
  String get surfaceSample => 'Surface sample';

  @override
  String get opaqueActive =>
      'Solid surfaces are active while glass is being checked on devices.';

  @override
  String get opaqueChosen => 'Solid surfaces are active.';

  @override
  String get glassActive => 'Glass is active on this sample surface.';

  @override
  String get motionReduced => 'Reduced motion is active.';

  @override
  String get motionStandard => 'Standard motion is active.';

  @override
  String get back => 'Back';

  @override
  String get formSamples => 'Form icons';

  @override
  String get tablet => 'Tablet';

  @override
  String get injection => 'Injection';

  @override
  String get liquid => 'Liquid';

  @override
  String get formHelper =>
      'Icons describe forms, not substance types or dose advice.';

  @override
  String get appearanceFailure =>
      'Appearance was not saved. Try the choice again.';

  @override
  String get loadingRecords => 'Opening records…';

  @override
  String get recoveryTitle => 'Records unavailable';

  @override
  String get recoveryBody =>
      'Vital could not open the saved records. Retry without deleting the app or its data.';

  @override
  String get unsupportedBody =>
      'Recording is available in the Android and Linux apps. This platform cannot open personal records.';

  @override
  String get retry => 'Retry';

  @override
  String get create => 'Create';

  @override
  String get record => 'Record';

  @override
  String get correct => 'Correct';

  @override
  String get undo => 'Undo';

  @override
  String get save => 'Save';

  @override
  String get cancel => 'Cancel';

  @override
  String get discard => 'Discard';

  @override
  String get keep => 'Keep';

  @override
  String get me => 'Me';

  @override
  String get newSubstance => 'New substance';

  @override
  String get nameLabel => 'Full name';

  @override
  String get formLabel => 'Form';

  @override
  String get unitLabel => 'Unit';

  @override
  String get typeLabel => 'Type';

  @override
  String get nameRequired => 'Enter the full substance name.';

  @override
  String get detailsRequired =>
      'Choose a unit and enter a form and type. Keep each field within 500 characters.';

  @override
  String get substancesReady => 'Create a substance to record what you take.';

  @override
  String get noRecords => 'Nothing recorded';

  @override
  String get todayReady =>
      'Actual use recorded today appears here. Earlier use stays in History.';

  @override
  String get historyReady => 'Record actual use to start your history.';

  @override
  String get recordHeading => 'Record dose';

  @override
  String get correctHeading => 'Correct use';

  @override
  String get amountLabel => 'Amount';

  @override
  String get actualDateLabel => 'Actual date';

  @override
  String get actualTimeLabel => 'Actual time';

  @override
  String get dateExample => 'Use YYYY-MM-DD.';

  @override
  String get timeExample => 'Use 24-hour HH:MM.';

  @override
  String get amountInvalid =>
      'Use a decimal point, without commas. Enter an amount above zero, up to 9,000,000,000, with up to 6 decimal places.';

  @override
  String get timeInvalid => 'Enter a valid actual date and time.';

  @override
  String get saveFailure =>
      'The save could not be confirmed. Retry with the same details.';

  @override
  String get conflictFailure =>
      'This record has changed. Return to History and review the latest version before correcting it.';

  @override
  String get saved => 'Saved';

  @override
  String get voided => 'Voided';

  @override
  String get undoHelp =>
      'Undo marks this entry as voided. The original and its corrections stay in history.';

  @override
  String get undoFailure =>
      'Undo could not be confirmed. Retry or review History.';

  @override
  String get unsavedHeading => 'Unsaved changes';

  @override
  String get unsavedBody => 'Keep editing or discard this unfinished entry.';

  @override
  String get pendingBody => 'Resolve the save before leaving this entry.';

  @override
  String get historyUnavailable =>
      'History could not be loaded. Retry to keep your current view.';

  @override
  String get recordHistory => 'Record history';

  @override
  String get noItem => 'This substance is unavailable. Return to Substances.';

  @override
  String get saving => 'Saving…';

  @override
  String ownerAmount(String person, String amount, String unit) {
    return '$person: $amount $unit';
  }

  @override
  String itemDetails(String form, String type, String unit) {
    return '$form · $type · $unit';
  }

  @override
  String actualStamp(String time) {
    return 'Actual: $time';
  }

  @override
  String entryStamp(String time) {
    return 'Entered: $time';
  }

  @override
  String revisionStamp(int revision) {
    return 'Revision $revision';
  }

  @override
  String recordContext(String person, String name, String unit) {
    return 'Record actual use for $person: $name, in $unit.';
  }

  @override
  String correctionContext(String person, String name, String unit) {
    return 'Correct actual use for $person: $name, in $unit.';
  }

  @override
  String savedContext(String person, String name, String amount, String unit) {
    return 'Saved for $person: $name, $amount $unit.';
  }

  @override
  String get ambiguousTime =>
      'This clock time occurs twice. Choose the earlier or later time.';

  @override
  String get earlier => 'Earlier';

  @override
  String get later => 'Later';

  @override
  String offsetChoice(String choice, String offset) {
    return '$choice: $offset';
  }

  @override
  String get more => 'More';

  @override
  String voidedContext(String person, String name, String amount, String unit) {
    return 'Voided for $person: $name, $amount $unit.';
  }

  @override
  String get keyringTitle => 'Keyring unavailable';

  @override
  String get keyringBody =>
      'Unlock the desktop keyring, then retry. If it stays unavailable, check that Secret Service and secret-tool are installed.';

  @override
  String get people => 'People';

  @override
  String get scope => 'Scope';

  @override
  String get everyone => 'Everyone';

  @override
  String get choosePerson => 'Choose person';

  @override
  String get addPerson => 'Add person';

  @override
  String get editPerson => 'Edit person';

  @override
  String get displayName => 'Display name';

  @override
  String get adultConfirmed => 'Adult confirmed';

  @override
  String get adultHelper => 'I am 18 or older.';

  @override
  String get profileSetupHelp =>
      'Enter your name and confirm you are an adult to start.';

  @override
  String get profileRequired => 'Enter your name and confirm you are an adult.';

  @override
  String get profileFailure =>
      'This profile could not be saved. Review the details and retry.';

  @override
  String get profileChanged =>
      'This profile has changed. Go back and review it before saving.';

  @override
  String get optionalDetails => 'Optional details';

  @override
  String get reportName => 'Report name (optional)';

  @override
  String get relationship => 'Relationship (optional)';

  @override
  String get profileNotes => 'Notes (optional)';

  @override
  String get edit => 'Edit';

  @override
  String get archive => 'Archive';

  @override
  String get reactivate => 'Reactivate';

  @override
  String get archived => 'Archived';

  @override
  String get archivePerson => 'Archive person';

  @override
  String archiveBody(String person) {
    return 'Archive $person? Their history stays available. They leave active feeds and their reminders stop.';
  }

  @override
  String reactivateBody(String person) {
    return 'Reactivate $person? Reminders stay stopped. No plans are available to resume in this build.';
  }

  @override
  String profileOwner(String person) {
    return 'Person: $person';
  }

  @override
  String onBehalf(String person) {
    return 'Recorded on behalf of $person.';
  }

  @override
  String meName(String name) {
    return '$name (Me)';
  }

  @override
  String profileReference(String name, String reference) {
    return '$name. Profile $reference';
  }

  @override
  String get scopeFailure => 'The browsing choice could not be saved. Retry.';

  @override
  String get profileUnavailable =>
      'This person is unavailable. Return to People to review their profile.';

  @override
  String get view => 'View';

  @override
  String get add => 'Add';

  @override
  String get details => 'Details';

  @override
  String get searchPeople => 'Find people';

  @override
  String get delete => 'Delete';

  @override
  String get deletePerson => 'Delete person';

  @override
  String get deleteRecords => 'Delete records';

  @override
  String deleteProfileBody(String person) {
    return 'Delete all saved records for $person? This cannot be undone. Me stays available; another adult’s profile is removed.';
  }

  @override
  String get archivedHelp =>
      'This person is archived. Reactivate them in People before recording or correcting use.';

  @override
  String get legacySource => 'Recording source was not recorded.';

  @override
  String get selfSource => 'Self-reported use.';

  @override
  String recordingOnBehalf(String person) {
    return 'You are recording on behalf of $person.';
  }

  @override
  String get profileDetailsLimit =>
      'Keep the display name within 500 characters and optional details within 4,000.';

  @override
  String get lockHeading => 'Unlock';

  @override
  String get lockBody =>
      'Use your device screen lock to open Vital. Your unfinished entries stay private.';

  @override
  String get lockLoading => 'Opening protected records.';

  @override
  String get lockUnavailable =>
      'Device authentication is unavailable. Check your device screen lock, then try again.';

  @override
  String get unlock => 'Unlock';

  @override
  String get lock => 'Lock';

  @override
  String get appLock => 'App lock';

  @override
  String get appLockHelper =>
      'Require your device screen lock when you open or return to Vital.';

  @override
  String get lockSetupRequired =>
      'Set up a device screen lock before enabling app lock.';

  @override
  String get lockUnsupported =>
      'Device authentication is unavailable on this platform. You can still record doses.';

  @override
  String get draftHeading => 'Unfinished entries';

  @override
  String get draftBody =>
      'Your entry is kept on this device until you save or discard it.';

  @override
  String get resume => 'Resume';

  @override
  String get draftFailure =>
      'Your latest changes could not be kept. Stay here and try again.';

  @override
  String get draftSaved =>
      'Your entry was already saved. Review the history before recording again.';

  @override
  String get draftDiscardFailure =>
      'This entry could not be discarded. Try again.';

  @override
  String get draftUnavailable =>
      'This entry is no longer available. Return to Today to review your records.';

  @override
  String get schedule => 'Schedule';

  @override
  String get planZoneUnavailable =>
      'The device time zone is unavailable. Retry or choose a named home zone.';

  @override
  String get planInputInvalid =>
      'Check the dates, times, count, amounts and time zone before previewing.';

  @override
  String get planEditHelp =>
      'Choose the date this change starts. Earlier versions and recorded doses stay in history.';

  @override
  String get planPattern => 'Timing';

  @override
  String get planCount => 'Count';

  @override
  String get planTimes => 'Chosen times';

  @override
  String get planAsNeeded => 'As needed';

  @override
  String get planCountHelp =>
      'The count applies to each selected date. Recorded and skipped counts are shown separately. This count is not a safe allowance.';

  @override
  String get planTime => 'Planned time';

  @override
  String get planPrnHelp =>
      'Record use when needed. There are no expected times or missed doses.';

  @override
  String get planStart => 'Start date';

  @override
  String get planEffective => 'Effective date';

  @override
  String get planEnd => 'End date (optional)';

  @override
  String get planEndHelp =>
      'YYYY-MM-DD. Includes this day. Leave blank for no end.';

  @override
  String get planZone => 'Time zone';

  @override
  String get planLocal => 'Follow local';

  @override
  String get planHome => 'Home zone';

  @override
  String get planHomeZone => 'Named home zone';

  @override
  String get planZoneExample => 'For example, Europe/London';

  @override
  String get planCalculationIssue =>
      'Some dates cannot be calculated with the available time zone data. Review this plan.';

  @override
  String get planIncomplete =>
      'The calculation limit was reached. This view is incomplete.';

  @override
  String get planBoundary => 'Clock boundary';

  @override
  String get planNoNext => 'No next planned date within this plan.';

  @override
  String get planMissingClock =>
      'This local time does not exist. Review the clock change.';

  @override
  String get planRepeatedClock =>
      'This local time occurs twice. Choose which one.';

  @override
  String get planNoAlert => 'No alert for this clock change';

  @override
  String get planPlanned => 'Planned';

  @override
  String get planNothingToday => 'Nothing planned today.';

  @override
  String get planTakenNow =>
      'Taken records the current time. Use Extra to enter another amount or actual time.';

  @override
  String get planClockReview => 'Clock review';

  @override
  String get planNoAlertHelp =>
      'Keep this planned dose without an alert, or enter a replacement time. This does not skip the dose.';

  @override
  String get planReplacementTime => 'Replacement time';

  @override
  String get taken => 'Taken';

  @override
  String get skip => 'Skip';

  @override
  String get extra => 'Extra';

  @override
  String get replace => 'Replace';

  @override
  String get remove => 'Remove';

  @override
  String planObserved(String zone) {
    return 'Observed zone: $zone';
  }

  @override
  String planPreviewRange(String start, String end) {
    return 'Preview: $start to $end';
  }

  @override
  String planNext(String date) {
    return 'Next planned date: $date';
  }

  @override
  String planEnds(String date) {
    return 'Last included date: $date';
  }

  @override
  String planReplacement(String time) {
    return 'Replacement time: $time';
  }

  @override
  String planUntimed(
    String date,
    int count,
    String amount,
    String unit,
    String zone,
  ) {
    return '$date: $count planned, $amount $unit each, untimed in $zone';
  }

  @override
  String planTimed(
    String date,
    String time,
    String amount,
    String unit,
    String zone,
    String status,
  ) {
    return '$date at $time: $amount $unit, $zone. $status';
  }

  @override
  String planProgress(int taken, int skipped, int planned) {
    return '$taken recorded, $skipped skipped, $planned planned';
  }

  @override
  String planClockInstant(String instant) {
    return 'Selected instant: $instant UTC';
  }

  @override
  String get planPreview => 'Preview';

  @override
  String get planZoneUnknown => 'Unknown';

  @override
  String get planHistory => 'Planned history';

  @override
  String get planHistoryHelp =>
      'Saved planned amounts and times appear here. Actual doses appear separately below.';

  @override
  String get planPreviewLimited =>
      'The first 20 planned doses are shown. The preview contains more doses.';

  @override
  String get planNextReview => 'Next date needs review';

  @override
  String get review => 'Review';

  @override
  String get planOlderActions =>
      'Earlier actions are available in pages of 100.';

  @override
  String planActionEntry(String action, String date) {
    return '$action, entered $date';
  }

  @override
  String planActionContext(
    String action,
    String person,
    String item,
    String amount,
    String unit,
    String date,
  ) {
    return '$action: $person, $item, $amount $unit, planned $date';
  }

  @override
  String get catalogue => 'Catalogue';

  @override
  String get catalogueSearch => 'Search medicines';

  @override
  String get catalogueHelp =>
      'Select the exact name, form and strength. The strength does not choose a dose or unit.';

  @override
  String get catalogueUnavailable =>
      'The medicine catalogue is unavailable. Enter a custom substance to continue.';

  @override
  String get catalogueSearching => 'Searching the offline catalogue…';

  @override
  String get catalogueStart =>
      'Enter a name, form or strength to search offline.';

  @override
  String get catalogueRefine =>
      'Some matches may be missing. Add more of the name, form or strength.';

  @override
  String get catalogueSearchFailure =>
      'Unable to search. Try again or enter a custom substance.';

  @override
  String get catalogueQueryLimit =>
      'Use up to 128 characters and 16 search words, or continue with a custom entry.';

  @override
  String get catalogueSelected => 'Selected product';

  @override
  String get catalogueCustom => 'Custom entry';

  @override
  String catalogueCustomHelp(String query) {
    return 'Continue with “$query” as the substance name.';
  }

  @override
  String catalogueNoMatch(String query) {
    return 'No catalogue match for “$query”. You can enter it as a custom substance.';
  }

  @override
  String catalogueRelease(String source, String version, String date) {
    return 'Source: $source. Version: $version. Released: $date.';
  }

  @override
  String catalogueProduct(String name, String form, String strength) {
    return '$name. Form: $form. Strength: $strength.';
  }

  @override
  String get catalogueMissing => 'Not supplied';

  @override
  String catalogueAttribution(String attribution) {
    return 'Attribution: $attribution';
  }

  @override
  String catalogueLicence(String licence) {
    return 'Licence: $licence';
  }

  @override
  String get catalogueSelect => 'Select';

  @override
  String get catalogueEnter => 'Enter';

  @override
  String get catalogueClear => 'Clear';

  @override
  String get catalogueSearchAction => 'Search';

  @override
  String get catalogueSelectedHelp =>
      'This saved source version stays with the substance and its dose history.';

  @override
  String catalogueSelectContext(String name, String form, String strength) {
    return 'Select $name, form $form, strength $strength';
  }

  @override
  String get itemTypes => 'Item types';

  @override
  String get itemTypesHelp =>
      'Types group this person’s substances. They do not change forms, strengths or icons.';

  @override
  String get itemTypesEmpty =>
      'No personal types yet. Create one or enter a type with a new substance.';

  @override
  String get itemTypeNew => 'New type';

  @override
  String get itemTypeEdit => 'Rename type';

  @override
  String get itemTypeName => 'Type name';

  @override
  String get itemTypeRenameHelp =>
      'Existing substances use the new name. Earlier dose records keep their saved type.';

  @override
  String get itemTypeManage => 'Manage';

  @override
  String get itemTypeRename => 'Rename';

  @override
  String itemTypeChoice(String name) {
    return 'Use type $name';
  }

  @override
  String itemTypeCurrent(String name) {
    return 'Selected type: $name';
  }

  @override
  String get previous => 'Previous';

  @override
  String get next => 'Next';

  @override
  String get itemTypeExists =>
      'This person already has that type. Choose a different name.';

  @override
  String get stock => 'Stock';

  @override
  String get stockCreate => 'Add container';

  @override
  String get stockAdjust => 'Adjust stock';

  @override
  String get stockLabel => 'Container name';

  @override
  String get stockStrength => 'Labelled strength';

  @override
  String get stockKnownStrength => 'Known strength';

  @override
  String get stockKnownStrengthHelp =>
      'Use the concentration printed on this container.';

  @override
  String get stockConcentration => 'Strength (mg/ml)';

  @override
  String get stockOpening => 'Starting amount';

  @override
  String get stockKnownOpening => 'Known amount';

  @override
  String get stockOpeningHelp =>
      'Leave this off when the remaining amount is unknown.';

  @override
  String get stockThreshold => 'Low-stock threshold';

  @override
  String get stockThresholdHelp =>
      'Optional. An empty threshold turns low-stock notices off.';

  @override
  String get stockRefill => 'Refill notices';

  @override
  String get stockRefillHelp =>
      'Show a notice here and in Today when known stock reaches zero or below.';

  @override
  String get stockEmpty =>
      'Containers are optional. Add one to track its supply.';

  @override
  String get stockOptional => 'Record without stock, or choose a container.';

  @override
  String get stockNone => 'No container';

  @override
  String get stockUnknown =>
      'Stock unknown. Measure the remaining amount to establish a balance.';

  @override
  String get stockLimit =>
      'Stock total unavailable. The recorded use remains saved.';

  @override
  String get stockLow => 'Low stock';

  @override
  String get stockRefillDue => 'Refill due';

  @override
  String get stockMismatch =>
      'Stock mismatch. The dose is saved. Review the container separately.';

  @override
  String get stockRestock => 'Restock';

  @override
  String get stockWaste => 'Waste';

  @override
  String get stockMeasure => 'Measure';

  @override
  String get stockReason => 'Reason (optional)';

  @override
  String get stockRestockHelp =>
      'Adds supply. An unknown balance stays unknown until measured.';

  @override
  String get stockWasteHelp => 'Removes supply without recording a dose.';

  @override
  String get stockMeasureHelp =>
      'Replaces the balance with the amount you measure. Earlier history stays unchanged.';

  @override
  String get stockUnknownMeasure => 'Unknown amount';

  @override
  String get stockUnknownMeasureHelp => 'Save the remaining stock as unknown.';

  @override
  String get stockDecimalHelp =>
      'Use a dot or comma for decimals, with no grouping. Up to six decimal places.';

  @override
  String get stockAmountInvalid =>
      'Enter an amount from 0.000001 to 9,000,000,000 with up to six decimal places.';

  @override
  String get stockMeasurementInvalid =>
      'Enter zero or a positive amount with up to six decimal places.';

  @override
  String get stockLabelRequired =>
      'Enter the container name and its labelled strength.';

  @override
  String get stockChooseKind => 'Choose restock, waste or measurement.';

  @override
  String get stockSource => 'Dose source';

  @override
  String get stockChoose => 'Choose';

  @override
  String get stockSelected => 'Selected';

  @override
  String get stockReplacement => 'Strength changed';

  @override
  String get stockReplacementHelp =>
      'Choose which amount to keep. This changes this dose only; future plans stay the same.';

  @override
  String get stockKeepMg => 'Keep mg';

  @override
  String get stockKeepMl => 'Keep ml';

  @override
  String get stockKeepRequired => 'Choose whether mg or ml stays fixed.';

  @override
  String get stockNoEquivalent =>
      'No equivalent is available for these strengths and units. Enter the actual amount for the selected container.';

  @override
  String get stockPhysical => 'Physical effect';

  @override
  String get stockPhysicalHelp =>
      'Choose what happened to the supply. Correcting details does not record another use.';

  @override
  String get stockRetain => 'Keep consumed';

  @override
  String get stockReverse => 'Reverse entry';

  @override
  String get stockRetainHelp =>
      'The supply was used or lost. Keep its stock effect.';

  @override
  String get stockReverseHelp =>
      'The recorded use was a mistake. Reverse its stock effect, preserving any later measurement.';

  @override
  String get stockPhysicalRequired =>
      'Choose whether the supply was consumed or the entry was a mistake.';

  @override
  String get stockAlreadyReviewed =>
      'The stock effect was already reviewed. Later detail changes keep that effect.';

  @override
  String get stockNotices => 'Stock notices';

  @override
  String get stockLocalNoticeHelp =>
      'Notices appear in Vital. No device notification is scheduled.';

  @override
  String get stockSaved => 'Stock saved';

  @override
  String get stockNoticeSaved => 'Notice settings saved.';

  @override
  String get stockNoticeFailure =>
      'Notice settings were not saved. Your entry is still here. Retry.';

  @override
  String stockEntered(String amount, String unit) {
    return 'Original entry: $amount $unit.';
  }

  @override
  String stockQuantity(String amount, String unit) {
    return '$amount $unit';
  }

  @override
  String stockApproximate(String amount, String unit) {
    return 'Approximately $amount $unit';
  }

  @override
  String stockBalance(String amount) {
    return 'Remaining: $amount';
  }

  @override
  String stockNoticeTarget(String person, String container) {
    return '$person: $container';
  }

  @override
  String stockStrengthValue(String strength) {
    return 'Labelled strength: $strength';
  }

  @override
  String stockReplacementFrom(String strength) {
    return 'Previous strength: $strength';
  }

  @override
  String stockNewEquivalent(String amount) {
    return 'This dose: $amount';
  }

  @override
  String stockThresholdValue(String amount) {
    return 'Low-stock threshold: $amount';
  }

  @override
  String get stockHistory => 'Stock history';

  @override
  String stockMovementEntry(String kind, String amount) {
    return '$kind: $amount';
  }

  @override
  String get stockUnavailable =>
      'This container is unavailable. Review the person and substance.';

  @override
  String get stockMore =>
      'More containers are available. Open Stock to review them.';

  @override
  String get stockApply => 'Apply';

  @override
  String get stockAdjustAction => 'Adjust';

  @override
  String get stockLabelOnly => 'Labelled strength';

  @override
  String get stockLabelOnlyHelp =>
      'Record the labelled strength without tracking a container.';

  @override
  String stockEntryProvenance(String amount, String unit) {
    return 'Entered: $amount $unit.';
  }

  @override
  String get stockCorrectionEntryHelp =>
      'Enter the corrected actual amount. A displayed approximate equivalent is never reused as an entry.';

  @override
  String get stockEnter => 'Enter';

  @override
  String get stockSourceAction => 'Source';

  @override
  String get stockCorrectionAmount => 'Actual amount (optional)';

  @override
  String get stockCorrectionKeep =>
      'Leave the amount empty to keep the saved exact quantity.';

  @override
  String get stockDeficit =>
      'Stock deficit. The recorded balance is below zero.';

  @override
  String get stockReviewedKeep =>
      'Leave the current stock balance unchanged. The earlier physical correction stays in history.';

  @override
  String get stockThresholdEditHelp =>
      'Enter a replacement threshold, or Clear to turn low-stock notices off. An empty unchanged entry keeps the saved threshold.';

  @override
  String get stockThresholdCleared =>
      'Low-stock notices will be turned off when you save.';

  @override
  String get stockStrengthRequired => 'Enter the labelled strength.';

  @override
  String get stockUnknownValue => 'Unknown';

  @override
  String get stockKeepBalance => 'Keep balance';

  @override
  String get stockConcentrationHelp =>
      'Optional. Leave empty when the concentration is unknown.';

  @override
  String get reminders => 'Reminders';

  @override
  String get reminderHelp =>
      'Alerts cover a limited window. Reopen Vital to prepare more. Android settings can affect delivery.';

  @override
  String get reminderUnsupported =>
      'Alerts are not available on this platform. Plans and records stay available.';

  @override
  String get reminderGeneric =>
      'Notifications show no person, substance or amount.';

  @override
  String get reminderDetailedUnavailable =>
      'Detailed notifications are not available.';

  @override
  String get reminderPermission =>
      'Allow notifications in Android to receive alerts.';

  @override
  String get reminderExact =>
      'Allow exact alarms in Android for planned alert times.';

  @override
  String get reminderBlocked =>
      'Android is blocking notifications. Review notification settings.';

  @override
  String get reminderProtected =>
      'Protected storage is unavailable. Unlock the device and reopen Vital.';

  @override
  String get reminderClock =>
      'Snooze is unavailable until the device clock can be checked. Reopen Vital and retry.';

  @override
  String get reminderAttention => 'Reminders need attention';

  @override
  String reminderUnprepared(String scope) {
    return 'No prepared coverage for $scope. Select Retry to check again.';
  }

  @override
  String reminderCoverage(String scope, String time) {
    return 'Prepared through $time for $scope. This does not confirm delivery.';
  }

  @override
  String get reminderIncomplete =>
      'Some alerts are not prepared in this scope. Reopen Vital and retry.';

  @override
  String reminderChecked(String time) {
    return 'Checked $time.';
  }

  @override
  String reminderPlanHelp(String person) {
    return 'Alerts for $person and this plan. Turning alerts off does not change the plan or records.';
  }

  @override
  String get reminderUntimed =>
      'Alerts need chosen times. Counts and as-needed plans have no alert times.';

  @override
  String get reminderPending => 'A reminder is awaiting review.';

  @override
  String get reminderDelay => 'Delay';

  @override
  String get reminderCustom => 'Custom delay';

  @override
  String get reminderCustomHelp => 'Enter a positive whole number of minutes.';

  @override
  String reminderMinutes(int minutes) {
    String _temp0 = intl.Intl.pluralLogic(
      minutes,
      locale: localeName,
      other: '$minutes minutes',
      one: '1 minute',
    );
    return '$_temp0';
  }

  @override
  String get reminderSnoozeHelp =>
      'The delay starts when you save. Snoozing does not record use.';

  @override
  String get reminderSaved =>
      'Snooze saved. Check reminder health to see whether the alert is prepared.';

  @override
  String get reminderChanged =>
      'This reminder has changed. Your entry is kept for review. Open the plan to check its current status.';

  @override
  String get reminderSubmitted =>
      'This action was submitted. Retry checks the same saved command.';

  @override
  String get reminderUnavailable =>
      'This reminder is no longer available. Review the plan before recording anything.';

  @override
  String get reminderInterrupted =>
      'Device restarted. Choose a delay to remind you again.';

  @override
  String get reminderSnoozeInterrupted => 'Snooze interrupted';

  @override
  String reminderActionContext(
    String person,
    String item,
    String amount,
    String unit,
  ) {
    return '$person: $item, $amount $unit.';
  }

  @override
  String reminderPlanScope(String person) {
    return 'Plan for $person';
  }

  @override
  String reminderRepairReason(String status) {
    return 'Alert status: $status.';
  }

  @override
  String get reminderStatePending => 'Awaiting preparation';

  @override
  String get reminderStatePrepared => 'Prepared';

  @override
  String get reminderStateConsumed => 'Issued, use not recorded';

  @override
  String get reminderStateCancelled => 'Cancelled';

  @override
  String get reminderStatePostUncertain =>
      'Display uncertain. Review this reminder';

  @override
  String get reminderStateFailed => 'Unavailable. Retry preparation';

  @override
  String get reminderStateUnknown => 'Preparation uncertain. Retry to check';

  @override
  String get reminderStateCapacity => 'Preparation limit reached';

  @override
  String get reminderStateExpired => 'Delay expired. Choose a new delay';

  @override
  String get reminderStateReview => 'Review required';

  @override
  String get reminderAllow => 'Allow';

  @override
  String get reminderSettings => 'Settings';

  @override
  String get snooze => 'Snooze';

  @override
  String get reminderDone => 'Done';

  @override
  String reminderScope(String person, String item) {
    return '$person: $item';
  }

  @override
  String reminderExcludedCount(int count) {
    return 'Entries outside coverage: $count.';
  }

  @override
  String get reminderDisabled => 'Alerts are off for this plan.';

  @override
  String get reminderNoOccurrences =>
      'No eligible alert times in this preparation window.';

  @override
  String get reminderWorkLimit =>
      'Preparation reached its work limit. Reopen Vital and retry.';

  @override
  String get reminderClockReview =>
      'Choose how to handle a missing or repeated clock time in this plan.';

  @override
  String get productToggle => 'Ready-mixed product';

  @override
  String get productToggleHelp =>
      'Record one volume with separate labelled ingredients.';

  @override
  String get productIngredients => 'Ingredients';

  @override
  String get productLabelHeading => 'Product label';

  @override
  String get productLabelHelp =>
      'Changes apply to future entries. Saved records keep their original label.';

  @override
  String get productIngredientName => 'Ingredient name';

  @override
  String get productConcentration => 'Concentration';

  @override
  String get productKnownStrength => 'Known strength';

  @override
  String get productKnownStrengthHelp =>
      'Copy a known concentration from the label. Otherwise leave it unknown.';

  @override
  String get productMassUnit => 'Mass unit';

  @override
  String get productVolumeUnit => 'Volume unit';

  @override
  String get productUnitsHelp =>
      'Only mg per ml has a calculated mass. Other labelled units stay unchanged.';

  @override
  String get productAdd => 'Add';

  @override
  String get productRemove => 'Remove';

  @override
  String get productLabelAction => 'Label';

  @override
  String get productIngredientInvalid =>
      'Enter 2–32 ingredients with names and units. Known concentrations must be positive decimals with up to six decimal places.';

  @override
  String get productUnknownAmount => 'Amount unknown.';

  @override
  String get productVolumeHelp =>
      'Enter the consumed volume in ml. Each ingredient is calculated separately.';

  @override
  String get productFixedVolume =>
      'The entered volume stays fixed. The selected container supplies this entry’s ingredient strengths. Future defaults stay unchanged.';

  @override
  String get productSnapshotHelp => 'Based on the label saved with this entry.';

  @override
  String get productNoLabel =>
      'No ready-mixed label is saved. Create a label with at least two ingredients.';

  @override
  String get productSourceHelp =>
      'This container keeps its own labelled ingredients. Later product edits leave this container unchanged.';

  @override
  String get productSourceRequired =>
      'Choose a container with labelled ingredients for this product, or select None.';

  @override
  String get productUnavailable =>
      'The labelled ingredients are unavailable. Retry before recording.';

  @override
  String productUnknownStrength(String massUnit, String volumeUnit) {
    return 'Concentration unknown ($massUnit/$volumeUnit).';
  }

  @override
  String productStrengthValue(
    String amount,
    String massUnit,
    String volumeUnit,
  ) {
    return 'Label: $amount $massUnit/$volumeUnit.';
  }

  @override
  String productIngredientNumber(int number) {
    return 'Ingredient $number';
  }

  @override
  String productAmountValue(String amount) {
    return 'Amount: $amount.';
  }

  @override
  String productVolumeValue(String amount) {
    return 'Product volume: $amount.';
  }

  @override
  String get productOldLabel => 'Default label';

  @override
  String get productNewLabel => 'Selected label';

  @override
  String productFieldContext(int number, String field) {
    return 'Ingredient $number: $field';
  }

  @override
  String productRemoveContext(int number) {
    return 'Remove ingredient $number';
  }

  @override
  String get productAddContext => 'Add ingredient';

  @override
  String get calendarDates => 'Dates';

  @override
  String get calendarDatesHelp =>
      'Choose the dates separately from the quantity and times.';

  @override
  String get calendarDaily => 'Daily';

  @override
  String get calendarWeekdays => 'Weekdays';

  @override
  String get calendarDays => 'Days';

  @override
  String get calendarWeeks => 'Weeks';

  @override
  String get calendarMonths => 'Months';

  @override
  String get calendarMonday => 'Monday';

  @override
  String get calendarTuesday => 'Tuesday';

  @override
  String get calendarWednesday => 'Wednesday';

  @override
  String get calendarThursday => 'Thursday';

  @override
  String get calendarFriday => 'Friday';

  @override
  String get calendarSaturday => 'Saturday';

  @override
  String get calendarSunday => 'Sunday';

  @override
  String get calendarDayInterval => 'Every N days';

  @override
  String get calendarWeekInterval => 'Every N weeks';

  @override
  String get calendarMonthInterval => 'Every N months';

  @override
  String get calendarIntervalHelp =>
      'Enter a positive whole number. Calendar days keep their local dates across clock changes.';

  @override
  String get calendarYearHelp =>
      'Enter a positive whole number. Use 12 for a yearly pattern.';

  @override
  String get calendarAnchor => 'First anchor date';

  @override
  String get calendarWeekAnchor => 'Anchor week start';

  @override
  String get calendarMonthAnchor => 'Anchor month';

  @override
  String get calendarWeekHelp =>
      'YYYY-MM-DD. This saved date starts the first week. Selected weekdays repeat from this week, regardless of display preferences.';

  @override
  String get calendarMonthHelp =>
      'YYYY-MM-DD. Any date in the first eligible month. The nominal day below stays separate from the effective start.';

  @override
  String get calendarSelectWeekdays => 'Choose at least one weekday.';

  @override
  String get calendarMonthRule => 'Monthly rule';

  @override
  String get calendarDate => 'Date';

  @override
  String get calendarOrdinal => 'Ordinal';

  @override
  String get calendarLast => 'Last';

  @override
  String get calendarNominalDay => 'Day of month';

  @override
  String get calendarNominalHelp =>
      'Enter 1 to 31. This nominal day stays the same after a short month.';

  @override
  String get calendarOrdinalNumber => 'Weekday occurrence';

  @override
  String get calendarWeekday => 'Weekday';

  @override
  String get calendarMissing => 'Missing dates';

  @override
  String get calendarMissingDayHelp =>
      'Omit creates no planned dose when the day is missing. Use chooses that month’s last day, then returns to the nominal day.';

  @override
  String get calendarMissingWeekHelp =>
      'Omit creates no planned dose when this weekday occurrence is missing. Use chooses the last matching weekday in that month.';

  @override
  String get calendarOmit => 'Omit';

  @override
  String get calendarUse => 'Use';

  @override
  String get calendarMissingRequired =>
      'Choose Omit or Use for months without the selected date.';

  @override
  String get calendarInvalid =>
      'Check the calendar dates, positive interval and selected weekdays, then preview again.';

  @override
  String get calendarUnsupported =>
      'This calendar combination is unsupported. Choose a supported date pattern before saving.';

  @override
  String calendarAnchorPreview(String from, String to) {
    return 'Anchor week: $from to $to. This saved week fixes the repeat pattern.';
  }

  @override
  String calendarBoundaryDay(String month, int day) {
    return '$month: nominal day $day does not exist.';
  }

  @override
  String calendarBoundaryWeekday(String month, int ordinal, String weekday) {
    return '$month: occurrence $ordinal of $weekday does not exist.';
  }

  @override
  String get calendarBoundaryOmitted =>
      'No dose is planned for this missing date. No Skip is recorded.';

  @override
  String calendarBoundaryUse(String date) {
    return 'The planned date is $date.';
  }

  @override
  String calendarBoundaryNext(String date) {
    return 'Next selected date: $date. The nominal rule stays unchanged.';
  }

  @override
  String calendarKnownDate(String date) {
    return 'Next calendar date: $date. Its time cannot be converted with the available timezone rules.';
  }

  @override
  String get calendarBeyondPreview =>
      'This next date is beyond the preview range. Reminder preparation uses a separate range.';

  @override
  String get calendarBoundaryLimit =>
      'The first missing-date boundary could not be established within the calculation range.';

  @override
  String get calendarOrdinalHelp =>
      'Choose 1 for the first matching weekday, 2 for the second, and so on.';

  @override
  String get intervalPattern => 'Interval';

  @override
  String get intervalBasis => 'Interval anchor';

  @override
  String get intervalFixed => 'Planned';

  @override
  String get intervalActual => 'Recorded';

  @override
  String get intervalFixedHelp =>
      'Keep the entered planned anchor. Recorded doses do not move this interval.';

  @override
  String get intervalActualHelp =>
      'Use the latest qualifying recorded time for this plan. Extra doses do not qualify automatically.';

  @override
  String get intervalDuration => 'Elapsed hours';

  @override
  String get intervalDurationHelp =>
      'Enter a positive number of hours, for example 6 or 1.5.';

  @override
  String get intervalAnchor => 'Planned instant';

  @override
  String get intervalAnchorHelp =>
      'Enter a date and time with its UTC offset, for example 2026-10-19T08:00:00+01:00. Use Z for UTC.';

  @override
  String get intervalNoAnchor => 'No qualifying dose';

  @override
  String get intervalNoAnchorHelp =>
      'Record a dose, then review whether it qualifies for this plan.';

  @override
  String intervalNext(String instant) {
    return 'Next planned instant: $instant';
  }

  @override
  String get intervalReview => 'Next time';

  @override
  String intervalBefore(String value) {
    return 'Before: $value';
  }

  @override
  String intervalAfter(String value) {
    return 'After: $value';
  }

  @override
  String get intervalQualify => 'Qualifying dose';

  @override
  String get intervalQualifyHelp =>
      'Select this recorded dose as a possible anchor for this plan. Review the resulting next time before saving.';

  @override
  String get intervalExtraHelp =>
      'Extra doses do not change this interval unless you select them explicitly.';

  @override
  String get intervalTakenHelp =>
      'Taken qualifies this dose for the plan. The latest qualifying recorded time sets the next time.';

  @override
  String get intervalFuture =>
      'Choose a recorded time that has already happened before setting the next time.';

  @override
  String intervalDurationValue(String hours) {
    return 'Every $hours elapsed hours';
  }

  @override
  String get intervalQualified =>
      'This dose qualifies for this plan. The latest qualifying recorded time sets the next time.';

  @override
  String get select => 'Select';

  @override
  String intervalPlan(String date, String hours) {
    return 'Plan from $date: every $hours elapsed hours';
  }

  @override
  String intervalSourceRevision(int revision) {
    return 'Recorded dose revision: $revision';
  }

  @override
  String get intervalEditHelp =>
      'Changing the interval or anchor starts a new segment. Recorded intervals then need a qualifying dose.';

  @override
  String get intervalInputInvalid =>
      'Enter positive elapsed hours, an amount and valid dates. A planned anchor needs an explicit time zone offset.';

  @override
  String intervalRecordedTime(String instant) {
    return 'Recorded instant: $instant';
  }

  @override
  String intervalProposedAmount(String amount, String unit) {
    return 'New amount: $amount $unit';
  }

  @override
  String intervalAnchorRevision(int revision) {
    return 'Anchor dose revision: $revision';
  }

  @override
  String get intervalClockHeading => 'Review timing';

  @override
  String get intervalClockHelp =>
      'Interval reminders need a timing review after a restart or clock change. Open this plan in Today to review recovery.';

  @override
  String get intervalClockStopped => 'Interval reminders stopped';

  @override
  String intervalClockReview(String date) {
    return 'Use the current device clock from $date. Keep recorded anchors and history. Earlier reminders will not be replayed.';
  }

  @override
  String get intervalEarlierReview =>
      'This time does not follow the current anchor. Record the dose separately, then review whether it qualifies for this plan.';

  @override
  String get pauseHeading => 'Pause plan';

  @override
  String get pauseResume => 'Resume plan';

  @override
  String get pauseBlocks => 'Repeating breaks';

  @override
  String get pauseContinuous => 'Continuous';

  @override
  String get pauseOnDays => 'Active days';

  @override
  String get pauseOffDays => 'Break days';

  @override
  String get pauseOffHelp =>
      'Enter whole days. Zero break days keeps the plan continuous.';

  @override
  String get pauseBlockAnchor => 'First active date';

  @override
  String get pauseIntersection =>
      'A date must match both the chosen calendar dates and the active block. Elapsed intervals keep their original instants.';

  @override
  String get pauseConsequence =>
      'Pausing stops planned opportunities and reminders. Recorded doses and stock history stay unchanged.';

  @override
  String get pauseStart => 'Pause instant';

  @override
  String get pauseResumeAt => 'Resume instant';

  @override
  String get pauseChoice => 'Choose how the pattern resumes.';

  @override
  String get pausePreserve => 'Preserve';

  @override
  String get pauseRestart => 'Restart';

  @override
  String get pausePreserveHelp =>
      'Keep the original dates and interval starting point. Time continues through the pause.';

  @override
  String get pauseRestartHelp =>
      'Start a new pattern from the date or instant you enter. The plan end stays unchanged.';

  @override
  String get pauseNewAnchor => 'New first date';

  @override
  String get pauseDateHelp =>
      'Enter YYYY-MM-DD. Weekly patterns need a Monday; monthly patterns need the first of a month.';

  @override
  String get pauseActualHelp =>
      'A paused next dose stays suppressed. Review a qualifying recorded dose or edit the timing basis to use a planned starting point. Resuming creates no dose.';

  @override
  String get pauseInvalid =>
      'Choose Preserve or Restart when resuming. Enter a valid instant with its UTC offset and any required new anchor.';

  @override
  String get pauseHistory => 'Pause history';

  @override
  String get pauseHistoryHelp =>
      'Recorded pause periods describe the plan. They do not prove doses were taken.';

  @override
  String get pauseNoHistory => 'No recorded pauses.';

  @override
  String get pauseOngoing => 'Ongoing';

  @override
  String get pauseState => 'Paused';

  @override
  String get pauseRecordHelp =>
      'Record actual use separately while this plan is paused.';

  @override
  String pauseBefore(String value) {
    return 'Before: $value';
  }

  @override
  String pauseAfter(String value) {
    return 'After: $value';
  }

  @override
  String pauseBoundary(String value) {
    return 'First affected boundary: $value';
  }

  @override
  String pausePeriod(String start, String resume) {
    return 'Recorded pause: $start to $resume';
  }

  @override
  String pauseDuration(int minutes) {
    return 'Recorded pause duration: $minutes complete minutes. This is not a count of doses taken.';
  }

  @override
  String pauseBlockSummary(int active, int rest, String anchor) {
    return '$active active days, $rest break days, starting on $anchor.';
  }

  @override
  String get pauseAction => 'Pause';

  @override
  String get phaseHeading => 'Phases';

  @override
  String get phaseMixed => 'Partly timed';

  @override
  String get phaseWindows => 'Time windows';

  @override
  String get phaseMixedHelp =>
      'The total includes the chosen times and an untimed remainder. Enter more total doses than chosen times.';

  @override
  String get phaseWindowHelp =>
      'A window belongs to its start date. An end before its start falls on the next day. Actual use is recorded separately.';

  @override
  String get phaseWindowStart => 'Window start';

  @override
  String get phaseWindowEnd => 'Window end';

  @override
  String get phaseWindowEndHelp => 'Use HH:MM. Both endpoints are kept.';

  @override
  String get phaseWindowAnchor => 'Reminder time';

  @override
  String get phaseWindowAnchorHelp =>
      'Optional HH:MM inside the window. This is an alert time, not a recorded dose.';

  @override
  String get phaseNoAnchor => 'No reminder time';

  @override
  String phaseWindowSummary(
    String date,
    String start,
    String end,
    String amount,
    String unit,
    String anchor,
    String zone,
  ) {
    return '$date: $start to $end, $amount $unit. Reminder: $anchor. Zone: $zone.';
  }

  @override
  String phaseOverrideSummary(
    String original,
    String oldAmount,
    String oldUnit,
    String effective,
    String amount,
    String unit,
  ) {
    return 'Original: $original, $oldAmount $oldUnit. Changed: $effective, $amount $unit.';
  }

  @override
  String get phaseHelp =>
      'Enter each phase yourself. Gaps have no planned doses. Existing recorded doses keep their original meaning.';

  @override
  String get phaseEndHeading => 'Plan end';

  @override
  String get phaseNoEnd => 'Open ended';

  @override
  String get phaseDateEnd => 'Last day';

  @override
  String get phaseExactEnd => 'Exact end';

  @override
  String get phaseEndZone => 'End zone';

  @override
  String get phaseEndHelp =>
      'The last day includes the whole day in this saved zone. An exact end excludes that instant. Choose an exact end if midnight needs a clock choice.';

  @override
  String get phaseExactHelp => 'Use a date, time and UTC or numerical offset.';

  @override
  String get phaseStart => 'Phase start';

  @override
  String get phaseLast => 'Phase last day';

  @override
  String phaseBoundary(String value) {
    return 'First boundary: $value.';
  }

  @override
  String phaseGap(String start, String end) {
    return 'Gap: $start to $end. No doses are planned in this range.';
  }

  @override
  String get phaseInvalid =>
      'Check phase dates, amounts and timing. Phases must not overlap. Review each entered endpoint and plan end.';

  @override
  String get phaseChangeHeading => 'One-off change';

  @override
  String get phaseChangeHelp =>
      'Choose the original dose by its date and identity. Moving keeps its original amount unless you enter a replacement amount.';

  @override
  String get phaseOriginalDate => 'Original date';

  @override
  String get phaseTarget => 'New time';

  @override
  String get phaseTargetHelp =>
      'Optional date, time and offset. Leave empty to keep the original time.';

  @override
  String get phaseAmount => 'New amount';

  @override
  String get phaseAmountHelp =>
      'Optional. Leave empty to keep the original amount and unit.';

  @override
  String phaseBefore(String value) {
    return 'Before: $value';
  }

  @override
  String phaseAfter(String value) {
    return 'After: $value';
  }

  @override
  String phaseEndSummary(String value, String zone) {
    return 'Plan end: $value. Saved zone: $zone.';
  }

  @override
  String get phaseCollision =>
      'Separate doses share this time. Review each identity before saving. This does not combine the doses.';

  @override
  String phaseCollisionLabel(String value) {
    return 'Dose identity: $value';
  }

  @override
  String get phaseSavedHelp =>
      'Phases and one-off changes retain their original dose identities. Actual use remains separate.';

  @override
  String get phaseRemoveHelp =>
      'Removing a phase changes future expectations. Review the resulting plan before saving.';

  @override
  String get phaseNotSelected =>
      'Choose an original dose before adding a one-off change.';

  @override
  String get phaseReviewIssue =>
      'This change crosses a pause, end or unresolved clock boundary. Choose valid timing or review the plan boundary.';

  @override
  String phaseSource(String value) {
    return 'Original identity: $value';
  }

  @override
  String get phaseReviewHelp =>
      'Review the complete amounts and first boundary before saving. Cancel clears this review and changes nothing.';

  @override
  String get phaseWindowMoveHelp =>
      'Enter the full reminder date, time and offset if alerts are enabled. Both endpoints must be entered when moving a window.';

  @override
  String phaseEndpoint(String value) {
    return 'Window endpoint: $value';
  }

  @override
  String phaseWindowChanged(
    String originalStart,
    String originalEnd,
    String originalAnchor,
    String oldAmount,
    String oldUnit,
    String start,
    String end,
    String anchor,
    String amount,
    String unit,
    String zone,
  ) {
    return 'Original window: $originalStart to $originalEnd, reminder $originalAnchor, $oldAmount $oldUnit. Changed window: $start to $end, reminder $anchor, $amount $unit. Zone: $zone.';
  }

  @override
  String phaseCountSummary(String count, String amount, String unit) {
    return '$count doses each planned day, $amount $unit each. No chosen times.';
  }

  @override
  String phaseMixedSummary(
    String count,
    String timed,
    String amount,
    String unit,
  ) {
    return '$count doses each planned day. $timed have chosen times. The untimed doses use $amount $unit each.';
  }

  @override
  String phaseSlotSummary(String time, String amount, String unit) {
    return 'Chosen time: $time, $amount $unit.';
  }

  @override
  String phaseWindowEntered(
    String start,
    String end,
    String amount,
    String unit,
    String anchor,
  ) {
    return 'Window: $start to $end, $amount $unit. Reminder time: $anchor.';
  }

  @override
  String phaseIntervalSummary(String hours, String amount, String unit) {
    return 'Every $hours elapsed hours, $amount $unit.';
  }

  @override
  String get phaseReviewed => 'Reviewed';

  @override
  String phaseFrom(String instant) {
    return 'Starts at $instant.';
  }

  @override
  String phaseUntil(String instant) {
    return 'Ends before $instant.';
  }

  @override
  String get phaseEditHelp =>
      'To change an active phase, enter its last day and add a new phase. Earlier recorded doses stay unchanged.';

  @override
  String phaseEndpointLabel(
    String label,
    String date,
    String time,
    String zone,
  ) {
    return '$label: $date at $time, $zone.';
  }

  @override
  String phaseWindowPending(
    String startDate,
    String start,
    String endDate,
    String end,
    String amount,
    String unit,
    String zone,
  ) {
    return 'Window: $startDate at $start to $endDate at $end, $amount $unit. Review endpoint clocks in $zone.';
  }

  @override
  String phaseBucketHelp(int count) {
    return 'This group has $count untimed doses. Edit the shared plan amount, or record an individual dose with its actual amount.';
  }

  @override
  String get phaseSingleCount =>
      'This dose has no chosen time. Enter a new amount, or record actual use separately.';

  @override
  String get combinedHeading => 'Combined entry';

  @override
  String get combinedHelp =>
      'Record several sources for one person at the same time. Review each amount and stock effect before saving.';

  @override
  String get combinedAction => 'Combine';

  @override
  String get combinedAdd => 'Add source';

  @override
  String get combinedCount =>
      'Choose 2 to 16 sources. Each source keeps its own amount and stock effect.';

  @override
  String get combinedSourceLoadFailure =>
      'The source could not be loaded. Choose it again.';

  @override
  String get combinedReview => 'Review entry';

  @override
  String get combinedReviewHelp =>
      'Save all sources together. Cancelling this review changes no records or stock.';

  @override
  String get combinedHistory => 'Combined record';

  @override
  String get combinedHistoryHelp =>
      'Correct or undo every source together. Each source retains its own history.';

  @override
  String get combinedCorrection => 'Correct entry';

  @override
  String get combinedUndoHelp =>
      'Undo marks every source as voided. Choose the physical stock consequence for each source.';

  @override
  String get combinedNoStock => 'No stock movement.';

  @override
  String get combinedStockUnknown =>
      'Stock outflow unknown. The remaining balance will be unknown.';

  @override
  String combinedOutflow(String amount) {
    return 'Stock outflow: $amount.';
  }

  @override
  String combinedTotal(String source, String amount) {
    return 'Total from $source: $amount.';
  }

  @override
  String combinedRemaining(String amount) {
    return 'Remaining: $amount.';
  }

  @override
  String get combinedSite => 'Site (optional)';

  @override
  String get combinedSiteHelp =>
      'Enter a site label if useful. It is saved for this person only.';

  @override
  String get combinedSites => 'Site history';

  @override
  String combinedSiteValue(String site) {
    return 'Site: $site.';
  }

  @override
  String combinedSource(int number) {
    return 'Source $number';
  }

  @override
  String get combinedRemove => 'Remove';

  @override
  String get combinedEdit => 'Edit';

  @override
  String get combinedChoose => 'Choose';

  @override
  String get combinedKeep => 'Keep';

  @override
  String get combinedReverse => 'Restore';

  @override
  String get combinedKeepHelp => 'Keep the original physical consumption.';

  @override
  String get combinedReverseHelp =>
      'Reverse the original stock outflow. Use this only for a mistaken entry.';

  @override
  String get combinedPhysicalRequired =>
      'Choose the stock consequence for every source.';

  @override
  String get combinedInvalid =>
      'Check each source amount, unit and time, then review again.';

  @override
  String get combinedRestoreEffect => 'Restore the original stock outflow.';

  @override
  String get combinedRetainEffect => 'Keep the original stock balance.';

  @override
  String get combinedSiteAction => 'Site';

  @override
  String combinedAmountLabel(String name, String unit) {
    return 'Amount for $name, in $unit.';
  }

  @override
  String combinedSiteLabel(String name) {
    return 'Site for $name.';
  }

  @override
  String combinedRemoveLabel(int number, String name) {
    return 'Remove source $number: $name.';
  }

  @override
  String combinedKeepLabel(String name) {
    return 'Keep consumption for $name.';
  }

  @override
  String combinedRestoreLabel(String name) {
    return 'Restore stock for $name.';
  }

  @override
  String combinedSourceLabel(int number, String name) {
    return 'Choose stock for source $number: $name.';
  }

  @override
  String get combinedSiteInvalid =>
      'Use a site label with 500 characters or fewer.';

  @override
  String get eventNew => 'New event';

  @override
  String get eventEdit => 'Edit event';

  @override
  String get eventName => 'Event name';

  @override
  String get eventType => 'Event type';

  @override
  String get eventCycle => 'Cycle';

  @override
  String get eventPrescription => 'Prescription';

  @override
  String get eventEmpty =>
      'No events yet. Create a cycle or prescription event to organise recorded use.';

  @override
  String get eventHelp =>
      'Events organise use history. They do not record doses or change stock or plans.';

  @override
  String get eventPlannedStart => 'Planned start';

  @override
  String get eventPlannedEnd => 'Planned end';

  @override
  String get eventActualStart => 'Actual start';

  @override
  String get eventActualEnd => 'Actual end';

  @override
  String get eventZone => 'Event zone';

  @override
  String get eventDateHelp =>
      'Optional. Enter YYYY-MM-DD or an exact ISO time with Z or an offset. A final date includes the whole day in the event zone.';

  @override
  String get eventCompleted => 'Completed';

  @override
  String get eventCompletedHelp =>
      'Record the event as complete. Each item keeps its current plan until you explicitly change it.';

  @override
  String get eventDateError =>
      'Enter a valid date or an exact time with Z or an offset. Leave an optional date empty.';

  @override
  String get eventZoneError =>
      'Enter a valid IANA zone, such as Europe/London.';

  @override
  String get eventMembers => 'Event items';

  @override
  String get eventMemberHelp =>
      'Membership uses exact times with Z or an offset. Earlier use is included only when it falls within the reviewed interval and event dates.';

  @override
  String get eventMemberStart => 'Membership start';

  @override
  String get eventMemberEnd => 'Membership end';

  @override
  String get eventMemberOpen => 'Open membership';

  @override
  String get eventReview => 'Review event';

  @override
  String get eventPreviewHelp =>
      'Review historical records before saving. Cancelling leaves membership and all records unchanged.';

  @override
  String eventPreviewEnter(int count) {
    return 'Records included: $count';
  }

  @override
  String eventPreviewLeave(int count) {
    return 'Records excluded: $count';
  }

  @override
  String get eventPreviewChanged =>
      'Event details changed. Review the new historical selection before saving.';

  @override
  String get eventNoActuals =>
      'No actual records fall within the selected event dates and memberships.';

  @override
  String get eventHistoryHelp =>
      'Actual records keep their original identity, amounts and recorded type. Combined event selections count each record once.';

  @override
  String get eventBounds => 'Event dates';

  @override
  String eventPlannedLabel(String start, String end) {
    return 'Planned: $start to $end';
  }

  @override
  String eventActualLabel(String start, String end) {
    return 'Actual: $start to $end';
  }

  @override
  String get eventNotRecorded => 'Not recorded';

  @override
  String get eventOpen => 'Open';

  @override
  String get eventEndReview => 'End review';

  @override
  String get eventEndHelp =>
      'Review each item’s current plan and next result. No stopping is selected. Dismiss leaves all plans and stock unchanged.';

  @override
  String get eventDismiss => 'Dismiss';

  @override
  String get eventContinue => 'Continue';

  @override
  String get eventStop => 'Stop';

  @override
  String get eventReviewRemaining =>
      'Review remaining items. Completed decisions stay saved.';

  @override
  String get eventContinueHelp =>
      'Keep the current plan. Its next result remains subject to its saved phases and end rules.';

  @override
  String get eventStopHelp =>
      'Stop future eligibility using the reviewed plan command. Saved doses and stock stay unchanged.';

  @override
  String get eventNoPlan => 'No current plan';

  @override
  String get eventDecisionSaved => 'Decision saved.';

  @override
  String get eventChoose => 'Select an item';

  @override
  String get eventOwner => 'Event owner';

  @override
  String get eventInvalid =>
      'Check the event name, dates and membership times, then review again.';

  @override
  String get eventNoMembers =>
      'No item memberships. Add an item with its effective start.';

  @override
  String get eventMembership => 'Membership';

  @override
  String get eventInclusive =>
      'A final date includes that whole day in the saved event zone.';

  @override
  String get eventCombined => 'Combined history';

  @override
  String get eventSelectHelp =>
      'Select events to inspect one combined history without counting the same actual record twice.';

  @override
  String get eventSelected => 'Selected';

  @override
  String get eventSelect => 'Select';

  @override
  String get useHistory => 'Use history';

  @override
  String get useNew => 'New period';

  @override
  String get useEdit => 'Edit period';

  @override
  String get useHelp =>
      'Recorded periods and first-ever starts are optional history. They do not infer continuous use, adherence or change any plan.';

  @override
  String get useEmpty =>
      'No use periods recorded. Individual actual records and plans remain separate.';

  @override
  String get useStart => 'Recorded start';

  @override
  String get useEnd => 'Recorded end';

  @override
  String get useDateHelp =>
      'Enter YYYY, YYYY-MM or YYYY-MM-DD. Use Unknown for an unknown date. Leave the end empty for an open period.';

  @override
  String get useDateError =>
      'Enter a valid year, month or date, or Unknown. Leave the end empty for an open period.';

  @override
  String get useFirstEver => 'First-ever start';

  @override
  String get useFirstEverHelp =>
      'Mark this supplied start as the first-ever use. Unknown stays unknown.';

  @override
  String get useKind => 'Period type';

  @override
  String get useTaking => 'Use';

  @override
  String get useBreak => 'Break';

  @override
  String useFirstLabel(String date) {
    return 'First-ever start: $date';
  }

  @override
  String usePeriodLabel(String start, String end) {
    return '$start to $end';
  }

  @override
  String get useUnknown => 'Unknown';

  @override
  String get eventRemove => 'Remove';

  @override
  String get eventAdd => 'Add';

  @override
  String eventItemIdentity(String name, String detail, String reference) {
    return 'Item: $name · $detail · Entry $reference';
  }

  @override
  String get eventClear => 'Clear';

  @override
  String get eventRevisions => 'Revisions';

  @override
  String eventRevision(int number) {
    return 'Revision $number';
  }

  @override
  String useDays(int days) {
    return 'Recorded length: $days days.';
  }

  @override
  String eventReviewTime(String time) {
    return 'Review time: $time';
  }

  @override
  String eventMemberStartFor(String name) {
    return 'Membership start for $name';
  }

  @override
  String eventMemberEndFor(String name) {
    return 'Membership end for $name';
  }

  @override
  String eventRemoveFor(String name) {
    return 'Remove $name from future event membership';
  }

  @override
  String eventReviewFor(String name, String person) {
    return 'Review $name for $person';
  }

  @override
  String eventSelectFor(String name, String person) {
    return 'Select $name for $person';
  }

  @override
  String eventMemberRange(String start, String end, String zone) {
    return 'Membership: $start to $end ($zone).';
  }

  @override
  String get eventBoundaryReview =>
      'This date needs review. Enter an exact time with Z or an offset, check the event zone, then review again.';

  @override
  String get eventDueReview =>
      'This event has ended. Review which plans continue.';

  @override
  String get attachments => 'Files';

  @override
  String get attachmentHelp =>
      'Add an optional original file or photo to this record. A photo does not confirm that a dose was taken.';

  @override
  String get attachmentEmpty =>
      'No files attached. Choose a file or an existing photo to add one.';

  @override
  String get attachmentChoose => 'Choose';

  @override
  String get attachmentPhotos => 'Photos';

  @override
  String get attachmentCapture => 'Capture';

  @override
  String get attachmentUnavailable =>
      'File selection is unavailable here. Existing protected files remain available.';

  @override
  String get attachmentCameraUnavailable =>
      'Camera capture is unavailable here. You can choose an existing photo.';

  @override
  String get attachmentNew => 'Add file';

  @override
  String get attachmentOriginal => 'Original file';

  @override
  String get attachmentName => 'File name';

  @override
  String get attachmentRename => 'Rename';

  @override
  String get attachmentDelete => 'Delete from record';

  @override
  String attachmentDeleteHelp(String name, String person) {
    return 'Delete $name from $person’s record. Vital removes its protected copy after any open preview or share releases it. Your source file and shared copies stay unchanged.';
  }

  @override
  String get attachmentShare => 'Share';

  @override
  String get attachmentShareHeading => 'Share file';

  @override
  String attachmentShareHelp(String name, String person) {
    return 'Share $name for $person. Only this original is handed to the destination you choose. Its contents and metadata may contain personal information.';
  }

  @override
  String get attachmentShareLifetime =>
      'The receiving app can read the prepared copy for up to 24 hours, including after Vital locks. It may keep its own copy.';

  @override
  String get attachmentSaveHelp =>
      'Save a copy of this original to the location you choose. That copy is outside Vital’s protected storage.';

  @override
  String get attachmentReady => 'Ready';

  @override
  String get attachmentStaging => 'Importing file';

  @override
  String get attachmentAwaiting => 'Waiting for selection';

  @override
  String get attachmentInterrupted =>
      'Selection interrupted. Resume the original import or cancel it.';

  @override
  String get attachmentRemoving => 'Removing file';

  @override
  String get attachmentPinned =>
      'An open preview or share keeps this exact original until it is released.';

  @override
  String attachmentBytes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count bytes',
      one: '1 byte',
    );
    return '$_temp0';
  }

  @override
  String get attachmentSaved => 'File added to this record.';

  @override
  String get attachmentCancelled =>
      'Selection cancelled. The original is unchanged.';

  @override
  String get attachmentShared =>
      'Share opened. The prepared original stays available for up to 24 hours.';

  @override
  String get attachmentCopySaved => 'Copy saved to the location you chose.';

  @override
  String get attachmentFailed =>
      'Unable to complete this file action. Try again.';

  @override
  String get attachmentStale =>
      'This file’s record changed or is unavailable. Return to its original record and review it.';

  @override
  String get attachmentArchivedProfile =>
      'This person is archived. Reactivate them in People to manage files.';

  @override
  String get attachmentVoidedRecord =>
      'This dose is voided. Files cannot be added to it.';

  @override
  String get attachmentNameError =>
      'Enter a file name with 1 to 255 characters.';

  @override
  String get attachmentByteError =>
      'Choose a file no larger than 16 MiB. Your source file is unchanged.';

  @override
  String get attachmentImageError =>
      'This image cannot be previewed. Choose a complete image with at most 16 million pixels and one frame. Your source is unchanged.';

  @override
  String get attachmentPdfError =>
      'This PDF cannot be previewed. Choose a complete, unencrypted PDF with no more than 100 pages. Your source is unchanged.';

  @override
  String get attachmentBusy =>
      'An import is already waiting. Resume or cancel it before choosing another file.';

  @override
  String get attachmentShareBusy =>
      'Earlier shares are still available to their receiving apps. Try again after their 24-hour handoff period.';

  @override
  String get attachmentPreview => 'File preview';

  @override
  String get attachmentPreviewHelp =>
      'This preview is scaled for display. Sharing or saving uses the unchanged original.';

  @override
  String get attachmentPreviewHelpShare =>
      'This preview is scaled for display. Sharing uses the unchanged original.';

  @override
  String get attachmentPreviewHelpSave =>
      'This preview is scaled for display. Saving uses the unchanged original.';

  @override
  String get attachmentPreviewHelpNone => 'This preview is scaled for display.';

  @override
  String get attachmentNoPreview => 'This file type has no preview.';

  @override
  String get attachmentNoPreviewShare =>
      'This file type has no preview. You can share the unchanged original.';

  @override
  String get attachmentNoPreviewSave =>
      'This file type has no preview. You can save the unchanged original.';

  @override
  String get attachmentNoPreviewShareSave =>
      'This file type has no preview. You can share or save the unchanged original.';

  @override
  String get attachmentPreviewFailure => 'Unable to show this preview. Retry.';

  @override
  String get attachmentPreviewFailureShare =>
      'Unable to show this preview. Retry. You can share the unchanged original.';

  @override
  String get attachmentPreviewFailureSave =>
      'Unable to show this preview. Retry. You can save the unchanged original.';

  @override
  String get attachmentPreviewFailureShareSave =>
      'Unable to show this preview. Retry. You can share or save the unchanged original.';

  @override
  String attachmentPage(int page, int total) {
    return 'Page $page of $total';
  }

  @override
  String get attachmentZoom => 'Zoom';

  @override
  String get attachmentReset => 'Reset';

  @override
  String get attachmentResume => 'Resume';

  @override
  String get attachmentJobs => 'Waiting imports';

  @override
  String attachmentTargetItem(String name) {
    return 'Item: $name';
  }

  @override
  String attachmentTargetDose(
    String name,
    String amount,
    String unit,
    String time,
  ) {
    return 'Dose: $name, $amount $unit at $time';
  }

  @override
  String attachmentFor(String person) {
    return 'Files for $person';
  }

  @override
  String attachmentViewFor(String name, String person) {
    return 'View $name for $person';
  }

  @override
  String attachmentImportAmount(int count) {
    return 'Imported: $count bytes.';
  }

  @override
  String get attachmentLocked => 'Unlock Vital to continue this file action.';

  @override
  String get attachmentJobUnavailable =>
      'This import no longer matches its original record. Cancel it and return to that record.';

  @override
  String get attachmentReopen => 'Open';

  @override
  String get attachmentClose => 'Close';

  @override
  String get attachmentBack => 'Back';

  @override
  String attachmentRecordRevision(int revision) {
    return 'Attached to revision $revision.';
  }

  @override
  String get attachmentRenamed => 'File name saved.';

  @override
  String get attachmentRemoved =>
      'File removed from this record. Open uses retain their copy until released.';

  @override
  String get attachmentSaveHeading => 'Save file';

  @override
  String attachmentSaveFor(String name, String person) {
    return 'Save a copy of $name for $person to the location you choose. That copy is outside Vital’s protected storage.';
  }

  @override
  String get historyTimeline => 'Timeline';

  @override
  String get historyCalendar => 'Calendar';

  @override
  String get historyFilters => 'Filters';

  @override
  String get filterType => 'Type';

  @override
  String get filterEvent => 'Event';

  @override
  String get filterStatus => 'Status';

  @override
  String get filterDates => 'Dates';

  @override
  String get statusAll => 'All';

  @override
  String get statusRecorded => 'Recorded';

  @override
  String get statusSkipped => 'Skipped';

  @override
  String get statusVoided => 'Voided';

  @override
  String get historyNoEntries => 'No entries';

  @override
  String get historyNoEntriesBody =>
      'No recorded or skipped entries match this view. Clear a filter or choose another date.';

  @override
  String get historyNewEntries =>
      'History changed. Refresh to show the latest entries.';

  @override
  String get historyRefreshed =>
      'History refreshed. Your filters are retained.';

  @override
  String historyMoved(String date) {
    return 'This entry moved to $date.';
  }

  @override
  String get refresh => 'Refresh';

  @override
  String get dates => 'Dates';

  @override
  String get timeFormat => 'Time format';

  @override
  String get timeSystem => 'System';

  @override
  String get time12 => '12-hour';

  @override
  String get time24 => '24-hour';

  @override
  String get timeFormatHelp =>
      'Choose how times appear. Recorded times and amounts stay unchanged. Time entry uses 24-hour HH:MM.';

  @override
  String get displaySaveFailure =>
      'Unable to save the time format. Choose it again to retry.';

  @override
  String shownInZone(String zone) {
    return 'Shown in $zone';
  }

  @override
  String plannedInZone(String zone) {
    return 'Planned in $zone';
  }

  @override
  String get dateOnly => 'Date only';

  @override
  String get timeNeedsReview => 'Time needs review';

  @override
  String get historyRangeTooBroad => 'Too many filters';

  @override
  String get historyRangeTooBroadBody =>
      'Choose fewer types or events to load this view.';

  @override
  String get historyLoadFailed => 'Unable to load history. Try again.';

  @override
  String get historyMatched => 'Matches filters';

  @override
  String get historyGroupContext =>
      'Full group shown. Matching sources are marked.';

  @override
  String get historyRecorded => 'Recorded use';

  @override
  String get historySkippedHelp =>
      'This is a skipped planned occurrence. It is not recorded use.';

  @override
  String historyPlannedAmount(String amount, String unit) {
    return 'Planned: $amount $unit';
  }

  @override
  String historyPlanCaptured(String name) {
    return 'Saved plan: $name';
  }

  @override
  String historyPlannedDate(String date) {
    return 'Planned date: $date';
  }

  @override
  String get historySkipAudit => 'Action history';

  @override
  String historyActionRevision(int revision, String kind, String date) {
    return 'Action revision $revision. $kind. $date.';
  }

  @override
  String historyExactInstant(String instant) {
    return 'Exact instant: $instant';
  }

  @override
  String get historyCalendarHelp =>
      'Choose a day to view its entries. Scroll across the calendar when needed.';

  @override
  String get historyMarkerLegend => '● Recorded. − Skipped. × Voided.';

  @override
  String historyDaySummary(String date, int recorded, int skipped, int voided) {
    return '$date. $recorded recorded, $skipped skipped, $voided voided.';
  }

  @override
  String historyDayCounts(int recorded, int skipped, int voided) {
    return 'Recorded: $recorded. Skipped: $skipped. Voided: $voided.';
  }

  @override
  String get previousMonth => 'Previous month';

  @override
  String get nextMonth => 'Next month';

  @override
  String get historyMonthLoading => 'Loading day counts…';

  @override
  String get historyWindow =>
      'Showing an older window. Refresh to return to the latest entries.';

  @override
  String get historyDateHelp =>
      'Use YYYY-MM-DD. The end date is included in the shown zone.';

  @override
  String get historyFrom => 'From';

  @override
  String get historyThrough => 'Through';

  @override
  String get historyDateError =>
      'Enter valid dates with the end on or after the start.';

  @override
  String get historyUnknownType => 'Unknown type';

  @override
  String get historyNoOptions => 'No matching choices. Try another search.';

  @override
  String historyFilterLimit(int count) {
    return 'Choose at most $count entries.';
  }

  @override
  String get historyScopeFixed =>
      'Your filters stay selected when you open a record.';

  @override
  String get historyPlanUnknown =>
      'No saved plan context. No missed use is inferred.';

  @override
  String get historyInspection => 'Source';

  @override
  String get historyUnknownSource =>
      'This source is no longer available. Return to history and refresh.';

  @override
  String get historyAuditEmpty => 'No earlier actions are available.';

  @override
  String historyShowing(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count entries',
      one: '1 entry',
    );
    return 'Showing $_temp0.';
  }

  @override
  String get historyNoCapturedPlan => 'No plan captured';

  @override
  String get historyNoCapturedPlanBody =>
      'There are no captured planned actions in this view. This does not show missed use.';

  @override
  String get chartsTitle => 'Charts';

  @override
  String get chartSeries => 'Series';

  @override
  String get chartRange => 'Range';

  @override
  String get chartBuckets => 'Buckets';

  @override
  String get chartDay => 'Day';

  @override
  String get chartWeek => 'Week';

  @override
  String get chartMonth => 'Month';

  @override
  String get chartTable => 'Table';

  @override
  String get chartPlot => 'Chart';

  @override
  String get chartTotal => 'Total';

  @override
  String get chartKnownTotal => 'Known total';

  @override
  String get chartIncomplete => 'Some ingredient amounts are unknown.';

  @override
  String get chartEmpty => 'No recorded use in this range.';

  @override
  String get chartLoading => 'Loading chart…';

  @override
  String get chartLoadFailed => 'Unable to load the chart. Try again.';

  @override
  String get chartInvalidZone =>
      'The display time zone is unavailable. Reset to show UTC.';

  @override
  String get chartTooLarge => 'Choose a shorter range to show every record.';

  @override
  String get chartGap => 'No recorded use';

  @override
  String get chartAnnotations => 'Context';

  @override
  String chartAnnotationOverflow(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count more context entries. Choose a shorter range.',
      one: '1 more context entry. Choose a shorter range.',
    );
    return '$_temp0';
  }

  @override
  String get chartInspect => 'View';

  @override
  String get chartZoomIn => 'Narrow';

  @override
  String get chartZoomOut => 'Widen';

  @override
  String get chartPrevious => 'Earlier';

  @override
  String get chartNext => 'Later';

  @override
  String get chartFrom => 'From';

  @override
  String get chartBefore => 'Before';

  @override
  String get chartApply => 'Apply';

  @override
  String get chartChoosePerson => 'Choose a person';

  @override
  String get chartChooseSeries => 'Choose a series';

  @override
  String get chartExact => 'Exact amount';

  @override
  String chartDoseCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count recorded doses',
      one: '1 recorded dose',
    );
    return '$_temp0';
  }

  @override
  String chartIngredientCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ingredient amounts',
      one: '1 ingredient amount',
    );
    return '$_temp0';
  }

  @override
  String get chartCombinedCountHelp =>
      'A combined record can contain several amounts.';

  @override
  String get chartVoidedSourcesHelp =>
      'Voided records are shown here but do not count towards totals.';

  @override
  String get chartNoRecordedSources => 'No recorded sources in this range.';

  @override
  String get chartNoVoidedSources => 'No voided sources in this range.';

  @override
  String get chartEventStart => 'Event start';

  @override
  String get chartEventEnd => 'Event end';

  @override
  String get chartPlanChanged => 'Plan changed';

  @override
  String get chartPauseStart => 'Pause start';

  @override
  String get chartPauseEnd => 'Pause end';

  @override
  String get chartPhaseStart => 'Phase start';

  @override
  String get chartPhaseEnd => 'Phase end';

  @override
  String get chartPlanEnd => 'Plan end';

  @override
  String get apply => 'Apply';

  @override
  String get choose => 'Choose';

  @override
  String get clear => 'Clear';

  @override
  String get reset => 'Reset';

  @override
  String get search => 'Search';

  @override
  String get undone => 'Undone';

  @override
  String cycleElapsed(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days days elapsed',
      one: '1 day elapsed',
      zero: '0 days elapsed',
    );
    return '$_temp0';
  }

  @override
  String cycleRemaining(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days days remaining',
      one: '1 day remaining',
      zero: '0 days remaining',
    );
    return '$_temp0';
  }

  @override
  String cycleStartsIn(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: 'Starts in $days days',
      one: 'Starts in 1 day',
      zero: 'Starts today',
    );
    return '$_temp0';
  }

  @override
  String get todayDue => 'Due';

  @override
  String get todayUpcoming => 'Upcoming';

  @override
  String get historyYesterday => 'Yesterday';

  @override
  String historyDaysAgo(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days days ago',
      one: '1 day ago',
    );
    return '$_temp0';
  }

  @override
  String historyRelativeExact(String relative, String exact) {
    return '$relative. $exact';
  }

  @override
  String historyDateZone(String date, String zone) {
    return '$date. $zone. Date only.';
  }

  @override
  String get historyDoseNoPlanBody =>
      'This dose has no captured plan. This does not show missed use.';

  @override
  String historySelectedTypes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count types selected',
      one: '1 type selected',
    );
    return '$_temp0';
  }

  @override
  String historySelectedEvents(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count events selected',
      one: '1 event selected',
    );
    return '$_temp0';
  }

  @override
  String historyDateFilter(String from, String through) {
    return '$from to $through';
  }

  @override
  String get historyAnyDate => 'Any date';

  @override
  String chartAmount(String amount, String unit) {
    return '$amount $unit';
  }

  @override
  String chartSeriesLabel(String name, String unit) {
    return '$name · $unit';
  }

  @override
  String chartCanvasSummary(String name, String unit) {
    return '$name, recorded amounts in $unit. Use the table to inspect exact values and sources.';
  }

  @override
  String chartDateRange(String start, String end) {
    return '$start to $end';
  }

  @override
  String get chartUnknown => 'Unknown';

  @override
  String get chartContextUnavailable =>
      'Some context could not be loaded. Choose a shorter range.';

  @override
  String get chartRangeInvalid =>
      'Choose valid dates with the end after the start.';

  @override
  String get chartSources => 'Sources';

  @override
  String chartViewBucketSources(
    String series,
    String unit,
    String period,
    String zone,
  ) {
    return 'View sources for $series in $unit for $period. $zone.';
  }

  @override
  String chartViewRangeSources(String series, String unit, String range) {
    return 'View sources for $series in $unit: $range.';
  }

  @override
  String get historyCapturedPlan => 'Plan captured';

  @override
  String get chartPlotUnavailable =>
      'Use the table to inspect this range of quantities.';

  @override
  String get working => 'Working…';

  @override
  String chartRangeSummary(String start, String end) {
    return '$start to before $end';
  }

  @override
  String get supportingTitle => 'Supporting';

  @override
  String get supportingPanels => 'Panels';

  @override
  String get supportingObservations => 'Observations';

  @override
  String get supportingPanel => 'Lab panel';

  @override
  String get supportingObservation => 'Observation';

  @override
  String get supportingAdd => 'Add';

  @override
  String get supportingManual =>
      'Enter values manually. Save before attaching source files.';

  @override
  String get supportingEmpty =>
      'No supporting records in this view. Add a panel or observation, or change the filters.';

  @override
  String get supportingTitleLabel => 'Title';

  @override
  String get supportingCollection => 'Collection date';

  @override
  String get supportingMeasured => 'Measured date';

  @override
  String get supportingReport => 'Report date';

  @override
  String get supportingEntry => 'Entry date';

  @override
  String get supportingUnknown => 'Unknown';

  @override
  String get supportingDay => 'Date';

  @override
  String get supportingExact => 'Exact';

  @override
  String get supportingPartial => 'Partial';

  @override
  String get supportingDateText => 'Source date';

  @override
  String get supportingDateHint =>
      'Use YYYY-MM-DD for a date. For an exact time, include its UTC offset and source time zone. Keep incomplete dates as written.';

  @override
  String get supportingZone => 'Source time zone';

  @override
  String get supportingPrecision => 'Date precision';

  @override
  String get supportingResults => 'Results';

  @override
  String get supportingMarker => 'Marker name';

  @override
  String get supportingOriginalMarker => 'Original marker';

  @override
  String get supportingValue => 'Original value';

  @override
  String get supportingNumeric => 'Numeric';

  @override
  String get supportingQualitative => 'Text';

  @override
  String get supportingMissing => 'Missing';

  @override
  String get supportingQualifier => 'Qualifier';

  @override
  String get supportingUnit => 'Original unit';

  @override
  String get supportingRange => 'Source range';

  @override
  String get supportingFlag => 'Source flag';

  @override
  String get supportingProvenance => 'Source details';

  @override
  String get supportingLab => 'Laboratory';

  @override
  String get supportingLabIdentity => 'Laboratory identity';

  @override
  String get supportingMethod => 'Method';

  @override
  String get supportingMethodIdentity => 'Method identity';

  @override
  String get supportingSpecimen => 'Specimen';

  @override
  String get supportingSpecimenIdentity => 'Specimen identity';

  @override
  String get supportingSourceText => 'Source text';

  @override
  String get supportingRecordedBy => 'Recorded by';

  @override
  String get supportingNotes => 'Notes';

  @override
  String get supportingNewMetric => 'New marker';

  @override
  String get supportingChooseMetric =>
      'Reuse a saved marker to continue its trend. Similar names are kept separate.';

  @override
  String get supportingMetrics => 'Markers';

  @override
  String get supportingInvalid =>
      'Check the title, dates and each result. Numeric values can include a sign or scientific notation. Exact times need an offset and time zone.';

  @override
  String get supportingNoResults => 'No results recorded.';

  @override
  String get supportingUnknownDate => 'Date unknown';

  @override
  String get supportingDateBasis => 'Date basis';

  @override
  String get supportingFrom => 'From date';

  @override
  String get supportingBefore => 'Before date';

  @override
  String get supportingIncludeUnknown => 'Include unknown dates';

  @override
  String get supportingFilters => 'Filters';

  @override
  String get supportingTrends => 'Trends';

  @override
  String get supportingTable => 'Table';

  @override
  String get supportingGroupUncertain =>
      'Source details are incomplete. These results are shown separately.';

  @override
  String get supportingTrendScope =>
      'Results are grouped by marker, original unit, laboratory, method and specimen. The table shows exact source values first. Points are separate. No totals or clinical interpretation are calculated.';

  @override
  String get supportingNoTrend =>
      'No numeric results for this marker and date range. Use the table to inspect every result.';

  @override
  String get supportingNoMatches =>
      'No results for this marker in the selected dates.';

  @override
  String get supportingTooMany =>
      'This view is too large. Narrow the date range and retry.';

  @override
  String get supportingUnavailable =>
      'This supporting record is unavailable for this person.';

  @override
  String get supportingVoided => 'Voided';

  @override
  String get supportingVoid => 'Void';

  @override
  String get supportingRestore => 'Restore';

  @override
  String get supportingVoidBody =>
      'Void this record? Its original values and revisions will remain available.';

  @override
  String get supportingRestoreBody =>
      'Restore this record to the current supporting list?';

  @override
  String get supportingRevisions => 'Revisions';

  @override
  String get supportingSource => 'Source';

  @override
  String get supportingContext => 'Linked context';

  @override
  String get supportingContextHint =>
      'Linked items and cycles provide context. They do not establish a cause.';

  @override
  String get supportingRangeHint =>
      'Copied source text only. A source flag or range is not advice.';

  @override
  String get supportingRemove => 'Remove';

  @override
  String get supportingPrevious => 'Previous';

  @override
  String get supportingNext => 'Next';

  @override
  String get supportingApply => 'Apply';

  @override
  String get supportingRetry => 'Retry';

  @override
  String get supportingExpand => 'Expand';

  @override
  String get supportingCollapse => 'Collapse';

  @override
  String supportingResultPosition(int current, int count) {
    return 'Result $current of $count';
  }

  @override
  String supportingRevisionLabel(int revision) {
    return 'Revision $revision';
  }

  @override
  String supportingTarget(String title) {
    return 'Supporting record: $title';
  }

  @override
  String supportingDateLabel(String label, String value) {
    return '$label: $value';
  }

  @override
  String supportingGroupLabel(String marker, String unit) {
    return '$marker · $unit';
  }

  @override
  String supportingPlotLabel(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count exact numeric results. Use the table to inspect every result.',
      one: '1 exact numeric result. Use the table to inspect every result.',
    );
    return '$_temp0';
  }

  @override
  String get supportingLocked => 'Unlock Vital to view supporting records.';

  @override
  String get supportingLoadFailure =>
      'Unable to load supporting records. Retry this view.';

  @override
  String supportingDateWindow(String start, String end) {
    return 'Dates from $start, before $end.';
  }

  @override
  String supportingPlotBounds(String minimum, String maximum) {
    return 'Displayed values range from $minimum to $maximum.';
  }

  @override
  String supportingPlotDates(String start, String end) {
    return 'Displayed source dates: $start to $end.';
  }

  @override
  String supportingSourceVersion(String version, String id) {
    return 'Source version $version: $id';
  }

  @override
  String get supportingOffsetFallback =>
      'This date uses UTC because its display time zone is unavailable. The saved source date is retained.';

  @override
  String get supportingIncludeVoided => 'Include voided';

  @override
  String get supportingIncludeVoidedHint =>
      'Show voided records alongside current records.';

  @override
  String get supportingCollectionChoice => 'Collection';

  @override
  String get supportingReportChoice => 'Report';

  @override
  String get supportingEntryChoice => 'Entry';

  @override
  String get supportingAddPanel => 'Add blood test';

  @override
  String get supportingEditPanel => 'Edit blood test';

  @override
  String get supportingAddObservation => 'Add observation';

  @override
  String get supportingEditObservation => 'Edit observation';

  @override
  String get supportingObservationManual =>
      'Add a value, text or note. Save before attaching source files.';

  @override
  String get supportingComponent => 'Component';

  @override
  String get supportingSearchMarkers => 'Search markers';

  @override
  String get supportingNoValues => 'No values entered.';

  @override
  String get supportingValueHint =>
      'Type <, ≤, > or ≥ before the value when the source uses a limit.';

  @override
  String get supportingIdentifiers => 'Identifiers';

  @override
  String get supportingResultMissing => 'No result supplied.';

  @override
  String get supportingUnitMissing => 'Unit not supplied.';

  @override
  String get supportingRangeMissing => 'Range not supplied.';

  @override
  String supportingSavedSource(String source) {
    return 'Saved source: $source.';
  }

  @override
  String supportingDisplayZone(String zone) {
    return 'Display zone: $zone.';
  }

  @override
  String supportingResultSemantics(
    String marker,
    String value,
    String unit,
    String range,
  ) {
    return '$marker. Original value: $value. Unit: $unit. Source range: $range.';
  }

  @override
  String supportingMarkerDisclosure(int position) {
    return 'Choose marker for result $position.';
  }

  @override
  String get supportingOpen => 'Open';

  @override
  String get supportingSourceUnavailable =>
      'This saved source is no longer available. The record keeps its saved source details.';

  @override
  String get supportingSourceChanged =>
      'This saved source changed after it was saved. Its exact original is not available.';

  @override
  String get supportingSourceTextOnly =>
      'This source is saved as text only. No file is attached.';

  @override
  String supportingSourceViewing(int version) {
    return 'Saved source version $version.';
  }

  @override
  String supportingSavedSourceReference(int version) {
    return 'Saved source, version $version';
  }

  @override
  String get supportingSourceReferences => 'Saved sources';

  @override
  String supportingOpenSourceVersion(int version) {
    return 'Open saved source version $version.';
  }

  @override
  String get supportingUndatedResults => 'Undated results';

  @override
  String get supportingUndatedHelp =>
      'Results without a full date are kept here. They are not placed on the trend.';

  @override
  String get supportingUndatedGroup => 'Undated group';

  @override
  String supportingGroupSummary(
    String marker,
    String unit,
    String laboratory,
    String method,
    String specimen,
  ) {
    return '$marker. Unit: $unit. Laboratory: $laboratory. Method: $method. Specimen: $specimen.';
  }

  @override
  String supportingGroupObservation(String marker, String unit) {
    return '$marker. Unit: $unit. Observation.';
  }

  @override
  String get supportingGroupObservationSeparate =>
      'Observed components are kept separate. No trend line joins them.';

  @override
  String supportingGroupNumber(int current, int count) {
    return 'Group $current of $count.';
  }

  @override
  String supportingGroupShort(int number) {
    return 'Group $number';
  }

  @override
  String get supportingSelectedGroup => 'Selected group';

  @override
  String get supportingGroups => 'Groups';

  @override
  String get supportingTableOrder =>
      'Oldest results first for the chosen date basis.';

  @override
  String supportingOpenRecord(String title) {
    return 'Open $title.';
  }

  @override
  String get supportingRecordsHeading => 'Supporting records';

  @override
  String get supportingFilterInvalid =>
      'Enter valid dates. The end date must be after the start.';

  @override
  String get supportingIncludeUnknownHint =>
      'Show records without a full date separately.';

  @override
  String get supportingAllDates => 'All dates';

  @override
  String get supportingValues => 'Values';

  @override
  String get supportingDateHelp => 'Enter the date as written on the source.';

  @override
  String get supportingExactDateHelp =>
      'Include the source time and offset, for example 2026-10-19T09:30+01:00.';

  @override
  String get supportingZoneHelp =>
      'The source time zone, when the report names one.';

  @override
  String get attachmentSupportingHelp =>
      'A source file does not confirm a recorded result. Keep the original report with its saved values.';

  @override
  String get attachmentSupportingVoided =>
      'This supporting record is voided. Its saved files stay available to view, but new files cannot be added.';

  @override
  String get supportingVoidPending => 'Void pending';

  @override
  String get supportingRestorePending => 'Restore pending';

  @override
  String get supportingVoidPendingBody =>
      'Your request is saved on this device. Resume to check and finish it, or discard it.';

  @override
  String get supportingVoidNotSaved =>
      'Request not saved. Nothing changed. Try again.';

  @override
  String get supportingVoidChanged =>
      'Record changed. Review the latest revision, then discard the saved request.';

  @override
  String get supportingVoidUncertain =>
      'The outcome is not confirmed. Your request is saved. Resume to check it.';

  @override
  String get supportingVoidArchived =>
      'This adult is archived. Discard the saved request or restore the adult first.';

  @override
  String get supportingVoidMissing =>
      'This record is unavailable. Discard the saved request.';

  @override
  String get supportingVoidSaved => 'Record voided.';

  @override
  String get supportingRestoreSaved => 'Record restored.';

  @override
  String get supportingVoidDiscarded => 'Request discarded.';

  @override
  String get exportTitle => 'Export';

  @override
  String get exportSelectionHelp =>
      'Choose a date range and the content to include. The preview is the exact file you can save.';

  @override
  String get exportPerson => 'Adult';

  @override
  String exportArchivedLabel(String name) {
    return '$name (archived)';
  }

  @override
  String get exportRange => 'Dates';

  @override
  String get exportFrom => 'From';

  @override
  String get exportBefore => 'Before';

  @override
  String exportRangeHelp(String zone) {
    return 'Dates use $zone. From is included. Before is not.';
  }

  @override
  String get exportContent => 'Content';

  @override
  String get exportDoses => 'Doses';

  @override
  String get exportDosesHelp =>
      'Recorded doses with every saved correction and the units used at entry.';

  @override
  String get exportSupporting => 'Supporting';

  @override
  String get exportSupportingHelp =>
      'Observations and lab panels recorded in the selected dates.';

  @override
  String get exportPrivateHelp =>
      'Your records are included. Notes stay private unless you include them.';

  @override
  String get exportPrivacy => 'Privacy';

  @override
  String get exportNotes => 'Notes';

  @override
  String get exportNotesHelp =>
      'Include supporting notes in the file. Source files are never included.';

  @override
  String exportSinglePerson(String name) {
    return 'Selected: $name';
  }

  @override
  String get exportFormat => 'Format';

  @override
  String get exportFormatJson => 'JSON';

  @override
  String get exportFormatCsv => 'CSV';

  @override
  String get exportFormatHelp =>
      'JSON keeps the full structure and meanings. CSV is a flat table for spreadsheets.';

  @override
  String get exportPreview => 'Preview';

  @override
  String get exportPreparing => 'Preparing';

  @override
  String get exportPreparingHelp =>
      'Building one file from the selected records. Cancel leaves nothing saved.';

  @override
  String get exportSaving => 'Saving the reviewed file.';

  @override
  String get exportCancel => 'Cancel';

  @override
  String get exportReview => 'Review';

  @override
  String exportDateRange(String from, String before) {
    return 'From $from up to, but not including, $before.';
  }

  @override
  String exportZoneLabel(String zone) {
    return 'Time zone: $zone';
  }

  @override
  String exportContentLabel(String content) {
    return 'Content: $content';
  }

  @override
  String get exportNotesIncluded => 'Supporting notes included.';

  @override
  String get exportNotesExcluded => 'Supporting notes excluded.';

  @override
  String exportDoseCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count dose records',
      one: '1 dose record',
      zero: 'No dose records',
    );
    return '$_temp0';
  }

  @override
  String exportRevisionCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count saved dose revisions',
      one: '1 saved dose revision',
      zero: 'No dose revisions',
    );
    return '$_temp0';
  }

  @override
  String exportSupportingCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count supporting records',
      one: '1 supporting record',
      zero: 'No supporting records',
    );
    return '$_temp0';
  }

  @override
  String exportSupportingResultCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count supporting results',
      one: '1 supporting result',
      zero: 'No supporting results',
    );
    return '$_temp0';
  }

  @override
  String exportUndatedExcluded(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count supporting records have unknown or partial collection dates and are left out of this file.',
      one: '1 supporting record has an unknown or partial collection date and is left out of this file.',
    );
    return '$_temp0';
  }

  @override
  String get exportUndatedUncounted =>
      'Supporting records with unknown or partial collection dates were not all counted and are left out of this file.';

  @override
  String exportByteCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count bytes',
      one: '1 byte',
    );
    return '$_temp0';
  }

  @override
  String exportFileName(String name) {
    return 'File: $name';
  }

  @override
  String get exportChecksumLabel => 'SHA-256';

  @override
  String get exportExactArtifact =>
      'This preview is the start of the exact file Save delivers.';

  @override
  String get exportSave => 'Save';

  @override
  String get exportChange => 'Change';

  @override
  String get exportSaved => 'Saved.';

  @override
  String get exportShared => 'Shared.';

  @override
  String get exportUnavailable =>
      'Saving is not available on this device. Preview only.';

  @override
  String get exportLocked => 'Unlock the app to export records.';

  @override
  String get exportZone =>
      'The display time zone is unavailable. Check the device time zone, then try again.';

  @override
  String get exportCancelled => 'Export cancelled. Nothing was saved.';

  @override
  String get exportTooLarge =>
      'This selection is too large. Choose a shorter date range or less content.';

  @override
  String get exportChooseContent => 'Choose at least one content type.';

  @override
  String get exportInvalidRange =>
      'Enter valid dates. Before must be later than From.';

  @override
  String get exportFailed =>
      'Unable to prepare the export. Nothing was saved. Try again.';

  @override
  String get exportHandoffCancelled =>
      'Save cancelled. The preview is unchanged.';

  @override
  String get exportSaveFailed =>
      'Unable to save. The preview is unchanged. Try again.';

  @override
  String get supportingDetails => 'Details';

  @override
  String get supportingAttach => 'Attach';

  @override
  String get supportingAttached => 'Attached';

  @override
  String get supportingSourceFiles => 'Saved files';

  @override
  String get supportingSourceFilesHelp =>
      'Choose a file for this adult. The saved file version stays linked if the file changes later.';

  @override
  String get supportingNoSourceFiles => 'No saved files for this adult.';

  @override
  String get supportingGroupUndated =>
      'Some results in this group have no full date. They are listed separately and do not connect the line.';

  @override
  String get supportingGroupNoResults =>
      'This group has no results in the selected dates. Choose another group or change the dates.';

  @override
  String get supportingConflict =>
      'This supporting record changed. Open Supporting records and review the latest revision before editing.';

  @override
  String get supportingDraftUnavailable =>
      'This entry is no longer available. Open Supporting records to review saved records.';

  @override
  String get supportingDraftSaved =>
      'This supporting record was already saved. Open it to review the latest revision.';

  @override
  String get supportingDraftFailure =>
      'Your latest changes were not kept on this device. Stay here and try again.';

  @override
  String get supportingSaveFailure =>
      'The supporting record could not be saved. Retry with the same details.';

  @override
  String get supportingNoValuesObservation =>
      'No values entered. Add a value, or add a note in Details.';

  @override
  String supportingAttachSource(String name) {
    return 'Attach $name.';
  }

  @override
  String supportingRemoveSource(String name) {
    return 'Remove saved source $name.';
  }

  @override
  String get supportingObservationRequired =>
      'Add a value or a note before saving this observation.';

  @override
  String get screenLabsHeading => 'Biomarkers & Labs';

  @override
  String get screenLabsSubtitle =>
      'Review saved lab panels and observations in their original units.';

  @override
  String get screenLabsAllRecords => 'All';

  @override
  String get screenLabsLatestEyebrow => 'Latest results';

  @override
  String screenLabsLatestCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count markers',
      one: '1 marker',
    );
    return '$_temp0';
  }

  @override
  String screenLabsLatestWindow(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count most recent dated records',
      one: 'most recent dated record',
    );
    return 'From the $_temp0, newest first.';
  }

  @override
  String get screenLabsLatestExcluded =>
      'Records without a complete date, and voided records, are not included.';

  @override
  String get screenLabsLatestOlder => 'Older dated records are not included.';

  @override
  String screenLabsLatestMarkerLimit(int count) {
    return 'Only the $count most recently measured markers are shown.';
  }

  @override
  String screenLabsLatestSemantics(
    String marker,
    String value,
    String unit,
    String range,
    String date,
    String record,
    String laboratory,
    String flag,
  ) {
    return '$marker. Value: $value $unit. Source range: $range. $date. From $record. Laboratory: $laboratory. Source flag: $flag.';
  }

  @override
  String get screenLabsNoLatestTitle => 'No dated results';

  @override
  String get screenLabsNoLatestBody =>
      'Add a panel with a collection date to see a latest value.';

  @override
  String screenLabsPreviousValue(String value) {
    return 'Previous value: $value';
  }

  @override
  String screenLabsChange(String value) {
    return 'Change: $value';
  }

  @override
  String screenLabsFromRecord(String record) {
    return 'From $record.';
  }

  @override
  String screenLabsLinked(String name) {
    return 'Linked: $name';
  }

  @override
  String get screenLabsRecordsEyebrow => 'Recent records';

  @override
  String get screenLabsNewestFirst => 'Newest first';

  @override
  String screenLabsRecordsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count records on this page',
      one: '1 record on this page',
      zero: 'No records on this page',
    );
    return '$_temp0';
  }

  @override
  String screenLabsResultsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count results',
      one: '1 result',
      zero: 'No results',
    );
    return '$_temp0';
  }

  @override
  String get screenLabsSourceFile => 'Source file saved';

  @override
  String get screenLabsNoMatchTitle => 'No records in this view';

  @override
  String get screenLabsNoMatchBody => 'Change the filters or add a record.';

  @override
  String get screenLabsEmptyTitle => 'No lab records';

  @override
  String get screenLabsEmptyBody =>
      'Add a panel to keep results and their source dates.';

  @override
  String get screenLabsPrivacyTitle => 'Stored on this device';

  @override
  String get screenLabsPrivacyBody =>
      'Lab records are stored on this device. Vital does not upload them.';

  @override
  String get screenLabsBasisReport => 'By report date';

  @override
  String get screenLabsBasisEntry => 'By entry date';

  @override
  String screenLabsRangeFrom(String date) {
    return 'From $date';
  }

  @override
  String screenLabsRangeBefore(String date) {
    return 'Before $date';
  }

  @override
  String get screenLabsUnknownExcluded => 'Unknown dates excluded';

  @override
  String get screenLabsVoidedIncluded => 'Voided included';

  @override
  String get screenLabsLess => 'Less';

  @override
  String get reminderLimits => 'Limits';

  @override
  String get reminderLimitsBody =>
      'Android may delay or drop alerts after a force stop, battery limit or long gap. Reopen Vital to prepare more.';

  @override
  String get settings => 'Settings';

  @override
  String get settingsBody => 'Appearance, privacy, records and help.';

  @override
  String get settingsDisplayUnsaved =>
      'Some display changes were not saved. Try again in Appearance.';

  @override
  String get settingsPeopleBody => 'Add or edit adults.';

  @override
  String get settingsPrivacyBody => 'Archive, delete or review copies.';

  @override
  String get display => 'Display';

  @override
  String get settingsAppearanceBody => 'Theme, motion, app lock and time.';

  @override
  String get alerts => 'Alerts';

  @override
  String get settingsRemindersBody => 'Notification settings and checks.';

  @override
  String get data => 'Data';

  @override
  String get reports => 'Reports';

  @override
  String get settingsReportsBody => 'Review your substance reports.';

  @override
  String get exports => 'Exports';

  @override
  String get settingsExportsBody => 'Save your records as structured data.';

  @override
  String get backup => 'Backup';

  @override
  String get settingsBackupBody => 'Create a protected full copy.';

  @override
  String get restore => 'Restore';

  @override
  String get settingsRestoreBody => 'Replace this installation from a backup.';

  @override
  String get support => 'Support';

  @override
  String get diagnostics => 'Diagnostics';

  @override
  String get settingsDiagnosticsBody => 'Recent local error codes.';

  @override
  String get help => 'Help';

  @override
  String get settingsHelpBody => 'Recovery, privacy and sources.';

  @override
  String get licences => 'Licences';

  @override
  String get settingsLicencesBody => 'Bundled open-source notices.';

  @override
  String get privacy => 'Privacy';

  @override
  String get privacyBody =>
      'Records stay on this device. They leave only when you export or back up.';

  @override
  String get privacyOperator =>
      'Anyone who can unlock Vital on this device can see your records.';

  @override
  String get privacyArchiveHelp =>
      'Archive keeps history and stops reminders. Delete removes only that person’s records, files and drafts. Me stays available.';

  @override
  String get copies => 'Copies';

  @override
  String get privacyCopies =>
      'Copies you saved or shared are outside Vital’s control. Restoring an old backup can bring back records you deleted here.';

  @override
  String get archivedPeople => 'Archived people';

  @override
  String get privacyArchivedHelp =>
      'History is kept. Reminders stay stopped until you set them again.';

  @override
  String get privacyNoneArchived => 'No archived people.';

  @override
  String get privacyMeOwner => 'Your profile stays available after deletion.';

  @override
  String get privacyOtherOwner => 'Records for this adult.';

  @override
  String get deleteMeBody =>
      'Delete all your saved records, files and drafts? This cannot be undone. Saved or shared copies outside Vital remain.';

  @override
  String privacyArchived(String person) {
    return '$person archived. History is kept and reminders are stopped.';
  }

  @override
  String privacyArchiveSemantic(String person) {
    return 'Archive $person';
  }

  @override
  String privacyReactivateSemantic(String person) {
    return 'Reactivate $person';
  }

  @override
  String privacyDeleteSemantic(String person) {
    return 'Delete $person';
  }

  @override
  String privacyDeleteRecordsSemantic(String person) {
    return 'Delete records for $person';
  }

  @override
  String privacyReactivated(String person) {
    return '$person reactivated. Reminders stay stopped until you set them again.';
  }

  @override
  String get privacyMeDeleted =>
      'Records deleted. Your profile is still available.';

  @override
  String privacyDeleted(String person) {
    return '$person deleted.';
  }

  @override
  String get privacyNotSaved =>
      'Could not confirm the change. Review your records before trying again.';

  @override
  String get diagnosticsBody =>
      'Diagnostics stay on this device. They contain error codes and the platform only.';

  @override
  String get diagnosticsNoSend =>
      'Nothing is sent automatically. This build has no diagnostic uploader.';

  @override
  String get diagnosticsEmpty => 'No recent issues.';

  @override
  String get diagnosticsCleared => 'Diagnostics cleared.';

  @override
  String get diagnosticsClearFailure => 'Not cleared. Try again.';

  @override
  String get diagnosticDataLoad => 'Data load failed';

  @override
  String get diagnosticLicenceNotice => 'Licence notice failed';

  @override
  String get diagnosticProfileArchive => 'Archive failed';

  @override
  String get diagnosticProfileDelete => 'Delete failed';

  @override
  String get helpBody =>
      'Recovery, privacy and source information for this device.';

  @override
  String get recovery => 'Recovery';

  @override
  String get recoveryOpen =>
      'If Vital cannot open your records, it never starts an empty replacement. Unlock your device and retry.';

  @override
  String get recoveryKeyring =>
      'On Linux, unlock the login keyring so Vital can reach its key.';

  @override
  String get recoveryLock =>
      'If app lock fails, records stay hidden. Retry after your device unlocks.';

  @override
  String get privacyLocal =>
      'Vital has no accounts, ads or analytics. Your records stay here unless you save or share a copy.';

  @override
  String get privacyNotifications =>
      'Reminders use a generic message without names or amounts.';

  @override
  String get privacySwitcher =>
      'Recent-app previews are hidden while app lock is on.';

  @override
  String get privacyShared => 'Copies you share are outside Vital’s control.';

  @override
  String get sources => 'Sources';

  @override
  String get sourcesNone =>
      'No catalogue is installed. Custom items are still available.';

  @override
  String get sourcesUnavailable => 'Catalogue source details are unavailable.';

  @override
  String get about => 'About';

  @override
  String get aboutBody => 'Vital keeps your substance records on this device.';

  @override
  String get aboutLimit =>
      'This is a personal record, not a clinical record or an emergency monitor.';

  @override
  String get appLicence => 'Vital licence';

  @override
  String get appLicenceBody => 'MIT licence text.';

  @override
  String get packageNotices => 'Package notices';

  @override
  String get licencesBody =>
      'Vital is open source under the MIT licence. Adopted package notices are bundled with the app.';

  @override
  String get licence => 'Licence';

  @override
  String get licenceDetailBody => 'Bundled licence text.';

  @override
  String get licencesUnavailable =>
      'Licence notices are unavailable in this build.';

  @override
  String get reportsTitle => 'Reports';

  @override
  String get reportScopeHelp =>
      'Choose exact dates and whether to include private context.';

  @override
  String get reportPerson => 'Person';

  @override
  String get reportFrom => 'From';

  @override
  String get reportThrough => 'Through';

  @override
  String get reportDateHelp => 'Use YYYY-MM-DD.';

  @override
  String get reportThroughHelp => 'The end date is included.';

  @override
  String get reportNameHelp => 'Optional. Shown on the first page.';

  @override
  String get reportContent => 'Content';

  @override
  String get reportContentHelp =>
      'All items are included unless you choose specific items.';

  @override
  String get reportAllItems => 'All items';

  @override
  String get reportNoItems => 'No recorded items in this period.';

  @override
  String get reportContext => 'Supporting records';

  @override
  String get reportContextHelp =>
      'Include supporting records from the selected period.';

  @override
  String get reportNotes => 'Private notes';

  @override
  String get reportNotesHelp =>
      'Include saved notes for selected supporting records.';

  @override
  String get reportSources => 'Source files';

  @override
  String get reportSourcesHelp =>
      'List attached source file names. File contents stay separate.';

  @override
  String get reportReview => 'Review';

  @override
  String reportPersonValue(String name) {
    return 'Person: $name';
  }

  @override
  String reportPeriodValue(String from, String to, String zone) {
    return 'Period: $from to $to. Times shown in $zone.';
  }

  @override
  String reportItemCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count selected items',
      one: '1 selected item',
    );
    return '$_temp0';
  }

  @override
  String reportTemplateValue(String id, String version) {
    return 'Template $id version $version';
  }

  @override
  String get reportCapturing => 'Reading records';

  @override
  String get reportRendering => 'Building report';

  @override
  String get reportPreview => 'Preview';

  @override
  String get reportCancelled => 'Report cancelled. Your choices are unchanged.';

  @override
  String get reportFailure => 'Report not created. Try again.';

  @override
  String get reportSourceLimit =>
      'Too many doses for one summary. Narrow the dates or items, then try again.';

  @override
  String get reportAttachmentLimit =>
      'Too many source files for one summary. Choose fewer items, then try again.';

  @override
  String get reportPersonMissing =>
      'Your profile is unavailable. Reopen Vital and try again.';

  @override
  String get reportPersonArchived =>
      'Your profile is unavailable. Reopen Vital and try again.';

  @override
  String get reportZoneUnavailable =>
      'The time zone is unavailable. Choose the device time zone, then try again.';

  @override
  String get reportLocked => 'Vital is locked. Unlock it, then try again.';

  @override
  String get reportGenerated => 'Report ready.';

  @override
  String get reportPreviewTitle => 'Report preview';

  @override
  String get reportUnavailable =>
      'No report is ready. Return to Reports and preview one.';

  @override
  String get reportPreviewMode => 'Preview';

  @override
  String get reportText => 'Text';

  @override
  String reportArtifactValue(int pages, int kilobytes) {
    String _temp0 = intl.Intl.pluralLogic(
      pages,
      locale: localeName,
      other: '$pages pages',
      one: '1 page',
    );
    return '$_temp0 · $kilobytes KB';
  }

  @override
  String get reportHandoffUnavailable =>
      'Save and share are unavailable in this build. The preview is complete.';

  @override
  String get reportSaveUnavailable => 'Save is unavailable in this build.';

  @override
  String get reportShareUnavailable => 'Share is unavailable in this build.';

  @override
  String get reportHandoffComplete => 'Report saved to the chosen location.';

  @override
  String get reportHandoffCancelled => 'Handoff cancelled.';

  @override
  String get reportHandoffFailed => 'Handoff failed. Try again.';

  @override
  String reportArtifactIdentity(String id, String hash) {
    return 'Report $id · Fingerprint $hash';
  }

  @override
  String get reportArtifactLimits =>
      'The PDF is not tagged. Use Text for the accessible structured version. Recipients\' copies are outside this app\'s control.';

  @override
  String get share => 'Share';

  @override
  String get reportIdentity => 'Report name';

  @override
  String get reportSourceChanged =>
      'Records changed while the report was prepared. Try again.';

  @override
  String get reportPageLimit =>
      'This report is too large. Narrow the dates or items, then try again.';

  @override
  String get reportShareOffered =>
      'Report offered to the chosen app. Vital cannot confirm receipt.';

  @override
  String get reportSummaryTemplate => 'Substance summary';

  @override
  String get reportHistoryTemplate => 'Detailed history';

  @override
  String get reportEventTemplate => 'Event review';

  @override
  String get reportSkippedRows => 'Skipped entries';

  @override
  String get reportSkippedRowsHelp => 'Include entries marked as skipped.';

  @override
  String get reportUnrecordedRows => 'Unrecorded entries';

  @override
  String get reportUnrecordedRowsHelp =>
      'Include past planned entries with no recorded action. These do not prove a missed dose.';

  @override
  String get reportEventRequired => 'Choose an event to review.';

  @override
  String get reportEventMissing =>
      'This event is no longer available. Choose another event.';

  @override
  String get reportEventRange =>
      'Choose dates that cover the event’s recorded start and end.';

  @override
  String get reportEventRangeHelp =>
      'Choose one event and dates that cover its recorded start and end. Dates without a known boundary stay uncertain.';

  @override
  String reportEventSelected(String name) {
    return 'Event: $name';
  }

  @override
  String reportEventZoneValue(String zone) {
    return 'Event zone: $zone';
  }

  @override
  String reportEventRangeAction(String from, String through) {
    return 'The selected dates do not include this event. Apply $from to $through to cover its recorded start and end.';
  }

  @override
  String reportEventRangePartialAction(String from, String through) {
    return 'The selected dates do not include this event. Apply $from to $through to cover its recorded dates.';
  }

  @override
  String reportEventApplyRangeLabel(String from, String through) {
    return 'Apply report dates from $from to $through';
  }

  @override
  String get reportNoEvents => 'No events are available.';

  @override
  String get reportNameLimit => 'Use a report name of 120 characters or fewer.';

  @override
  String get backupCreateHeading => 'Create backup';

  @override
  String get backupAllAdults => 'All your records';

  @override
  String get backupIncludesFiles => 'Attached files included';

  @override
  String get backupPasswordLabel => 'Backup password';

  @override
  String get backupConfirmLabel => 'Confirm password';

  @override
  String get backupPasswordHelper => 'Use at least 12 characters.';

  @override
  String get backupPasswordLoss =>
      'You need this password to restore your records. It cannot be recovered.';

  @override
  String get backupPasswordNotStored => 'The password is not stored.';

  @override
  String get backupPreparing => 'Preparing records';

  @override
  String get backupEncrypting => 'Encrypting backup';

  @override
  String get backupChecking => 'Checking backup';

  @override
  String get backupReadyHeading => 'Backup ready';

  @override
  String backupContents(int people, int attachments) {
    String _temp0 = intl.Intl.pluralLogic(
      people,
      locale: localeName,
      other: '$people adults',
      one: '1 adult',
    );
    String _temp1 = intl.Intl.pluralLogic(
      attachments,
      locale: localeName,
      other: '$attachments files',
      one: '1 file',
    );
    return 'Includes $_temp0 and $_temp1.';
  }

  @override
  String backupSize(String size) {
    return 'Size $size.';
  }

  @override
  String backupCreated(String date) {
    return 'Created $date.';
  }

  @override
  String get backupKeepSafe =>
      'Keep the file and password safe. Restore needs both.';

  @override
  String get backupUnsavedWarning =>
      'Save before leaving. An unsaved backup is deleted at the next launch.';

  @override
  String get backupCannotSave => 'Cannot save';

  @override
  String get backupSavingUnavailable =>
      'Saving backup files is unavailable on this device.';

  @override
  String get backupSavedHeading => 'Backup saved';

  @override
  String backupSavedBody(String name) {
    return 'Saved as $name.';
  }

  @override
  String get backupDeleteHeading => 'Delete backup?';

  @override
  String get backupDeleteBody =>
      'The backup file will be deleted. Your records are not changed.';

  @override
  String get backupCancelled => 'Backup cancelled';

  @override
  String get backupCancelledBody => 'No backup was created.';

  @override
  String get backupFailedHeading => 'Backup failed';

  @override
  String get backupFailedBody => 'Your records were not changed. Try again.';

  @override
  String get backupNoSpaceHeading => 'Not enough space';

  @override
  String get backupNoSpaceBody =>
      'Free some space and try again. Your records were not changed.';

  @override
  String get backupWrongPassword => 'Password not accepted';

  @override
  String get backupWrongPasswordBody => 'Check the password and try again.';

  @override
  String get backupDamagedHeading => 'Backup damaged';

  @override
  String get backupDamagedBody => 'The file is damaged or not a Vital backup.';

  @override
  String get backupNewerHeading => 'Newer backup';

  @override
  String get backupNewerBody => 'This backup needs a newer version of Vital.';

  @override
  String get backupIncompleteHeading => 'Backup incomplete';

  @override
  String get backupIncompleteBody =>
      'The file did not match its records. Your records were not changed.';

  @override
  String get backupLocked => 'Unlock to create a backup.';

  @override
  String get backupLockedHeading => 'Unlock first';

  @override
  String get backupShortPassword => 'Use at least 12 characters.';

  @override
  String get backupPasswordMismatch => 'Passwords do not match.';

  @override
  String get backupPasswordLong => 'Use a shorter password.';

  @override
  String get backupBusyHeading => 'Backup busy';

  @override
  String get backupBusyBody =>
      'Finish the current backup before starting another.';

  @override
  String get backupUnavailableHeading => 'Backup unavailable';

  @override
  String get backupUnavailableBody =>
      'Open your records before creating a backup.';

  @override
  String get backupSaveFailedHeading => 'Not saved';

  @override
  String get backupSaveFailedBody =>
      'The backup file is still here. Try again.';

  @override
  String get done => 'Done';

  @override
  String get backupSaveLimit =>
      'This backup is larger than this device’s save limit. The staged backup is kept.';

  @override
  String get restoreTitle => 'Restore';

  @override
  String get restoreIntro =>
      'Use a Vital backup to replace every record on this device. You review the backup before anything changes.';

  @override
  String get restoreChoose => 'Choose';

  @override
  String get restoreArchiveLabel => 'Backup file';

  @override
  String get restoreArchiveNone => 'No backup chosen';

  @override
  String get restorePasswordLabel => 'Backup password';

  @override
  String get restorePasswordHelp =>
      'Enter the password used when this backup was created.';

  @override
  String get restoreCheck => 'Check';

  @override
  String get restoreChecking => 'Checking archive';

  @override
  String get restorePreviewTitle => 'Backup contents';

  @override
  String restoreCreated(String date) {
    return 'Created $date';
  }

  @override
  String get restorePeople => 'Profile';

  @override
  String restorePeopleCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count people',
      one: '1 person',
      zero: 'No people',
    );
    return '$_temp0';
  }

  @override
  String restorePeopleMore(int count) {
    return 'Showing the first $count people.';
  }

  @override
  String get restoreArchived => 'Archived';

  @override
  String get restoreCoverage => 'Record dates';

  @override
  String restoreCoverageRange(String from, String to) {
    return '$from to $to';
  }

  @override
  String get restoreCoverageEmpty => 'No dated records';

  @override
  String get restoreLocalDates => 'Dates use this device\'s time zone.';

  @override
  String restoreRecords(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count records',
      one: '1 record',
      zero: 'No records',
    );
    return '$_temp0';
  }

  @override
  String restoreSubstances(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count substances',
      one: '1 substance',
      zero: 'No substances',
    );
    return '$_temp0';
  }

  @override
  String restoreSupporting(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count supporting records',
      one: '1 supporting record',
      zero: 'No supporting records',
    );
    return '$_temp0';
  }

  @override
  String restoreAttachments(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count attachments',
      one: '1 attachment',
      zero: 'No attachments',
    );
    return '$_temp0';
  }

  @override
  String get restoreOlderWarning =>
      'This backup uses older app data. Vital will update it during restore.';

  @override
  String restoreMultipleWarning(int count) {
    return 'This backup contains $count people. Their records stay separate.';
  }

  @override
  String get restoreConsequence =>
      'Replacing removes your current records, drafts and reminder settings on this device. A rollback copy is kept until the restored records open.';

  @override
  String get restoreReplaceAll => 'Replace all records';

  @override
  String get restoreReplaceAllHelp =>
      'Current records will be replaced. Switch this on only after reviewing the backup contents.';

  @override
  String get restoreReplace => 'Replace';

  @override
  String get restoreCancel => 'Cancel';

  @override
  String get restorePreparing => 'Preparing records';

  @override
  String get restoreReplacing => 'Replacing records';

  @override
  String get restoreWorking => 'Keep Vital open while this finishes.';

  @override
  String get restoreCompleteTitle => 'Restore complete';

  @override
  String restoreCompleteBody(String name) {
    return 'This device now uses the records from $name.';
  }

  @override
  String get restoreCompleteCleared =>
      'Old drafts and reminder actions were cleared.';

  @override
  String get restoreCompleteReminder =>
      'Reminders will be rebuilt when you continue.';

  @override
  String get restoreReminderWarning =>
      'Records were restored. Reminder schedules could not be cleared. Check reminder settings after reopening Vital.';

  @override
  String get restoreDone => 'Done';

  @override
  String get restoreFailedTitle => 'Restore failed';

  @override
  String get restoreRetry => 'Retry';

  @override
  String get restoreUnavailable => 'Restore unavailable';

  @override
  String get restoreUnavailableBody =>
      'Restore needs the protected record store. Open Vital again and retry.';

  @override
  String get restoreLocked => 'Unlock Vital to restore records.';

  @override
  String get restoreWrongPassword =>
      'That password does not open this backup. Check the password and try again.';

  @override
  String get restoreCorrupt =>
      'This backup cannot be opened safely. Current records were kept. Choose another backup.';

  @override
  String get restoreUnsupportedVersion =>
      'This backup was made by a newer version of Vital. Update Vital before restoring it.';

  @override
  String get restoreTooLarge =>
      'This backup is too large to restore on this device.';

  @override
  String get restoreChooseArchive => 'Choose a backup first.';

  @override
  String get restorePasswordRequired => 'Enter the backup password.';

  @override
  String get restorePasswordLong => 'That password is too long.';

  @override
  String get restoreConfirmationRequired =>
      'Switch on Replace all records before replacing.';

  @override
  String get restoreRecoveryRequired =>
      'Vital could not finish the last restore safely. Reopen Vital before trying again.';

  @override
  String get restoreStorage =>
      'There is not enough protected storage to replace these records. Free some space and try again.';

  @override
  String get restoreArchiveChanged =>
      'The backup changed while it was being read. Choose it again.';

  @override
  String get restoreFailedBody =>
      'Nothing was replaced. Check the backup and try again.';

  @override
  String get restoreCancelled =>
      'Restore cancelled. Current records were not changed.';

  @override
  String get restoreBusy => 'Restore is already running.';

  @override
  String get restoreRecoveryCompleted =>
      'Restore complete. Vital is using the restored records.';

  @override
  String get restoreRecoveryRolledBack =>
      'Vital recovered the previous records after an interrupted restore.';

  @override
  String get restoreRecoveryCleaned =>
      'An interrupted restore was cleared. Your existing records are still in use.';

  @override
  String get profile => 'Profile';

  @override
  String get settingsProfileBody => 'Your name and report details.';

  @override
  String get singleUserRequired =>
      'This older dataset contains other people. Open it with the previous version of Vital. Your records have not been deleted.';

  @override
  String get restoreSingleUserRequired =>
      'This backup contains other people. Choose a backup containing only your records.';

  @override
  String get designSubstancesSearchLabel => 'Search';

  @override
  String get designSubstancesSearchHint => 'Name of a substance';

  @override
  String get designSubstancesAllFilter => 'All';

  @override
  String designSubstancesItemCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items',
      one: '1 item',
    );
    return '$_temp0';
  }

  @override
  String get designSubstancesClear => 'Clear';

  @override
  String get designSubstancesNoMatchesTitle => 'No matches';

  @override
  String get designSubstancesNoMatchesBody =>
      'Try another name or clear the filter.';

  @override
  String designSubstancesOpenItem(String name) {
    return 'Open $name';
  }

  @override
  String get designSubstancesUnavailable =>
      'The substance list is unavailable right now.';

  @override
  String get designComponentsUnknown => 'Unknown';

  @override
  String get designSubstancesSchedulesHeading => 'Schedules';

  @override
  String get designSubstancesNoSchedule => 'No schedule recorded.';

  @override
  String get designSubstancesNoStock => 'No stock recorded.';

  @override
  String get designSubstancesNotStarted => 'Not started.';

  @override
  String get designSubstancesEnded => 'This schedule has ended.';

  @override
  String designSubstancesScheduleCount(int count, String amount, String unit) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Planned $count times a day, $amount $unit each',
      one: 'Planned once a day, $amount $unit each',
    );
    return '$_temp0';
  }

  @override
  String designSubstancesScheduleSlots(String times) {
    return 'Planned times: $times';
  }

  @override
  String designSubstancesScheduleSlot(String time, String amount, String unit) {
    return '$time $amount $unit';
  }

  @override
  String designSubstancesScheduleWindows(String windows) {
    return 'Planned windows: $windows';
  }

  @override
  String designSubstancesScheduleWindow(
    String start,
    String end,
    String amount,
    String unit,
  ) {
    return '$start to $end: $amount $unit';
  }

  @override
  String designSubstancesMixedSchedule(
    String slots,
    int count,
    String amount,
    String unit,
  ) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count untimed slots',
      one: '1 untimed slot',
    );
    return '$slots, plus $_temp0 ($amount $unit each)';
  }

  @override
  String designSubstancesIntervalSchedule(
    String hours,
    String amount,
    String unit,
  ) {
    return 'Every $hours h, $amount $unit each';
  }

  @override
  String designSubstancesCalendarWeekdays(String days) {
    return 'Days of week: $days';
  }

  @override
  String designSubstancesCalendarDays(int interval, String date) {
    String _temp0 = intl.Intl.pluralLogic(
      interval,
      locale: localeName,
      other: '$interval days',
      one: '1 day',
    );
    return 'Every $_temp0 from $date';
  }

  @override
  String designSubstancesCalendarWeeks(int interval, String date) {
    String _temp0 = intl.Intl.pluralLogic(
      interval,
      locale: localeName,
      other: '$interval weeks',
      one: '1 week',
    );
    return 'Every $_temp0 from $date';
  }

  @override
  String designSubstancesCalendarMonths(
    int interval,
    String selector,
    String date,
  ) {
    String _temp0 = intl.Intl.pluralLogic(
      interval,
      locale: localeName,
      other: '$interval months',
      one: '1 month',
    );
    return 'Every $_temp0 $selector from $date';
  }

  @override
  String designSubstancesMonthDay(int day) {
    return 'on day $day';
  }

  @override
  String get designSubstancesMonthWeekday => 'on a selected weekday';

  @override
  String designSubstancesPlanBounds(String start, String end) {
    return '$start to $end';
  }

  @override
  String designSubstancesPlanStart(String start) {
    return 'From $start';
  }

  @override
  String designSubstancesZone(String zone) {
    return 'Time zone: $zone';
  }

  @override
  String designSubstancesNextDose(
    String amount,
    String unit,
    String time,
    String zone,
  ) {
    return 'Next planned dose: $amount $unit at $time ($zone)';
  }

  @override
  String designSubstancesNextUntimed(
    String amount,
    String unit,
    String date,
    String zone,
  ) {
    return 'Next planned dose: $amount $unit on $date, untimed ($zone)';
  }

  @override
  String designSubstancesReviewClock(String date, String time, String zone) {
    return 'Clock review: $date $time ($zone)';
  }

  @override
  String designSubstancesContainerEntry(String label, String balance) {
    return '$label · $balance';
  }

  @override
  String get designSubstancesDeficit => 'Deficit';

  @override
  String designSubstancesMoreStock(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count more containers.',
      one: '1 more container.',
    );
    return '$_temp0';
  }

  @override
  String designSubstancesMoreSlots(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count more slots.',
      one: '1 more slot.',
    );
    return '$_temp0';
  }

  @override
  String get designSubstancesSummaryUnavailable =>
      'The substance summary could not be loaded.';

  @override
  String get designOverviewContext => 'Context';

  @override
  String get designOverviewNoPlan => 'No plan yet';

  @override
  String get designOverviewNoPlanHelp =>
      'Add a schedule to see planned doses. Recording stays available without one.';

  @override
  String get designOverviewPlansBound =>
      'This summary shows the first plans. Open Schedule to review the rest.';

  @override
  String get designOverviewNextMissing =>
      'This plan is not in the bounded next-dose summary. Open Schedule to review it.';

  @override
  String designOverviewStart(String date) {
    return 'Starts $date';
  }

  @override
  String designOverviewWeekdays(String weekdays) {
    return 'On $weekdays';
  }

  @override
  String designOverviewEveryDays(int count) {
    return 'Every $count days';
  }

  @override
  String designOverviewEveryWeeks(int count) {
    return 'Every $count weeks';
  }

  @override
  String designOverviewEveryMonths(int count) {
    return 'Every $count months';
  }

  @override
  String get designOverviewStockEmpty => 'No stock recorded';

  @override
  String get designOverviewStockHelp =>
      'Stock is optional. Add a container to track the remaining amount.';

  @override
  String get designOverviewHistoryHint =>
      'Older records stay in the full history.';

  @override
  String designOverviewStockReview(String name) {
    return 'Review the stock for $name';
  }

  @override
  String designOverviewHistoryReview(String name) {
    return 'Review the full history for $name';
  }

  @override
  String get designOverviewEventsHint =>
      'This summary shows the first events. Open Events to review them all.';

  @override
  String get designTodayHeading => 'Daily schedule';

  @override
  String designTodayRemaining(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count remaining',
      one: '1 remaining',
    );
    return '$_temp0';
  }

  @override
  String designTodayRecorded(int taken, int planned, int skipped) {
    return '$taken of $planned doses recorded, $skipped skipped.';
  }

  @override
  String get designTodayNothingPlanned => 'No doses are planned today.';

  @override
  String get designTodayNext => 'Next dose';

  @override
  String designTodayNextInMinutes(int minutes) {
    String _temp0 = intl.Intl.pluralLogic(
      minutes,
      locale: localeName,
      other: 'Next dose in $minutes minutes.',
      one: 'Next dose in 1 minute.',
    );
    return '$_temp0';
  }

  @override
  String get designTodayNextDue => 'Next dose is due now.';

  @override
  String get designTodayNextUntimed => 'The next dose has no expected time.';

  @override
  String designTodayRecordedSoFar(int taken, int skipped) {
    String _temp0 = intl.Intl.pluralLogic(
      taken,
      locale: localeName,
      other: '$taken doses recorded',
      one: '1 dose recorded',
    );
    String _temp1 = intl.Intl.pluralLogic(
      skipped,
      locale: localeName,
      other: '$skipped skipped',
      one: '1 skipped',
    );
    return '$_temp0, $_temp1 so far.';
  }

  @override
  String designTodayUtcDate(String date) {
    return '$date (UTC)';
  }

  @override
  String get designTodayProgressLabel => 'Recorded doses';

  @override
  String designTodayRecordedCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count recorded',
      one: '1 recorded',
    );
    return '$_temp0';
  }

  @override
  String designTodayPlannedTotal(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count doses',
      one: '1 dose',
    );
    return 'of $_temp0';
  }

  @override
  String designTodaySkippedCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count skipped',
      one: '1 skipped',
    );
    return '$_temp0';
  }

  @override
  String get designTodayActionsIncomplete =>
      'Some dose actions are still loading. Counts may change.';

  @override
  String designTodayNextPlanNamed(
    String name,
    String amount,
    String unit,
    String when,
  ) {
    return 'Next planned dose: $name, $amount $unit, $when.';
  }

  @override
  String designTodayNextPlanUnnamed(String amount, String unit, String when) {
    return 'Next planned dose: $amount $unit, $when.';
  }

  @override
  String get designTodayUnderMinute => 'Next dose in under a minute.';

  @override
  String get stitchPlaceholderBody => 'This feature is not available yet.';

  @override
  String get stitchDailyProgress => 'Daily progress';

  @override
  String get stitchPartial => 'Partial';

  @override
  String get stitchWeek => 'Weekly overview';

  @override
  String get stitchNextDose => 'Next dose';

  @override
  String get stitchNoNext => 'No upcoming dose';

  @override
  String get stitchNextHelp =>
      'Add a substance and schedule to see your next dose here.';

  @override
  String get stitchConfigure => 'Configure';

  @override
  String get stitchSequence => 'Today’s sequence';

  @override
  String get stitchScheduleManage => 'Manage';

  @override
  String get stitchBloodPressure => 'Blood pressure';

  @override
  String get stitchRefillBuffer => 'Refill buffer';

  @override
  String get stitchForecastPending => 'Forecast not available yet';

  @override
  String get stitchStored => 'Encrypted on device';

  @override
  String get stitchLocalBody =>
      'Your records stay on this device unless you export or share them.';

  @override
  String get stitchPaused => 'Paused';

  @override
  String get stitchPreview => 'Design preview';

  @override
  String get stitchFilter => 'Filters';

  @override
  String get stitchUntimed => 'Anytime';

  @override
  String get stitchPrn => 'As needed';

  @override
  String get stitchSearch => 'Search by name…';

  @override
  String stitchSubstanceCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count substances',
      one: '1 substance',
    );
    return '$_temp0';
  }

  @override
  String stitchGroupCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count planned',
      one: '1 planned',
    );
    return '$_temp0';
  }

  @override
  String stitchAmountForm(String amount, String unit, String form) {
    return '$amount $unit · $form';
  }

  @override
  String stitchDailyAt(String time) {
    return 'Daily at $time';
  }

  @override
  String stitchFilterCount(String name, int count) {
    return '$name ($count)';
  }

  @override
  String stitchStockRemaining(String amount, String unit) {
    return '$amount $unit remaining';
  }

  @override
  String stitchNextAt(String time) {
    return 'Next: $time';
  }

  @override
  String get stitchObservation => 'Observation';

  @override
  String get stitchSnoozeUnavailable =>
      'Snooze is available when reminders are enabled for this schedule.';

  @override
  String get screenCreateDrafting => 'Drafting';

  @override
  String get screenCreateClassification => 'Classification';

  @override
  String get screenCreateIdentity => 'Identity';

  @override
  String get screenCreateFormHelp => 'Tap a common form or enter your own.';

  @override
  String get screenCreateFormCapsule => 'Capsule';

  @override
  String get screenCreateFormSoftgel => 'Softgel';

  @override
  String get screenCreateFormPowder => 'Powder';

  @override
  String get screenCreateStrengthLater =>
      'Strength belongs to a stock container. Add it from the substance overview after you save.';

  @override
  String get screenCreateScheduleLater =>
      'Frequency and dose times are added from the substance overview after you save.';

  @override
  String get screenCreateStockLater =>
      'Opening quantity, low-stock threshold and strength are added from the substance overview after you save.';

  @override
  String get screenCreateNotes => 'Notes';

  @override
  String get screenCreateNotesUnavailable =>
      'Substance notes are not available in this version.';

  @override
  String get screenCreateAfterSave => 'After save';

  @override
  String get screenCreateUnavailable => 'Unavailable';

  @override
  String get screenScheduleSubtitle =>
      'Set the days, times and amounts for this plan. Preview before saving.';

  @override
  String get screenScheduleNew => 'New plan';

  @override
  String get screenScheduleRecurrence => 'Recurrence';

  @override
  String get screenScheduleDates => 'Plan dates';

  @override
  String get screenScheduleDoseWindows => 'Dose windows';

  @override
  String get screenScheduleChosenTimes => 'Chosen times';

  @override
  String screenScheduleSlotCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count times',
      one: '1 time',
    );
    return '$_temp0';
  }

  @override
  String screenScheduleWindowCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count windows',
      one: '1 window',
    );
    return '$_temp0';
  }

  @override
  String get screenScheduleTolerancePreview =>
      'Timing tolerance is not available yet. This plan saves only the chosen time.';

  @override
  String get screenScheduleRequirements => 'Requirements';

  @override
  String get screenScheduleRequirementsBody =>
      'Food and timing requirements are not available yet. Nothing from this preview is saved.';

  @override
  String get screenScheduleSaveFirst =>
      'Save this plan before using pause or reminders.';

  @override
  String get screenScheduleAlerts => 'Reminders';

  @override
  String get screenScheduleAlertsMeta => 'Device support applies.';

  @override
  String get screenScheduleRemindersAfterSave =>
      'Save this plan to set reminders. Alerts also depend on device support.';

  @override
  String get screenScheduleFollowUp => 'Follow-up';

  @override
  String get screenScheduleFollowUpBody =>
      'Follow-up alerts are not available yet.';

  @override
  String get screenSchedulePreviewHelp =>
      'Preview checks the next planned doses before saving.';

  @override
  String get screenSchedulePreviewResult => 'Planned doses';

  @override
  String get screenRecordEditTime => 'Edit';

  @override
  String screenRecordUnitValue(String unit) {
    return 'Unit $unit';
  }

  @override
  String screenRecordTypeForm(String type, String form) {
    return '$type · $form';
  }

  @override
  String screenRecordTimestamp(String date, String time) {
    return '$date at $time';
  }

  @override
  String get screenRecordTimeUnset => 'Time not set';

  @override
  String get screenRecordQuantity => 'Quantity';

  @override
  String get screenRecordWhen => 'When';

  @override
  String get screenRecordContext => 'Context & conditions';

  @override
  String get screenRecordContextHelp =>
      'Food, water and symptom tags are not saved yet.';

  @override
  String get screenRecordVitals => 'Vitals & observations';

  @override
  String get screenRecordVitalsHelp =>
      'Vitals and notes are not attached to this dose yet.';

  @override
  String get screenRecordObservations => 'Observations';

  @override
  String get screenRecordPreview => 'Preview';

  @override
  String screenRecordStockDeducts(String deducted, String remaining) {
    return 'Deducts $deducted, leaving $remaining.';
  }

  @override
  String screenRecordStockUnknownDeduction(String deducted) {
    return 'Deducts $deducted. Remaining balance is unknown.';
  }

  @override
  String get screenRecordStockNotCalculated =>
      'The stock deduction cannot be calculated for these units.';

  @override
  String get screenRecordStockLimitPreview =>
      'The stock total is unavailable. Saving still records this dose.';

  @override
  String get screenRecordStockDeficitPreview =>
      'This leaves the balance below zero.';

  @override
  String screenRecordStockLow(String threshold) {
    return 'Low stock at or below $threshold.';
  }

  @override
  String get screenRecordSkipNote =>
      'Skip is available on Today for a scheduled dose.';

  @override
  String get screenStockActionNeeded => 'Action needed';

  @override
  String get screenStockAddAllHelp => 'Open a substance to add its container.';

  @override
  String get screenStockAddHeading => 'Add container';

  @override
  String get screenStockAddItemHelp =>
      'Add a physical container for this substance.';

  @override
  String get screenStockArchived =>
      'This profile is archived. Stock is read only.';

  @override
  String get screenStockContainers => 'Active containers';

  @override
  String get screenStockGaps =>
      'Pack scanning, batch lots, expiry, capacity and runout forecasts are not available yet.';

  @override
  String get screenStockLoadedOnly => 'Only the loaded page is shown.';

  @override
  String get screenStockMoreNotices => 'More containers need attention.';

  @override
  String get screenStockNoContainers => 'No containers';

  @override
  String get screenStockNoContainersHelp =>
      'Add a container when you need to track its supply.';

  @override
  String get screenStockNoticesAction => 'Notices';

  @override
  String get screenStockStocked => 'No notice';

  @override
  String get screenStockUnavailable => 'Unavailable';

  @override
  String get screenStockUnknown => 'Unknown';

  @override
  String get screenHistorySubtitle =>
      'Recorded use and skipped plans kept on this device.';

  @override
  String get screenHistoryLastSevenDays => 'Last 7 days';

  @override
  String screenHistoryRecordedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count recorded',
      one: '1 recorded',
      zero: 'No recorded entries',
    );
    return '$_temp0';
  }

  @override
  String screenHistoryEntryCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count entries',
      one: '1 entry',
    );
    return '$_temp0';
  }

  @override
  String screenHistoryRecordedAt(String time) {
    return 'Recorded at $time';
  }

  @override
  String screenHistoryScheduledAt(String time) {
    return 'Scheduled $time';
  }

  @override
  String get screenHistoryReportsHelp =>
      'Build a report or open related records.';

  @override
  String get screenHistoryAudit => 'Audit';

  @override
  String get screenHistoryAuditPreview =>
      'Adherence and integrity measures are not available yet. Your records are unchanged.';

  @override
  String screenHistoryViewEntry(String name) {
    return 'View $name';
  }

  @override
  String screenHistoryDayUnavailable(String date, String state) {
    return '$date. $state';
  }

  @override
  String screenLabsOpenLinked(String name) {
    return 'Open linked record $name';
  }

  @override
  String get screenLabsLatestDateScope =>
      'Latest results use collection or measured dates across all dates. Date filters apply to the records below.';

  @override
  String get calendarFiltered => 'Filtered';

  @override
  String get calendarMonthlySummary => 'Monthly summary (PDF)';

  @override
  String calendarExportMonth(String month) {
    return 'Export $month summary';
  }

  @override
  String calendarRecordedDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count days recorded this month',
      one: '1 day recorded this month',
    );
    return '$_temp0';
  }

  @override
  String calendarEntryState(String status, String time) {
    return '$status · $time';
  }

  @override
  String get screenEventsDescription =>
      'Courses and cycles add context to your recorded use.';

  @override
  String get screenEventsActive => 'Active';

  @override
  String get screenEventsUpcoming => 'Upcoming';

  @override
  String get screenEventsAll => 'All';

  @override
  String screenEventsActiveCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count active',
      one: '1 active',
    );
    return '$_temp0';
  }

  @override
  String screenEventsUpcomingCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count upcoming',
      one: '1 upcoming',
    );
    return '$_temp0';
  }

  @override
  String screenEventsCompletedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count completed',
      one: '1 completed',
    );
    return '$_temp0';
  }

  @override
  String screenEventsShown(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count shown',
      one: '1 shown',
    );
    return '$_temp0';
  }

  @override
  String get screenEventsLoadedOnly => 'Filters only cover the events shown.';

  @override
  String get screenEventsNoMatches => 'No events match this filter.';

  @override
  String screenEventsRange(String start, String end) {
    return '$start to $end';
  }

  @override
  String screenEventsStarted(String date) {
    return 'Start: $date';
  }

  @override
  String screenEventsStarts(String date) {
    return 'Starts $date';
  }

  @override
  String get screenEventsNoDates => 'No dates recorded';

  @override
  String screenEventsDayOf(int day, int total) {
    return 'Day $day of $total';
  }

  @override
  String screenEventsPercentElapsed(int percent) {
    return '$percent% elapsed';
  }

  @override
  String get screenEventsHorizon => 'Date progress';

  @override
  String get screenEventsLinkedItems => 'Linked items';

  @override
  String get screenEventsPlannedItems => 'Planned items';

  @override
  String get screenEventsDatesReview => 'Dates need review';

  @override
  String get screenEventsReviewDue => 'End review due';

  @override
  String screenEventsMoreFor(String name) {
    return 'More actions for $name';
  }

  @override
  String screenEventsDetailsFor(String name) {
    return 'Details for $name';
  }

  @override
  String screenEventsEditFor(String name) {
    return 'Edit $name';
  }

  @override
  String screenEventsSelectFor(String name) {
    return 'Select $name for combined history';
  }

  @override
  String screenEventsSelectedFor(String name) {
    return 'Selected $name for combined history';
  }

  @override
  String screenEventsConfigureFor(String name) {
    return 'Configure $name';
  }

  @override
  String screenEventsReviewFor(String name) {
    return 'Review the end of $name';
  }

  @override
  String screenEventsRevisionsFor(String name) {
    return 'Revisions for $name';
  }

  @override
  String screenEventsNoteFor(String name) {
    return 'Add a note for $name';
  }

  @override
  String get screenEventsNote => 'Note';

  @override
  String get screenEventsNotes => 'Event notes';

  @override
  String get screenEventsNotesUnavailable =>
      'Saved event notes are not available in this version. Nothing is added.';

  @override
  String get screenEventsCompletedNote =>
      'Marked complete. Recorded history stays available.';

  @override
  String get screenEventsContext => 'Event context';

  @override
  String get screenEventsDates => 'Dates';

  @override
  String get screenEventsPlanned => 'Planned';

  @override
  String get screenEventsActual => 'Actual';

  @override
  String get screenEventsFilterLabel => 'Event status';

  @override
  String screenEventsEnds(String date) {
    return 'Ends $date';
  }

  @override
  String screenEventsReviewCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count need date review',
      one: '1 needs date review',
    );
    return '$_temp0';
  }

  @override
  String get screenEventsItemUnavailable => 'Substance unavailable';

  @override
  String get screenSettingsGroupAll => 'All';

  @override
  String get screenSettingsGroupGeneral => 'General';

  @override
  String get screenSettingsGeneralBody =>
      'Profile, appearance, reminders and help.';

  @override
  String get screenSettingsDataBody => 'Reports, exports, backups and restore.';

  @override
  String get screenSettingsVaultBadge => 'On this device';

  @override
  String get screenSettingsStorageTitle => 'Local storage';

  @override
  String get screenSettingsStorageBody =>
      'Database size and record totals are not available yet.';

  @override
  String get screenSettingsPreviewBadge => 'Preview';

  @override
  String get screenSettingsAutoBackup => 'Automatic backups';

  @override
  String get screenSettingsAutoBackupBody =>
      'Not available yet. Create a backup when you need one.';

  @override
  String get screenSettingsFhir => 'FHIR export';

  @override
  String get screenSettingsFhirBody =>
      'Not available yet. Use Exports for structured data.';

  @override
  String screenOverviewFormUnit(String form, String unit) {
    return '$form · $unit';
  }

  @override
  String get screenOverviewSectionOverview => 'Overview';

  @override
  String get screenOverviewPeriods => 'Periods';

  @override
  String get screenPanelPanelDetail => 'Panel detail';

  @override
  String get screenPanelObservationDetail => 'Observation detail';

  @override
  String screenPanelCollected(String date) {
    return 'Collected $date';
  }

  @override
  String get screenPanelRecorded => 'Recorded';

  @override
  String get screenPanelRevision => 'Revision';

  @override
  String get screenPanelSaved => 'Saved';

  @override
  String get screenPanelRevised => 'Revised';

  @override
  String screenPanelFilterAll(int count) {
    return 'All ($count)';
  }

  @override
  String screenPanelFilterRange(int count) {
    return 'With range ($count)';
  }

  @override
  String screenPanelFilterNoRange(int count) {
    return 'No range ($count)';
  }

  @override
  String get screenPanelNoFilteredResults => 'No results in this filter.';

  @override
  String get screenPanelSubstance => 'Substance';

  @override
  String get screenPanelEvent => 'Event';

  @override
  String get screenPanelLinkGone => 'Linked record unavailable';

  @override
  String get screenPanelFileChecksums => 'File checksums';

  @override
  String get screenPanelFileChecksumsHelp =>
      'Recorded when each file was saved. This does not verify the whole record.';

  @override
  String get screenPanelChecksumsUnavailable =>
      'Saved checksums could not be loaded. Retry.';

  @override
  String screenPanelFileLabel(String name) {
    return 'File: $name';
  }

  @override
  String get screenPanelChecksumLimit =>
      'Checksums use up to 25 saved files. Open Files to review all files.';

  @override
  String get screenPanelNoFiles =>
      'No saved files. Add a source file to record its checksum.';

  @override
  String get screenPanelCopy => 'Copy';

  @override
  String get screenPanelCopied => 'Copied';

  @override
  String get screenPanelChecksumCopied => 'Checksum copied.';

  @override
  String get screenPanelCopyFailed => 'Copy failed. Try again.';

  @override
  String screenPanelCopyChecksum(String name) {
    return 'Copy checksum for $name';
  }

  @override
  String get screenPanelFhirUnavailable =>
      'FHIR export is not available in this build. Use Export for the formats Vital supports.';

  @override
  String get screenPanelNoChecksums =>
      'The files shown have no recorded checksum. Open Files to review them.';

  @override
  String get featurePresetHeading => 'Saved amounts';

  @override
  String get featurePresetHelp =>
      'Choose a saved amount or enter your own. Schedule amounts come from the latest saved schedule.';

  @override
  String get featurePresetManageHelp =>
      'Enter an amount above, then Add to keep it for this substance. This does not record a dose.';

  @override
  String get featurePresetLoadFailed => 'Unable to load saved amounts. Retry.';

  @override
  String get featurePresetSaveFailed => 'Unable to save the change. Retry.';

  @override
  String get featurePresetPlanFailed =>
      'Unable to load schedule amounts. Retry.';

  @override
  String get featurePresetLimit =>
      'You can save up to 8 amounts. Remove one to add another.';

  @override
  String get featurePresetLess => 'Less';

  @override
  String featurePresetSelect(String amount, String unit) {
    return 'Choose $amount $unit';
  }

  @override
  String featurePresetRemove(String amount, String unit) {
    return 'Remove saved amount $amount $unit';
  }

  @override
  String featureWeekRange(String start, String end) {
    return '$start to $end';
  }

  @override
  String get featureWeekPrevious => 'Previous week';

  @override
  String get featureWeekNext => 'Next week';

  @override
  String get featureWeekSummary => 'Week summary';

  @override
  String get featureWeekSummaryHelp => 'Counts cover planned doses.';

  @override
  String get featureWeekPlanned => 'Planned';

  @override
  String get featureWeekRecorded => 'Recorded';

  @override
  String get featureWeekSkipped => 'Skipped';

  @override
  String get featureWeekIncomplete =>
      'Some days could not be calculated. This summary is incomplete.';

  @override
  String get featureWeekNoPlans => 'No doses are planned this week.';

  @override
  String get featureWeekViewing => 'Viewing';

  @override
  String get featureWeekViewingHelp =>
      'Taken, Skip and Snooze stay on today. Record uses the time you enter.';

  @override
  String get featureWeekDaySequence => 'Day sequence';

  @override
  String get featureWeekNothingPlanned => 'No doses are planned for this day.';

  @override
  String get featureWeekNoRecorded => 'No doses recorded on this day.';

  @override
  String get featureWeekQuickRecord => 'Quick record';

  @override
  String get featureWeekFavouritesHelp =>
      'Choose as-needed plans and their order.';

  @override
  String get featureWeekFavouritesEmptyHelp =>
      'With nothing chosen, every as-needed plan appears.';

  @override
  String featureWeekFavouritesStale(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count saved choices are no longer available.',
      one: '1 saved choice is no longer available.',
    );
    return '$_temp0';
  }

  @override
  String get featureWeekFavouritesStaleHelp => 'Saving removes them.';

  @override
  String get featureWeekFavouriteSaveFailure =>
      'Not saved. Your saved choices are unchanged.';

  @override
  String get featureWeekFavouriteLoadFailure =>
      'Saved choices could not be loaded.';

  @override
  String get featureWeekPlansLoadFailure => 'Plans could not be loaded.';

  @override
  String get featureWeekFavouriteListIncomplete =>
      'The plan list is incomplete. Reload before saving.';

  @override
  String featureWeekFavouriteUnavailable(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count saved choices are unavailable.',
      one: '1 saved choice is unavailable.',
    );
    return '$_temp0';
  }

  @override
  String get featureWeekMoveUp => 'Move up';

  @override
  String get featureWeekMoveDown => 'Move down';

  @override
  String featureWeekInclude(String name) {
    return 'Include $name';
  }

  @override
  String get featureWeekNoAsNeeded => 'No as-needed plans.';

  @override
  String get featureWeekUtc => 'Times shown in UTC.';

  @override
  String get featureStatusFiltersLabel => 'Plan status';

  @override
  String get featureStatusAll => 'All statuses';

  @override
  String get featureStatusActive => 'Active';

  @override
  String get featureStatusPaused => 'Paused';

  @override
  String get featureStatusAsNeeded => 'As needed';

  @override
  String get featureStatusUnscheduled => 'Unscheduled';

  @override
  String get featureStatusMixedHelp =>
      'An item with more than one plan can appear under each matching status. Future and ended plans count as unscheduled.';

  @override
  String featureStatusUnresolvedHelp(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count items are only in All because their plans could not be checked.',
      one: '1 item is only in All because its plan could not be checked.',
    );
    return '$_temp0';
  }
}
