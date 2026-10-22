import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[Locale('en')];

  /// Development-shell appearance choice or explanatory text. Keep UK English, complete meaning and brief wording; this preview has no saved records.
  ///
  /// In en, this message translates to:
  /// **'True Grit: Vital'**
  String get appTitle;

  /// Development-shell heading or navigation label. Keep UK English, complete meaning and brief wording; this preview has no saved records.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get today;

  /// Development-shell heading or navigation label. Keep UK English, complete meaning and brief wording; this preview has no saved records.
  ///
  /// In en, this message translates to:
  /// **'Substances'**
  String get substances;

  /// Primary destination for optional cycles and prescription courses.
  ///
  /// In en, this message translates to:
  /// **'Events'**
  String get events;

  /// Development-shell heading or navigation label. Keep UK English, complete meaning and brief wording; this preview has no saved records.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get history;

  /// Development-shell heading or navigation label. Keep UK English, complete meaning and brief wording; this preview has no saved records.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get appearance;

  /// Development-shell heading or navigation label. Keep UK English, complete meaning and brief wording; this preview has no saved records.
  ///
  /// In en, this message translates to:
  /// **'Development preview'**
  String get preview;

  /// Development-shell appearance choice or explanatory text. Keep UK English, complete meaning and brief wording; this preview has no saved records.
  ///
  /// In en, this message translates to:
  /// **'Recording and profiles are not available in this build.'**
  String get previewBody;

  /// Development-shell heading or navigation label. Keep UK English, complete meaning and brief wording; this preview has no saved records.
  ///
  /// In en, this message translates to:
  /// **'Your daily view'**
  String get todayEmpty;

  /// Development-shell appearance choice or explanatory text. Keep UK English, complete meaning and brief wording; this preview has no saved records.
  ///
  /// In en, this message translates to:
  /// **'Planned doses and recorded use will appear here.'**
  String get todayBody;

  /// Development-shell heading or navigation label. Keep UK English, complete meaning and brief wording; this preview has no saved records.
  ///
  /// In en, this message translates to:
  /// **'Your substances'**
  String get substancesEmpty;

  /// Development-shell appearance choice or explanatory text. Keep UK English, complete meaning and brief wording; this preview has no saved records.
  ///
  /// In en, this message translates to:
  /// **'Medicines, supplements and other substances will appear here.'**
  String get substancesBody;

  /// Development-shell heading or navigation label. Keep UK English, complete meaning and brief wording; this preview has no saved records.
  ///
  /// In en, this message translates to:
  /// **'Your events'**
  String get eventsEmpty;

  /// Vital recording flow. Keep full person, substance, amount, unit and saved-state meaning. Headings use 1–3 words; action buttons use one word.
  ///
  /// In en, this message translates to:
  /// **'Events are not available in this build. Actual use can be recorded in Substances.'**
  String get eventsBody;

  /// Development-shell heading or navigation label. Keep UK English, complete meaning and brief wording; this preview has no saved records.
  ///
  /// In en, this message translates to:
  /// **'Your history'**
  String get historyEmpty;

  /// Development-shell appearance choice or explanatory text. Keep UK English, complete meaning and brief wording; this preview has no saved records.
  ///
  /// In en, this message translates to:
  /// **'Recorded doses and corrections will appear here.'**
  String get historyBody;

  /// Vital recording flow. Keep full person, substance, amount, unit and saved-state meaning. Headings use 1–3 words; action buttons use one word.
  ///
  /// In en, this message translates to:
  /// **'Appearance choices are saved on this device.'**
  String get appearanceBody;

  /// Development-shell heading or navigation label. Keep UK English, complete meaning and brief wording; this preview has no saved records.
  ///
  /// In en, this message translates to:
  /// **'Colour mode'**
  String get colourMode;

  /// Development-shell appearance choice or explanatory text. Keep UK English, complete meaning and brief wording; this preview has no saved records.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get system;

  /// Development-shell appearance choice or explanatory text. Keep UK English, complete meaning and brief wording; this preview has no saved records.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get light;

  /// Development-shell appearance choice or explanatory text. Keep UK English, complete meaning and brief wording; this preview has no saved records.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get dark;

  /// Development-shell appearance choice or explanatory text. Keep UK English, complete meaning and brief wording; this preview has no saved records.
  ///
  /// In en, this message translates to:
  /// **'Opaque surfaces'**
  String get opaqueSurfaces;

  /// Development-shell appearance choice or explanatory text. Keep UK English, complete meaning and brief wording; this preview has no saved records.
  ///
  /// In en, this message translates to:
  /// **'Use solid backgrounds for decorative surfaces.'**
  String get opaqueHelper;

  /// Development-shell appearance choice or explanatory text. Keep UK English, complete meaning and brief wording; this preview has no saved records.
  ///
  /// In en, this message translates to:
  /// **'Reduce motion'**
  String get reduceMotion;

  /// Development-shell appearance choice or explanatory text. Keep UK English, complete meaning and brief wording; this preview has no saved records.
  ///
  /// In en, this message translates to:
  /// **'Limit optional movement. System settings also apply.'**
  String get motionHelper;

  /// Development-shell heading or navigation label. Keep UK English, complete meaning and brief wording; this preview has no saved records.
  ///
  /// In en, this message translates to:
  /// **'Surface sample'**
  String get surfaceSample;

  /// Development-shell appearance choice or explanatory text. Keep UK English, complete meaning and brief wording; this preview has no saved records.
  ///
  /// In en, this message translates to:
  /// **'Solid surfaces are active while glass is being checked on devices.'**
  String get opaqueActive;

  /// Development-shell appearance choice or explanatory text. Keep UK English, complete meaning and brief wording; this preview has no saved records.
  ///
  /// In en, this message translates to:
  /// **'Solid surfaces are active.'**
  String get opaqueChosen;

  /// Development-shell appearance choice or explanatory text. Keep UK English, complete meaning and brief wording; this preview has no saved records.
  ///
  /// In en, this message translates to:
  /// **'Glass is active on this sample surface.'**
  String get glassActive;

  /// Development-shell appearance choice or explanatory text. Keep UK English, complete meaning and brief wording; this preview has no saved records.
  ///
  /// In en, this message translates to:
  /// **'Reduced motion is active.'**
  String get motionReduced;

  /// Development-shell appearance choice or explanatory text. Keep UK English, complete meaning and brief wording; this preview has no saved records.
  ///
  /// In en, this message translates to:
  /// **'Standard motion is active.'**
  String get motionStandard;

  /// Development-shell appearance choice or explanatory text. Keep UK English, complete meaning and brief wording; this preview has no saved records.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get back;

  /// Development-shell heading or navigation label. Keep UK English, complete meaning and brief wording; this preview has no saved records.
  ///
  /// In en, this message translates to:
  /// **'Form icons'**
  String get formSamples;

  /// Development-shell appearance choice or explanatory text. Keep UK English, complete meaning and brief wording; this preview has no saved records.
  ///
  /// In en, this message translates to:
  /// **'Tablet'**
  String get tablet;

  /// Development-shell appearance choice or explanatory text. Keep UK English, complete meaning and brief wording; this preview has no saved records.
  ///
  /// In en, this message translates to:
  /// **'Injection'**
  String get injection;

  /// Development-shell appearance choice or explanatory text. Keep UK English, complete meaning and brief wording; this preview has no saved records.
  ///
  /// In en, this message translates to:
  /// **'Liquid'**
  String get liquid;

  /// Development-shell appearance choice or explanatory text. Keep UK English, complete meaning and brief wording; this preview has no saved records.
  ///
  /// In en, this message translates to:
  /// **'Icons describe forms, not substance types or dose advice.'**
  String get formHelper;

  /// Vital recording flow. Keep full person, substance, amount, unit and saved-state meaning. Headings use 1–3 words; action buttons use one word.
  ///
  /// In en, this message translates to:
  /// **'Appearance was not saved. Try the choice again.'**
  String get appearanceFailure;

  /// Vital recording flow. Keep full person, substance, amount, unit and saved-state meaning. Headings use 1–3 words; action buttons use one word.
  ///
  /// In en, this message translates to:
  /// **'Opening records…'**
  String get loadingRecords;

  /// Vital recording flow. Keep full person, substance, amount, unit and saved-state meaning. Headings use 1–3 words; action buttons use one word.
  ///
  /// In en, this message translates to:
  /// **'Records unavailable'**
  String get recoveryTitle;

  /// Vital recording flow. Keep full person, substance, amount, unit and saved-state meaning. Headings use 1–3 words; action buttons use one word.
  ///
  /// In en, this message translates to:
  /// **'Vital could not open the saved records. Retry without deleting the app or its data.'**
  String get recoveryBody;

  /// Vital recording flow. Keep full person, substance, amount, unit and saved-state meaning. Headings use 1–3 words; action buttons use one word.
  ///
  /// In en, this message translates to:
  /// **'Recording is available in the Android and Linux apps. This platform cannot open personal records.'**
  String get unsupportedBody;

  /// Vital recording flow. Keep full person, substance, amount, unit and saved-state meaning. Headings use 1–3 words; action buttons use one word.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// Vital recording flow. Keep full person, substance, amount, unit and saved-state meaning. Headings use 1–3 words; action buttons use one word.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get create;

  /// Vital recording flow. Keep full person, substance, amount, unit and saved-state meaning. Headings use 1–3 words; action buttons use one word.
  ///
  /// In en, this message translates to:
  /// **'Record'**
  String get record;

  /// Vital recording flow. Keep full person, substance, amount, unit and saved-state meaning. Headings use 1–3 words; action buttons use one word.
  ///
  /// In en, this message translates to:
  /// **'Correct'**
  String get correct;

  /// Vital recording flow. Keep full person, substance, amount, unit and saved-state meaning. Headings use 1–3 words; action buttons use one word.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get undo;

  /// Vital recording flow. Keep full person, substance, amount, unit and saved-state meaning. Headings use 1–3 words; action buttons use one word.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// Vital recording flow. Keep full person, substance, amount, unit and saved-state meaning. Headings use 1–3 words; action buttons use one word.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// Vital recording flow. Keep full person, substance, amount, unit and saved-state meaning. Headings use 1–3 words; action buttons use one word.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get discard;

  /// Vital recording flow. Keep full person, substance, amount, unit and saved-state meaning. Headings use 1–3 words; action buttons use one word.
  ///
  /// In en, this message translates to:
  /// **'Keep'**
  String get keep;

  /// Vital recording flow. Keep full person, substance, amount, unit and saved-state meaning. Headings use 1–3 words; action buttons use one word.
  ///
  /// In en, this message translates to:
  /// **'Me'**
  String get me;

  /// Vital recording flow. Keep full person, substance, amount, unit and saved-state meaning. Headings use 1–3 words; action buttons use one word.
  ///
  /// In en, this message translates to:
  /// **'New substance'**
  String get newSubstance;

  /// Vital recording flow. Keep full person, substance, amount, unit and saved-state meaning. Headings use 1–3 words; action buttons use one word.
  ///
  /// In en, this message translates to:
  /// **'Full name'**
  String get nameLabel;

  /// Vital recording flow. Keep full person, substance, amount, unit and saved-state meaning. Headings use 1–3 words; action buttons use one word.
  ///
  /// In en, this message translates to:
  /// **'Form'**
  String get formLabel;

  /// Vital recording flow. Keep full person, substance, amount, unit and saved-state meaning. Headings use 1–3 words; action buttons use one word.
  ///
  /// In en, this message translates to:
  /// **'Unit'**
  String get unitLabel;

  /// Vital recording flow. Keep full person, substance, amount, unit and saved-state meaning. Headings use 1–3 words; action buttons use one word.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get typeLabel;

  /// Vital recording flow. Keep full person, substance, amount, unit and saved-state meaning. Headings use 1–3 words; action buttons use one word.
  ///
  /// In en, this message translates to:
  /// **'Enter the full substance name.'**
  String get nameRequired;

  /// Vital recording flow. Keep full person, substance, amount, unit and saved-state meaning. Headings use 1–3 words; action buttons use one word.
  ///
  /// In en, this message translates to:
  /// **'Choose a unit and enter a form and type. Keep each field within 500 characters.'**
  String get detailsRequired;

  /// Vital recording flow. Keep full person, substance, amount, unit and saved-state meaning. Headings use 1–3 words; action buttons use one word.
  ///
  /// In en, this message translates to:
  /// **'Create a substance to record what you take.'**
  String get substancesReady;

  /// Vital recording flow. Keep full person, substance, amount, unit and saved-state meaning. Headings use 1–3 words; action buttons use one word.
  ///
  /// In en, this message translates to:
  /// **'Nothing recorded'**
  String get noRecords;

  /// Vital recording flow. Keep full person, substance, amount, unit and saved-state meaning. Headings use 1–3 words; action buttons use one word.
  ///
  /// In en, this message translates to:
  /// **'Actual use recorded today appears here. Earlier use stays in History.'**
  String get todayReady;

  /// Vital recording flow. Keep full person, substance, amount, unit and saved-state meaning. Headings use 1–3 words; action buttons use one word.
  ///
  /// In en, this message translates to:
  /// **'Record actual use to start your history.'**
  String get historyReady;

  /// Vital recording flow. Keep full person, substance, amount, unit and saved-state meaning. Headings use 1–3 words; action buttons use one word.
  ///
  /// In en, this message translates to:
  /// **'Record dose'**
  String get recordHeading;

  /// Vital recording flow. Keep full person, substance, amount, unit and saved-state meaning. Headings use 1–3 words; action buttons use one word.
  ///
  /// In en, this message translates to:
  /// **'Correct use'**
  String get correctHeading;

  /// Vital recording flow. Keep full person, substance, amount, unit and saved-state meaning. Headings use 1–3 words; action buttons use one word.
  ///
  /// In en, this message translates to:
  /// **'Amount'**
  String get amountLabel;

  /// Vital recording flow. Keep full person, substance, amount, unit and saved-state meaning. Headings use 1–3 words; action buttons use one word.
  ///
  /// In en, this message translates to:
  /// **'Actual date'**
  String get actualDateLabel;

  /// Vital recording flow. Keep full person, substance, amount, unit and saved-state meaning. Headings use 1–3 words; action buttons use one word.
  ///
  /// In en, this message translates to:
  /// **'Actual time'**
  String get actualTimeLabel;

  /// Vital recording flow. Keep full person, substance, amount, unit and saved-state meaning. Headings use 1–3 words; action buttons use one word.
  ///
  /// In en, this message translates to:
  /// **'Use YYYY-MM-DD.'**
  String get dateExample;

  /// Vital recording flow. Keep full person, substance, amount, unit and saved-state meaning. Headings use 1–3 words; action buttons use one word.
  ///
  /// In en, this message translates to:
  /// **'Use 24-hour HH:MM.'**
  String get timeExample;

  /// Vital recording flow. Keep full person, substance, amount, unit and saved-state meaning. Headings use 1–3 words; action buttons use one word.
  ///
  /// In en, this message translates to:
  /// **'Use a decimal point, without commas. Enter an amount above zero, up to 9,000,000,000, with up to 6 decimal places.'**
  String get amountInvalid;

  /// Vital recording flow. Keep full person, substance, amount, unit and saved-state meaning. Headings use 1–3 words; action buttons use one word.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid actual date and time.'**
  String get timeInvalid;

  /// Vital recording flow. Keep full person, substance, amount, unit and saved-state meaning. Headings use 1–3 words; action buttons use one word.
  ///
  /// In en, this message translates to:
  /// **'The save could not be confirmed. Retry with the same details.'**
  String get saveFailure;

  /// Vital recording flow. Keep full person, substance, amount, unit and saved-state meaning. Headings use 1–3 words; action buttons use one word.
  ///
  /// In en, this message translates to:
  /// **'This record has changed. Return to History and review the latest version before correcting it.'**
  String get conflictFailure;

  /// Vital recording flow. Keep full person, substance, amount, unit and saved-state meaning. Headings use 1–3 words; action buttons use one word.
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get saved;

  /// Vital recording flow. Keep full person, substance, amount, unit and saved-state meaning. Headings use 1–3 words; action buttons use one word.
  ///
  /// In en, this message translates to:
  /// **'Voided'**
  String get voided;

  /// Vital recording flow. Keep full person, substance, amount, unit and saved-state meaning. Headings use 1–3 words; action buttons use one word.
  ///
  /// In en, this message translates to:
  /// **'Undo marks this entry as voided. The original and its corrections stay in history.'**
  String get undoHelp;

  /// Vital recording flow. Keep full person, substance, amount, unit and saved-state meaning. Headings use 1–3 words; action buttons use one word.
  ///
  /// In en, this message translates to:
  /// **'Undo could not be confirmed. Retry or review History.'**
  String get undoFailure;

  /// Vital recording flow. Keep full person, substance, amount, unit and saved-state meaning. Headings use 1–3 words; action buttons use one word.
  ///
  /// In en, this message translates to:
  /// **'Unsaved changes'**
  String get unsavedHeading;

  /// Vital recording flow. Keep full person, substance, amount, unit and saved-state meaning. Headings use 1–3 words; action buttons use one word.
  ///
  /// In en, this message translates to:
  /// **'Keep editing or discard this unfinished entry.'**
  String get unsavedBody;

  /// Vital recording flow. Keep full person, substance, amount, unit and saved-state meaning. Headings use 1–3 words; action buttons use one word.
  ///
  /// In en, this message translates to:
  /// **'Resolve the save before leaving this entry.'**
  String get pendingBody;

  /// Vital recording flow. Keep full person, substance, amount, unit and saved-state meaning. Headings use 1–3 words; action buttons use one word.
  ///
  /// In en, this message translates to:
  /// **'History could not be loaded. Retry to keep your current view.'**
  String get historyUnavailable;

  /// Vital recording flow. Keep full person, substance, amount, unit and saved-state meaning. Headings use 1–3 words; action buttons use one word.
  ///
  /// In en, this message translates to:
  /// **'Record history'**
  String get recordHistory;

  /// Vital recording flow. Keep full person, substance, amount, unit and saved-state meaning. Headings use 1–3 words; action buttons use one word.
  ///
  /// In en, this message translates to:
  /// **'This substance is unavailable. Return to Substances.'**
  String get noItem;

  /// Vital recording flow. Keep full person, substance, amount, unit and saved-state meaning. Headings use 1–3 words; action buttons use one word.
  ///
  /// In en, this message translates to:
  /// **'Saving…'**
  String get saving;

  /// Vital recording flow. Keep full person, substance, amount, unit and saved-state meaning. Headings use 1–3 words; action buttons use one word.
  ///
  /// In en, this message translates to:
  /// **'{person}: {amount} {unit}'**
  String ownerAmount(String person, String amount, String unit);

  /// Vital recording flow. Keep full person, substance, amount, unit and saved-state meaning. Headings use 1–3 words; action buttons use one word.
  ///
  /// In en, this message translates to:
  /// **'{form} · {type} · {unit}'**
  String itemDetails(String form, String type, String unit);

  /// Vital recording flow. Keep full person, substance, amount, unit and saved-state meaning. Headings use 1–3 words; action buttons use one word.
  ///
  /// In en, this message translates to:
  /// **'Actual: {time}'**
  String actualStamp(String time);

  /// Vital recording flow. Keep full person, substance, amount, unit and saved-state meaning. Headings use 1–3 words; action buttons use one word.
  ///
  /// In en, this message translates to:
  /// **'Entered: {time}'**
  String entryStamp(String time);

  /// Vital recording flow. Keep full person, substance, amount, unit and saved-state meaning. Headings use 1–3 words; action buttons use one word.
  ///
  /// In en, this message translates to:
  /// **'Revision {revision}'**
  String revisionStamp(int revision);

  /// Vital recording flow. Keep full person, substance, amount, unit and saved-state meaning. Headings use 1–3 words; action buttons use one word.
  ///
  /// In en, this message translates to:
  /// **'Record actual use for {person}: {name}, in {unit}.'**
  String recordContext(String person, String name, String unit);

  /// Vital recording flow. Keep full person, substance, amount, unit and saved-state meaning. Headings use 1–3 words; action buttons use one word.
  ///
  /// In en, this message translates to:
  /// **'Correct actual use for {person}: {name}, in {unit}.'**
  String correctionContext(String person, String name, String unit);

  /// Vital recording flow. Keep full person, substance, amount, unit and saved-state meaning. Headings use 1–3 words; action buttons use one word.
  ///
  /// In en, this message translates to:
  /// **'Saved for {person}: {name}, {amount} {unit}.'**
  String savedContext(String person, String name, String amount, String unit);

  /// Repeated local clock during daylight-saving change. Require explicit selection; do not guess the recorded instant.
  ///
  /// In en, this message translates to:
  /// **'This clock time occurs twice. Choose the earlier or later time.'**
  String get ambiguousTime;

  /// Repeated local clock during daylight-saving change. Require explicit selection; do not guess the recorded instant.
  ///
  /// In en, this message translates to:
  /// **'Earlier'**
  String get earlier;

  /// Repeated local clock during daylight-saving change. Require explicit selection; do not guess the recorded instant.
  ///
  /// In en, this message translates to:
  /// **'Later'**
  String get later;

  /// Repeated local clock during daylight-saving change. Require explicit selection; do not guess the recorded instant.
  ///
  /// In en, this message translates to:
  /// **'{choice}: {offset}'**
  String offsetChoice(String choice, String offset);

  /// One-word button to load more saved records after the currently displayed history page.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get more;

  /// Confirmation after the durable Undo commit. Full person, item, amount and unit must remain visible.
  ///
  /// In en, this message translates to:
  /// **'Voided for {person}: {name}, {amount} {unit}.'**
  String voidedContext(String person, String name, String amount, String unit);

  /// Heading when Linux protected key storage cannot be accessed. Not an app lock or an empty dataset.
  ///
  /// In en, this message translates to:
  /// **'Keyring unavailable'**
  String get keyringTitle;

  /// Linux keyring unavailable, locked or timed out. Retry repeats protected startup without deleting records or creating a replacement dataset.
  ///
  /// In en, this message translates to:
  /// **'Unlock the desktop keyring, then retry. If it stays unavailable, check that Secret Service and secret-tool are installed.'**
  String get keyringBody;

  /// Local adult profiles. Preserve full identity and consequences; short headings and one-word commands.
  ///
  /// In en, this message translates to:
  /// **'People'**
  String get people;

  /// Local adult profiles. Preserve full identity and consequences; short headings and one-word commands.
  ///
  /// In en, this message translates to:
  /// **'Scope'**
  String get scope;

  /// Local adult profiles. Preserve full identity and consequences; short headings and one-word commands.
  ///
  /// In en, this message translates to:
  /// **'Everyone'**
  String get everyone;

  /// Local adult profiles. Preserve full identity and consequences; short headings and one-word commands.
  ///
  /// In en, this message translates to:
  /// **'Choose person'**
  String get choosePerson;

  /// Local adult profiles. Preserve full identity and consequences; short headings and one-word commands.
  ///
  /// In en, this message translates to:
  /// **'Add person'**
  String get addPerson;

  /// Local adult profiles. Preserve full identity and consequences; short headings and one-word commands.
  ///
  /// In en, this message translates to:
  /// **'Edit person'**
  String get editPerson;

  /// Local adult profiles. Preserve full identity and consequences; short headings and one-word commands.
  ///
  /// In en, this message translates to:
  /// **'Display name'**
  String get displayName;

  /// Local adult profiles. Preserve full identity and consequences; short headings and one-word commands.
  ///
  /// In en, this message translates to:
  /// **'Adult confirmed'**
  String get adultConfirmed;

  /// Local adult profiles. Preserve full identity and consequences; short headings and one-word commands.
  ///
  /// In en, this message translates to:
  /// **'I am 18 or older.'**
  String get adultHelper;

  /// Required first-run profile setup and how to continue.
  ///
  /// In en, this message translates to:
  /// **'Enter your name and confirm you are an adult to start.'**
  String get profileSetupHelp;

  /// Local adult profiles. Preserve full identity and consequences; short headings and one-word commands.
  ///
  /// In en, this message translates to:
  /// **'Enter your name and confirm you are an adult.'**
  String get profileRequired;

  /// Local adult profiles. Preserve full identity and consequences; short headings and one-word commands.
  ///
  /// In en, this message translates to:
  /// **'This profile could not be saved. Review the details and retry.'**
  String get profileFailure;

  /// Local adult profiles. Preserve full identity and consequences; short headings and one-word commands.
  ///
  /// In en, this message translates to:
  /// **'This profile has changed. Go back and review it before saving.'**
  String get profileChanged;

  /// Local adult profiles. Preserve full identity and consequences; short headings and one-word commands.
  ///
  /// In en, this message translates to:
  /// **'Optional details'**
  String get optionalDetails;

  /// Local adult profiles. Preserve full identity and consequences; short headings and one-word commands.
  ///
  /// In en, this message translates to:
  /// **'Report name (optional)'**
  String get reportName;

  /// Local adult profiles. Preserve full identity and consequences; short headings and one-word commands.
  ///
  /// In en, this message translates to:
  /// **'Relationship (optional)'**
  String get relationship;

  /// Local adult profiles. Preserve full identity and consequences; short headings and one-word commands.
  ///
  /// In en, this message translates to:
  /// **'Notes (optional)'**
  String get profileNotes;

  /// Local adult profiles. Preserve full identity and consequences; short headings and one-word commands.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get edit;

  /// Local adult profiles. Preserve full identity and consequences; short headings and one-word commands.
  ///
  /// In en, this message translates to:
  /// **'Archive'**
  String get archive;

  /// Local adult profiles. Preserve full identity and consequences; short headings and one-word commands.
  ///
  /// In en, this message translates to:
  /// **'Reactivate'**
  String get reactivate;

  /// Local adult profiles. Preserve full identity and consequences; short headings and one-word commands.
  ///
  /// In en, this message translates to:
  /// **'Archived'**
  String get archived;

  /// Local adult profiles. Preserve full identity and consequences; short headings and one-word commands.
  ///
  /// In en, this message translates to:
  /// **'Archive person'**
  String get archivePerson;

  /// Local adult profiles. Preserve full identity and consequences; short headings and one-word commands.
  ///
  /// In en, this message translates to:
  /// **'Archive {person}? Their history stays available. They leave active feeds and their reminders stop.'**
  String archiveBody(String person);

  /// Local adult profiles. Preserve full identity and consequences; short headings and one-word commands.
  ///
  /// In en, this message translates to:
  /// **'Reactivate {person}? Reminders stay stopped. No plans are available to resume in this build.'**
  String reactivateBody(String person);

  /// Local adult profiles. Preserve full identity and consequences; short headings and one-word commands.
  ///
  /// In en, this message translates to:
  /// **'Person: {person}'**
  String profileOwner(String person);

  /// Local adult profiles. Preserve full identity and consequences; short headings and one-word commands.
  ///
  /// In en, this message translates to:
  /// **'Recorded on behalf of {person}.'**
  String onBehalf(String person);

  /// Local adult profiles. Preserve full identity and consequences; short headings and one-word commands.
  ///
  /// In en, this message translates to:
  /// **'{name} (Me)'**
  String meName(String name);

  /// Local adult profiles. Preserve full identity and consequences; short headings and one-word commands.
  ///
  /// In en, this message translates to:
  /// **'{name}. Profile {reference}'**
  String profileReference(String name, String reference);

  /// Local adult profiles. Preserve full identity and consequences; short headings and one-word commands.
  ///
  /// In en, this message translates to:
  /// **'The browsing choice could not be saved. Retry.'**
  String get scopeFailure;

  /// Local adult profiles. Preserve full identity and consequences; short headings and one-word commands.
  ///
  /// In en, this message translates to:
  /// **'This person is unavailable. Return to People to review their profile.'**
  String get profileUnavailable;

  /// Local adult profiles. Preserve full identity and consequences; short headings and one-word commands.
  ///
  /// In en, this message translates to:
  /// **'View'**
  String get view;

  /// Local adult profiles. Preserve full identity and consequences; short headings and one-word commands.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get add;

  /// Local adult profiles. Preserve full identity and consequences; short headings and one-word commands.
  ///
  /// In en, this message translates to:
  /// **'Details'**
  String get details;

  /// Local profiles: short headings and one-word commands, full scope and consequences.
  ///
  /// In en, this message translates to:
  /// **'Find people'**
  String get searchPeople;

  /// Local profiles: short headings and one-word commands, full scope and consequences.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// Local profiles: short headings and one-word commands, full scope and consequences.
  ///
  /// In en, this message translates to:
  /// **'Delete person'**
  String get deletePerson;

  /// Local profiles: short headings and one-word commands, full scope and consequences.
  ///
  /// In en, this message translates to:
  /// **'Delete records'**
  String get deleteRecords;

  /// Local profiles: short headings and one-word commands, full scope and consequences.
  ///
  /// In en, this message translates to:
  /// **'Delete all saved records for {person}? This cannot be undone. Me stays available; another adult’s profile is removed.'**
  String deleteProfileBody(String person);

  /// Local profiles: short headings and one-word commands, full scope and consequences.
  ///
  /// In en, this message translates to:
  /// **'This person is archived. Reactivate them in People before recording or correcting use.'**
  String get archivedHelp;

  /// Local profiles: short headings and one-word commands, full scope and consequences.
  ///
  /// In en, this message translates to:
  /// **'Recording source was not recorded.'**
  String get legacySource;

  /// Local profiles: short headings and one-word commands, full scope and consequences.
  ///
  /// In en, this message translates to:
  /// **'Self-reported use.'**
  String get selfSource;

  /// Unsaved use form context, does not claim durable recording.
  ///
  /// In en, this message translates to:
  /// **'You are recording on behalf of {person}.'**
  String recordingOnBehalf(String person);

  /// Validation instruction for profile field length limits.
  ///
  /// In en, this message translates to:
  /// **'Keep the display name within 500 characters and optional details within 4,000.'**
  String get profileDetailsLimit;

  /// No description provided for @lockHeading.
  ///
  /// In en, this message translates to:
  /// **'Unlock'**
  String get lockHeading;

  /// No description provided for @lockBody.
  ///
  /// In en, this message translates to:
  /// **'Use your device screen lock to open Vital. Your unfinished entries stay private.'**
  String get lockBody;

  /// No description provided for @lockLoading.
  ///
  /// In en, this message translates to:
  /// **'Opening protected records.'**
  String get lockLoading;

  /// No description provided for @lockUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Device authentication is unavailable. Check your device screen lock, then try again.'**
  String get lockUnavailable;

  /// No description provided for @unlock.
  ///
  /// In en, this message translates to:
  /// **'Unlock'**
  String get unlock;

  /// No description provided for @lock.
  ///
  /// In en, this message translates to:
  /// **'Lock'**
  String get lock;

  /// No description provided for @appLock.
  ///
  /// In en, this message translates to:
  /// **'App lock'**
  String get appLock;

  /// No description provided for @appLockHelper.
  ///
  /// In en, this message translates to:
  /// **'Require your device screen lock when you open or return to Vital.'**
  String get appLockHelper;

  /// No description provided for @lockSetupRequired.
  ///
  /// In en, this message translates to:
  /// **'Set up a device screen lock before enabling app lock.'**
  String get lockSetupRequired;

  /// No description provided for @lockUnsupported.
  ///
  /// In en, this message translates to:
  /// **'Device authentication is unavailable on this platform. You can still record doses.'**
  String get lockUnsupported;

  /// No description provided for @draftHeading.
  ///
  /// In en, this message translates to:
  /// **'Unfinished entries'**
  String get draftHeading;

  /// No description provided for @draftBody.
  ///
  /// In en, this message translates to:
  /// **'Your entry is kept on this device until you save or discard it.'**
  String get draftBody;

  /// No description provided for @resume.
  ///
  /// In en, this message translates to:
  /// **'Resume'**
  String get resume;

  /// No description provided for @draftFailure.
  ///
  /// In en, this message translates to:
  /// **'Your latest changes could not be kept. Stay here and try again.'**
  String get draftFailure;

  /// No description provided for @draftSaved.
  ///
  /// In en, this message translates to:
  /// **'Your entry was already saved. Review the history before recording again.'**
  String get draftSaved;

  /// No description provided for @draftDiscardFailure.
  ///
  /// In en, this message translates to:
  /// **'This entry could not be discarded. Try again.'**
  String get draftDiscardFailure;

  /// An ordinary entry invalidated by scoped deletion or dataset replacement. Does not claim that the main adult profile was deleted.
  ///
  /// In en, this message translates to:
  /// **'This entry is no longer available. Return to Today to review your records.'**
  String get draftUnavailable;

  /// No description provided for @schedule.
  ///
  /// In en, this message translates to:
  /// **'Schedule'**
  String get schedule;

  /// No description provided for @planZoneUnavailable.
  ///
  /// In en, this message translates to:
  /// **'The device time zone is unavailable. Retry or choose a named home zone.'**
  String get planZoneUnavailable;

  /// No description provided for @planInputInvalid.
  ///
  /// In en, this message translates to:
  /// **'Check the dates, times, count, amounts and time zone before previewing.'**
  String get planInputInvalid;

  /// No description provided for @planEditHelp.
  ///
  /// In en, this message translates to:
  /// **'Choose the date this change starts. Earlier versions and recorded doses stay in history.'**
  String get planEditHelp;

  /// No description provided for @planPattern.
  ///
  /// In en, this message translates to:
  /// **'Timing'**
  String get planPattern;

  /// No description provided for @planCount.
  ///
  /// In en, this message translates to:
  /// **'Count'**
  String get planCount;

  /// No description provided for @planTimes.
  ///
  /// In en, this message translates to:
  /// **'Chosen times'**
  String get planTimes;

  /// No description provided for @planAsNeeded.
  ///
  /// In en, this message translates to:
  /// **'As needed'**
  String get planAsNeeded;

  /// No description provided for @planCountHelp.
  ///
  /// In en, this message translates to:
  /// **'The count applies to each selected date. Recorded and skipped counts are shown separately. This count is not a safe allowance.'**
  String get planCountHelp;

  /// No description provided for @planTime.
  ///
  /// In en, this message translates to:
  /// **'Planned time'**
  String get planTime;

  /// No description provided for @planPrnHelp.
  ///
  /// In en, this message translates to:
  /// **'Record use when needed. There are no expected times or missed doses.'**
  String get planPrnHelp;

  /// No description provided for @planStart.
  ///
  /// In en, this message translates to:
  /// **'Start date'**
  String get planStart;

  /// No description provided for @planEffective.
  ///
  /// In en, this message translates to:
  /// **'Effective date'**
  String get planEffective;

  /// No description provided for @planEnd.
  ///
  /// In en, this message translates to:
  /// **'End date (optional)'**
  String get planEnd;

  /// No description provided for @planEndHelp.
  ///
  /// In en, this message translates to:
  /// **'YYYY-MM-DD. Includes this day. Leave blank for no end.'**
  String get planEndHelp;

  /// No description provided for @planZone.
  ///
  /// In en, this message translates to:
  /// **'Time zone'**
  String get planZone;

  /// No description provided for @planLocal.
  ///
  /// In en, this message translates to:
  /// **'Follow local'**
  String get planLocal;

  /// No description provided for @planHome.
  ///
  /// In en, this message translates to:
  /// **'Home zone'**
  String get planHome;

  /// No description provided for @planHomeZone.
  ///
  /// In en, this message translates to:
  /// **'Named home zone'**
  String get planHomeZone;

  /// No description provided for @planZoneExample.
  ///
  /// In en, this message translates to:
  /// **'For example, Europe/London'**
  String get planZoneExample;

  /// No description provided for @planCalculationIssue.
  ///
  /// In en, this message translates to:
  /// **'Some dates cannot be calculated with the available time zone data. Review this plan.'**
  String get planCalculationIssue;

  /// No description provided for @planIncomplete.
  ///
  /// In en, this message translates to:
  /// **'The calculation limit was reached. This view is incomplete.'**
  String get planIncomplete;

  /// No description provided for @planBoundary.
  ///
  /// In en, this message translates to:
  /// **'Clock boundary'**
  String get planBoundary;

  /// No description provided for @planNoNext.
  ///
  /// In en, this message translates to:
  /// **'No next planned date within this plan.'**
  String get planNoNext;

  /// No description provided for @planMissingClock.
  ///
  /// In en, this message translates to:
  /// **'This local time does not exist. Review the clock change.'**
  String get planMissingClock;

  /// No description provided for @planRepeatedClock.
  ///
  /// In en, this message translates to:
  /// **'This local time occurs twice. Choose which one.'**
  String get planRepeatedClock;

  /// No description provided for @planNoAlert.
  ///
  /// In en, this message translates to:
  /// **'No alert for this clock change'**
  String get planNoAlert;

  /// No description provided for @planPlanned.
  ///
  /// In en, this message translates to:
  /// **'Planned'**
  String get planPlanned;

  /// No description provided for @planNothingToday.
  ///
  /// In en, this message translates to:
  /// **'Nothing planned today.'**
  String get planNothingToday;

  /// No description provided for @planTakenNow.
  ///
  /// In en, this message translates to:
  /// **'Taken records the current time. Use Extra to enter another amount or actual time.'**
  String get planTakenNow;

  /// No description provided for @planClockReview.
  ///
  /// In en, this message translates to:
  /// **'Clock review'**
  String get planClockReview;

  /// No description provided for @planNoAlertHelp.
  ///
  /// In en, this message translates to:
  /// **'Keep this planned dose without an alert, or enter a replacement time. This does not skip the dose.'**
  String get planNoAlertHelp;

  /// No description provided for @planReplacementTime.
  ///
  /// In en, this message translates to:
  /// **'Replacement time'**
  String get planReplacementTime;

  /// No description provided for @taken.
  ///
  /// In en, this message translates to:
  /// **'Taken'**
  String get taken;

  /// No description provided for @skip.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get skip;

  /// No description provided for @extra.
  ///
  /// In en, this message translates to:
  /// **'Extra'**
  String get extra;

  /// No description provided for @replace.
  ///
  /// In en, this message translates to:
  /// **'Replace'**
  String get replace;

  /// No description provided for @remove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get remove;

  /// Daily plan context; preserve full values and person ownership.
  ///
  /// In en, this message translates to:
  /// **'Observed zone: {zone}'**
  String planObserved(String zone);

  /// Daily plan context; preserve full values and person ownership.
  ///
  /// In en, this message translates to:
  /// **'Preview: {start} to {end}'**
  String planPreviewRange(String start, String end);

  /// Daily plan context; preserve full values and person ownership.
  ///
  /// In en, this message translates to:
  /// **'Next planned date: {date}'**
  String planNext(String date);

  /// Daily plan context; preserve full values and person ownership.
  ///
  /// In en, this message translates to:
  /// **'Last included date: {date}'**
  String planEnds(String date);

  /// Daily plan context; preserve full values and person ownership.
  ///
  /// In en, this message translates to:
  /// **'Replacement time: {time}'**
  String planReplacement(String time);

  /// Daily plan context; preserve full values and person ownership.
  ///
  /// In en, this message translates to:
  /// **'{date}: {count} planned, {amount} {unit} each, untimed in {zone}'**
  String planUntimed(
    String date,
    int count,
    String amount,
    String unit,
    String zone,
  );

  /// Daily plan context; preserve full values and person ownership.
  ///
  /// In en, this message translates to:
  /// **'{date} at {time}: {amount} {unit}, {zone}. {status}'**
  String planTimed(
    String date,
    String time,
    String amount,
    String unit,
    String zone,
    String status,
  );

  /// Daily plan context; preserve full values and person ownership.
  ///
  /// In en, this message translates to:
  /// **'{taken} recorded, {skipped} skipped, {planned} planned'**
  String planProgress(int taken, int skipped, int planned);

  /// Daily plan context; preserve full values and person ownership.
  ///
  /// In en, this message translates to:
  /// **'Selected instant: {instant} UTC'**
  String planClockInstant(String instant);

  /// No description provided for @planPreview.
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get planPreview;

  /// No description provided for @planZoneUnknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get planZoneUnknown;

  /// No description provided for @planHistory.
  ///
  /// In en, this message translates to:
  /// **'Planned history'**
  String get planHistory;

  /// No description provided for @planHistoryHelp.
  ///
  /// In en, this message translates to:
  /// **'Saved planned amounts and times appear here. Actual doses appear separately below.'**
  String get planHistoryHelp;

  /// No description provided for @planPreviewLimited.
  ///
  /// In en, this message translates to:
  /// **'The first 20 planned doses are shown. The preview contains more doses.'**
  String get planPreviewLimited;

  /// No description provided for @planNextReview.
  ///
  /// In en, this message translates to:
  /// **'Next date needs review'**
  String get planNextReview;

  /// No description provided for @review.
  ///
  /// In en, this message translates to:
  /// **'Review'**
  String get review;

  /// No description provided for @planOlderActions.
  ///
  /// In en, this message translates to:
  /// **'Earlier actions are available in pages of 100.'**
  String get planOlderActions;

  /// Audit entry time, not an actual dose time.
  ///
  /// In en, this message translates to:
  /// **'{action}, entered {date}'**
  String planActionEntry(String action, String date);

  /// Accessible name for a correctly owned planned-dose command.
  ///
  /// In en, this message translates to:
  /// **'{action}: {person}, {item}, {amount} {unit}, planned {date}'**
  String planActionContext(
    String action,
    String person,
    String item,
    String amount,
    String unit,
    String date,
  );

  /// Offline catalogue and person-owned item type interaction.
  ///
  /// In en, this message translates to:
  /// **'Catalogue'**
  String get catalogue;

  /// Offline catalogue and person-owned item type interaction.
  ///
  /// In en, this message translates to:
  /// **'Search medicines'**
  String get catalogueSearch;

  /// Offline catalogue and person-owned item type interaction.
  ///
  /// In en, this message translates to:
  /// **'Select the exact name, form and strength. The strength does not choose a dose or unit.'**
  String get catalogueHelp;

  /// Offline catalogue and person-owned item type interaction.
  ///
  /// In en, this message translates to:
  /// **'The medicine catalogue is unavailable. Enter a custom substance to continue.'**
  String get catalogueUnavailable;

  /// Offline catalogue and person-owned item type interaction.
  ///
  /// In en, this message translates to:
  /// **'Searching the offline catalogue…'**
  String get catalogueSearching;

  /// Offline catalogue and person-owned item type interaction.
  ///
  /// In en, this message translates to:
  /// **'Enter a name, form or strength to search offline.'**
  String get catalogueStart;

  /// Offline catalogue and person-owned item type interaction.
  ///
  /// In en, this message translates to:
  /// **'Some matches may be missing. Add more of the name, form or strength.'**
  String get catalogueRefine;

  /// Offline catalogue and person-owned item type interaction.
  ///
  /// In en, this message translates to:
  /// **'Unable to search. Try again or enter a custom substance.'**
  String get catalogueSearchFailure;

  /// Offline catalogue and person-owned item type interaction.
  ///
  /// In en, this message translates to:
  /// **'Use up to 128 characters and 16 search words, or continue with a custom entry.'**
  String get catalogueQueryLimit;

  /// Offline catalogue and person-owned item type interaction.
  ///
  /// In en, this message translates to:
  /// **'Selected product'**
  String get catalogueSelected;

  /// Offline catalogue and person-owned item type interaction.
  ///
  /// In en, this message translates to:
  /// **'Custom entry'**
  String get catalogueCustom;

  /// Offline catalogue and person-owned item type interaction.
  ///
  /// In en, this message translates to:
  /// **'Continue with “{query}” as the substance name.'**
  String catalogueCustomHelp(String query);

  /// Offline catalogue and person-owned item type interaction.
  ///
  /// In en, this message translates to:
  /// **'No catalogue match for “{query}”. You can enter it as a custom substance.'**
  String catalogueNoMatch(String query);

  /// Offline catalogue and person-owned item type interaction.
  ///
  /// In en, this message translates to:
  /// **'Source: {source}. Version: {version}. Released: {date}.'**
  String catalogueRelease(String source, String version, String date);

  /// Offline catalogue and person-owned item type interaction.
  ///
  /// In en, this message translates to:
  /// **'{name}. Form: {form}. Strength: {strength}.'**
  String catalogueProduct(String name, String form, String strength);

  /// Offline catalogue and person-owned item type interaction.
  ///
  /// In en, this message translates to:
  /// **'Not supplied'**
  String get catalogueMissing;

  /// Offline catalogue and person-owned item type interaction.
  ///
  /// In en, this message translates to:
  /// **'Attribution: {attribution}'**
  String catalogueAttribution(String attribution);

  /// Offline catalogue and person-owned item type interaction.
  ///
  /// In en, this message translates to:
  /// **'Licence: {licence}'**
  String catalogueLicence(String licence);

  /// Offline catalogue and person-owned item type interaction.
  ///
  /// In en, this message translates to:
  /// **'Select'**
  String get catalogueSelect;

  /// Offline catalogue and person-owned item type interaction.
  ///
  /// In en, this message translates to:
  /// **'Enter'**
  String get catalogueEnter;

  /// Offline catalogue and person-owned item type interaction.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get catalogueClear;

  /// Offline catalogue and person-owned item type interaction.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get catalogueSearchAction;

  /// Offline catalogue and person-owned item type interaction.
  ///
  /// In en, this message translates to:
  /// **'This saved source version stays with the substance and its dose history.'**
  String get catalogueSelectedHelp;

  /// Offline catalogue and person-owned item type interaction.
  ///
  /// In en, this message translates to:
  /// **'Select {name}, form {form}, strength {strength}'**
  String catalogueSelectContext(String name, String form, String strength);

  /// Offline catalogue and person-owned item type interaction.
  ///
  /// In en, this message translates to:
  /// **'Item types'**
  String get itemTypes;

  /// Offline catalogue and person-owned item type interaction.
  ///
  /// In en, this message translates to:
  /// **'Types group this person’s substances. They do not change forms, strengths or icons.'**
  String get itemTypesHelp;

  /// Offline catalogue and person-owned item type interaction.
  ///
  /// In en, this message translates to:
  /// **'No personal types yet. Create one or enter a type with a new substance.'**
  String get itemTypesEmpty;

  /// Offline catalogue and person-owned item type interaction.
  ///
  /// In en, this message translates to:
  /// **'New type'**
  String get itemTypeNew;

  /// Offline catalogue and person-owned item type interaction.
  ///
  /// In en, this message translates to:
  /// **'Rename type'**
  String get itemTypeEdit;

  /// Offline catalogue and person-owned item type interaction.
  ///
  /// In en, this message translates to:
  /// **'Type name'**
  String get itemTypeName;

  /// Offline catalogue and person-owned item type interaction.
  ///
  /// In en, this message translates to:
  /// **'Existing substances use the new name. Earlier dose records keep their saved type.'**
  String get itemTypeRenameHelp;

  /// Offline catalogue and person-owned item type interaction.
  ///
  /// In en, this message translates to:
  /// **'Manage'**
  String get itemTypeManage;

  /// Offline catalogue and person-owned item type interaction.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get itemTypeRename;

  /// Offline catalogue and person-owned item type interaction.
  ///
  /// In en, this message translates to:
  /// **'Use type {name}'**
  String itemTypeChoice(String name);

  /// Offline catalogue and person-owned item type interaction.
  ///
  /// In en, this message translates to:
  /// **'Selected type: {name}'**
  String itemTypeCurrent(String name);

  /// Bounded list page navigation command.
  ///
  /// In en, this message translates to:
  /// **'Previous'**
  String get previous;

  /// Bounded list page navigation command.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get next;

  /// Duplicate owner-scoped type name; fields remain editable.
  ///
  /// In en, this message translates to:
  /// **'This person already has that type. Choose a different name.'**
  String get itemTypeExists;

  /// Stock tracking copy. Preserve owner, original quantities, units and physical consequences.
  ///
  /// In en, this message translates to:
  /// **'Stock'**
  String get stock;

  /// Stock tracking copy. Preserve owner, original quantities, units and physical consequences.
  ///
  /// In en, this message translates to:
  /// **'Add container'**
  String get stockCreate;

  /// Stock tracking copy. Preserve owner, original quantities, units and physical consequences.
  ///
  /// In en, this message translates to:
  /// **'Adjust stock'**
  String get stockAdjust;

  /// Stock tracking copy. Preserve owner, original quantities, units and physical consequences.
  ///
  /// In en, this message translates to:
  /// **'Container name'**
  String get stockLabel;

  /// Stock tracking copy. Preserve owner, original quantities, units and physical consequences.
  ///
  /// In en, this message translates to:
  /// **'Labelled strength'**
  String get stockStrength;

  /// Stock tracking copy. Preserve owner, original quantities, units and physical consequences.
  ///
  /// In en, this message translates to:
  /// **'Known strength'**
  String get stockKnownStrength;

  /// Stock tracking copy. Preserve owner, original quantities, units and physical consequences.
  ///
  /// In en, this message translates to:
  /// **'Use the concentration printed on this container.'**
  String get stockKnownStrengthHelp;

  /// Stock tracking copy. Preserve owner, original quantities, units and physical consequences.
  ///
  /// In en, this message translates to:
  /// **'Strength (mg/ml)'**
  String get stockConcentration;

  /// Stock tracking copy. Preserve owner, original quantities, units and physical consequences.
  ///
  /// In en, this message translates to:
  /// **'Starting amount'**
  String get stockOpening;

  /// Stock tracking copy. Preserve owner, original quantities, units and physical consequences.
  ///
  /// In en, this message translates to:
  /// **'Known amount'**
  String get stockKnownOpening;

  /// Stock tracking copy. Preserve owner, original quantities, units and physical consequences.
  ///
  /// In en, this message translates to:
  /// **'Leave this off when the remaining amount is unknown.'**
  String get stockOpeningHelp;

  /// Stock tracking copy. Preserve owner, original quantities, units and physical consequences.
  ///
  /// In en, this message translates to:
  /// **'Low-stock threshold'**
  String get stockThreshold;

  /// Stock tracking copy. Preserve owner, original quantities, units and physical consequences.
  ///
  /// In en, this message translates to:
  /// **'Optional. An empty threshold turns low-stock notices off.'**
  String get stockThresholdHelp;

  /// Stock tracking copy. Preserve owner, original quantities, units and physical consequences.
  ///
  /// In en, this message translates to:
  /// **'Refill notices'**
  String get stockRefill;

  /// Stock tracking copy. Preserve owner, original quantities, units and physical consequences.
  ///
  /// In en, this message translates to:
  /// **'Show a notice here and in Today when known stock reaches zero or below.'**
  String get stockRefillHelp;

  /// Stock tracking copy. Preserve owner, original quantities, units and physical consequences.
  ///
  /// In en, this message translates to:
  /// **'Containers are optional. Add one to track its supply.'**
  String get stockEmpty;

  /// Stock tracking copy. Preserve owner, original quantities, units and physical consequences.
  ///
  /// In en, this message translates to:
  /// **'Record without stock, or choose a container.'**
  String get stockOptional;

  /// Stock tracking copy. Preserve owner, original quantities, units and physical consequences.
  ///
  /// In en, this message translates to:
  /// **'No container'**
  String get stockNone;

  /// Stock tracking copy. Preserve owner, original quantities, units and physical consequences.
  ///
  /// In en, this message translates to:
  /// **'Stock unknown. Measure the remaining amount to establish a balance.'**
  String get stockUnknown;

  /// Stock tracking copy. Preserve owner, original quantities, units and physical consequences.
  ///
  /// In en, this message translates to:
  /// **'Stock total unavailable. The recorded use remains saved.'**
  String get stockLimit;

  /// Stock tracking copy. Preserve owner, original quantities, units and physical consequences.
  ///
  /// In en, this message translates to:
  /// **'Low stock'**
  String get stockLow;

  /// Stock tracking copy. Preserve owner, original quantities, units and physical consequences.
  ///
  /// In en, this message translates to:
  /// **'Refill due'**
  String get stockRefillDue;

  /// Stock tracking copy. Preserve owner, original quantities, units and physical consequences.
  ///
  /// In en, this message translates to:
  /// **'Stock mismatch. The dose is saved. Review the container separately.'**
  String get stockMismatch;

  /// Stock tracking copy. Preserve owner, original quantities, units and physical consequences.
  ///
  /// In en, this message translates to:
  /// **'Restock'**
  String get stockRestock;

  /// Stock tracking copy. Preserve owner, original quantities, units and physical consequences.
  ///
  /// In en, this message translates to:
  /// **'Waste'**
  String get stockWaste;

  /// Stock tracking copy. Preserve owner, original quantities, units and physical consequences.
  ///
  /// In en, this message translates to:
  /// **'Measure'**
  String get stockMeasure;

  /// Stock tracking copy. Preserve owner, original quantities, units and physical consequences.
  ///
  /// In en, this message translates to:
  /// **'Reason (optional)'**
  String get stockReason;

  /// Stock tracking copy. Preserve owner, original quantities, units and physical consequences.
  ///
  /// In en, this message translates to:
  /// **'Adds supply. An unknown balance stays unknown until measured.'**
  String get stockRestockHelp;

  /// Stock tracking copy. Preserve owner, original quantities, units and physical consequences.
  ///
  /// In en, this message translates to:
  /// **'Removes supply without recording a dose.'**
  String get stockWasteHelp;

  /// Stock tracking copy. Preserve owner, original quantities, units and physical consequences.
  ///
  /// In en, this message translates to:
  /// **'Replaces the balance with the amount you measure. Earlier history stays unchanged.'**
  String get stockMeasureHelp;

  /// Stock tracking copy. Preserve owner, original quantities, units and physical consequences.
  ///
  /// In en, this message translates to:
  /// **'Unknown amount'**
  String get stockUnknownMeasure;

  /// Stock tracking copy. Preserve owner, original quantities, units and physical consequences.
  ///
  /// In en, this message translates to:
  /// **'Save the remaining stock as unknown.'**
  String get stockUnknownMeasureHelp;

  /// Stock tracking copy. Preserve owner, original quantities, units and physical consequences.
  ///
  /// In en, this message translates to:
  /// **'Use a dot or comma for decimals, with no grouping. Up to six decimal places.'**
  String get stockDecimalHelp;

  /// Stock tracking copy. Preserve owner, original quantities, units and physical consequences.
  ///
  /// In en, this message translates to:
  /// **'Enter an amount from 0.000001 to 9,000,000,000 with up to six decimal places.'**
  String get stockAmountInvalid;

  /// Stock tracking copy. Preserve owner, original quantities, units and physical consequences.
  ///
  /// In en, this message translates to:
  /// **'Enter zero or a positive amount with up to six decimal places.'**
  String get stockMeasurementInvalid;

  /// Stock tracking copy. Preserve owner, original quantities, units and physical consequences.
  ///
  /// In en, this message translates to:
  /// **'Enter the container name and its labelled strength.'**
  String get stockLabelRequired;

  /// Stock tracking copy. Preserve owner, original quantities, units and physical consequences.
  ///
  /// In en, this message translates to:
  /// **'Choose restock, waste or measurement.'**
  String get stockChooseKind;

  /// Stock tracking copy. Preserve owner, original quantities, units and physical consequences.
  ///
  /// In en, this message translates to:
  /// **'Dose source'**
  String get stockSource;

  /// Stock tracking copy. Preserve owner, original quantities, units and physical consequences.
  ///
  /// In en, this message translates to:
  /// **'Choose'**
  String get stockChoose;

  /// Stock tracking copy. Preserve owner, original quantities, units and physical consequences.
  ///
  /// In en, this message translates to:
  /// **'Selected'**
  String get stockSelected;

  /// Stock tracking copy. Preserve owner, original quantities, units and physical consequences.
  ///
  /// In en, this message translates to:
  /// **'Strength changed'**
  String get stockReplacement;

  /// Stock tracking copy. Preserve owner, original quantities, units and physical consequences.
  ///
  /// In en, this message translates to:
  /// **'Choose which amount to keep. This changes this dose only; future plans stay the same.'**
  String get stockReplacementHelp;

  /// Stock tracking copy. Preserve owner, original quantities, units and physical consequences.
  ///
  /// In en, this message translates to:
  /// **'Keep mg'**
  String get stockKeepMg;

  /// Stock tracking copy. Preserve owner, original quantities, units and physical consequences.
  ///
  /// In en, this message translates to:
  /// **'Keep ml'**
  String get stockKeepMl;

  /// Stock tracking copy. Preserve owner, original quantities, units and physical consequences.
  ///
  /// In en, this message translates to:
  /// **'Choose whether mg or ml stays fixed.'**
  String get stockKeepRequired;

  /// Stock tracking copy. Preserve owner, original quantities, units and physical consequences.
  ///
  /// In en, this message translates to:
  /// **'No equivalent is available for these strengths and units. Enter the actual amount for the selected container.'**
  String get stockNoEquivalent;

  /// Stock tracking copy. Preserve owner, original quantities, units and physical consequences.
  ///
  /// In en, this message translates to:
  /// **'Physical effect'**
  String get stockPhysical;

  /// Stock tracking copy. Preserve owner, original quantities, units and physical consequences.
  ///
  /// In en, this message translates to:
  /// **'Choose what happened to the supply. Correcting details does not record another use.'**
  String get stockPhysicalHelp;

  /// Stock tracking copy. Preserve owner, original quantities, units and physical consequences.
  ///
  /// In en, this message translates to:
  /// **'Keep consumed'**
  String get stockRetain;

  /// Stock tracking copy. Preserve owner, original quantities, units and physical consequences.
  ///
  /// In en, this message translates to:
  /// **'Reverse entry'**
  String get stockReverse;

  /// Stock tracking copy. Preserve owner, original quantities, units and physical consequences.
  ///
  /// In en, this message translates to:
  /// **'The supply was used or lost. Keep its stock effect.'**
  String get stockRetainHelp;

  /// Stock tracking copy. Preserve owner, original quantities, units and physical consequences.
  ///
  /// In en, this message translates to:
  /// **'The recorded use was a mistake. Reverse its stock effect, preserving any later measurement.'**
  String get stockReverseHelp;

  /// Stock tracking copy. Preserve owner, original quantities, units and physical consequences.
  ///
  /// In en, this message translates to:
  /// **'Choose whether the supply was consumed or the entry was a mistake.'**
  String get stockPhysicalRequired;

  /// Stock tracking copy. Preserve owner, original quantities, units and physical consequences.
  ///
  /// In en, this message translates to:
  /// **'The stock effect was already reviewed. Later detail changes keep that effect.'**
  String get stockAlreadyReviewed;

  /// Stock tracking copy. Preserve owner, original quantities, units and physical consequences.
  ///
  /// In en, this message translates to:
  /// **'Stock notices'**
  String get stockNotices;

  /// Stock tracking copy. Preserve owner, original quantities, units and physical consequences.
  ///
  /// In en, this message translates to:
  /// **'Notices appear in Vital. No device notification is scheduled.'**
  String get stockLocalNoticeHelp;

  /// Stock tracking copy. Preserve owner, original quantities, units and physical consequences.
  ///
  /// In en, this message translates to:
  /// **'Stock saved'**
  String get stockSaved;

  /// Stock tracking copy. Preserve owner, original quantities, units and physical consequences.
  ///
  /// In en, this message translates to:
  /// **'Notice settings saved.'**
  String get stockNoticeSaved;

  /// Stock tracking copy. Preserve owner, original quantities, units and physical consequences.
  ///
  /// In en, this message translates to:
  /// **'Notice settings were not saved. Your entry is still here. Retry.'**
  String get stockNoticeFailure;

  /// Stock tracking copy. Preserve owner, original quantities, units and physical consequences.
  ///
  /// In en, this message translates to:
  /// **'Original entry: {amount} {unit}.'**
  String stockEntered(String amount, String unit);

  /// Stock tracking copy. Preserve owner, original quantities, units and physical consequences.
  ///
  /// In en, this message translates to:
  /// **'{amount} {unit}'**
  String stockQuantity(String amount, String unit);

  /// Stock tracking copy. Preserve owner, original quantities, units and physical consequences.
  ///
  /// In en, this message translates to:
  /// **'Approximately {amount} {unit}'**
  String stockApproximate(String amount, String unit);

  /// Stock tracking copy. Preserve owner, original quantities, units and physical consequences.
  ///
  /// In en, this message translates to:
  /// **'Remaining: {amount}'**
  String stockBalance(String amount);

  /// Stock tracking copy. Preserve owner, original quantities, units and physical consequences.
  ///
  /// In en, this message translates to:
  /// **'{person}: {container}'**
  String stockNoticeTarget(String person, String container);

  /// Stock tracking copy. Preserve owner, original quantities, units and physical consequences.
  ///
  /// In en, this message translates to:
  /// **'Labelled strength: {strength}'**
  String stockStrengthValue(String strength);

  /// Stock tracking copy. Preserve owner, original quantities, units and physical consequences.
  ///
  /// In en, this message translates to:
  /// **'Previous strength: {strength}'**
  String stockReplacementFrom(String strength);

  /// Stock tracking copy. Preserve owner, original quantities, units and physical consequences.
  ///
  /// In en, this message translates to:
  /// **'This dose: {amount}'**
  String stockNewEquivalent(String amount);

  /// Stock tracking copy. Preserve owner, original quantities, units and physical consequences.
  ///
  /// In en, this message translates to:
  /// **'Low-stock threshold: {amount}'**
  String stockThresholdValue(String amount);

  /// Stock tracking copy. Preserve owner, original quantities, units and physical consequences.
  ///
  /// In en, this message translates to:
  /// **'Stock history'**
  String get stockHistory;

  /// Stock tracking copy. Preserve owner, original quantities, units and physical consequences.
  ///
  /// In en, this message translates to:
  /// **'{kind}: {amount}'**
  String stockMovementEntry(String kind, String amount);

  /// Stock tracking copy. Preserve owner, original quantities, units and physical consequences.
  ///
  /// In en, this message translates to:
  /// **'This container is unavailable. Review the person and substance.'**
  String get stockUnavailable;

  /// Stock tracking copy. Preserve owner, original quantities, units and physical consequences.
  ///
  /// In en, this message translates to:
  /// **'More containers are available. Open Stock to review them.'**
  String get stockMore;

  /// Stock tracking copy. Preserve owner, original quantities, units and physical consequences.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get stockApply;

  /// Stock tracking action or explanatory copy.
  ///
  /// In en, this message translates to:
  /// **'Adjust'**
  String get stockAdjustAction;

  /// Stock tracking action or explanatory copy.
  ///
  /// In en, this message translates to:
  /// **'Labelled strength'**
  String get stockLabelOnly;

  /// Stock tracking action or explanatory copy.
  ///
  /// In en, this message translates to:
  /// **'Record the labelled strength without tracking a container.'**
  String get stockLabelOnlyHelp;

  /// Stock tracking action or explanatory copy.
  ///
  /// In en, this message translates to:
  /// **'Entered: {amount} {unit}.'**
  String stockEntryProvenance(String amount, String unit);

  /// Stock tracking action or explanatory copy.
  ///
  /// In en, this message translates to:
  /// **'Enter the corrected actual amount. A displayed approximate equivalent is never reused as an entry.'**
  String get stockCorrectionEntryHelp;

  /// Enter the actual quantity for the selected source when conversion is unavailable.
  ///
  /// In en, this message translates to:
  /// **'Enter'**
  String get stockEnter;

  /// Opens optional container source selection for this planned dose.
  ///
  /// In en, this message translates to:
  /// **'Source'**
  String get stockSourceAction;

  /// New actual quantity for a correction. Empty means preserve the exact stored quantity.
  ///
  /// In en, this message translates to:
  /// **'Actual amount (optional)'**
  String get stockCorrectionAmount;

  /// Time-only correction keeps exact quantity and source snapshots.
  ///
  /// In en, this message translates to:
  /// **'Leave the amount empty to keep the saved exact quantity.'**
  String get stockCorrectionKeep;

  /// Signed stock balance is negative; no clamping or invented refill.
  ///
  /// In en, this message translates to:
  /// **'Stock deficit. The recorded balance is below zero.'**
  String get stockDeficit;

  /// For later corrections or Undo after a physical stock consequence was already reviewed.
  ///
  /// In en, this message translates to:
  /// **'Leave the current stock balance unchanged. The earlier physical correction stays in history.'**
  String get stockReviewedKeep;

  /// Existing exact threshold is readonly; empty new input preserves it.
  ///
  /// In en, this message translates to:
  /// **'Enter a replacement threshold, or Clear to turn low-stock notices off. An empty unchanged entry keeps the saved threshold.'**
  String get stockThresholdEditHelp;

  /// Explicit Clear action previews disabling the low-stock threshold.
  ///
  /// In en, this message translates to:
  /// **'Low-stock notices will be turned off when you save.'**
  String get stockThresholdCleared;

  /// Standalone strength label missing; keep draft editable.
  ///
  /// In en, this message translates to:
  /// **'Enter the labelled strength.'**
  String get stockStrengthRequired;

  /// Unknown stock quantity, distinct from zero.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get stockUnknownValue;

  /// Selection to retain the current physical balance after an earlier reviewed stock correction.
  ///
  /// In en, this message translates to:
  /// **'Keep balance'**
  String get stockKeepBalance;

  /// Standalone labelled strength can remain unknown without a tracked container.
  ///
  /// In en, this message translates to:
  /// **'Optional. Leave empty when the concentration is unknown.'**
  String get stockConcentrationHelp;

  /// No description provided for @reminders.
  ///
  /// In en, this message translates to:
  /// **'Reminders'**
  String get reminders;

  /// No description provided for @reminderHelp.
  ///
  /// In en, this message translates to:
  /// **'Alerts cover a limited window. Reopen Vital to prepare more. Android settings can affect delivery.'**
  String get reminderHelp;

  /// No description provided for @reminderUnsupported.
  ///
  /// In en, this message translates to:
  /// **'Alerts are not available on this platform. Plans and records stay available.'**
  String get reminderUnsupported;

  /// No description provided for @reminderGeneric.
  ///
  /// In en, this message translates to:
  /// **'Notifications show no person, substance or amount.'**
  String get reminderGeneric;

  /// No description provided for @reminderDetailedUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Detailed notifications are not available.'**
  String get reminderDetailedUnavailable;

  /// No description provided for @reminderPermission.
  ///
  /// In en, this message translates to:
  /// **'Allow notifications in Android to receive alerts.'**
  String get reminderPermission;

  /// No description provided for @reminderExact.
  ///
  /// In en, this message translates to:
  /// **'Allow exact alarms in Android for planned alert times.'**
  String get reminderExact;

  /// No description provided for @reminderBlocked.
  ///
  /// In en, this message translates to:
  /// **'Android is blocking notifications. Review notification settings.'**
  String get reminderBlocked;

  /// No description provided for @reminderProtected.
  ///
  /// In en, this message translates to:
  /// **'Protected storage is unavailable. Unlock the device and reopen Vital.'**
  String get reminderProtected;

  /// No description provided for @reminderClock.
  ///
  /// In en, this message translates to:
  /// **'Snooze is unavailable until the device clock can be checked. Reopen Vital and retry.'**
  String get reminderClock;

  /// No description provided for @reminderAttention.
  ///
  /// In en, this message translates to:
  /// **'Reminders need attention'**
  String get reminderAttention;

  /// No description provided for @reminderUnprepared.
  ///
  /// In en, this message translates to:
  /// **'No prepared coverage for {scope}. Select Retry to check again.'**
  String reminderUnprepared(String scope);

  /// No description provided for @reminderCoverage.
  ///
  /// In en, this message translates to:
  /// **'Prepared through {time} for {scope}. This does not confirm delivery.'**
  String reminderCoverage(String scope, String time);

  /// No description provided for @reminderIncomplete.
  ///
  /// In en, this message translates to:
  /// **'Some alerts are not prepared in this scope. Reopen Vital and retry.'**
  String get reminderIncomplete;

  /// No description provided for @reminderChecked.
  ///
  /// In en, this message translates to:
  /// **'Checked {time}.'**
  String reminderChecked(String time);

  /// No description provided for @reminderPlanHelp.
  ///
  /// In en, this message translates to:
  /// **'Alerts for {person} and this plan. Turning alerts off does not change the plan or records.'**
  String reminderPlanHelp(String person);

  /// No description provided for @reminderUntimed.
  ///
  /// In en, this message translates to:
  /// **'Alerts need chosen times. Counts and as-needed plans have no alert times.'**
  String get reminderUntimed;

  /// No description provided for @reminderPending.
  ///
  /// In en, this message translates to:
  /// **'A reminder is awaiting review.'**
  String get reminderPending;

  /// No description provided for @reminderDelay.
  ///
  /// In en, this message translates to:
  /// **'Delay'**
  String get reminderDelay;

  /// No description provided for @reminderCustom.
  ///
  /// In en, this message translates to:
  /// **'Custom delay'**
  String get reminderCustom;

  /// No description provided for @reminderCustomHelp.
  ///
  /// In en, this message translates to:
  /// **'Enter a positive whole number of minutes.'**
  String get reminderCustomHelp;

  /// No description provided for @reminderMinutes.
  ///
  /// In en, this message translates to:
  /// **'{minutes, plural, one{1 minute} other{{minutes} minutes}}'**
  String reminderMinutes(int minutes);

  /// No description provided for @reminderSnoozeHelp.
  ///
  /// In en, this message translates to:
  /// **'The delay starts when you save. Snoozing does not record use.'**
  String get reminderSnoozeHelp;

  /// No description provided for @reminderSaved.
  ///
  /// In en, this message translates to:
  /// **'Snooze saved. Check reminder health to see whether the alert is prepared.'**
  String get reminderSaved;

  /// No description provided for @reminderChanged.
  ///
  /// In en, this message translates to:
  /// **'This reminder has changed. Your entry is kept for review. Open the plan to check its current status.'**
  String get reminderChanged;

  /// No description provided for @reminderSubmitted.
  ///
  /// In en, this message translates to:
  /// **'This action was submitted. Retry checks the same saved command.'**
  String get reminderSubmitted;

  /// No description provided for @reminderUnavailable.
  ///
  /// In en, this message translates to:
  /// **'This reminder is no longer available. Review the plan before recording anything.'**
  String get reminderUnavailable;

  /// No description provided for @reminderInterrupted.
  ///
  /// In en, this message translates to:
  /// **'Device restarted. Choose a delay to remind you again.'**
  String get reminderInterrupted;

  /// No description provided for @reminderSnoozeInterrupted.
  ///
  /// In en, this message translates to:
  /// **'Snooze interrupted'**
  String get reminderSnoozeInterrupted;

  /// No description provided for @reminderActionContext.
  ///
  /// In en, this message translates to:
  /// **'{person}: {item}, {amount} {unit}.'**
  String reminderActionContext(
    String person,
    String item,
    String amount,
    String unit,
  );

  /// No description provided for @reminderPlanScope.
  ///
  /// In en, this message translates to:
  /// **'Plan for {person}'**
  String reminderPlanScope(String person);

  /// No description provided for @reminderRepairReason.
  ///
  /// In en, this message translates to:
  /// **'Alert status: {status}.'**
  String reminderRepairReason(String status);

  /// No description provided for @reminderStatePending.
  ///
  /// In en, this message translates to:
  /// **'Awaiting preparation'**
  String get reminderStatePending;

  /// No description provided for @reminderStatePrepared.
  ///
  /// In en, this message translates to:
  /// **'Prepared'**
  String get reminderStatePrepared;

  /// No description provided for @reminderStateConsumed.
  ///
  /// In en, this message translates to:
  /// **'Issued, use not recorded'**
  String get reminderStateConsumed;

  /// No description provided for @reminderStateCancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get reminderStateCancelled;

  /// No description provided for @reminderStatePostUncertain.
  ///
  /// In en, this message translates to:
  /// **'Display uncertain. Review this reminder'**
  String get reminderStatePostUncertain;

  /// No description provided for @reminderStateFailed.
  ///
  /// In en, this message translates to:
  /// **'Unavailable. Retry preparation'**
  String get reminderStateFailed;

  /// No description provided for @reminderStateUnknown.
  ///
  /// In en, this message translates to:
  /// **'Preparation uncertain. Retry to check'**
  String get reminderStateUnknown;

  /// No description provided for @reminderStateCapacity.
  ///
  /// In en, this message translates to:
  /// **'Preparation limit reached'**
  String get reminderStateCapacity;

  /// No description provided for @reminderStateExpired.
  ///
  /// In en, this message translates to:
  /// **'Delay expired. Choose a new delay'**
  String get reminderStateExpired;

  /// No description provided for @reminderStateReview.
  ///
  /// In en, this message translates to:
  /// **'Review required'**
  String get reminderStateReview;

  /// No description provided for @reminderAllow.
  ///
  /// In en, this message translates to:
  /// **'Allow'**
  String get reminderAllow;

  /// No description provided for @reminderSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get reminderSettings;

  /// No description provided for @snooze.
  ///
  /// In en, this message translates to:
  /// **'Snooze'**
  String get snooze;

  /// No description provided for @reminderDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get reminderDone;

  /// No description provided for @reminderScope.
  ///
  /// In en, this message translates to:
  /// **'{person}: {item}'**
  String reminderScope(String person, String item);

  /// No description provided for @reminderExcludedCount.
  ///
  /// In en, this message translates to:
  /// **'Entries outside coverage: {count}.'**
  String reminderExcludedCount(int count);

  /// No description provided for @reminderDisabled.
  ///
  /// In en, this message translates to:
  /// **'Alerts are off for this plan.'**
  String get reminderDisabled;

  /// No description provided for @reminderNoOccurrences.
  ///
  /// In en, this message translates to:
  /// **'No eligible alert times in this preparation window.'**
  String get reminderNoOccurrences;

  /// No description provided for @reminderWorkLimit.
  ///
  /// In en, this message translates to:
  /// **'Preparation reached its work limit. Reopen Vital and retry.'**
  String get reminderWorkLimit;

  /// No description provided for @reminderClockReview.
  ///
  /// In en, this message translates to:
  /// **'Choose how to handle a missing or repeated clock time in this plan.'**
  String get reminderClockReview;

  /// Ready-mixed product entry or labelled snapshot. Preserve full names, units, explicit unknowns and ownership. Headings use 1–3 words; visible commands use one word.
  ///
  /// In en, this message translates to:
  /// **'Ready-mixed product'**
  String get productToggle;

  /// Ready-mixed product entry or labelled snapshot. Preserve full names, units, explicit unknowns and ownership. Headings use 1–3 words; visible commands use one word.
  ///
  /// In en, this message translates to:
  /// **'Record one volume with separate labelled ingredients.'**
  String get productToggleHelp;

  /// Ready-mixed product entry or labelled snapshot. Preserve full names, units, explicit unknowns and ownership. Headings use 1–3 words; visible commands use one word.
  ///
  /// In en, this message translates to:
  /// **'Ingredients'**
  String get productIngredients;

  /// Ready-mixed product entry or labelled snapshot. Preserve full names, units, explicit unknowns and ownership. Headings use 1–3 words; visible commands use one word.
  ///
  /// In en, this message translates to:
  /// **'Product label'**
  String get productLabelHeading;

  /// Ready-mixed product entry or labelled snapshot. Preserve full names, units, explicit unknowns and ownership. Headings use 1–3 words; visible commands use one word.
  ///
  /// In en, this message translates to:
  /// **'Changes apply to future entries. Saved records keep their original label.'**
  String get productLabelHelp;

  /// Ready-mixed product entry or labelled snapshot. Preserve full names, units, explicit unknowns and ownership. Headings use 1–3 words; visible commands use one word.
  ///
  /// In en, this message translates to:
  /// **'Ingredient name'**
  String get productIngredientName;

  /// Ready-mixed product entry or labelled snapshot. Preserve full names, units, explicit unknowns and ownership. Headings use 1–3 words; visible commands use one word.
  ///
  /// In en, this message translates to:
  /// **'Concentration'**
  String get productConcentration;

  /// Ready-mixed product entry or labelled snapshot. Preserve full names, units, explicit unknowns and ownership. Headings use 1–3 words; visible commands use one word.
  ///
  /// In en, this message translates to:
  /// **'Known strength'**
  String get productKnownStrength;

  /// Ready-mixed product entry or labelled snapshot. Preserve full names, units, explicit unknowns and ownership. Headings use 1–3 words; visible commands use one word.
  ///
  /// In en, this message translates to:
  /// **'Copy a known concentration from the label. Otherwise leave it unknown.'**
  String get productKnownStrengthHelp;

  /// Ready-mixed product entry or labelled snapshot. Preserve full names, units, explicit unknowns and ownership. Headings use 1–3 words; visible commands use one word.
  ///
  /// In en, this message translates to:
  /// **'Mass unit'**
  String get productMassUnit;

  /// Ready-mixed product entry or labelled snapshot. Preserve full names, units, explicit unknowns and ownership. Headings use 1–3 words; visible commands use one word.
  ///
  /// In en, this message translates to:
  /// **'Volume unit'**
  String get productVolumeUnit;

  /// Ready-mixed product entry or labelled snapshot. Preserve full names, units, explicit unknowns and ownership. Headings use 1–3 words; visible commands use one word.
  ///
  /// In en, this message translates to:
  /// **'Only mg per ml has a calculated mass. Other labelled units stay unchanged.'**
  String get productUnitsHelp;

  /// Ready-mixed product entry or labelled snapshot. Preserve full names, units, explicit unknowns and ownership. Headings use 1–3 words; visible commands use one word.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get productAdd;

  /// Ready-mixed product entry or labelled snapshot. Preserve full names, units, explicit unknowns and ownership. Headings use 1–3 words; visible commands use one word.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get productRemove;

  /// Ready-mixed product entry or labelled snapshot. Preserve full names, units, explicit unknowns and ownership. Headings use 1–3 words; visible commands use one word.
  ///
  /// In en, this message translates to:
  /// **'Label'**
  String get productLabelAction;

  /// Ready-mixed product entry or labelled snapshot. Preserve full names, units, explicit unknowns and ownership. Headings use 1–3 words; visible commands use one word.
  ///
  /// In en, this message translates to:
  /// **'Enter 2–32 ingredients with names and units. Known concentrations must be positive decimals with up to six decimal places.'**
  String get productIngredientInvalid;

  /// Ready-mixed product entry or labelled snapshot. Preserve full names, units, explicit unknowns and ownership. Headings use 1–3 words; visible commands use one word.
  ///
  /// In en, this message translates to:
  /// **'Amount unknown.'**
  String get productUnknownAmount;

  /// Ready-mixed product entry or labelled snapshot. Preserve full names, units, explicit unknowns and ownership. Headings use 1–3 words; visible commands use one word.
  ///
  /// In en, this message translates to:
  /// **'Enter the consumed volume in ml. Each ingredient is calculated separately.'**
  String get productVolumeHelp;

  /// Ready-mixed product entry or labelled snapshot. Preserve full names, units, explicit unknowns and ownership. Headings use 1–3 words; visible commands use one word.
  ///
  /// In en, this message translates to:
  /// **'The entered volume stays fixed. The selected container supplies this entry’s ingredient strengths. Future defaults stay unchanged.'**
  String get productFixedVolume;

  /// Ready-mixed product entry or labelled snapshot. Preserve full names, units, explicit unknowns and ownership. Headings use 1–3 words; visible commands use one word.
  ///
  /// In en, this message translates to:
  /// **'Based on the label saved with this entry.'**
  String get productSnapshotHelp;

  /// Ready-mixed product entry or labelled snapshot. Preserve full names, units, explicit unknowns and ownership. Headings use 1–3 words; visible commands use one word.
  ///
  /// In en, this message translates to:
  /// **'No ready-mixed label is saved. Create a label with at least two ingredients.'**
  String get productNoLabel;

  /// Ready-mixed product entry or labelled snapshot. Preserve full names, units, explicit unknowns and ownership. Headings use 1–3 words; visible commands use one word.
  ///
  /// In en, this message translates to:
  /// **'This container keeps its own labelled ingredients. Later product edits leave this container unchanged.'**
  String get productSourceHelp;

  /// Ready-mixed product entry or labelled snapshot. Preserve full names, units, explicit unknowns and ownership. Headings use 1–3 words; visible commands use one word.
  ///
  /// In en, this message translates to:
  /// **'Choose a container with labelled ingredients for this product, or select None.'**
  String get productSourceRequired;

  /// Ready-mixed product entry or labelled snapshot. Preserve full names, units, explicit unknowns and ownership. Headings use 1–3 words; visible commands use one word.
  ///
  /// In en, this message translates to:
  /// **'The labelled ingredients are unavailable. Retry before recording.'**
  String get productUnavailable;

  /// Ready-mixed product entry or labelled snapshot. Preserve full names, units, explicit unknowns and ownership. Headings use 1–3 words; visible commands use one word.
  ///
  /// In en, this message translates to:
  /// **'Concentration unknown ({massUnit}/{volumeUnit}).'**
  String productUnknownStrength(String massUnit, String volumeUnit);

  /// Ready-mixed product entry or labelled snapshot. Preserve full names, units, explicit unknowns and ownership. Headings use 1–3 words; visible commands use one word.
  ///
  /// In en, this message translates to:
  /// **'Label: {amount} {massUnit}/{volumeUnit}.'**
  String productStrengthValue(
    String amount,
    String massUnit,
    String volumeUnit,
  );

  /// Ready-mixed product entry or labelled snapshot. Preserve full names, units, explicit unknowns and ownership. Headings use 1–3 words; visible commands use one word.
  ///
  /// In en, this message translates to:
  /// **'Ingredient {number}'**
  String productIngredientNumber(int number);

  /// Ready-mixed product entry or labelled snapshot. Preserve full names, units, explicit unknowns and ownership. Headings use 1–3 words; visible commands use one word.
  ///
  /// In en, this message translates to:
  /// **'Amount: {amount}.'**
  String productAmountValue(String amount);

  /// Ready-mixed product entry or labelled snapshot. Preserve full names, units, explicit unknowns and ownership. Headings use 1–3 words; visible commands use one word.
  ///
  /// In en, this message translates to:
  /// **'Product volume: {amount}.'**
  String productVolumeValue(String amount);

  /// Ready-mixed product entry or labelled snapshot. Preserve full names, units, explicit unknowns and ownership. Headings use 1–3 words; visible commands use one word.
  ///
  /// In en, this message translates to:
  /// **'Default label'**
  String get productOldLabel;

  /// Ready-mixed product entry or labelled snapshot. Preserve full names, units, explicit unknowns and ownership. Headings use 1–3 words; visible commands use one word.
  ///
  /// In en, this message translates to:
  /// **'Selected label'**
  String get productNewLabel;

  /// Accessible name for a ready-mixed ingredient control. The visible action remains one word.
  ///
  /// In en, this message translates to:
  /// **'Ingredient {number}: {field}'**
  String productFieldContext(int number, String field);

  /// Accessible name for a ready-mixed ingredient control. The visible action remains one word.
  ///
  /// In en, this message translates to:
  /// **'Remove ingredient {number}'**
  String productRemoveContext(int number);

  /// Accessible name for a ready-mixed ingredient control. The visible action remains one word.
  ///
  /// In en, this message translates to:
  /// **'Add ingredient'**
  String get productAddContext;

  /// Calendar schedule editor, validation or preview. Preserve date selection separately from times and recorded use. One-word button labels and plain UK English.
  ///
  /// In en, this message translates to:
  /// **'Dates'**
  String get calendarDates;

  /// Calendar schedule editor, validation or preview. Preserve date selection separately from times and recorded use. One-word button labels and plain UK English.
  ///
  /// In en, this message translates to:
  /// **'Choose the dates separately from the quantity and times.'**
  String get calendarDatesHelp;

  /// Calendar schedule editor, validation or preview. Preserve date selection separately from times and recorded use. One-word button labels and plain UK English.
  ///
  /// In en, this message translates to:
  /// **'Daily'**
  String get calendarDaily;

  /// Calendar schedule editor, validation or preview. Preserve date selection separately from times and recorded use. One-word button labels and plain UK English.
  ///
  /// In en, this message translates to:
  /// **'Weekdays'**
  String get calendarWeekdays;

  /// Calendar schedule editor, validation or preview. Preserve date selection separately from times and recorded use. One-word button labels and plain UK English.
  ///
  /// In en, this message translates to:
  /// **'Days'**
  String get calendarDays;

  /// Calendar schedule editor, validation or preview. Preserve date selection separately from times and recorded use. One-word button labels and plain UK English.
  ///
  /// In en, this message translates to:
  /// **'Weeks'**
  String get calendarWeeks;

  /// Calendar schedule editor, validation or preview. Preserve date selection separately from times and recorded use. One-word button labels and plain UK English.
  ///
  /// In en, this message translates to:
  /// **'Months'**
  String get calendarMonths;

  /// Calendar schedule editor, validation or preview. Preserve date selection separately from times and recorded use. One-word button labels and plain UK English.
  ///
  /// In en, this message translates to:
  /// **'Monday'**
  String get calendarMonday;

  /// Calendar schedule editor, validation or preview. Preserve date selection separately from times and recorded use. One-word button labels and plain UK English.
  ///
  /// In en, this message translates to:
  /// **'Tuesday'**
  String get calendarTuesday;

  /// Calendar schedule editor, validation or preview. Preserve date selection separately from times and recorded use. One-word button labels and plain UK English.
  ///
  /// In en, this message translates to:
  /// **'Wednesday'**
  String get calendarWednesday;

  /// Calendar schedule editor, validation or preview. Preserve date selection separately from times and recorded use. One-word button labels and plain UK English.
  ///
  /// In en, this message translates to:
  /// **'Thursday'**
  String get calendarThursday;

  /// Calendar schedule editor, validation or preview. Preserve date selection separately from times and recorded use. One-word button labels and plain UK English.
  ///
  /// In en, this message translates to:
  /// **'Friday'**
  String get calendarFriday;

  /// Calendar schedule editor, validation or preview. Preserve date selection separately from times and recorded use. One-word button labels and plain UK English.
  ///
  /// In en, this message translates to:
  /// **'Saturday'**
  String get calendarSaturday;

  /// Calendar schedule editor, validation or preview. Preserve date selection separately from times and recorded use. One-word button labels and plain UK English.
  ///
  /// In en, this message translates to:
  /// **'Sunday'**
  String get calendarSunday;

  /// Calendar schedule editor, validation or preview. Preserve date selection separately from times and recorded use. One-word button labels and plain UK English.
  ///
  /// In en, this message translates to:
  /// **'Every N days'**
  String get calendarDayInterval;

  /// Calendar schedule editor, validation or preview. Preserve date selection separately from times and recorded use. One-word button labels and plain UK English.
  ///
  /// In en, this message translates to:
  /// **'Every N weeks'**
  String get calendarWeekInterval;

  /// Calendar schedule editor, validation or preview. Preserve date selection separately from times and recorded use. One-word button labels and plain UK English.
  ///
  /// In en, this message translates to:
  /// **'Every N months'**
  String get calendarMonthInterval;

  /// Calendar schedule editor, validation or preview. Preserve date selection separately from times and recorded use. One-word button labels and plain UK English.
  ///
  /// In en, this message translates to:
  /// **'Enter a positive whole number. Calendar days keep their local dates across clock changes.'**
  String get calendarIntervalHelp;

  /// Calendar schedule editor, validation or preview. Preserve date selection separately from times and recorded use. One-word button labels and plain UK English.
  ///
  /// In en, this message translates to:
  /// **'Enter a positive whole number. Use 12 for a yearly pattern.'**
  String get calendarYearHelp;

  /// Calendar schedule editor, validation or preview. Preserve date selection separately from times and recorded use. One-word button labels and plain UK English.
  ///
  /// In en, this message translates to:
  /// **'First anchor date'**
  String get calendarAnchor;

  /// Calendar schedule editor, validation or preview. Preserve date selection separately from times and recorded use. One-word button labels and plain UK English.
  ///
  /// In en, this message translates to:
  /// **'Anchor week start'**
  String get calendarWeekAnchor;

  /// Calendar schedule editor, validation or preview. Preserve date selection separately from times and recorded use. One-word button labels and plain UK English.
  ///
  /// In en, this message translates to:
  /// **'Anchor month'**
  String get calendarMonthAnchor;

  /// Calendar schedule editor, validation or preview. Preserve date selection separately from times and recorded use. One-word button labels and plain UK English.
  ///
  /// In en, this message translates to:
  /// **'YYYY-MM-DD. This saved date starts the first week. Selected weekdays repeat from this week, regardless of display preferences.'**
  String get calendarWeekHelp;

  /// Calendar schedule editor, validation or preview. Preserve date selection separately from times and recorded use. One-word button labels and plain UK English.
  ///
  /// In en, this message translates to:
  /// **'YYYY-MM-DD. Any date in the first eligible month. The nominal day below stays separate from the effective start.'**
  String get calendarMonthHelp;

  /// Calendar schedule editor, validation or preview. Preserve date selection separately from times and recorded use. One-word button labels and plain UK English.
  ///
  /// In en, this message translates to:
  /// **'Choose at least one weekday.'**
  String get calendarSelectWeekdays;

  /// Calendar schedule editor, validation or preview. Preserve date selection separately from times and recorded use. One-word button labels and plain UK English.
  ///
  /// In en, this message translates to:
  /// **'Monthly rule'**
  String get calendarMonthRule;

  /// Calendar schedule editor, validation or preview. Preserve date selection separately from times and recorded use. One-word button labels and plain UK English.
  ///
  /// In en, this message translates to:
  /// **'Date'**
  String get calendarDate;

  /// Calendar schedule editor, validation or preview. Preserve date selection separately from times and recorded use. One-word button labels and plain UK English.
  ///
  /// In en, this message translates to:
  /// **'Ordinal'**
  String get calendarOrdinal;

  /// Calendar schedule editor, validation or preview. Preserve date selection separately from times and recorded use. One-word button labels and plain UK English.
  ///
  /// In en, this message translates to:
  /// **'Last'**
  String get calendarLast;

  /// Calendar schedule editor, validation or preview. Preserve date selection separately from times and recorded use. One-word button labels and plain UK English.
  ///
  /// In en, this message translates to:
  /// **'Day of month'**
  String get calendarNominalDay;

  /// Calendar schedule editor, validation or preview. Preserve date selection separately from times and recorded use. One-word button labels and plain UK English.
  ///
  /// In en, this message translates to:
  /// **'Enter 1 to 31. This nominal day stays the same after a short month.'**
  String get calendarNominalHelp;

  /// Calendar schedule editor, validation or preview. Preserve date selection separately from times and recorded use. One-word button labels and plain UK English.
  ///
  /// In en, this message translates to:
  /// **'Weekday occurrence'**
  String get calendarOrdinalNumber;

  /// Calendar schedule editor, validation or preview. Preserve date selection separately from times and recorded use. One-word button labels and plain UK English.
  ///
  /// In en, this message translates to:
  /// **'Weekday'**
  String get calendarWeekday;

  /// Calendar schedule editor, validation or preview. Preserve date selection separately from times and recorded use. One-word button labels and plain UK English.
  ///
  /// In en, this message translates to:
  /// **'Missing dates'**
  String get calendarMissing;

  /// Calendar schedule editor, validation or preview. Preserve date selection separately from times and recorded use. One-word button labels and plain UK English.
  ///
  /// In en, this message translates to:
  /// **'Omit creates no planned dose when the day is missing. Use chooses that month’s last day, then returns to the nominal day.'**
  String get calendarMissingDayHelp;

  /// Calendar schedule editor, validation or preview. Preserve date selection separately from times and recorded use. One-word button labels and plain UK English.
  ///
  /// In en, this message translates to:
  /// **'Omit creates no planned dose when this weekday occurrence is missing. Use chooses the last matching weekday in that month.'**
  String get calendarMissingWeekHelp;

  /// Calendar schedule editor, validation or preview. Preserve date selection separately from times and recorded use. One-word button labels and plain UK English.
  ///
  /// In en, this message translates to:
  /// **'Omit'**
  String get calendarOmit;

  /// Calendar schedule editor, validation or preview. Preserve date selection separately from times and recorded use. One-word button labels and plain UK English.
  ///
  /// In en, this message translates to:
  /// **'Use'**
  String get calendarUse;

  /// Calendar schedule editor, validation or preview. Preserve date selection separately from times and recorded use. One-word button labels and plain UK English.
  ///
  /// In en, this message translates to:
  /// **'Choose Omit or Use for months without the selected date.'**
  String get calendarMissingRequired;

  /// Calendar schedule editor, validation or preview. Preserve date selection separately from times and recorded use. One-word button labels and plain UK English.
  ///
  /// In en, this message translates to:
  /// **'Check the calendar dates, positive interval and selected weekdays, then preview again.'**
  String get calendarInvalid;

  /// Calendar schedule editor, validation or preview. Preserve date selection separately from times and recorded use. One-word button labels and plain UK English.
  ///
  /// In en, this message translates to:
  /// **'This calendar combination is unsupported. Choose a supported date pattern before saving.'**
  String get calendarUnsupported;

  /// Calendar schedule editor, validation or preview. Preserve date selection separately from times and recorded use. One-word button labels and plain UK English.
  ///
  /// In en, this message translates to:
  /// **'Anchor week: {from} to {to}. This saved week fixes the repeat pattern.'**
  String calendarAnchorPreview(String from, String to);

  /// Calendar schedule editor, validation or preview. Preserve date selection separately from times and recorded use. One-word button labels and plain UK English.
  ///
  /// In en, this message translates to:
  /// **'{month}: nominal day {day} does not exist.'**
  String calendarBoundaryDay(String month, int day);

  /// Calendar schedule editor, validation or preview. Preserve date selection separately from times and recorded use. One-word button labels and plain UK English.
  ///
  /// In en, this message translates to:
  /// **'{month}: occurrence {ordinal} of {weekday} does not exist.'**
  String calendarBoundaryWeekday(String month, int ordinal, String weekday);

  /// Calendar schedule editor, validation or preview. Preserve date selection separately from times and recorded use. One-word button labels and plain UK English.
  ///
  /// In en, this message translates to:
  /// **'No dose is planned for this missing date. No Skip is recorded.'**
  String get calendarBoundaryOmitted;

  /// Calendar schedule editor, validation or preview. Preserve date selection separately from times and recorded use. One-word button labels and plain UK English.
  ///
  /// In en, this message translates to:
  /// **'The planned date is {date}.'**
  String calendarBoundaryUse(String date);

  /// Calendar schedule editor, validation or preview. Preserve date selection separately from times and recorded use. One-word button labels and plain UK English.
  ///
  /// In en, this message translates to:
  /// **'Next selected date: {date}. The nominal rule stays unchanged.'**
  String calendarBoundaryNext(String date);

  /// Calendar schedule editor, validation or preview. Preserve date selection separately from times and recorded use. One-word button labels and plain UK English.
  ///
  /// In en, this message translates to:
  /// **'Next calendar date: {date}. Its time cannot be converted with the available timezone rules.'**
  String calendarKnownDate(String date);

  /// Calendar schedule editor, validation or preview. Preserve date selection separately from times and recorded use. One-word button labels and plain UK English.
  ///
  /// In en, this message translates to:
  /// **'This next date is beyond the preview range. Reminder preparation uses a separate range.'**
  String get calendarBeyondPreview;

  /// Calendar schedule editor, validation or preview. Preserve date selection separately from times and recorded use. One-word button labels and plain UK English.
  ///
  /// In en, this message translates to:
  /// **'The first missing-date boundary could not be established within the calculation range.'**
  String get calendarBoundaryLimit;

  /// Explanation of the monthly ordinal weekday selector. The number is an occurrence within a month, not a dose count.
  ///
  /// In en, this message translates to:
  /// **'Choose 1 for the first matching weekday, 2 for the second, and so on.'**
  String get calendarOrdinalHelp;

  /// No description provided for @intervalPattern.
  ///
  /// In en, this message translates to:
  /// **'Interval'**
  String get intervalPattern;

  /// No description provided for @intervalBasis.
  ///
  /// In en, this message translates to:
  /// **'Interval anchor'**
  String get intervalBasis;

  /// No description provided for @intervalFixed.
  ///
  /// In en, this message translates to:
  /// **'Planned'**
  String get intervalFixed;

  /// No description provided for @intervalActual.
  ///
  /// In en, this message translates to:
  /// **'Recorded'**
  String get intervalActual;

  /// No description provided for @intervalFixedHelp.
  ///
  /// In en, this message translates to:
  /// **'Keep the entered planned anchor. Recorded doses do not move this interval.'**
  String get intervalFixedHelp;

  /// No description provided for @intervalActualHelp.
  ///
  /// In en, this message translates to:
  /// **'Use the latest qualifying recorded time for this plan. Extra doses do not qualify automatically.'**
  String get intervalActualHelp;

  /// No description provided for @intervalDuration.
  ///
  /// In en, this message translates to:
  /// **'Elapsed hours'**
  String get intervalDuration;

  /// No description provided for @intervalDurationHelp.
  ///
  /// In en, this message translates to:
  /// **'Enter a positive number of hours, for example 6 or 1.5.'**
  String get intervalDurationHelp;

  /// No description provided for @intervalAnchor.
  ///
  /// In en, this message translates to:
  /// **'Planned instant'**
  String get intervalAnchor;

  /// No description provided for @intervalAnchorHelp.
  ///
  /// In en, this message translates to:
  /// **'Enter a date and time with its UTC offset, for example 2026-10-19T08:00:00+01:00. Use Z for UTC.'**
  String get intervalAnchorHelp;

  /// No description provided for @intervalNoAnchor.
  ///
  /// In en, this message translates to:
  /// **'No qualifying dose'**
  String get intervalNoAnchor;

  /// No description provided for @intervalNoAnchorHelp.
  ///
  /// In en, this message translates to:
  /// **'Record a dose, then review whether it qualifies for this plan.'**
  String get intervalNoAnchorHelp;

  /// No description provided for @intervalNext.
  ///
  /// In en, this message translates to:
  /// **'Next planned instant: {instant}'**
  String intervalNext(String instant);

  /// No description provided for @intervalReview.
  ///
  /// In en, this message translates to:
  /// **'Next time'**
  String get intervalReview;

  /// No description provided for @intervalBefore.
  ///
  /// In en, this message translates to:
  /// **'Before: {value}'**
  String intervalBefore(String value);

  /// No description provided for @intervalAfter.
  ///
  /// In en, this message translates to:
  /// **'After: {value}'**
  String intervalAfter(String value);

  /// No description provided for @intervalQualify.
  ///
  /// In en, this message translates to:
  /// **'Qualifying dose'**
  String get intervalQualify;

  /// No description provided for @intervalQualifyHelp.
  ///
  /// In en, this message translates to:
  /// **'Select this recorded dose as a possible anchor for this plan. Review the resulting next time before saving.'**
  String get intervalQualifyHelp;

  /// No description provided for @intervalExtraHelp.
  ///
  /// In en, this message translates to:
  /// **'Extra doses do not change this interval unless you select them explicitly.'**
  String get intervalExtraHelp;

  /// No description provided for @intervalTakenHelp.
  ///
  /// In en, this message translates to:
  /// **'Taken qualifies this dose for the plan. The latest qualifying recorded time sets the next time.'**
  String get intervalTakenHelp;

  /// No description provided for @intervalFuture.
  ///
  /// In en, this message translates to:
  /// **'Choose a recorded time that has already happened before setting the next time.'**
  String get intervalFuture;

  /// No description provided for @intervalDurationValue.
  ///
  /// In en, this message translates to:
  /// **'Every {hours} elapsed hours'**
  String intervalDurationValue(String hours);

  /// No description provided for @intervalQualified.
  ///
  /// In en, this message translates to:
  /// **'This dose qualifies for this plan. The latest qualifying recorded time sets the next time.'**
  String get intervalQualified;

  /// No description provided for @select.
  ///
  /// In en, this message translates to:
  /// **'Select'**
  String get select;

  /// No description provided for @intervalPlan.
  ///
  /// In en, this message translates to:
  /// **'Plan from {date}: every {hours} elapsed hours'**
  String intervalPlan(String date, String hours);

  /// No description provided for @intervalSourceRevision.
  ///
  /// In en, this message translates to:
  /// **'Recorded dose revision: {revision}'**
  String intervalSourceRevision(int revision);

  /// No description provided for @intervalEditHelp.
  ///
  /// In en, this message translates to:
  /// **'Changing the interval or anchor starts a new segment. Recorded intervals then need a qualifying dose.'**
  String get intervalEditHelp;

  /// No description provided for @intervalInputInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter positive elapsed hours, an amount and valid dates. A planned anchor needs an explicit time zone offset.'**
  String get intervalInputInvalid;

  /// No description provided for @intervalRecordedTime.
  ///
  /// In en, this message translates to:
  /// **'Recorded instant: {instant}'**
  String intervalRecordedTime(String instant);

  /// No description provided for @intervalProposedAmount.
  ///
  /// In en, this message translates to:
  /// **'New amount: {amount} {unit}'**
  String intervalProposedAmount(String amount, String unit);

  /// No description provided for @intervalAnchorRevision.
  ///
  /// In en, this message translates to:
  /// **'Anchor dose revision: {revision}'**
  String intervalAnchorRevision(int revision);

  /// No description provided for @intervalClockHeading.
  ///
  /// In en, this message translates to:
  /// **'Review timing'**
  String get intervalClockHeading;

  /// No description provided for @intervalClockHelp.
  ///
  /// In en, this message translates to:
  /// **'Interval reminders need a timing review after a restart or clock change. Open this plan in Today to review recovery.'**
  String get intervalClockHelp;

  /// No description provided for @intervalClockStopped.
  ///
  /// In en, this message translates to:
  /// **'Interval reminders stopped'**
  String get intervalClockStopped;

  /// No description provided for @intervalClockReview.
  ///
  /// In en, this message translates to:
  /// **'Use the current device clock from {date}. Keep recorded anchors and history. Earlier reminders will not be replayed.'**
  String intervalClockReview(String date);

  /// No description provided for @intervalEarlierReview.
  ///
  /// In en, this message translates to:
  /// **'This time does not follow the current anchor. Record the dose separately, then review whether it qualifies for this plan.'**
  String get intervalEarlierReview;

  /// No description provided for @pauseHeading.
  ///
  /// In en, this message translates to:
  /// **'Pause plan'**
  String get pauseHeading;

  /// No description provided for @pauseResume.
  ///
  /// In en, this message translates to:
  /// **'Resume plan'**
  String get pauseResume;

  /// No description provided for @pauseBlocks.
  ///
  /// In en, this message translates to:
  /// **'Repeating breaks'**
  String get pauseBlocks;

  /// No description provided for @pauseContinuous.
  ///
  /// In en, this message translates to:
  /// **'Continuous'**
  String get pauseContinuous;

  /// No description provided for @pauseOnDays.
  ///
  /// In en, this message translates to:
  /// **'Active days'**
  String get pauseOnDays;

  /// No description provided for @pauseOffDays.
  ///
  /// In en, this message translates to:
  /// **'Break days'**
  String get pauseOffDays;

  /// No description provided for @pauseOffHelp.
  ///
  /// In en, this message translates to:
  /// **'Enter whole days. Zero break days keeps the plan continuous.'**
  String get pauseOffHelp;

  /// No description provided for @pauseBlockAnchor.
  ///
  /// In en, this message translates to:
  /// **'First active date'**
  String get pauseBlockAnchor;

  /// No description provided for @pauseIntersection.
  ///
  /// In en, this message translates to:
  /// **'A date must match both the chosen calendar dates and the active block. Elapsed intervals keep their original instants.'**
  String get pauseIntersection;

  /// No description provided for @pauseConsequence.
  ///
  /// In en, this message translates to:
  /// **'Pausing stops planned opportunities and reminders. Recorded doses and stock history stay unchanged.'**
  String get pauseConsequence;

  /// No description provided for @pauseStart.
  ///
  /// In en, this message translates to:
  /// **'Pause instant'**
  String get pauseStart;

  /// No description provided for @pauseResumeAt.
  ///
  /// In en, this message translates to:
  /// **'Resume instant'**
  String get pauseResumeAt;

  /// No description provided for @pauseChoice.
  ///
  /// In en, this message translates to:
  /// **'Choose how the pattern resumes.'**
  String get pauseChoice;

  /// No description provided for @pausePreserve.
  ///
  /// In en, this message translates to:
  /// **'Preserve'**
  String get pausePreserve;

  /// No description provided for @pauseRestart.
  ///
  /// In en, this message translates to:
  /// **'Restart'**
  String get pauseRestart;

  /// No description provided for @pausePreserveHelp.
  ///
  /// In en, this message translates to:
  /// **'Keep the original dates and interval starting point. Time continues through the pause.'**
  String get pausePreserveHelp;

  /// No description provided for @pauseRestartHelp.
  ///
  /// In en, this message translates to:
  /// **'Start a new pattern from the date or instant you enter. The plan end stays unchanged.'**
  String get pauseRestartHelp;

  /// No description provided for @pauseNewAnchor.
  ///
  /// In en, this message translates to:
  /// **'New first date'**
  String get pauseNewAnchor;

  /// No description provided for @pauseDateHelp.
  ///
  /// In en, this message translates to:
  /// **'Enter YYYY-MM-DD. Weekly patterns need a Monday; monthly patterns need the first of a month.'**
  String get pauseDateHelp;

  /// No description provided for @pauseActualHelp.
  ///
  /// In en, this message translates to:
  /// **'A paused next dose stays suppressed. Review a qualifying recorded dose or edit the timing basis to use a planned starting point. Resuming creates no dose.'**
  String get pauseActualHelp;

  /// No description provided for @pauseInvalid.
  ///
  /// In en, this message translates to:
  /// **'Choose Preserve or Restart when resuming. Enter a valid instant with its UTC offset and any required new anchor.'**
  String get pauseInvalid;

  /// No description provided for @pauseHistory.
  ///
  /// In en, this message translates to:
  /// **'Pause history'**
  String get pauseHistory;

  /// No description provided for @pauseHistoryHelp.
  ///
  /// In en, this message translates to:
  /// **'Recorded pause periods describe the plan. They do not prove doses were taken.'**
  String get pauseHistoryHelp;

  /// No description provided for @pauseNoHistory.
  ///
  /// In en, this message translates to:
  /// **'No recorded pauses.'**
  String get pauseNoHistory;

  /// No description provided for @pauseOngoing.
  ///
  /// In en, this message translates to:
  /// **'Ongoing'**
  String get pauseOngoing;

  /// No description provided for @pauseState.
  ///
  /// In en, this message translates to:
  /// **'Paused'**
  String get pauseState;

  /// No description provided for @pauseRecordHelp.
  ///
  /// In en, this message translates to:
  /// **'Record actual use separately while this plan is paused.'**
  String get pauseRecordHelp;

  /// Pause or repeating block review. Periods describe recorded plan history, not actual intake.
  ///
  /// In en, this message translates to:
  /// **'Before: {value}'**
  String pauseBefore(String value);

  /// Pause or repeating block review. Periods describe recorded plan history, not actual intake.
  ///
  /// In en, this message translates to:
  /// **'After: {value}'**
  String pauseAfter(String value);

  /// Pause or repeating block review. Periods describe recorded plan history, not actual intake.
  ///
  /// In en, this message translates to:
  /// **'First affected boundary: {value}'**
  String pauseBoundary(String value);

  /// Pause or repeating block review. Periods describe recorded plan history, not actual intake.
  ///
  /// In en, this message translates to:
  /// **'Recorded pause: {start} to {resume}'**
  String pausePeriod(String start, String resume);

  /// Pause or repeating block review. Periods describe recorded plan history, not actual intake.
  ///
  /// In en, this message translates to:
  /// **'Recorded pause duration: {minutes} complete minutes. This is not a count of doses taken.'**
  String pauseDuration(int minutes);

  /// Pause or repeating block review. Periods describe recorded plan history, not actual intake.
  ///
  /// In en, this message translates to:
  /// **'{active} active days, {rest} break days, starting on {anchor}.'**
  String pauseBlockSummary(int active, int rest, String anchor);

  /// No description provided for @pauseAction.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get pauseAction;

  /// Phase and exception scheduling interface. Full identities and units must remain visible.
  ///
  /// In en, this message translates to:
  /// **'Phases'**
  String get phaseHeading;

  /// Phase and exception scheduling interface. Full identities and units must remain visible.
  ///
  /// In en, this message translates to:
  /// **'Partly timed'**
  String get phaseMixed;

  /// Phase and exception scheduling interface. Full identities and units must remain visible.
  ///
  /// In en, this message translates to:
  /// **'Time windows'**
  String get phaseWindows;

  /// Phase and exception scheduling interface. Full identities and units must remain visible.
  ///
  /// In en, this message translates to:
  /// **'The total includes the chosen times and an untimed remainder. Enter more total doses than chosen times.'**
  String get phaseMixedHelp;

  /// Phase and exception scheduling interface. Full identities and units must remain visible.
  ///
  /// In en, this message translates to:
  /// **'A window belongs to its start date. An end before its start falls on the next day. Actual use is recorded separately.'**
  String get phaseWindowHelp;

  /// Phase and exception scheduling interface. Full identities and units must remain visible.
  ///
  /// In en, this message translates to:
  /// **'Window start'**
  String get phaseWindowStart;

  /// Phase and exception scheduling interface. Full identities and units must remain visible.
  ///
  /// In en, this message translates to:
  /// **'Window end'**
  String get phaseWindowEnd;

  /// Phase and exception scheduling interface. Full identities and units must remain visible.
  ///
  /// In en, this message translates to:
  /// **'Use HH:MM. Both endpoints are kept.'**
  String get phaseWindowEndHelp;

  /// Phase and exception scheduling interface. Full identities and units must remain visible.
  ///
  /// In en, this message translates to:
  /// **'Reminder time'**
  String get phaseWindowAnchor;

  /// Phase and exception scheduling interface. Full identities and units must remain visible.
  ///
  /// In en, this message translates to:
  /// **'Optional HH:MM inside the window. This is an alert time, not a recorded dose.'**
  String get phaseWindowAnchorHelp;

  /// Phase and exception scheduling interface. Full identities and units must remain visible.
  ///
  /// In en, this message translates to:
  /// **'No reminder time'**
  String get phaseNoAnchor;

  /// Phase and exception scheduling interface. Full identities and units must remain visible.
  ///
  /// In en, this message translates to:
  /// **'{date}: {start} to {end}, {amount} {unit}. Reminder: {anchor}. Zone: {zone}.'**
  String phaseWindowSummary(
    String date,
    String start,
    String end,
    String amount,
    String unit,
    String anchor,
    String zone,
  );

  /// Phase and exception scheduling interface. Full identities and units must remain visible.
  ///
  /// In en, this message translates to:
  /// **'Original: {original}, {oldAmount} {oldUnit}. Changed: {effective}, {amount} {unit}.'**
  String phaseOverrideSummary(
    String original,
    String oldAmount,
    String oldUnit,
    String effective,
    String amount,
    String unit,
  );

  /// Phase and exception scheduling interface. Full identities and units must remain visible.
  ///
  /// In en, this message translates to:
  /// **'Enter each phase yourself. Gaps have no planned doses. Existing recorded doses keep their original meaning.'**
  String get phaseHelp;

  /// Phase and exception scheduling interface. Full identities and units must remain visible.
  ///
  /// In en, this message translates to:
  /// **'Plan end'**
  String get phaseEndHeading;

  /// Phase and exception scheduling interface. Full identities and units must remain visible.
  ///
  /// In en, this message translates to:
  /// **'Open ended'**
  String get phaseNoEnd;

  /// Phase and exception scheduling interface. Full identities and units must remain visible.
  ///
  /// In en, this message translates to:
  /// **'Last day'**
  String get phaseDateEnd;

  /// Phase and exception scheduling interface. Full identities and units must remain visible.
  ///
  /// In en, this message translates to:
  /// **'Exact end'**
  String get phaseExactEnd;

  /// Phase and exception scheduling interface. Full identities and units must remain visible.
  ///
  /// In en, this message translates to:
  /// **'End zone'**
  String get phaseEndZone;

  /// Phase and exception scheduling interface. Full identities and units must remain visible.
  ///
  /// In en, this message translates to:
  /// **'The last day includes the whole day in this saved zone. An exact end excludes that instant. Choose an exact end if midnight needs a clock choice.'**
  String get phaseEndHelp;

  /// Phase and exception scheduling interface. Full identities and units must remain visible.
  ///
  /// In en, this message translates to:
  /// **'Use a date, time and UTC or numerical offset.'**
  String get phaseExactHelp;

  /// Phase and exception scheduling interface. Full identities and units must remain visible.
  ///
  /// In en, this message translates to:
  /// **'Phase start'**
  String get phaseStart;

  /// Phase and exception scheduling interface. Full identities and units must remain visible.
  ///
  /// In en, this message translates to:
  /// **'Phase last day'**
  String get phaseLast;

  /// Phase and exception scheduling interface. Full identities and units must remain visible.
  ///
  /// In en, this message translates to:
  /// **'First boundary: {value}.'**
  String phaseBoundary(String value);

  /// Phase and exception scheduling interface. Full identities and units must remain visible.
  ///
  /// In en, this message translates to:
  /// **'Gap: {start} to {end}. No doses are planned in this range.'**
  String phaseGap(String start, String end);

  /// Phase and exception scheduling interface. Full identities and units must remain visible.
  ///
  /// In en, this message translates to:
  /// **'Check phase dates, amounts and timing. Phases must not overlap. Review each entered endpoint and plan end.'**
  String get phaseInvalid;

  /// Phase and exception scheduling interface. Full identities and units must remain visible.
  ///
  /// In en, this message translates to:
  /// **'One-off change'**
  String get phaseChangeHeading;

  /// Phase and exception scheduling interface. Full identities and units must remain visible.
  ///
  /// In en, this message translates to:
  /// **'Choose the original dose by its date and identity. Moving keeps its original amount unless you enter a replacement amount.'**
  String get phaseChangeHelp;

  /// Phase and exception scheduling interface. Full identities and units must remain visible.
  ///
  /// In en, this message translates to:
  /// **'Original date'**
  String get phaseOriginalDate;

  /// Phase and exception scheduling interface. Full identities and units must remain visible.
  ///
  /// In en, this message translates to:
  /// **'New time'**
  String get phaseTarget;

  /// Phase and exception scheduling interface. Full identities and units must remain visible.
  ///
  /// In en, this message translates to:
  /// **'Optional date, time and offset. Leave empty to keep the original time.'**
  String get phaseTargetHelp;

  /// Phase and exception scheduling interface. Full identities and units must remain visible.
  ///
  /// In en, this message translates to:
  /// **'New amount'**
  String get phaseAmount;

  /// Phase and exception scheduling interface. Full identities and units must remain visible.
  ///
  /// In en, this message translates to:
  /// **'Optional. Leave empty to keep the original amount and unit.'**
  String get phaseAmountHelp;

  /// Phase and exception scheduling interface. Full identities and units must remain visible.
  ///
  /// In en, this message translates to:
  /// **'Before: {value}'**
  String phaseBefore(String value);

  /// Phase and exception scheduling interface. Full identities and units must remain visible.
  ///
  /// In en, this message translates to:
  /// **'After: {value}'**
  String phaseAfter(String value);

  /// Phase and exception scheduling interface. Full identities and units must remain visible.
  ///
  /// In en, this message translates to:
  /// **'Plan end: {value}. Saved zone: {zone}.'**
  String phaseEndSummary(String value, String zone);

  /// Phase and exception scheduling interface. Full identities and units must remain visible.
  ///
  /// In en, this message translates to:
  /// **'Separate doses share this time. Review each identity before saving. This does not combine the doses.'**
  String get phaseCollision;

  /// Phase and exception scheduling interface. Full identities and units must remain visible.
  ///
  /// In en, this message translates to:
  /// **'Dose identity: {value}'**
  String phaseCollisionLabel(String value);

  /// Phase and exception scheduling interface. Full identities and units must remain visible.
  ///
  /// In en, this message translates to:
  /// **'Phases and one-off changes retain their original dose identities. Actual use remains separate.'**
  String get phaseSavedHelp;

  /// Phase and exception scheduling interface. Full identities and units must remain visible.
  ///
  /// In en, this message translates to:
  /// **'Removing a phase changes future expectations. Review the resulting plan before saving.'**
  String get phaseRemoveHelp;

  /// Phase and exception scheduling interface. Full identities and units must remain visible.
  ///
  /// In en, this message translates to:
  /// **'Choose an original dose before adding a one-off change.'**
  String get phaseNotSelected;

  /// Phase and exception scheduling interface. Full identities and units must remain visible.
  ///
  /// In en, this message translates to:
  /// **'This change crosses a pause, end or unresolved clock boundary. Choose valid timing or review the plan boundary.'**
  String get phaseReviewIssue;

  /// Phase and exception scheduling interface. Full identities and units must remain visible.
  ///
  /// In en, this message translates to:
  /// **'Original identity: {value}'**
  String phaseSource(String value);

  /// Phase and exception scheduling interface. Full identities and units must remain visible.
  ///
  /// In en, this message translates to:
  /// **'Review the complete amounts and first boundary before saving. Cancel clears this review and changes nothing.'**
  String get phaseReviewHelp;

  /// Explicit one-off window target, no duration or reminder assumption.
  ///
  /// In en, this message translates to:
  /// **'Enter the full reminder date, time and offset if alerts are enabled. Both endpoints must be entered when moving a window.'**
  String get phaseWindowMoveHelp;

  /// Full original window endpoint requiring a clock choice.
  ///
  /// In en, this message translates to:
  /// **'Window endpoint: {value}'**
  String phaseEndpoint(String value);

  /// Original and effective full window endpoints, explicit reminder anchor and amounts.
  ///
  /// In en, this message translates to:
  /// **'Original window: {originalStart} to {originalEnd}, reminder {originalAnchor}, {oldAmount} {oldUnit}. Changed window: {start} to {end}, reminder {anchor}, {amount} {unit}. Zone: {zone}.'**
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
  );

  /// Full manually entered phase summary; never generated advice.
  ///
  /// In en, this message translates to:
  /// **'{count} doses each planned day, {amount} {unit} each. No chosen times.'**
  String phaseCountSummary(String count, String amount, String unit);

  /// Full manually entered phase summary; never generated advice.
  ///
  /// In en, this message translates to:
  /// **'{count} doses each planned day. {timed} have chosen times. The untimed doses use {amount} {unit} each.'**
  String phaseMixedSummary(
    String count,
    String timed,
    String amount,
    String unit,
  );

  /// Full manually entered phase summary; never generated advice.
  ///
  /// In en, this message translates to:
  /// **'Chosen time: {time}, {amount} {unit}.'**
  String phaseSlotSummary(String time, String amount, String unit);

  /// Full manually entered phase summary; never generated advice.
  ///
  /// In en, this message translates to:
  /// **'Window: {start} to {end}, {amount} {unit}. Reminder time: {anchor}.'**
  String phaseWindowEntered(
    String start,
    String end,
    String amount,
    String unit,
    String anchor,
  );

  /// Full manually entered phase summary; never generated advice.
  ///
  /// In en, this message translates to:
  /// **'Every {hours} elapsed hours, {amount} {unit}.'**
  String phaseIntervalSummary(String hours, String amount, String unit);

  /// Full manually entered phase summary; never generated advice.
  ///
  /// In en, this message translates to:
  /// **'Reviewed'**
  String get phaseReviewed;

  /// Full manually entered phase summary; never generated advice.
  ///
  /// In en, this message translates to:
  /// **'Starts at {instant}.'**
  String phaseFrom(String instant);

  /// Full manually entered phase summary; never generated advice.
  ///
  /// In en, this message translates to:
  /// **'Ends before {instant}.'**
  String phaseUntil(String instant);

  /// How to preserve an already active phase while entering future changes.
  ///
  /// In en, this message translates to:
  /// **'To change an active phase, enter its last day and add a new phase. Earlier recorded doses stay unchanged.'**
  String get phaseEditHelp;

  /// Explicit window endpoint identity and clock review.
  ///
  /// In en, this message translates to:
  /// **'{label}: {date} at {time}, {zone}.'**
  String phaseEndpointLabel(
    String label,
    String date,
    String time,
    String zone,
  );

  /// Explicit window endpoint identity and clock review.
  ///
  /// In en, this message translates to:
  /// **'Window: {startDate} at {start} to {endDate} at {end}, {amount} {unit}. Review endpoint clocks in {zone}.'**
  String phaseWindowPending(
    String startDate,
    String start,
    String endDate,
    String end,
    String amount,
    String unit,
    String zone,
  );

  /// A multi-opportunity daily bucket has no individual planned dose identity. Offer Edit and Record instead of a bucket-wide one-off override.
  ///
  /// In en, this message translates to:
  /// **'This group has {count} untimed doses. Edit the shared plan amount, or record an individual dose with its actual amount.'**
  String phaseBucketHelp(int count);

  /// Count-one amount-only exception. Do not invent an exact time.
  ///
  /// In en, this message translates to:
  /// **'This dose has no chosen time. Enter a new amount, or record actual use separately.'**
  String get phaseSingleCount;

  /// Combined recording or optional site context. Fixed adult ownership, exact independent source amounts and explicit stock consequences.
  ///
  /// In en, this message translates to:
  /// **'Combined entry'**
  String get combinedHeading;

  /// Combined recording or optional site context. Fixed adult ownership, exact independent source amounts and explicit stock consequences.
  ///
  /// In en, this message translates to:
  /// **'Record several sources for one person at the same time. Review each amount and stock effect before saving.'**
  String get combinedHelp;

  /// Combined recording or optional site context. Fixed adult ownership, exact independent source amounts and explicit stock consequences.
  ///
  /// In en, this message translates to:
  /// **'Combine'**
  String get combinedAction;

  /// Combined recording or optional site context. Fixed adult ownership, exact independent source amounts and explicit stock consequences.
  ///
  /// In en, this message translates to:
  /// **'Add source'**
  String get combinedAdd;

  /// Combined recording or optional site context. Fixed adult ownership, exact independent source amounts and explicit stock consequences.
  ///
  /// In en, this message translates to:
  /// **'Choose 2 to 16 sources. Each source keeps its own amount and stock effect.'**
  String get combinedCount;

  /// A combined-entry source label could not be read. The open chooser lets the person select the same source again.
  ///
  /// In en, this message translates to:
  /// **'The source could not be loaded. Choose it again.'**
  String get combinedSourceLoadFailure;

  /// Combined recording or optional site context. Fixed adult ownership, exact independent source amounts and explicit stock consequences.
  ///
  /// In en, this message translates to:
  /// **'Review entry'**
  String get combinedReview;

  /// Combined recording or optional site context. Fixed adult ownership, exact independent source amounts and explicit stock consequences.
  ///
  /// In en, this message translates to:
  /// **'Save all sources together. Cancelling this review changes no records or stock.'**
  String get combinedReviewHelp;

  /// Combined recording or optional site context. Fixed adult ownership, exact independent source amounts and explicit stock consequences.
  ///
  /// In en, this message translates to:
  /// **'Combined record'**
  String get combinedHistory;

  /// Combined recording or optional site context. Fixed adult ownership, exact independent source amounts and explicit stock consequences.
  ///
  /// In en, this message translates to:
  /// **'Correct or undo every source together. Each source retains its own history.'**
  String get combinedHistoryHelp;

  /// Combined recording or optional site context. Fixed adult ownership, exact independent source amounts and explicit stock consequences.
  ///
  /// In en, this message translates to:
  /// **'Correct entry'**
  String get combinedCorrection;

  /// Combined recording or optional site context. Fixed adult ownership, exact independent source amounts and explicit stock consequences.
  ///
  /// In en, this message translates to:
  /// **'Undo marks every source as voided. Choose the physical stock consequence for each source.'**
  String get combinedUndoHelp;

  /// Combined recording or optional site context. Fixed adult ownership, exact independent source amounts and explicit stock consequences.
  ///
  /// In en, this message translates to:
  /// **'No stock movement.'**
  String get combinedNoStock;

  /// Combined recording or optional site context. Fixed adult ownership, exact independent source amounts and explicit stock consequences.
  ///
  /// In en, this message translates to:
  /// **'Stock outflow unknown. The remaining balance will be unknown.'**
  String get combinedStockUnknown;

  /// Combined recording or optional site context. Fixed adult ownership, exact independent source amounts and explicit stock consequences.
  ///
  /// In en, this message translates to:
  /// **'Stock outflow: {amount}.'**
  String combinedOutflow(String amount);

  /// Combined recording or optional site context. Fixed adult ownership, exact independent source amounts and explicit stock consequences.
  ///
  /// In en, this message translates to:
  /// **'Total from {source}: {amount}.'**
  String combinedTotal(String source, String amount);

  /// Combined recording or optional site context. Fixed adult ownership, exact independent source amounts and explicit stock consequences.
  ///
  /// In en, this message translates to:
  /// **'Remaining: {amount}.'**
  String combinedRemaining(String amount);

  /// Combined recording or optional site context. Fixed adult ownership, exact independent source amounts and explicit stock consequences.
  ///
  /// In en, this message translates to:
  /// **'Site (optional)'**
  String get combinedSite;

  /// Combined recording or optional site context. Fixed adult ownership, exact independent source amounts and explicit stock consequences.
  ///
  /// In en, this message translates to:
  /// **'Enter a site label if useful. It is saved for this person only.'**
  String get combinedSiteHelp;

  /// Combined recording or optional site context. Fixed adult ownership, exact independent source amounts and explicit stock consequences.
  ///
  /// In en, this message translates to:
  /// **'Site history'**
  String get combinedSites;

  /// Combined recording or optional site context. Fixed adult ownership, exact independent source amounts and explicit stock consequences.
  ///
  /// In en, this message translates to:
  /// **'Site: {site}.'**
  String combinedSiteValue(String site);

  /// Combined recording or optional site context. Fixed adult ownership, exact independent source amounts and explicit stock consequences.
  ///
  /// In en, this message translates to:
  /// **'Source {number}'**
  String combinedSource(int number);

  /// Combined recording or optional site context. Fixed adult ownership, exact independent source amounts and explicit stock consequences.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get combinedRemove;

  /// Combined recording or optional site context. Fixed adult ownership, exact independent source amounts and explicit stock consequences.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get combinedEdit;

  /// Combined recording or optional site context. Fixed adult ownership, exact independent source amounts and explicit stock consequences.
  ///
  /// In en, this message translates to:
  /// **'Choose'**
  String get combinedChoose;

  /// Combined recording or optional site context. Fixed adult ownership, exact independent source amounts and explicit stock consequences.
  ///
  /// In en, this message translates to:
  /// **'Keep'**
  String get combinedKeep;

  /// Combined recording or optional site context. Fixed adult ownership, exact independent source amounts and explicit stock consequences.
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get combinedReverse;

  /// Combined recording or optional site context. Fixed adult ownership, exact independent source amounts and explicit stock consequences.
  ///
  /// In en, this message translates to:
  /// **'Keep the original physical consumption.'**
  String get combinedKeepHelp;

  /// Combined recording or optional site context. Fixed adult ownership, exact independent source amounts and explicit stock consequences.
  ///
  /// In en, this message translates to:
  /// **'Reverse the original stock outflow. Use this only for a mistaken entry.'**
  String get combinedReverseHelp;

  /// Combined recording or optional site context. Fixed adult ownership, exact independent source amounts and explicit stock consequences.
  ///
  /// In en, this message translates to:
  /// **'Choose the stock consequence for every source.'**
  String get combinedPhysicalRequired;

  /// Combined recording or optional site context. Fixed adult ownership, exact independent source amounts and explicit stock consequences.
  ///
  /// In en, this message translates to:
  /// **'Check each source amount, unit and time, then review again.'**
  String get combinedInvalid;

  /// Combined recording or optional site context. Fixed adult ownership, exact independent source amounts and explicit stock consequences.
  ///
  /// In en, this message translates to:
  /// **'Restore the original stock outflow.'**
  String get combinedRestoreEffect;

  /// Combined recording or optional site context. Fixed adult ownership, exact independent source amounts and explicit stock consequences.
  ///
  /// In en, this message translates to:
  /// **'Keep the original stock balance.'**
  String get combinedRetainEffect;

  /// One-word command revealing optional site entry or its history editor.
  ///
  /// In en, this message translates to:
  /// **'Site'**
  String get combinedSiteAction;

  /// Contextual accessible name for a combined source control. Preserve the full entered name and units.
  ///
  /// In en, this message translates to:
  /// **'Amount for {name}, in {unit}.'**
  String combinedAmountLabel(String name, String unit);

  /// Contextual accessible name for a combined source control. Preserve the full entered name and units.
  ///
  /// In en, this message translates to:
  /// **'Site for {name}.'**
  String combinedSiteLabel(String name);

  /// Contextual accessible name for a combined source control. Preserve the full entered name and units.
  ///
  /// In en, this message translates to:
  /// **'Remove source {number}: {name}.'**
  String combinedRemoveLabel(int number, String name);

  /// Contextual accessible name for a combined source control. Preserve the full entered name and units.
  ///
  /// In en, this message translates to:
  /// **'Keep consumption for {name}.'**
  String combinedKeepLabel(String name);

  /// Contextual accessible name for a combined source control. Preserve the full entered name and units.
  ///
  /// In en, this message translates to:
  /// **'Restore stock for {name}.'**
  String combinedRestoreLabel(String name);

  /// Contextual accessible name for a combined source control. Preserve the full entered name and units.
  ///
  /// In en, this message translates to:
  /// **'Choose stock for source {number}: {name}.'**
  String combinedSourceLabel(int number, String name);

  /// Recoverable validation beside optional site field; preserves the entered label.
  ///
  /// In en, this message translates to:
  /// **'Use a site label with 500 characters or fewer.'**
  String get combinedSiteInvalid;

  /// No description provided for @eventNew.
  ///
  /// In en, this message translates to:
  /// **'New event'**
  String get eventNew;

  /// No description provided for @eventEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit event'**
  String get eventEdit;

  /// No description provided for @eventName.
  ///
  /// In en, this message translates to:
  /// **'Event name'**
  String get eventName;

  /// No description provided for @eventType.
  ///
  /// In en, this message translates to:
  /// **'Event type'**
  String get eventType;

  /// No description provided for @eventCycle.
  ///
  /// In en, this message translates to:
  /// **'Cycle'**
  String get eventCycle;

  /// No description provided for @eventPrescription.
  ///
  /// In en, this message translates to:
  /// **'Prescription'**
  String get eventPrescription;

  /// No description provided for @eventEmpty.
  ///
  /// In en, this message translates to:
  /// **'No events yet. Create a cycle or prescription event to organise recorded use.'**
  String get eventEmpty;

  /// No description provided for @eventHelp.
  ///
  /// In en, this message translates to:
  /// **'Events organise use history. They do not record doses or change stock or plans.'**
  String get eventHelp;

  /// No description provided for @eventPlannedStart.
  ///
  /// In en, this message translates to:
  /// **'Planned start'**
  String get eventPlannedStart;

  /// No description provided for @eventPlannedEnd.
  ///
  /// In en, this message translates to:
  /// **'Planned end'**
  String get eventPlannedEnd;

  /// No description provided for @eventActualStart.
  ///
  /// In en, this message translates to:
  /// **'Actual start'**
  String get eventActualStart;

  /// No description provided for @eventActualEnd.
  ///
  /// In en, this message translates to:
  /// **'Actual end'**
  String get eventActualEnd;

  /// No description provided for @eventZone.
  ///
  /// In en, this message translates to:
  /// **'Event zone'**
  String get eventZone;

  /// No description provided for @eventDateHelp.
  ///
  /// In en, this message translates to:
  /// **'Optional. Enter YYYY-MM-DD or an exact ISO time with Z or an offset. A final date includes the whole day in the event zone.'**
  String get eventDateHelp;

  /// No description provided for @eventCompleted.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get eventCompleted;

  /// No description provided for @eventCompletedHelp.
  ///
  /// In en, this message translates to:
  /// **'Record the event as complete. Each item keeps its current plan until you explicitly change it.'**
  String get eventCompletedHelp;

  /// No description provided for @eventDateError.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid date or an exact time with Z or an offset. Leave an optional date empty.'**
  String get eventDateError;

  /// No description provided for @eventZoneError.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid IANA zone, such as Europe/London.'**
  String get eventZoneError;

  /// No description provided for @eventMembers.
  ///
  /// In en, this message translates to:
  /// **'Event items'**
  String get eventMembers;

  /// No description provided for @eventMemberHelp.
  ///
  /// In en, this message translates to:
  /// **'Membership uses exact times with Z or an offset. Earlier use is included only when it falls within the reviewed interval and event dates.'**
  String get eventMemberHelp;

  /// No description provided for @eventMemberStart.
  ///
  /// In en, this message translates to:
  /// **'Membership start'**
  String get eventMemberStart;

  /// No description provided for @eventMemberEnd.
  ///
  /// In en, this message translates to:
  /// **'Membership end'**
  String get eventMemberEnd;

  /// No description provided for @eventMemberOpen.
  ///
  /// In en, this message translates to:
  /// **'Open membership'**
  String get eventMemberOpen;

  /// No description provided for @eventReview.
  ///
  /// In en, this message translates to:
  /// **'Review event'**
  String get eventReview;

  /// No description provided for @eventPreviewHelp.
  ///
  /// In en, this message translates to:
  /// **'Review historical records before saving. Cancelling leaves membership and all records unchanged.'**
  String get eventPreviewHelp;

  /// No description provided for @eventPreviewEnter.
  ///
  /// In en, this message translates to:
  /// **'Records included: {count}'**
  String eventPreviewEnter(int count);

  /// No description provided for @eventPreviewLeave.
  ///
  /// In en, this message translates to:
  /// **'Records excluded: {count}'**
  String eventPreviewLeave(int count);

  /// No description provided for @eventPreviewChanged.
  ///
  /// In en, this message translates to:
  /// **'Event details changed. Review the new historical selection before saving.'**
  String get eventPreviewChanged;

  /// No description provided for @eventNoActuals.
  ///
  /// In en, this message translates to:
  /// **'No actual records fall within the selected event dates and memberships.'**
  String get eventNoActuals;

  /// No description provided for @eventHistoryHelp.
  ///
  /// In en, this message translates to:
  /// **'Actual records keep their original identity, amounts and recorded type. Combined event selections count each record once.'**
  String get eventHistoryHelp;

  /// No description provided for @eventBounds.
  ///
  /// In en, this message translates to:
  /// **'Event dates'**
  String get eventBounds;

  /// No description provided for @eventPlannedLabel.
  ///
  /// In en, this message translates to:
  /// **'Planned: {start} to {end}'**
  String eventPlannedLabel(String start, String end);

  /// No description provided for @eventActualLabel.
  ///
  /// In en, this message translates to:
  /// **'Actual: {start} to {end}'**
  String eventActualLabel(String start, String end);

  /// No description provided for @eventNotRecorded.
  ///
  /// In en, this message translates to:
  /// **'Not recorded'**
  String get eventNotRecorded;

  /// No description provided for @eventOpen.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get eventOpen;

  /// No description provided for @eventEndReview.
  ///
  /// In en, this message translates to:
  /// **'End review'**
  String get eventEndReview;

  /// No description provided for @eventEndHelp.
  ///
  /// In en, this message translates to:
  /// **'Review each item’s current plan and next result. No stopping is selected. Dismiss leaves all plans and stock unchanged.'**
  String get eventEndHelp;

  /// No description provided for @eventDismiss.
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get eventDismiss;

  /// No description provided for @eventContinue.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get eventContinue;

  /// No description provided for @eventStop.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get eventStop;

  /// No description provided for @eventReviewRemaining.
  ///
  /// In en, this message translates to:
  /// **'Review remaining items. Completed decisions stay saved.'**
  String get eventReviewRemaining;

  /// No description provided for @eventContinueHelp.
  ///
  /// In en, this message translates to:
  /// **'Keep the current plan. Its next result remains subject to its saved phases and end rules.'**
  String get eventContinueHelp;

  /// No description provided for @eventStopHelp.
  ///
  /// In en, this message translates to:
  /// **'Stop future eligibility using the reviewed plan command. Saved doses and stock stay unchanged.'**
  String get eventStopHelp;

  /// No description provided for @eventNoPlan.
  ///
  /// In en, this message translates to:
  /// **'No current plan'**
  String get eventNoPlan;

  /// No description provided for @eventDecisionSaved.
  ///
  /// In en, this message translates to:
  /// **'Decision saved.'**
  String get eventDecisionSaved;

  /// No description provided for @eventChoose.
  ///
  /// In en, this message translates to:
  /// **'Select an item'**
  String get eventChoose;

  /// No description provided for @eventOwner.
  ///
  /// In en, this message translates to:
  /// **'Event owner'**
  String get eventOwner;

  /// No description provided for @eventInvalid.
  ///
  /// In en, this message translates to:
  /// **'Check the event name, dates and membership times, then review again.'**
  String get eventInvalid;

  /// No description provided for @eventNoMembers.
  ///
  /// In en, this message translates to:
  /// **'No item memberships. Add an item with its effective start.'**
  String get eventNoMembers;

  /// No description provided for @eventMembership.
  ///
  /// In en, this message translates to:
  /// **'Membership'**
  String get eventMembership;

  /// No description provided for @eventInclusive.
  ///
  /// In en, this message translates to:
  /// **'A final date includes that whole day in the saved event zone.'**
  String get eventInclusive;

  /// No description provided for @eventCombined.
  ///
  /// In en, this message translates to:
  /// **'Combined history'**
  String get eventCombined;

  /// No description provided for @eventSelectHelp.
  ///
  /// In en, this message translates to:
  /// **'Select events to inspect one combined history without counting the same actual record twice.'**
  String get eventSelectHelp;

  /// No description provided for @eventSelected.
  ///
  /// In en, this message translates to:
  /// **'Selected'**
  String get eventSelected;

  /// No description provided for @eventSelect.
  ///
  /// In en, this message translates to:
  /// **'Select'**
  String get eventSelect;

  /// No description provided for @useHistory.
  ///
  /// In en, this message translates to:
  /// **'Use history'**
  String get useHistory;

  /// No description provided for @useNew.
  ///
  /// In en, this message translates to:
  /// **'New period'**
  String get useNew;

  /// No description provided for @useEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit period'**
  String get useEdit;

  /// No description provided for @useHelp.
  ///
  /// In en, this message translates to:
  /// **'Recorded periods and first-ever starts are optional history. They do not infer continuous use, adherence or change any plan.'**
  String get useHelp;

  /// No description provided for @useEmpty.
  ///
  /// In en, this message translates to:
  /// **'No use periods recorded. Individual actual records and plans remain separate.'**
  String get useEmpty;

  /// No description provided for @useStart.
  ///
  /// In en, this message translates to:
  /// **'Recorded start'**
  String get useStart;

  /// No description provided for @useEnd.
  ///
  /// In en, this message translates to:
  /// **'Recorded end'**
  String get useEnd;

  /// No description provided for @useDateHelp.
  ///
  /// In en, this message translates to:
  /// **'Enter YYYY, YYYY-MM or YYYY-MM-DD. Use Unknown for an unknown date. Leave the end empty for an open period.'**
  String get useDateHelp;

  /// No description provided for @useDateError.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid year, month or date, or Unknown. Leave the end empty for an open period.'**
  String get useDateError;

  /// No description provided for @useFirstEver.
  ///
  /// In en, this message translates to:
  /// **'First-ever start'**
  String get useFirstEver;

  /// No description provided for @useFirstEverHelp.
  ///
  /// In en, this message translates to:
  /// **'Mark this supplied start as the first-ever use. Unknown stays unknown.'**
  String get useFirstEverHelp;

  /// No description provided for @useKind.
  ///
  /// In en, this message translates to:
  /// **'Period type'**
  String get useKind;

  /// No description provided for @useTaking.
  ///
  /// In en, this message translates to:
  /// **'Use'**
  String get useTaking;

  /// No description provided for @useBreak.
  ///
  /// In en, this message translates to:
  /// **'Break'**
  String get useBreak;

  /// No description provided for @useFirstLabel.
  ///
  /// In en, this message translates to:
  /// **'First-ever start: {date}'**
  String useFirstLabel(String date);

  /// No description provided for @usePeriodLabel.
  ///
  /// In en, this message translates to:
  /// **'{start} to {end}'**
  String usePeriodLabel(String start, String end);

  /// No description provided for @useUnknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get useUnknown;

  /// No description provided for @eventRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get eventRemove;

  /// No description provided for @eventAdd.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get eventAdd;

  /// No description provided for @eventItemIdentity.
  ///
  /// In en, this message translates to:
  /// **'Item: {name} · {detail} · Entry {reference}'**
  String eventItemIdentity(String name, String detail, String reference);

  /// No description provided for @eventClear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get eventClear;

  /// No description provided for @eventRevisions.
  ///
  /// In en, this message translates to:
  /// **'Revisions'**
  String get eventRevisions;

  /// No description provided for @eventRevision.
  ///
  /// In en, this message translates to:
  /// **'Revision {number}'**
  String eventRevision(int number);

  /// No description provided for @useDays.
  ///
  /// In en, this message translates to:
  /// **'Recorded length: {days} days.'**
  String useDays(int days);

  /// No description provided for @eventReviewTime.
  ///
  /// In en, this message translates to:
  /// **'Review time: {time}'**
  String eventReviewTime(String time);

  /// No description provided for @eventMemberStartFor.
  ///
  /// In en, this message translates to:
  /// **'Membership start for {name}'**
  String eventMemberStartFor(String name);

  /// No description provided for @eventMemberEndFor.
  ///
  /// In en, this message translates to:
  /// **'Membership end for {name}'**
  String eventMemberEndFor(String name);

  /// No description provided for @eventRemoveFor.
  ///
  /// In en, this message translates to:
  /// **'Remove {name} from future event membership'**
  String eventRemoveFor(String name);

  /// No description provided for @eventReviewFor.
  ///
  /// In en, this message translates to:
  /// **'Review {name} for {person}'**
  String eventReviewFor(String name, String person);

  /// No description provided for @eventSelectFor.
  ///
  /// In en, this message translates to:
  /// **'Select {name} for {person}'**
  String eventSelectFor(String name, String person);

  /// No description provided for @eventMemberRange.
  ///
  /// In en, this message translates to:
  /// **'Membership: {start} to {end} ({zone}).'**
  String eventMemberRange(String start, String end, String zone);

  /// No description provided for @eventBoundaryReview.
  ///
  /// In en, this message translates to:
  /// **'This date needs review. Enter an exact time with Z or an offset, check the event zone, then review again.'**
  String get eventBoundaryReview;

  /// No description provided for @eventDueReview.
  ///
  /// In en, this message translates to:
  /// **'This event has ended. Review which plans continue.'**
  String get eventDueReview;

  /// No description provided for @attachments.
  ///
  /// In en, this message translates to:
  /// **'Files'**
  String get attachments;

  /// No description provided for @attachmentHelp.
  ///
  /// In en, this message translates to:
  /// **'Add an optional original file or photo to this record. A photo does not confirm that a dose was taken.'**
  String get attachmentHelp;

  /// No description provided for @attachmentEmpty.
  ///
  /// In en, this message translates to:
  /// **'No files attached. Choose a file or an existing photo to add one.'**
  String get attachmentEmpty;

  /// No description provided for @attachmentChoose.
  ///
  /// In en, this message translates to:
  /// **'Choose'**
  String get attachmentChoose;

  /// No description provided for @attachmentPhotos.
  ///
  /// In en, this message translates to:
  /// **'Photos'**
  String get attachmentPhotos;

  /// No description provided for @attachmentCapture.
  ///
  /// In en, this message translates to:
  /// **'Capture'**
  String get attachmentCapture;

  /// No description provided for @attachmentUnavailable.
  ///
  /// In en, this message translates to:
  /// **'File selection is unavailable here. Existing protected files remain available.'**
  String get attachmentUnavailable;

  /// No description provided for @attachmentCameraUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Camera capture is unavailable here. You can choose an existing photo.'**
  String get attachmentCameraUnavailable;

  /// No description provided for @attachmentNew.
  ///
  /// In en, this message translates to:
  /// **'Add file'**
  String get attachmentNew;

  /// No description provided for @attachmentOriginal.
  ///
  /// In en, this message translates to:
  /// **'Original file'**
  String get attachmentOriginal;

  /// No description provided for @attachmentName.
  ///
  /// In en, this message translates to:
  /// **'File name'**
  String get attachmentName;

  /// No description provided for @attachmentRename.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get attachmentRename;

  /// No description provided for @attachmentDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete from record'**
  String get attachmentDelete;

  /// No description provided for @attachmentDeleteHelp.
  ///
  /// In en, this message translates to:
  /// **'Delete {name} from {person}’s record. Vital removes its protected copy after any open preview or share releases it. Your source file and shared copies stay unchanged.'**
  String attachmentDeleteHelp(String name, String person);

  /// No description provided for @attachmentShare.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get attachmentShare;

  /// No description provided for @attachmentShareHeading.
  ///
  /// In en, this message translates to:
  /// **'Share file'**
  String get attachmentShareHeading;

  /// No description provided for @attachmentShareHelp.
  ///
  /// In en, this message translates to:
  /// **'Share {name} for {person}. Only this original is handed to the destination you choose. Its contents and metadata may contain personal information.'**
  String attachmentShareHelp(String name, String person);

  /// No description provided for @attachmentShareLifetime.
  ///
  /// In en, this message translates to:
  /// **'The receiving app can read the prepared copy for up to 24 hours, including after Vital locks. It may keep its own copy.'**
  String get attachmentShareLifetime;

  /// No description provided for @attachmentSaveHelp.
  ///
  /// In en, this message translates to:
  /// **'Save a copy of this original to the location you choose. That copy is outside Vital’s protected storage.'**
  String get attachmentSaveHelp;

  /// No description provided for @attachmentReady.
  ///
  /// In en, this message translates to:
  /// **'Ready'**
  String get attachmentReady;

  /// No description provided for @attachmentStaging.
  ///
  /// In en, this message translates to:
  /// **'Importing file'**
  String get attachmentStaging;

  /// No description provided for @attachmentAwaiting.
  ///
  /// In en, this message translates to:
  /// **'Waiting for selection'**
  String get attachmentAwaiting;

  /// No description provided for @attachmentInterrupted.
  ///
  /// In en, this message translates to:
  /// **'Selection interrupted. Resume the original import or cancel it.'**
  String get attachmentInterrupted;

  /// No description provided for @attachmentRemoving.
  ///
  /// In en, this message translates to:
  /// **'Removing file'**
  String get attachmentRemoving;

  /// No description provided for @attachmentPinned.
  ///
  /// In en, this message translates to:
  /// **'An open preview or share keeps this exact original until it is released.'**
  String get attachmentPinned;

  /// No description provided for @attachmentBytes.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 byte} other{{count} bytes}}'**
  String attachmentBytes(int count);

  /// No description provided for @attachmentSaved.
  ///
  /// In en, this message translates to:
  /// **'File added to this record.'**
  String get attachmentSaved;

  /// No description provided for @attachmentCancelled.
  ///
  /// In en, this message translates to:
  /// **'Selection cancelled. The original is unchanged.'**
  String get attachmentCancelled;

  /// No description provided for @attachmentShared.
  ///
  /// In en, this message translates to:
  /// **'Share opened. The prepared original stays available for up to 24 hours.'**
  String get attachmentShared;

  /// No description provided for @attachmentCopySaved.
  ///
  /// In en, this message translates to:
  /// **'Copy saved to the location you chose.'**
  String get attachmentCopySaved;

  /// No description provided for @attachmentFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to complete this file action. Try again.'**
  String get attachmentFailed;

  /// No description provided for @attachmentStale.
  ///
  /// In en, this message translates to:
  /// **'This file’s record changed or is unavailable. Return to its original record and review it.'**
  String get attachmentStale;

  /// No description provided for @attachmentArchivedProfile.
  ///
  /// In en, this message translates to:
  /// **'This person is archived. Reactivate them in People to manage files.'**
  String get attachmentArchivedProfile;

  /// No description provided for @attachmentVoidedRecord.
  ///
  /// In en, this message translates to:
  /// **'This dose is voided. Files cannot be added to it.'**
  String get attachmentVoidedRecord;

  /// No description provided for @attachmentNameError.
  ///
  /// In en, this message translates to:
  /// **'Enter a file name with 1 to 255 characters.'**
  String get attachmentNameError;

  /// No description provided for @attachmentByteError.
  ///
  /// In en, this message translates to:
  /// **'Choose a file no larger than 16 MiB. Your source file is unchanged.'**
  String get attachmentByteError;

  /// No description provided for @attachmentImageError.
  ///
  /// In en, this message translates to:
  /// **'This image cannot be previewed. Choose a complete image with at most 16 million pixels and one frame. Your source is unchanged.'**
  String get attachmentImageError;

  /// No description provided for @attachmentPdfError.
  ///
  /// In en, this message translates to:
  /// **'This PDF cannot be previewed. Choose a complete, unencrypted PDF with no more than 100 pages. Your source is unchanged.'**
  String get attachmentPdfError;

  /// No description provided for @attachmentBusy.
  ///
  /// In en, this message translates to:
  /// **'An import is already waiting. Resume or cancel it before choosing another file.'**
  String get attachmentBusy;

  /// No description provided for @attachmentShareBusy.
  ///
  /// In en, this message translates to:
  /// **'Earlier shares are still available to their receiving apps. Try again after their 24-hour handoff period.'**
  String get attachmentShareBusy;

  /// No description provided for @attachmentPreview.
  ///
  /// In en, this message translates to:
  /// **'File preview'**
  String get attachmentPreview;

  /// No description provided for @attachmentPreviewHelp.
  ///
  /// In en, this message translates to:
  /// **'This preview is scaled for display. Sharing or saving uses the unchanged original.'**
  String get attachmentPreviewHelp;

  /// No description provided for @attachmentPreviewHelpShare.
  ///
  /// In en, this message translates to:
  /// **'This preview is scaled for display. Sharing uses the unchanged original.'**
  String get attachmentPreviewHelpShare;

  /// No description provided for @attachmentPreviewHelpSave.
  ///
  /// In en, this message translates to:
  /// **'This preview is scaled for display. Saving uses the unchanged original.'**
  String get attachmentPreviewHelpSave;

  /// No description provided for @attachmentPreviewHelpNone.
  ///
  /// In en, this message translates to:
  /// **'This preview is scaled for display.'**
  String get attachmentPreviewHelpNone;

  /// No description provided for @attachmentNoPreview.
  ///
  /// In en, this message translates to:
  /// **'This file type has no preview.'**
  String get attachmentNoPreview;

  /// No description provided for @attachmentNoPreviewShare.
  ///
  /// In en, this message translates to:
  /// **'This file type has no preview. You can share the unchanged original.'**
  String get attachmentNoPreviewShare;

  /// No description provided for @attachmentNoPreviewSave.
  ///
  /// In en, this message translates to:
  /// **'This file type has no preview. You can save the unchanged original.'**
  String get attachmentNoPreviewSave;

  /// No description provided for @attachmentNoPreviewShareSave.
  ///
  /// In en, this message translates to:
  /// **'This file type has no preview. You can share or save the unchanged original.'**
  String get attachmentNoPreviewShareSave;

  /// No description provided for @attachmentPreviewFailure.
  ///
  /// In en, this message translates to:
  /// **'Unable to show this preview. Retry.'**
  String get attachmentPreviewFailure;

  /// No description provided for @attachmentPreviewFailureShare.
  ///
  /// In en, this message translates to:
  /// **'Unable to show this preview. Retry. You can share the unchanged original.'**
  String get attachmentPreviewFailureShare;

  /// No description provided for @attachmentPreviewFailureSave.
  ///
  /// In en, this message translates to:
  /// **'Unable to show this preview. Retry. You can save the unchanged original.'**
  String get attachmentPreviewFailureSave;

  /// No description provided for @attachmentPreviewFailureShareSave.
  ///
  /// In en, this message translates to:
  /// **'Unable to show this preview. Retry. You can share or save the unchanged original.'**
  String get attachmentPreviewFailureShareSave;

  /// No description provided for @attachmentPage.
  ///
  /// In en, this message translates to:
  /// **'Page {page} of {total}'**
  String attachmentPage(int page, int total);

  /// No description provided for @attachmentZoom.
  ///
  /// In en, this message translates to:
  /// **'Zoom'**
  String get attachmentZoom;

  /// No description provided for @attachmentReset.
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get attachmentReset;

  /// No description provided for @attachmentResume.
  ///
  /// In en, this message translates to:
  /// **'Resume'**
  String get attachmentResume;

  /// No description provided for @attachmentJobs.
  ///
  /// In en, this message translates to:
  /// **'Waiting imports'**
  String get attachmentJobs;

  /// No description provided for @attachmentTargetItem.
  ///
  /// In en, this message translates to:
  /// **'Item: {name}'**
  String attachmentTargetItem(String name);

  /// No description provided for @attachmentTargetDose.
  ///
  /// In en, this message translates to:
  /// **'Dose: {name}, {amount} {unit} at {time}'**
  String attachmentTargetDose(
    String name,
    String amount,
    String unit,
    String time,
  );

  /// No description provided for @attachmentFor.
  ///
  /// In en, this message translates to:
  /// **'Files for {person}'**
  String attachmentFor(String person);

  /// No description provided for @attachmentViewFor.
  ///
  /// In en, this message translates to:
  /// **'View {name} for {person}'**
  String attachmentViewFor(String name, String person);

  /// No description provided for @attachmentImportAmount.
  ///
  /// In en, this message translates to:
  /// **'Imported: {count} bytes.'**
  String attachmentImportAmount(int count);

  /// No description provided for @attachmentLocked.
  ///
  /// In en, this message translates to:
  /// **'Unlock Vital to continue this file action.'**
  String get attachmentLocked;

  /// No description provided for @attachmentJobUnavailable.
  ///
  /// In en, this message translates to:
  /// **'This import no longer matches its original record. Cancel it and return to that record.'**
  String get attachmentJobUnavailable;

  /// No description provided for @attachmentReopen.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get attachmentReopen;

  /// No description provided for @attachmentClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get attachmentClose;

  /// No description provided for @attachmentBack.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get attachmentBack;

  /// No description provided for @attachmentRecordRevision.
  ///
  /// In en, this message translates to:
  /// **'Attached to revision {revision}.'**
  String attachmentRecordRevision(int revision);

  /// No description provided for @attachmentRenamed.
  ///
  /// In en, this message translates to:
  /// **'File name saved.'**
  String get attachmentRenamed;

  /// No description provided for @attachmentRemoved.
  ///
  /// In en, this message translates to:
  /// **'File removed from this record. Open uses retain their copy until released.'**
  String get attachmentRemoved;

  /// No description provided for @attachmentSaveHeading.
  ///
  /// In en, this message translates to:
  /// **'Save file'**
  String get attachmentSaveHeading;

  /// No description provided for @attachmentSaveFor.
  ///
  /// In en, this message translates to:
  /// **'Save a copy of {name} for {person} to the location you choose. That copy is outside Vital’s protected storage.'**
  String attachmentSaveFor(String name, String person);

  /// No description provided for @historyTimeline.
  ///
  /// In en, this message translates to:
  /// **'Timeline'**
  String get historyTimeline;

  /// No description provided for @historyCalendar.
  ///
  /// In en, this message translates to:
  /// **'Calendar'**
  String get historyCalendar;

  /// No description provided for @historyFilters.
  ///
  /// In en, this message translates to:
  /// **'Filters'**
  String get historyFilters;

  /// No description provided for @filterType.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get filterType;

  /// No description provided for @filterEvent.
  ///
  /// In en, this message translates to:
  /// **'Event'**
  String get filterEvent;

  /// No description provided for @filterStatus.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get filterStatus;

  /// No description provided for @filterDates.
  ///
  /// In en, this message translates to:
  /// **'Dates'**
  String get filterDates;

  /// No description provided for @statusAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get statusAll;

  /// No description provided for @statusRecorded.
  ///
  /// In en, this message translates to:
  /// **'Recorded'**
  String get statusRecorded;

  /// No description provided for @statusSkipped.
  ///
  /// In en, this message translates to:
  /// **'Skipped'**
  String get statusSkipped;

  /// No description provided for @statusVoided.
  ///
  /// In en, this message translates to:
  /// **'Voided'**
  String get statusVoided;

  /// No description provided for @historyNoEntries.
  ///
  /// In en, this message translates to:
  /// **'No entries'**
  String get historyNoEntries;

  /// No description provided for @historyNoEntriesBody.
  ///
  /// In en, this message translates to:
  /// **'No recorded or skipped entries match this view. Clear a filter or choose another date.'**
  String get historyNoEntriesBody;

  /// No description provided for @historyNewEntries.
  ///
  /// In en, this message translates to:
  /// **'History changed. Refresh to show the latest entries.'**
  String get historyNewEntries;

  /// No description provided for @historyRefreshed.
  ///
  /// In en, this message translates to:
  /// **'History refreshed. Your filters are retained.'**
  String get historyRefreshed;

  /// No description provided for @historyMoved.
  ///
  /// In en, this message translates to:
  /// **'This entry moved to {date}.'**
  String historyMoved(String date);

  /// No description provided for @refresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get refresh;

  /// No description provided for @dates.
  ///
  /// In en, this message translates to:
  /// **'Dates'**
  String get dates;

  /// No description provided for @timeFormat.
  ///
  /// In en, this message translates to:
  /// **'Time format'**
  String get timeFormat;

  /// No description provided for @timeSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get timeSystem;

  /// No description provided for @time12.
  ///
  /// In en, this message translates to:
  /// **'12-hour'**
  String get time12;

  /// No description provided for @time24.
  ///
  /// In en, this message translates to:
  /// **'24-hour'**
  String get time24;

  /// No description provided for @timeFormatHelp.
  ///
  /// In en, this message translates to:
  /// **'Choose how times appear. Recorded times and amounts stay unchanged. Time entry uses 24-hour HH:MM.'**
  String get timeFormatHelp;

  /// No description provided for @displaySaveFailure.
  ///
  /// In en, this message translates to:
  /// **'Unable to save the time format. Choose it again to retry.'**
  String get displaySaveFailure;

  /// No description provided for @shownInZone.
  ///
  /// In en, this message translates to:
  /// **'Shown in {zone}'**
  String shownInZone(String zone);

  /// No description provided for @plannedInZone.
  ///
  /// In en, this message translates to:
  /// **'Planned in {zone}'**
  String plannedInZone(String zone);

  /// No description provided for @dateOnly.
  ///
  /// In en, this message translates to:
  /// **'Date only'**
  String get dateOnly;

  /// No description provided for @timeNeedsReview.
  ///
  /// In en, this message translates to:
  /// **'Time needs review'**
  String get timeNeedsReview;

  /// No description provided for @historyRangeTooBroad.
  ///
  /// In en, this message translates to:
  /// **'Too many filters'**
  String get historyRangeTooBroad;

  /// No description provided for @historyRangeTooBroadBody.
  ///
  /// In en, this message translates to:
  /// **'Choose fewer types or events to load this view.'**
  String get historyRangeTooBroadBody;

  /// No description provided for @historyLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to load history. Try again.'**
  String get historyLoadFailed;

  /// No description provided for @historyMatched.
  ///
  /// In en, this message translates to:
  /// **'Matches filters'**
  String get historyMatched;

  /// No description provided for @historyGroupContext.
  ///
  /// In en, this message translates to:
  /// **'Full group shown. Matching sources are marked.'**
  String get historyGroupContext;

  /// No description provided for @historyRecorded.
  ///
  /// In en, this message translates to:
  /// **'Recorded use'**
  String get historyRecorded;

  /// No description provided for @historySkippedHelp.
  ///
  /// In en, this message translates to:
  /// **'This is a skipped planned occurrence. It is not recorded use.'**
  String get historySkippedHelp;

  /// No description provided for @historyPlannedAmount.
  ///
  /// In en, this message translates to:
  /// **'Planned: {amount} {unit}'**
  String historyPlannedAmount(String amount, String unit);

  /// No description provided for @historyPlanCaptured.
  ///
  /// In en, this message translates to:
  /// **'Saved plan: {name}'**
  String historyPlanCaptured(String name);

  /// No description provided for @historyPlannedDate.
  ///
  /// In en, this message translates to:
  /// **'Planned date: {date}'**
  String historyPlannedDate(String date);

  /// No description provided for @historySkipAudit.
  ///
  /// In en, this message translates to:
  /// **'Action history'**
  String get historySkipAudit;

  /// No description provided for @historyActionRevision.
  ///
  /// In en, this message translates to:
  /// **'Action revision {revision}. {kind}. {date}.'**
  String historyActionRevision(int revision, String kind, String date);

  /// No description provided for @historyExactInstant.
  ///
  /// In en, this message translates to:
  /// **'Exact instant: {instant}'**
  String historyExactInstant(String instant);

  /// No description provided for @historyCalendarHelp.
  ///
  /// In en, this message translates to:
  /// **'Choose a day to view its entries. Scroll across the calendar when needed.'**
  String get historyCalendarHelp;

  /// No description provided for @historyMarkerLegend.
  ///
  /// In en, this message translates to:
  /// **'● Recorded. − Skipped. × Voided.'**
  String get historyMarkerLegend;

  /// No description provided for @historyDaySummary.
  ///
  /// In en, this message translates to:
  /// **'{date}. {recorded} recorded, {skipped} skipped, {voided} voided.'**
  String historyDaySummary(String date, int recorded, int skipped, int voided);

  /// No description provided for @historyDayCounts.
  ///
  /// In en, this message translates to:
  /// **'Recorded: {recorded}. Skipped: {skipped}. Voided: {voided}.'**
  String historyDayCounts(int recorded, int skipped, int voided);

  /// No description provided for @previousMonth.
  ///
  /// In en, this message translates to:
  /// **'Previous month'**
  String get previousMonth;

  /// No description provided for @nextMonth.
  ///
  /// In en, this message translates to:
  /// **'Next month'**
  String get nextMonth;

  /// No description provided for @historyMonthLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading day counts…'**
  String get historyMonthLoading;

  /// No description provided for @historyWindow.
  ///
  /// In en, this message translates to:
  /// **'Showing an older window. Refresh to return to the latest entries.'**
  String get historyWindow;

  /// No description provided for @historyDateHelp.
  ///
  /// In en, this message translates to:
  /// **'Use YYYY-MM-DD. The end date is included in the shown zone.'**
  String get historyDateHelp;

  /// No description provided for @historyFrom.
  ///
  /// In en, this message translates to:
  /// **'From'**
  String get historyFrom;

  /// No description provided for @historyThrough.
  ///
  /// In en, this message translates to:
  /// **'Through'**
  String get historyThrough;

  /// No description provided for @historyDateError.
  ///
  /// In en, this message translates to:
  /// **'Enter valid dates with the end on or after the start.'**
  String get historyDateError;

  /// No description provided for @historyUnknownType.
  ///
  /// In en, this message translates to:
  /// **'Unknown type'**
  String get historyUnknownType;

  /// No description provided for @historyNoOptions.
  ///
  /// In en, this message translates to:
  /// **'No matching choices. Try another search.'**
  String get historyNoOptions;

  /// No description provided for @historyFilterLimit.
  ///
  /// In en, this message translates to:
  /// **'Choose at most {count} entries.'**
  String historyFilterLimit(int count);

  /// No description provided for @historyScopeFixed.
  ///
  /// In en, this message translates to:
  /// **'Your filters stay selected when you open a record.'**
  String get historyScopeFixed;

  /// No description provided for @historyPlanUnknown.
  ///
  /// In en, this message translates to:
  /// **'No saved plan context. No missed use is inferred.'**
  String get historyPlanUnknown;

  /// No description provided for @historyInspection.
  ///
  /// In en, this message translates to:
  /// **'Source'**
  String get historyInspection;

  /// No description provided for @historyUnknownSource.
  ///
  /// In en, this message translates to:
  /// **'This source is no longer available. Return to history and refresh.'**
  String get historyUnknownSource;

  /// No description provided for @historyAuditEmpty.
  ///
  /// In en, this message translates to:
  /// **'No earlier actions are available.'**
  String get historyAuditEmpty;

  /// No description provided for @historyShowing.
  ///
  /// In en, this message translates to:
  /// **'Showing {count, plural, =1{1 entry} other{{count} entries}}.'**
  String historyShowing(int count);

  /// No description provided for @historyNoCapturedPlan.
  ///
  /// In en, this message translates to:
  /// **'No plan captured'**
  String get historyNoCapturedPlan;

  /// No description provided for @historyNoCapturedPlanBody.
  ///
  /// In en, this message translates to:
  /// **'There are no captured planned actions in this view. This does not show missed use.'**
  String get historyNoCapturedPlanBody;

  /// No description provided for @chartsTitle.
  ///
  /// In en, this message translates to:
  /// **'Charts'**
  String get chartsTitle;

  /// No description provided for @chartSeries.
  ///
  /// In en, this message translates to:
  /// **'Series'**
  String get chartSeries;

  /// No description provided for @chartRange.
  ///
  /// In en, this message translates to:
  /// **'Range'**
  String get chartRange;

  /// No description provided for @chartBuckets.
  ///
  /// In en, this message translates to:
  /// **'Buckets'**
  String get chartBuckets;

  /// No description provided for @chartDay.
  ///
  /// In en, this message translates to:
  /// **'Day'**
  String get chartDay;

  /// No description provided for @chartWeek.
  ///
  /// In en, this message translates to:
  /// **'Week'**
  String get chartWeek;

  /// No description provided for @chartMonth.
  ///
  /// In en, this message translates to:
  /// **'Month'**
  String get chartMonth;

  /// No description provided for @chartTable.
  ///
  /// In en, this message translates to:
  /// **'Table'**
  String get chartTable;

  /// No description provided for @chartPlot.
  ///
  /// In en, this message translates to:
  /// **'Chart'**
  String get chartPlot;

  /// No description provided for @chartTotal.
  ///
  /// In en, this message translates to:
  /// **'Total'**
  String get chartTotal;

  /// No description provided for @chartKnownTotal.
  ///
  /// In en, this message translates to:
  /// **'Known total'**
  String get chartKnownTotal;

  /// No description provided for @chartIncomplete.
  ///
  /// In en, this message translates to:
  /// **'Some ingredient amounts are unknown.'**
  String get chartIncomplete;

  /// No description provided for @chartEmpty.
  ///
  /// In en, this message translates to:
  /// **'No recorded use in this range.'**
  String get chartEmpty;

  /// No description provided for @chartLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading chart…'**
  String get chartLoading;

  /// No description provided for @chartLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to load the chart. Try again.'**
  String get chartLoadFailed;

  /// No description provided for @chartInvalidZone.
  ///
  /// In en, this message translates to:
  /// **'The display time zone is unavailable. Reset to show UTC.'**
  String get chartInvalidZone;

  /// No description provided for @chartTooLarge.
  ///
  /// In en, this message translates to:
  /// **'Choose a shorter range to show every record.'**
  String get chartTooLarge;

  /// No description provided for @chartGap.
  ///
  /// In en, this message translates to:
  /// **'No recorded use'**
  String get chartGap;

  /// No description provided for @chartAnnotations.
  ///
  /// In en, this message translates to:
  /// **'Context'**
  String get chartAnnotations;

  /// No description provided for @chartAnnotationOverflow.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one {1 more context entry. Choose a shorter range.} other {{count} more context entries. Choose a shorter range.}}'**
  String chartAnnotationOverflow(int count);

  /// No description provided for @chartInspect.
  ///
  /// In en, this message translates to:
  /// **'View'**
  String get chartInspect;

  /// No description provided for @chartZoomIn.
  ///
  /// In en, this message translates to:
  /// **'Narrow'**
  String get chartZoomIn;

  /// No description provided for @chartZoomOut.
  ///
  /// In en, this message translates to:
  /// **'Widen'**
  String get chartZoomOut;

  /// No description provided for @chartPrevious.
  ///
  /// In en, this message translates to:
  /// **'Earlier'**
  String get chartPrevious;

  /// No description provided for @chartNext.
  ///
  /// In en, this message translates to:
  /// **'Later'**
  String get chartNext;

  /// No description provided for @chartFrom.
  ///
  /// In en, this message translates to:
  /// **'From'**
  String get chartFrom;

  /// No description provided for @chartBefore.
  ///
  /// In en, this message translates to:
  /// **'Before'**
  String get chartBefore;

  /// No description provided for @chartApply.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get chartApply;

  /// No description provided for @chartChoosePerson.
  ///
  /// In en, this message translates to:
  /// **'Choose a person'**
  String get chartChoosePerson;

  /// No description provided for @chartChooseSeries.
  ///
  /// In en, this message translates to:
  /// **'Choose a series'**
  String get chartChooseSeries;

  /// No description provided for @chartExact.
  ///
  /// In en, this message translates to:
  /// **'Exact amount'**
  String get chartExact;

  /// No description provided for @chartDoseCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one {1 recorded dose} other {{count} recorded doses}}'**
  String chartDoseCount(int count);

  /// No description provided for @chartIngredientCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one {1 ingredient amount} other {{count} ingredient amounts}}'**
  String chartIngredientCount(int count);

  /// No description provided for @chartCombinedCountHelp.
  ///
  /// In en, this message translates to:
  /// **'A combined record can contain several amounts.'**
  String get chartCombinedCountHelp;

  /// No description provided for @chartVoidedSourcesHelp.
  ///
  /// In en, this message translates to:
  /// **'Voided records are shown here but do not count towards totals.'**
  String get chartVoidedSourcesHelp;

  /// No description provided for @chartNoRecordedSources.
  ///
  /// In en, this message translates to:
  /// **'No recorded sources in this range.'**
  String get chartNoRecordedSources;

  /// No description provided for @chartNoVoidedSources.
  ///
  /// In en, this message translates to:
  /// **'No voided sources in this range.'**
  String get chartNoVoidedSources;

  /// No description provided for @chartEventStart.
  ///
  /// In en, this message translates to:
  /// **'Event start'**
  String get chartEventStart;

  /// No description provided for @chartEventEnd.
  ///
  /// In en, this message translates to:
  /// **'Event end'**
  String get chartEventEnd;

  /// No description provided for @chartPlanChanged.
  ///
  /// In en, this message translates to:
  /// **'Plan changed'**
  String get chartPlanChanged;

  /// No description provided for @chartPauseStart.
  ///
  /// In en, this message translates to:
  /// **'Pause start'**
  String get chartPauseStart;

  /// No description provided for @chartPauseEnd.
  ///
  /// In en, this message translates to:
  /// **'Pause end'**
  String get chartPauseEnd;

  /// No description provided for @chartPhaseStart.
  ///
  /// In en, this message translates to:
  /// **'Phase start'**
  String get chartPhaseStart;

  /// No description provided for @chartPhaseEnd.
  ///
  /// In en, this message translates to:
  /// **'Phase end'**
  String get chartPhaseEnd;

  /// No description provided for @chartPlanEnd.
  ///
  /// In en, this message translates to:
  /// **'Plan end'**
  String get chartPlanEnd;

  /// No description provided for @apply.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get apply;

  /// No description provided for @choose.
  ///
  /// In en, this message translates to:
  /// **'Choose'**
  String get choose;

  /// No description provided for @clear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clear;

  /// No description provided for @reset.
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get reset;

  /// No description provided for @search.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get search;

  /// No description provided for @undone.
  ///
  /// In en, this message translates to:
  /// **'Undone'**
  String get undone;

  /// Cycle timing in its saved zone. Date-only periods count calendar days, with the final date included. Exact times count full elapsed or started remaining 24-hour periods.
  ///
  /// In en, this message translates to:
  /// **'{days, plural, =0 {0 days elapsed} =1 {1 day elapsed} other {{days} days elapsed}}'**
  String cycleElapsed(int days);

  /// Cycle timing in its saved zone. Date-only periods count calendar days, with the final date included. Exact times count full elapsed or started remaining 24-hour periods.
  ///
  /// In en, this message translates to:
  /// **'{days, plural, =0 {0 days remaining} =1 {1 day remaining} other {{days} days remaining}}'**
  String cycleRemaining(int days);

  /// Future cycle start. Date-only values use saved-zone calendar days; exact starts round remaining 24-hour periods up.
  ///
  /// In en, this message translates to:
  /// **'{days, plural, =0 {Starts today} =1 {Starts in 1 day} other {Starts in {days} days}}'**
  String cycleStartsIn(int days);

  /// Today section heading for planned occurrences, separate from recorded activity.
  ///
  /// In en, this message translates to:
  /// **'Due'**
  String get todayDue;

  /// Today section heading for planned occurrences, separate from recorded activity.
  ///
  /// In en, this message translates to:
  /// **'Upcoming'**
  String get todayUpcoming;

  /// No description provided for @historyYesterday.
  ///
  /// In en, this message translates to:
  /// **'Yesterday'**
  String get historyYesterday;

  /// Relative civil date in the displayed timezone, never elapsed 24-hour periods.
  ///
  /// In en, this message translates to:
  /// **'{days, plural, one{1 day ago} other{{days} days ago}}'**
  String historyDaysAgo(int days);

  /// Accessible relative date followed by full exact date, time and displayed timezone.
  ///
  /// In en, this message translates to:
  /// **'{relative}. {exact}'**
  String historyRelativeExact(String relative, String exact);

  /// Accessible date-only entry with its saved plan timezone. Do not imply an exact time.
  ///
  /// In en, this message translates to:
  /// **'{date}. {zone}. Date only.'**
  String historyDateZone(String date, String zone);

  /// No description provided for @historyDoseNoPlanBody.
  ///
  /// In en, this message translates to:
  /// **'This dose has no captured plan. This does not show missed use.'**
  String get historyDoseNoPlanBody;

  /// No description provided for @historySelectedTypes.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{1 type selected} other{{count} types selected}}'**
  String historySelectedTypes(int count);

  /// No description provided for @historySelectedEvents.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{1 event selected} other{{count} events selected}}'**
  String historySelectedEvents(int count);

  /// Active inclusive date filter. Either endpoint may be Any date.
  ///
  /// In en, this message translates to:
  /// **'{from} to {through}'**
  String historyDateFilter(String from, String through);

  /// No description provided for @historyAnyDate.
  ///
  /// In en, this message translates to:
  /// **'Any date'**
  String get historyAnyDate;

  /// No description provided for @chartAmount.
  ///
  /// In en, this message translates to:
  /// **'{amount} {unit}'**
  String chartAmount(String amount, String unit);

  /// No description provided for @chartSeriesLabel.
  ///
  /// In en, this message translates to:
  /// **'{name} · {unit}'**
  String chartSeriesLabel(String name, String unit);

  /// No description provided for @chartCanvasSummary.
  ///
  /// In en, this message translates to:
  /// **'{name}, recorded amounts in {unit}. Use the table to inspect exact values and sources.'**
  String chartCanvasSummary(String name, String unit);

  /// No description provided for @chartDateRange.
  ///
  /// In en, this message translates to:
  /// **'{start} to {end}'**
  String chartDateRange(String start, String end);

  /// No description provided for @chartUnknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get chartUnknown;

  /// No description provided for @chartContextUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Some context could not be loaded. Choose a shorter range.'**
  String get chartContextUnavailable;

  /// No description provided for @chartRangeInvalid.
  ///
  /// In en, this message translates to:
  /// **'Choose valid dates with the end after the start.'**
  String get chartRangeInvalid;

  /// No description provided for @chartSources.
  ///
  /// In en, this message translates to:
  /// **'Sources'**
  String get chartSources;

  /// Accessible name for the one-word View command on one table bucket. Preserve the visible word View, the full series name and unit, and the exact displayed civil period and zone.
  ///
  /// In en, this message translates to:
  /// **'View sources for {series} in {unit} for {period}. {zone}.'**
  String chartViewBucketSources(
    String series,
    String unit,
    String period,
    String zone,
  );

  /// Accessible name for the one-word View command that opens every source in the displayed chart range. Preserve the visible word View, the full series name and unit, and the exact displayed range including its zone.
  ///
  /// In en, this message translates to:
  /// **'View sources for {series} in {unit}: {range}.'**
  String chartViewRangeSources(String series, String unit, String range);

  /// No description provided for @historyCapturedPlan.
  ///
  /// In en, this message translates to:
  /// **'Plan captured'**
  String get historyCapturedPlan;

  /// No description provided for @chartPlotUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Use the table to inspect this range of quantities.'**
  String get chartPlotUnavailable;

  /// Accessible status while a command button is processing; does not claim a save succeeded.
  ///
  /// In en, this message translates to:
  /// **'Working…'**
  String get working;

  /// Exact chart range with an inclusive start and exclusive end. Preserve the word before.
  ///
  /// In en, this message translates to:
  /// **'{start} to before {end}'**
  String chartRangeSummary(String start, String end);

  /// Manual supporting record flow. Preserve original values, ownership and date precision. Commands use one word.
  ///
  /// In en, this message translates to:
  /// **'Supporting'**
  String get supportingTitle;

  /// Manual supporting record flow. Preserve original values, ownership and date precision. Commands use one word.
  ///
  /// In en, this message translates to:
  /// **'Panels'**
  String get supportingPanels;

  /// Manual supporting record flow. Preserve original values, ownership and date precision. Commands use one word.
  ///
  /// In en, this message translates to:
  /// **'Observations'**
  String get supportingObservations;

  /// Manual supporting record flow. Preserve original values, ownership and date precision. Commands use one word.
  ///
  /// In en, this message translates to:
  /// **'Lab panel'**
  String get supportingPanel;

  /// Manual supporting record flow. Preserve original values, ownership and date precision. Commands use one word.
  ///
  /// In en, this message translates to:
  /// **'Observation'**
  String get supportingObservation;

  /// Manual supporting record flow. Preserve original values, ownership and date precision. Commands use one word.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get supportingAdd;

  /// Manual supporting record flow. Preserve original values, ownership and date precision. Commands use one word.
  ///
  /// In en, this message translates to:
  /// **'Enter values manually. Save before attaching source files.'**
  String get supportingManual;

  /// Manual supporting record flow. Preserve original values, ownership and date precision. Commands use one word.
  ///
  /// In en, this message translates to:
  /// **'No supporting records in this view. Add a panel or observation, or change the filters.'**
  String get supportingEmpty;

  /// Manual supporting record flow. Preserve original values, ownership and date precision. Commands use one word.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get supportingTitleLabel;

  /// Manual supporting record flow. Preserve original values, ownership and date precision. Commands use one word.
  ///
  /// In en, this message translates to:
  /// **'Collection date'**
  String get supportingCollection;

  /// Manual supporting record flow. Preserve original values, ownership and date precision. Commands use one word.
  ///
  /// In en, this message translates to:
  /// **'Measured date'**
  String get supportingMeasured;

  /// Manual supporting record flow. Preserve original values, ownership and date precision. Commands use one word.
  ///
  /// In en, this message translates to:
  /// **'Report date'**
  String get supportingReport;

  /// Manual supporting record flow. Preserve original values, ownership and date precision. Commands use one word.
  ///
  /// In en, this message translates to:
  /// **'Entry date'**
  String get supportingEntry;

  /// Manual supporting record flow. Preserve original values, ownership and date precision. Commands use one word.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get supportingUnknown;

  /// Manual supporting record flow. Preserve original values, ownership and date precision. Commands use one word.
  ///
  /// In en, this message translates to:
  /// **'Date'**
  String get supportingDay;

  /// Manual supporting record flow. Preserve original values, ownership and date precision. Commands use one word.
  ///
  /// In en, this message translates to:
  /// **'Exact'**
  String get supportingExact;

  /// Manual supporting record flow. Preserve original values, ownership and date precision. Commands use one word.
  ///
  /// In en, this message translates to:
  /// **'Partial'**
  String get supportingPartial;

  /// Manual supporting record flow. Preserve original values, ownership and date precision. Commands use one word.
  ///
  /// In en, this message translates to:
  /// **'Source date'**
  String get supportingDateText;

  /// Manual supporting record flow. Preserve original values, ownership and date precision. Commands use one word.
  ///
  /// In en, this message translates to:
  /// **'Use YYYY-MM-DD for a date. For an exact time, include its UTC offset and source time zone. Keep incomplete dates as written.'**
  String get supportingDateHint;

  /// Manual supporting record flow. Preserve original values, ownership and date precision. Commands use one word.
  ///
  /// In en, this message translates to:
  /// **'Source time zone'**
  String get supportingZone;

  /// Manual supporting record flow. Preserve original values, ownership and date precision. Commands use one word.
  ///
  /// In en, this message translates to:
  /// **'Date precision'**
  String get supportingPrecision;

  /// Manual supporting record flow. Preserve original values, ownership and date precision. Commands use one word.
  ///
  /// In en, this message translates to:
  /// **'Results'**
  String get supportingResults;

  /// Manual supporting record flow. Preserve original values, ownership and date precision. Commands use one word.
  ///
  /// In en, this message translates to:
  /// **'Marker name'**
  String get supportingMarker;

  /// Manual supporting record flow. Preserve original values, ownership and date precision. Commands use one word.
  ///
  /// In en, this message translates to:
  /// **'Original marker'**
  String get supportingOriginalMarker;

  /// Manual supporting record flow. Preserve original values, ownership and date precision. Commands use one word.
  ///
  /// In en, this message translates to:
  /// **'Original value'**
  String get supportingValue;

  /// Manual supporting record flow. Preserve original values, ownership and date precision. Commands use one word.
  ///
  /// In en, this message translates to:
  /// **'Numeric'**
  String get supportingNumeric;

  /// Manual supporting record flow. Preserve original values, ownership and date precision. Commands use one word.
  ///
  /// In en, this message translates to:
  /// **'Text'**
  String get supportingQualitative;

  /// Manual supporting record flow. Preserve original values, ownership and date precision. Commands use one word.
  ///
  /// In en, this message translates to:
  /// **'Missing'**
  String get supportingMissing;

  /// Manual supporting record flow. Preserve original values, ownership and date precision. Commands use one word.
  ///
  /// In en, this message translates to:
  /// **'Qualifier'**
  String get supportingQualifier;

  /// Manual supporting record flow. Preserve original values, ownership and date precision. Commands use one word.
  ///
  /// In en, this message translates to:
  /// **'Original unit'**
  String get supportingUnit;

  /// Manual supporting record flow. Preserve original values, ownership and date precision. Commands use one word.
  ///
  /// In en, this message translates to:
  /// **'Source range'**
  String get supportingRange;

  /// Manual supporting record flow. Preserve original values, ownership and date precision. Commands use one word.
  ///
  /// In en, this message translates to:
  /// **'Source flag'**
  String get supportingFlag;

  /// Manual supporting record flow. Preserve original values, ownership and date precision. Commands use one word.
  ///
  /// In en, this message translates to:
  /// **'Source details'**
  String get supportingProvenance;

  /// Manual supporting record flow. Preserve original values, ownership and date precision. Commands use one word.
  ///
  /// In en, this message translates to:
  /// **'Laboratory'**
  String get supportingLab;

  /// Manual supporting record flow. Preserve original values, ownership and date precision. Commands use one word.
  ///
  /// In en, this message translates to:
  /// **'Laboratory identity'**
  String get supportingLabIdentity;

  /// Manual supporting record flow. Preserve original values, ownership and date precision. Commands use one word.
  ///
  /// In en, this message translates to:
  /// **'Method'**
  String get supportingMethod;

  /// Manual supporting record flow. Preserve original values, ownership and date precision. Commands use one word.
  ///
  /// In en, this message translates to:
  /// **'Method identity'**
  String get supportingMethodIdentity;

  /// Manual supporting record flow. Preserve original values, ownership and date precision. Commands use one word.
  ///
  /// In en, this message translates to:
  /// **'Specimen'**
  String get supportingSpecimen;

  /// Manual supporting record flow. Preserve original values, ownership and date precision. Commands use one word.
  ///
  /// In en, this message translates to:
  /// **'Specimen identity'**
  String get supportingSpecimenIdentity;

  /// Manual supporting record flow. Preserve original values, ownership and date precision. Commands use one word.
  ///
  /// In en, this message translates to:
  /// **'Source text'**
  String get supportingSourceText;

  /// Manual supporting record flow. Preserve original values, ownership and date precision. Commands use one word.
  ///
  /// In en, this message translates to:
  /// **'Recorded by'**
  String get supportingRecordedBy;

  /// Manual supporting record flow. Preserve original values, ownership and date precision. Commands use one word.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get supportingNotes;

  /// Manual supporting record flow. Preserve original values, ownership and date precision. Commands use one word.
  ///
  /// In en, this message translates to:
  /// **'New marker'**
  String get supportingNewMetric;

  /// Manual supporting record flow. Preserve original values, ownership and date precision. Commands use one word.
  ///
  /// In en, this message translates to:
  /// **'Reuse a saved marker to continue its trend. Similar names are kept separate.'**
  String get supportingChooseMetric;

  /// Manual supporting record flow. Preserve original values, ownership and date precision. Commands use one word.
  ///
  /// In en, this message translates to:
  /// **'Markers'**
  String get supportingMetrics;

  /// Manual supporting record flow. Preserve original values, ownership and date precision. Commands use one word.
  ///
  /// In en, this message translates to:
  /// **'Check the title, dates and each result. Numeric values can include a sign or scientific notation. Exact times need an offset and time zone.'**
  String get supportingInvalid;

  /// Manual supporting record flow. Preserve original values, ownership and date precision. Commands use one word.
  ///
  /// In en, this message translates to:
  /// **'No results recorded.'**
  String get supportingNoResults;

  /// Manual supporting record flow. Preserve original values, ownership and date precision. Commands use one word.
  ///
  /// In en, this message translates to:
  /// **'Date unknown'**
  String get supportingUnknownDate;

  /// Manual supporting record flow. Preserve original values, ownership and date precision. Commands use one word.
  ///
  /// In en, this message translates to:
  /// **'Date basis'**
  String get supportingDateBasis;

  /// Manual supporting record flow. Preserve original values, ownership and date precision. Commands use one word.
  ///
  /// In en, this message translates to:
  /// **'From date'**
  String get supportingFrom;

  /// Manual supporting record flow. Preserve original values, ownership and date precision. Commands use one word.
  ///
  /// In en, this message translates to:
  /// **'Before date'**
  String get supportingBefore;

  /// Manual supporting record flow. Preserve original values, ownership and date precision. Commands use one word.
  ///
  /// In en, this message translates to:
  /// **'Include unknown dates'**
  String get supportingIncludeUnknown;

  /// Manual supporting record flow. Preserve original values, ownership and date precision. Commands use one word.
  ///
  /// In en, this message translates to:
  /// **'Filters'**
  String get supportingFilters;

  /// Manual supporting record flow. Preserve original values, ownership and date precision. Commands use one word.
  ///
  /// In en, this message translates to:
  /// **'Trends'**
  String get supportingTrends;

  /// Manual supporting record flow. Preserve original values, ownership and date precision. Commands use one word.
  ///
  /// In en, this message translates to:
  /// **'Table'**
  String get supportingTable;

  /// Manual supporting record flow. Preserve original values, ownership and date precision. Commands use one word.
  ///
  /// In en, this message translates to:
  /// **'Source details are incomplete. These results are shown separately.'**
  String get supportingGroupUncertain;

  /// Manual supporting record flow. Preserve original values, ownership and date precision. Commands use one word.
  ///
  /// In en, this message translates to:
  /// **'Results are grouped by marker, original unit, laboratory, method and specimen. The table shows exact source values first. Points are separate. No totals or clinical interpretation are calculated.'**
  String get supportingTrendScope;

  /// Manual supporting record flow. Preserve original values, ownership and date precision. Commands use one word.
  ///
  /// In en, this message translates to:
  /// **'No numeric results for this marker and date range. Use the table to inspect every result.'**
  String get supportingNoTrend;

  /// Empty supporting trend for the selected marker and date range.
  ///
  /// In en, this message translates to:
  /// **'No results for this marker in the selected dates.'**
  String get supportingNoMatches;

  /// Manual supporting record flow. Preserve original values, ownership and date precision. Commands use one word.
  ///
  /// In en, this message translates to:
  /// **'This view is too large. Narrow the date range and retry.'**
  String get supportingTooMany;

  /// Manual supporting record flow. Preserve original values, ownership and date precision. Commands use one word.
  ///
  /// In en, this message translates to:
  /// **'This supporting record is unavailable for this person.'**
  String get supportingUnavailable;

  /// Manual supporting record flow. Preserve original values, ownership and date precision. Commands use one word.
  ///
  /// In en, this message translates to:
  /// **'Voided'**
  String get supportingVoided;

  /// Manual supporting record flow. Preserve original values, ownership and date precision. Commands use one word.
  ///
  /// In en, this message translates to:
  /// **'Void'**
  String get supportingVoid;

  /// Manual supporting record flow. Preserve original values, ownership and date precision. Commands use one word.
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get supportingRestore;

  /// Manual supporting record flow. Preserve original values, ownership and date precision. Commands use one word.
  ///
  /// In en, this message translates to:
  /// **'Void this record? Its original values and revisions will remain available.'**
  String get supportingVoidBody;

  /// Manual supporting record flow. Preserve original values, ownership and date precision. Commands use one word.
  ///
  /// In en, this message translates to:
  /// **'Restore this record to the current supporting list?'**
  String get supportingRestoreBody;

  /// Manual supporting record flow. Preserve original values, ownership and date precision. Commands use one word.
  ///
  /// In en, this message translates to:
  /// **'Revisions'**
  String get supportingRevisions;

  /// Manual supporting record flow. Preserve original values, ownership and date precision. Commands use one word.
  ///
  /// In en, this message translates to:
  /// **'Source'**
  String get supportingSource;

  /// Manual supporting record flow. Preserve original values, ownership and date precision. Commands use one word.
  ///
  /// In en, this message translates to:
  /// **'Linked context'**
  String get supportingContext;

  /// Manual supporting record flow. Preserve original values, ownership and date precision. Commands use one word.
  ///
  /// In en, this message translates to:
  /// **'Linked items and cycles provide context. They do not establish a cause.'**
  String get supportingContextHint;

  /// Manual supporting record flow. Preserve original values, ownership and date precision. Commands use one word.
  ///
  /// In en, this message translates to:
  /// **'Copied source text only. A source flag or range is not advice.'**
  String get supportingRangeHint;

  /// Manual supporting record flow. Preserve original values, ownership and date precision. Commands use one word.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get supportingRemove;

  /// Manual supporting record flow. Preserve original values, ownership and date precision. Commands use one word.
  ///
  /// In en, this message translates to:
  /// **'Previous'**
  String get supportingPrevious;

  /// Manual supporting record flow. Preserve original values, ownership and date precision. Commands use one word.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get supportingNext;

  /// Manual supporting record flow. Preserve original values, ownership and date precision. Commands use one word.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get supportingApply;

  /// Manual supporting record flow. Preserve original values, ownership and date precision. Commands use one word.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get supportingRetry;

  /// Manual supporting record flow. Preserve original values, ownership and date precision. Commands use one word.
  ///
  /// In en, this message translates to:
  /// **'Expand'**
  String get supportingExpand;

  /// Manual supporting record flow. Preserve original values, ownership and date precision. Commands use one word.
  ///
  /// In en, this message translates to:
  /// **'Collapse'**
  String get supportingCollapse;

  /// Complete supporting record message.
  ///
  /// In en, this message translates to:
  /// **'Result {current} of {count}'**
  String supportingResultPosition(int current, int count);

  /// Complete supporting record message.
  ///
  /// In en, this message translates to:
  /// **'Revision {revision}'**
  String supportingRevisionLabel(int revision);

  /// Complete supporting record message.
  ///
  /// In en, this message translates to:
  /// **'Supporting record: {title}'**
  String supportingTarget(String title);

  /// Complete supporting record message.
  ///
  /// In en, this message translates to:
  /// **'{label}: {value}'**
  String supportingDateLabel(String label, String value);

  /// Complete supporting record message.
  ///
  /// In en, this message translates to:
  /// **'{marker} · {unit}'**
  String supportingGroupLabel(String marker, String unit);

  /// Complete supporting record message.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 exact numeric result. Use the table to inspect every result.} other{{count} exact numeric results. Use the table to inspect every result.}}'**
  String supportingPlotLabel(int count);

  /// Supporting records context and precise display state.
  ///
  /// In en, this message translates to:
  /// **'Unlock Vital to view supporting records.'**
  String get supportingLocked;

  /// Supporting records context and precise display state.
  ///
  /// In en, this message translates to:
  /// **'Unable to load supporting records. Retry this view.'**
  String get supportingLoadFailure;

  /// Supporting records context and precise display state.
  ///
  /// In en, this message translates to:
  /// **'Dates from {start}, before {end}.'**
  String supportingDateWindow(String start, String end);

  /// Supporting records context and precise display state.
  ///
  /// In en, this message translates to:
  /// **'Displayed values range from {minimum} to {maximum}.'**
  String supportingPlotBounds(String minimum, String maximum);

  /// Supporting records context and precise display state.
  ///
  /// In en, this message translates to:
  /// **'Displayed source dates: {start} to {end}.'**
  String supportingPlotDates(String start, String end);

  /// Supporting records context and precise display state.
  ///
  /// In en, this message translates to:
  /// **'Source version {version}: {id}'**
  String supportingSourceVersion(String version, String id);

  /// Supporting records context and precise display state.
  ///
  /// In en, this message translates to:
  /// **'This date uses UTC because its display time zone is unavailable. The saved source date is retained.'**
  String get supportingOffsetFallback;

  /// Supporting date filter or positive list toggle.
  ///
  /// In en, this message translates to:
  /// **'Include voided'**
  String get supportingIncludeVoided;

  /// Supporting date filter or positive list toggle.
  ///
  /// In en, this message translates to:
  /// **'Show voided records alongside current records.'**
  String get supportingIncludeVoidedHint;

  /// Supporting date filter or positive list toggle.
  ///
  /// In en, this message translates to:
  /// **'Collection'**
  String get supportingCollectionChoice;

  /// Supporting date filter or positive list toggle.
  ///
  /// In en, this message translates to:
  /// **'Report'**
  String get supportingReportChoice;

  /// Supporting date filter or positive list toggle.
  ///
  /// In en, this message translates to:
  /// **'Entry'**
  String get supportingEntryChoice;

  /// Manual supporting form heading or essential save requirement.
  ///
  /// In en, this message translates to:
  /// **'Add blood test'**
  String get supportingAddPanel;

  /// Manual supporting form heading or essential save requirement.
  ///
  /// In en, this message translates to:
  /// **'Edit blood test'**
  String get supportingEditPanel;

  /// Manual supporting form heading or essential save requirement.
  ///
  /// In en, this message translates to:
  /// **'Add observation'**
  String get supportingAddObservation;

  /// Manual supporting form heading or essential save requirement.
  ///
  /// In en, this message translates to:
  /// **'Edit observation'**
  String get supportingEditObservation;

  /// Manual supporting form heading or essential save requirement.
  ///
  /// In en, this message translates to:
  /// **'Add a value, text or note. Save before attaching source files.'**
  String get supportingObservationManual;

  /// Supporting observation component field.
  ///
  /// In en, this message translates to:
  /// **'Component'**
  String get supportingComponent;

  /// Search field label in the saved marker picker.
  ///
  /// In en, this message translates to:
  /// **'Search markers'**
  String get supportingSearchMarkers;

  /// Draft supporting form with no result rows yet.
  ///
  /// In en, this message translates to:
  /// **'No values entered.'**
  String get supportingNoValues;

  /// Helper for retaining a source qualifier in the original value text.
  ///
  /// In en, this message translates to:
  /// **'Type <, ≤, > or ≥ before the value when the source uses a limit.'**
  String get supportingValueHint;

  /// Disclosure label for optional saved laboratory, method and specimen identity values.
  ///
  /// In en, this message translates to:
  /// **'Identifiers'**
  String get supportingIdentifiers;

  /// Explicit supporting result state distinct from zero and from a missing unit.
  ///
  /// In en, this message translates to:
  /// **'No result supplied.'**
  String get supportingResultMissing;

  /// Explicit missing supporting unit distinct from an entered unit.
  ///
  /// In en, this message translates to:
  /// **'Unit not supplied.'**
  String get supportingUnitMissing;

  /// Explicit missing supporting source range.
  ///
  /// In en, this message translates to:
  /// **'Range not supplied.'**
  String get supportingRangeMissing;

  /// Original saved date, zone and offset shown separately from the display date.
  ///
  /// In en, this message translates to:
  /// **'Saved source: {source}.'**
  String supportingSavedSource(String source);

  /// The requested zone used for displayed exact dates.
  ///
  /// In en, this message translates to:
  /// **'Display zone: {zone}.'**
  String supportingDisplayZone(String zone);

  /// Accessible summary for one saved supporting result row.
  ///
  /// In en, this message translates to:
  /// **'{marker}. Original value: {value}. Unit: {unit}. Source range: {range}.'**
  String supportingResultSemantics(
    String marker,
    String value,
    String unit,
    String range,
  );

  /// Accessible name for a result row marker disclosure.
  ///
  /// In en, this message translates to:
  /// **'Choose marker for result {position}.'**
  String supportingMarkerDisclosure(int position);

  /// One-word action that opens a saved supporting record or source.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get supportingOpen;

  /// Honest state when a saved supporting source version cannot be opened.
  ///
  /// In en, this message translates to:
  /// **'This saved source is no longer available. The record keeps its saved source details.'**
  String get supportingSourceUnavailable;

  /// The captured source revision or content version is no longer the current attachment.
  ///
  /// In en, this message translates to:
  /// **'This saved source changed after it was saved. Its exact original is not available.'**
  String get supportingSourceChanged;

  /// A source reference that is a report text rather than an attachment.
  ///
  /// In en, this message translates to:
  /// **'This source is saved as text only. No file is attached.'**
  String get supportingSourceTextOnly;

  /// Identifies the exact saved attachment version being viewed.
  ///
  /// In en, this message translates to:
  /// **'Saved source version {version}.'**
  String supportingSourceViewing(int version);

  /// Visible label for one saved supporting source reference.
  ///
  /// In en, this message translates to:
  /// **'Saved source, version {version}'**
  String supportingSavedSourceReference(int version);

  /// Section label for saved supporting source references.
  ///
  /// In en, this message translates to:
  /// **'Saved sources'**
  String get supportingSourceReferences;

  /// Accessible name for opening one exact saved source version.
  ///
  /// In en, this message translates to:
  /// **'Open saved source version {version}.'**
  String supportingOpenSourceVersion(int version);

  /// Labelled supporting trend table section for results without a full date.
  ///
  /// In en, this message translates to:
  /// **'Undated results'**
  String get supportingUndatedResults;

  /// Explains why undated or partial-date results cannot be plotted.
  ///
  /// In en, this message translates to:
  /// **'Results without a full date are kept here. They are not placed on the trend.'**
  String get supportingUndatedHelp;

  /// Short group reference for a supporting trend row without a full date.
  ///
  /// In en, this message translates to:
  /// **'Undated group'**
  String get supportingUndatedGroup;

  /// Visible and accessible summary of a supporting trend comparison group.
  ///
  /// In en, this message translates to:
  /// **'{marker}. Unit: {unit}. Laboratory: {laboratory}. Method: {method}. Specimen: {specimen}.'**
  String supportingGroupSummary(
    String marker,
    String unit,
    String laboratory,
    String method,
    String specimen,
  );

  /// Comparison group summary for an observed component without laboratory metadata.
  ///
  /// In en, this message translates to:
  /// **'{marker}. Unit: {unit}. Observation.'**
  String supportingGroupObservation(String marker, String unit);

  /// Conservative comparison state for observed components without laboratory identity.
  ///
  /// In en, this message translates to:
  /// **'Observed components are kept separate. No trend line joins them.'**
  String get supportingGroupObservationSeparate;

  /// Stable visible number for one supporting trend group.
  ///
  /// In en, this message translates to:
  /// **'Group {current} of {count}.'**
  String supportingGroupNumber(int current, int count);

  /// Short group reference shown in a supporting trend table row.
  ///
  /// In en, this message translates to:
  /// **'Group {number}'**
  String supportingGroupShort(int number);

  /// Labels the currently selected supporting trend group.
  ///
  /// In en, this message translates to:
  /// **'Selected group'**
  String get supportingSelectedGroup;

  /// Heading for the supporting trend comparison group selector.
  ///
  /// In en, this message translates to:
  /// **'Groups'**
  String get supportingGroups;

  /// Explains the exact supporting table order.
  ///
  /// In en, this message translates to:
  /// **'Oldest results first for the chosen date basis.'**
  String get supportingTableOrder;

  /// Accessible name for opening one saved supporting record.
  ///
  /// In en, this message translates to:
  /// **'Open {title}.'**
  String supportingOpenRecord(String title);

  /// Authored page heading for the supporting record list.
  ///
  /// In en, this message translates to:
  /// **'Supporting records'**
  String get supportingRecordsHeading;

  /// Supporting date filter error with a recovery step.
  ///
  /// In en, this message translates to:
  /// **'Enter valid dates. The end date must be after the start.'**
  String get supportingFilterInvalid;

  /// Positive description for the supporting unknown-date filter toggle.
  ///
  /// In en, this message translates to:
  /// **'Show records without a full date separately.'**
  String get supportingIncludeUnknownHint;

  /// Summary when no supporting date filter is applied.
  ///
  /// In en, this message translates to:
  /// **'All dates'**
  String get supportingAllDates;

  /// Heading for observation values in the draft form.
  ///
  /// In en, this message translates to:
  /// **'Values'**
  String get supportingValues;

  /// Plain helper for a saved supporting date.
  ///
  /// In en, this message translates to:
  /// **'Enter the date as written on the source.'**
  String get supportingDateHelp;

  /// Helper for an exact supporting source time.
  ///
  /// In en, this message translates to:
  /// **'Include the source time and offset, for example 2026-10-19T09:30+01:00.'**
  String get supportingExactDateHelp;

  /// Helper for optional source time zone provenance.
  ///
  /// In en, this message translates to:
  /// **'The source time zone, when the report names one.'**
  String get supportingZoneHelp;

  /// Files help for a supporting record rather than a dose.
  ///
  /// In en, this message translates to:
  /// **'A source file does not confirm a recorded result. Keep the original report with its saved values.'**
  String get attachmentSupportingHelp;

  /// Explains disabled file addition for a voided supporting record.
  ///
  /// In en, this message translates to:
  /// **'This supporting record is voided. Its saved files stay available to view, but new files cannot be added.'**
  String get attachmentSupportingVoided;

  /// No description provided for @supportingVoidPending.
  ///
  /// In en, this message translates to:
  /// **'Void pending'**
  String get supportingVoidPending;

  /// No description provided for @supportingRestorePending.
  ///
  /// In en, this message translates to:
  /// **'Restore pending'**
  String get supportingRestorePending;

  /// No description provided for @supportingVoidPendingBody.
  ///
  /// In en, this message translates to:
  /// **'Your request is saved on this device. Resume to check and finish it, or discard it.'**
  String get supportingVoidPendingBody;

  /// No description provided for @supportingVoidNotSaved.
  ///
  /// In en, this message translates to:
  /// **'Request not saved. Nothing changed. Try again.'**
  String get supportingVoidNotSaved;

  /// No description provided for @supportingVoidChanged.
  ///
  /// In en, this message translates to:
  /// **'Record changed. Review the latest revision, then discard the saved request.'**
  String get supportingVoidChanged;

  /// No description provided for @supportingVoidUncertain.
  ///
  /// In en, this message translates to:
  /// **'The outcome is not confirmed. Your request is saved. Resume to check it.'**
  String get supportingVoidUncertain;

  /// No description provided for @supportingVoidArchived.
  ///
  /// In en, this message translates to:
  /// **'This adult is archived. Discard the saved request or restore the adult first.'**
  String get supportingVoidArchived;

  /// No description provided for @supportingVoidMissing.
  ///
  /// In en, this message translates to:
  /// **'This record is unavailable. Discard the saved request.'**
  String get supportingVoidMissing;

  /// No description provided for @supportingVoidSaved.
  ///
  /// In en, this message translates to:
  /// **'Record voided.'**
  String get supportingVoidSaved;

  /// No description provided for @supportingRestoreSaved.
  ///
  /// In en, this message translates to:
  /// **'Record restored.'**
  String get supportingRestoreSaved;

  /// No description provided for @supportingVoidDiscarded.
  ///
  /// In en, this message translates to:
  /// **'Request discarded.'**
  String get supportingVoidDiscarded;

  /// Page title for structured JSON or CSV export.
  ///
  /// In en, this message translates to:
  /// **'Export'**
  String get exportTitle;

  /// Explains the single-person structured export selection.
  ///
  /// In en, this message translates to:
  /// **'Choose a date range and the content to include. The preview is the exact file you can save.'**
  String get exportSelectionHelp;

  /// Label for choosing the one adult whose records are exported.
  ///
  /// In en, this message translates to:
  /// **'Adult'**
  String get exportPerson;

  /// Marks an archived adult that can still be exported deliberately.
  ///
  /// In en, this message translates to:
  /// **'{name} (archived)'**
  String exportArchivedLabel(String name);

  /// Heading for the export date range.
  ///
  /// In en, this message translates to:
  /// **'Dates'**
  String get exportRange;

  /// Label for the inclusive start date.
  ///
  /// In en, this message translates to:
  /// **'From'**
  String get exportFrom;

  /// Label for the exclusive end date.
  ///
  /// In en, this message translates to:
  /// **'Before'**
  String get exportBefore;

  /// Plain explanation of the export date boundaries and time zone.
  ///
  /// In en, this message translates to:
  /// **'Dates use {zone}. From is included. Before is not.'**
  String exportRangeHelp(String zone);

  /// Heading for choosing which record types are exported.
  ///
  /// In en, this message translates to:
  /// **'Content'**
  String get exportContent;

  /// Toggle label for recorded dose revisions.
  ///
  /// In en, this message translates to:
  /// **'Doses'**
  String get exportDoses;

  /// Explains that dose corrections and original units are included.
  ///
  /// In en, this message translates to:
  /// **'Recorded doses with corrections and original units, plus explicit skips.'**
  String get exportDosesHelp;

  /// Toggle label for observations and lab panels.
  ///
  /// In en, this message translates to:
  /// **'Supporting'**
  String get exportSupporting;

  /// Explains which supporting records are included.
  ///
  /// In en, this message translates to:
  /// **'Observations and lab panels recorded in the selected dates.'**
  String get exportSupportingHelp;

  /// Privacy statement for single-person export.
  ///
  /// In en, this message translates to:
  /// **'Selected lab records include categories and source identifiers. Notes stay private unless selected.'**
  String get exportPrivateHelp;

  /// Heading for private inclusion choices.
  ///
  /// In en, this message translates to:
  /// **'Privacy'**
  String get exportPrivacy;

  /// Toggle label for optional private text in the selected content.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get exportNotes;

  /// Explains the notes toggle and that attachments are excluded.
  ///
  /// In en, this message translates to:
  /// **'Include substance instructions, notes and skip reasons. Files stay excluded.'**
  String get exportNotesHelp;

  /// Confirms the one adult included in the export.
  ///
  /// In en, this message translates to:
  /// **'Selected: {name}'**
  String exportSinglePerson(String name);

  /// Heading for choosing JSON or CSV.
  ///
  /// In en, this message translates to:
  /// **'Format'**
  String get exportFormat;

  /// JSON format choice. Not translated.
  ///
  /// In en, this message translates to:
  /// **'JSON'**
  String get exportFormatJson;

  /// CSV format choice. Not translated.
  ///
  /// In en, this message translates to:
  /// **'CSV'**
  String get exportFormatCsv;

  /// Explains the difference between JSON and CSV exports.
  ///
  /// In en, this message translates to:
  /// **'JSON keeps the full structure and meanings. CSV is a flat table for spreadsheets.'**
  String get exportFormatHelp;

  /// Command button that prepares the exact reviewed file.
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get exportPreview;

  /// Status heading while the export is captured and encoded.
  ///
  /// In en, this message translates to:
  /// **'Preparing'**
  String get exportPreparing;

  /// Explains the bounded export preparation while it runs.
  ///
  /// In en, this message translates to:
  /// **'Building one file from the selected records. Cancel leaves nothing saved.'**
  String get exportPreparingHelp;

  /// Status while the destination handoff is running.
  ///
  /// In en, this message translates to:
  /// **'Saving the reviewed file.'**
  String get exportSaving;

  /// Command button that stops export preparation or saving.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get exportCancel;

  /// Heading for the export summary before saving.
  ///
  /// In en, this message translates to:
  /// **'Review'**
  String get exportReview;

  /// Complete summary of the export date boundaries.
  ///
  /// In en, this message translates to:
  /// **'From {from} up to, but not including, {before}.'**
  String exportDateRange(String from, String before);

  /// Shows the time zone used for the date boundaries.
  ///
  /// In en, this message translates to:
  /// **'Time zone: {zone}'**
  String exportZoneLabel(String zone);

  /// Lists the selected record types in the review.
  ///
  /// In en, this message translates to:
  /// **'Content: {content}'**
  String exportContentLabel(String content);

  /// Review state when optional private text is included.
  ///
  /// In en, this message translates to:
  /// **'Private text included.'**
  String get exportNotesIncluded;

  /// Review state when optional private text is excluded.
  ///
  /// In en, this message translates to:
  /// **'Private text excluded.'**
  String get exportNotesExcluded;

  /// Number of dose records in the reviewed export.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No dose records} =1{1 dose record} other{{count} dose records}}'**
  String exportDoseCount(int count);

  /// Number of saved dose revisions, including corrections.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No dose revisions} =1{1 saved dose revision} other{{count} saved dose revisions}}'**
  String exportRevisionCount(int count);

  /// Number of supporting records in the reviewed export.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No supporting records} =1{1 supporting record} other{{count} supporting records}}'**
  String exportSupportingCount(int count);

  /// Number of supporting results across saved revisions.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No supporting results} =1{1 supporting result} other{{count} supporting results}}'**
  String exportSupportingResultCount(int count);

  /// Complete summary of the supporting records the reviewed export deliberately leaves out because their collection date cannot be placed in the selected range.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 supporting record has an unknown or partial collection date and is left out of this file.} other{{count} supporting records have unknown or partial collection dates and are left out of this file.}}'**
  String exportUndatedExcluded(int count);

  /// Review state when the unknown or partial collection dates exceeded the bounded counting window, so no exact number is claimed.
  ///
  /// In en, this message translates to:
  /// **'Supporting records with unknown or partial collection dates were not all counted and are left out of this file.'**
  String get exportUndatedUncounted;

  /// Exact byte size of the reviewed export file.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 byte} other{{count} bytes}}'**
  String exportByteCount(int count);

  /// Neutral generated file name shown in the review.
  ///
  /// In en, this message translates to:
  /// **'File: {name}'**
  String exportFileName(String name);

  /// Label for the checksum of the exact reviewed file.
  ///
  /// In en, this message translates to:
  /// **'SHA-256'**
  String get exportChecksumLabel;

  /// Explains that the preview and saved file are identical bytes.
  ///
  /// In en, this message translates to:
  /// **'This preview is the start of the exact file Save delivers.'**
  String get exportExactArtifact;

  /// Command button that hands the reviewed file to the destination.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get exportSave;

  /// Command button that returns to the export selection.
  ///
  /// In en, this message translates to:
  /// **'Change'**
  String get exportChange;

  /// Confirmation after the destination reports a saved file.
  ///
  /// In en, this message translates to:
  /// **'Saved.'**
  String get exportSaved;

  /// Confirmation after the destination reports a share handoff.
  ///
  /// In en, this message translates to:
  /// **'Shared.'**
  String get exportShared;

  /// Honest state when no destination handoff is installed.
  ///
  /// In en, this message translates to:
  /// **'Saving is not available on this device. Preview only.'**
  String get exportUnavailable;

  /// Shown when export is requested behind the app lock.
  ///
  /// In en, this message translates to:
  /// **'Unlock the app to export records.'**
  String get exportLocked;

  /// Recovery message when the display zone cannot be resolved.
  ///
  /// In en, this message translates to:
  /// **'The display time zone is unavailable. Check the device time zone, then try again.'**
  String get exportZone;

  /// Confirmation that cancellation saved nothing.
  ///
  /// In en, this message translates to:
  /// **'Export cancelled. Nothing was saved.'**
  String get exportCancelled;

  /// Recovery message when an export bound is reached.
  ///
  /// In en, this message translates to:
  /// **'This selection is too large. Choose a shorter date range or less content.'**
  String get exportTooLarge;

  /// Validation message when no export content is selected.
  ///
  /// In en, this message translates to:
  /// **'Choose at least one content type.'**
  String get exportChooseContent;

  /// Validation message for an invalid export date range.
  ///
  /// In en, this message translates to:
  /// **'Enter valid dates. Before must be later than From.'**
  String get exportInvalidRange;

  /// Generic export preparation failure with recovery.
  ///
  /// In en, this message translates to:
  /// **'Unable to prepare the export. Nothing was saved. Try again.'**
  String get exportFailed;

  /// Confirmation that a cancelled save copied nothing.
  ///
  /// In en, this message translates to:
  /// **'Save cancelled. The preview is unchanged.'**
  String get exportHandoffCancelled;

  /// Save failure that preserves the reviewed preview.
  ///
  /// In en, this message translates to:
  /// **'Unable to save. The preview is unchanged. Try again.'**
  String get exportSaveFailed;

  /// Disclosure containing optional source details, saved files and notes.
  ///
  /// In en, this message translates to:
  /// **'Details'**
  String get supportingDetails;

  /// Visible one-word command that captures an existing saved file as this record source.
  ///
  /// In en, this message translates to:
  /// **'Attach'**
  String get supportingAttach;

  /// Non-actionable state showing that the current saved file version is already a source.
  ///
  /// In en, this message translates to:
  /// **'Attached'**
  String get supportingAttached;

  /// Heading for saved files that can be captured as a source.
  ///
  /// In en, this message translates to:
  /// **'Saved files'**
  String get supportingSourceFiles;

  /// Explains the frozen source version; no claim that the file proves a result.
  ///
  /// In en, this message translates to:
  /// **'Choose a file for this adult. The saved file version stays linked if the file changes later.'**
  String get supportingSourceFilesHelp;

  /// Empty state for saved source candidates.
  ///
  /// In en, this message translates to:
  /// **'No saved files for this adult.'**
  String get supportingNoSourceFiles;

  /// Truthful trend limitation.
  ///
  /// In en, this message translates to:
  /// **'Some results in this group have no full date. They are listed separately and do not connect the line.'**
  String get supportingGroupUndated;

  /// Truthful absence for the chosen comparison identity; no other group is substituted and no plot is shown.
  ///
  /// In en, this message translates to:
  /// **'This group has no results in the selected dates. Choose another group or change the dates.'**
  String get supportingGroupNoResults;

  /// Supporting form stale-record recovery; no History or Today instruction.
  ///
  /// In en, this message translates to:
  /// **'This supporting record changed. Open Supporting records and review the latest revision before editing.'**
  String get supportingConflict;

  /// Supporting draft invalidated by deletion or dataset replacement.
  ///
  /// In en, this message translates to:
  /// **'This entry is no longer available. Open Supporting records to review saved records.'**
  String get supportingDraftUnavailable;

  /// Supporting entry whose operation already committed.
  ///
  /// In en, this message translates to:
  /// **'This supporting record was already saved. Open it to review the latest revision.'**
  String get supportingDraftSaved;

  /// Supporting local draft persistence failure.
  ///
  /// In en, this message translates to:
  /// **'Your latest changes were not kept on this device. Stay here and try again.'**
  String get supportingDraftFailure;

  /// Supporting save failure after an unconfirmed operation.
  ///
  /// In en, this message translates to:
  /// **'The supporting record could not be saved. Retry with the same details.'**
  String get supportingSaveFailure;

  /// Empty observation state with a truthful next action.
  ///
  /// In en, this message translates to:
  /// **'No values entered. Add a value, or add a note in Details.'**
  String get supportingNoValuesObservation;

  /// Accessible name for the one-word Attach command on a saved file.
  ///
  /// In en, this message translates to:
  /// **'Attach {name}.'**
  String supportingAttachSource(String name);

  /// Accessible name for the one-word Remove command on a captured source.
  ///
  /// In en, this message translates to:
  /// **'Remove saved source {name}.'**
  String supportingRemoveSource(String name);

  /// Observation empty-state validation with a concrete next action.
  ///
  /// In en, this message translates to:
  /// **'Add a value or a note before saving this observation.'**
  String get supportingObservationRequired;

  /// Authored heading for the canonical supporting labs collection.
  ///
  /// In en, this message translates to:
  /// **'Biomarkers & Labs'**
  String get screenLabsHeading;

  /// One-sentence introduction to the saved labs collection. No clinical claim.
  ///
  /// In en, this message translates to:
  /// **'Review saved lab panels and observations in their original units.'**
  String get screenLabsSubtitle;

  /// Filter choice that keeps both lab panels and observations.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get screenLabsAllRecords;

  /// Section label for the bounded latest-value projection.
  ///
  /// In en, this message translates to:
  /// **'Latest results'**
  String get screenLabsLatestEyebrow;

  /// Factual count of markers in the latest-value projection.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 marker} other{{count} markers}}'**
  String screenLabsLatestCount(int count);

  /// States the bounded window used for latest values.
  ///
  /// In en, this message translates to:
  /// **'From the {count, plural, =1{most recent dated record} other{{count} most recent dated records}}, newest first.'**
  String screenLabsLatestWindow(int count);

  /// Limits of the latest-value projection.
  ///
  /// In en, this message translates to:
  /// **'Records without a complete date, and voided records, are not included.'**
  String get screenLabsLatestExcluded;

  /// Shown when the bounded latest window does not reach the oldest record.
  ///
  /// In en, this message translates to:
  /// **'Older dated records are not included.'**
  String get screenLabsLatestOlder;

  /// Shown when more markers exist than the bounded projection keeps.
  ///
  /// In en, this message translates to:
  /// **'Only the {count} most recently measured markers are shown.'**
  String screenLabsLatestMarkerLimit(int count);

  /// Accessible summary for one latest-value card, including its exact date, record and laboratory.
  ///
  /// In en, this message translates to:
  /// **'{marker}. Value: {value} {unit}. Source range: {range}. {date}. From {record}. Laboratory: {laboratory}. Source flag: {flag}.'**
  String screenLabsLatestSemantics(
    String marker,
    String value,
    String unit,
    String range,
    String date,
    String record,
    String laboratory,
    String flag,
  );

  /// Latest-value state when all saved records have unknown dates.
  ///
  /// In en, this message translates to:
  /// **'No dated results'**
  String get screenLabsNoLatestTitle;

  /// Explains how a dated latest value is produced.
  ///
  /// In en, this message translates to:
  /// **'Add a panel with a collection date to see a latest value.'**
  String get screenLabsNoLatestBody;

  /// A comparable earlier value with its original unit.
  ///
  /// In en, this message translates to:
  /// **'Previous value: {value}'**
  String screenLabsPreviousValue(String value);

  /// Exact arithmetic change between comparable saved values.
  ///
  /// In en, this message translates to:
  /// **'Change: {value}'**
  String screenLabsChange(String value);

  /// Names the saved record that supplied a latest value.
  ///
  /// In en, this message translates to:
  /// **'From {record}.'**
  String screenLabsFromRecord(String record);

  /// A saved item or event linked as context, not as a cause.
  ///
  /// In en, this message translates to:
  /// **'Linked: {name}'**
  String screenLabsLinked(String name);

  /// Section label for the paged saved supporting records.
  ///
  /// In en, this message translates to:
  /// **'Recent records'**
  String get screenLabsRecordsEyebrow;

  /// States the collection ordering without claiming completeness.
  ///
  /// In en, this message translates to:
  /// **'Newest first'**
  String get screenLabsNewestFirst;

  /// Factual count of the saved records on the current page.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No records on this page} =1{1 record on this page} other{{count} records on this page}}'**
  String screenLabsRecordsCount(int count);

  /// Factual saved result count for one supporting record.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No results} =1{1 result} other{{count} results}}'**
  String screenLabsResultsCount(int count);

  /// A saved source reference that points to a protected attachment.
  ///
  /// In en, this message translates to:
  /// **'Source file saved'**
  String get screenLabsSourceFile;

  /// Filtered-empty heading for the labs collection.
  ///
  /// In en, this message translates to:
  /// **'No records in this view'**
  String get screenLabsNoMatchTitle;

  /// Filtered-empty recovery without inventing a network or sync state.
  ///
  /// In en, this message translates to:
  /// **'Change the filters or add a record.'**
  String get screenLabsNoMatchBody;

  /// Genuine first-use empty heading for the labs collection.
  ///
  /// In en, this message translates to:
  /// **'No lab records'**
  String get screenLabsEmptyTitle;

  /// Genuine first-use empty explanation.
  ///
  /// In en, this message translates to:
  /// **'Add a panel to keep results and their source dates.'**
  String get screenLabsEmptyBody;

  /// Factual local-storage notice heading.
  ///
  /// In en, this message translates to:
  /// **'Stored on this device'**
  String get screenLabsPrivacyTitle;

  /// Factual local-only storage statement; no cryptographic or sync claim.
  ///
  /// In en, this message translates to:
  /// **'Lab records are stored on this device. Vital does not upload them.'**
  String get screenLabsPrivacyBody;

  /// Active filter summary when browsing by report date.
  ///
  /// In en, this message translates to:
  /// **'By report date'**
  String get screenLabsBasisReport;

  /// Active filter summary when browsing by entry date.
  ///
  /// In en, this message translates to:
  /// **'By entry date'**
  String get screenLabsBasisEntry;

  /// One-sided inclusive date filter summary.
  ///
  /// In en, this message translates to:
  /// **'From {date}'**
  String screenLabsRangeFrom(String date);

  /// One-sided exclusive date filter summary.
  ///
  /// In en, this message translates to:
  /// **'Before {date}'**
  String screenLabsRangeBefore(String date);

  /// Active filter summary when undated records are hidden.
  ///
  /// In en, this message translates to:
  /// **'Unknown dates excluded'**
  String get screenLabsUnknownExcluded;

  /// Active filter summary when voided records are shown.
  ///
  /// In en, this message translates to:
  /// **'Voided included'**
  String get screenLabsVoidedIncluded;

  /// One-word action that collapses the expanded latest-value list.
  ///
  /// In en, this message translates to:
  /// **'Less'**
  String get screenLabsLess;

  /// No description provided for @reminderLimits.
  ///
  /// In en, this message translates to:
  /// **'Limits'**
  String get reminderLimits;

  /// No description provided for @reminderLimitsBody.
  ///
  /// In en, this message translates to:
  /// **'Android may delay or drop alerts after a force stop, battery limit or long gap. Reopen Vital to prepare more.'**
  String get reminderLimitsBody;

  /// Settings screen heading and shell navigation label.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// Short introduction to the settings inventory.
  ///
  /// In en, this message translates to:
  /// **'Appearance, privacy, records and help.'**
  String get settingsBody;

  /// Settings notice when appearance or time format persistence failed.
  ///
  /// In en, this message translates to:
  /// **'Some display changes were not saved. Try again in Appearance.'**
  String get settingsDisplayUnsaved;

  /// People row helper in Settings.
  ///
  /// In en, this message translates to:
  /// **'Add or edit adults.'**
  String get settingsPeopleBody;

  /// Privacy row helper in Settings.
  ///
  /// In en, this message translates to:
  /// **'Archive, delete or review copies.'**
  String get settingsPrivacyBody;

  /// Settings group heading for appearance and time controls.
  ///
  /// In en, this message translates to:
  /// **'Display'**
  String get display;

  /// Appearance row helper in Settings.
  ///
  /// In en, this message translates to:
  /// **'Theme, motion, app lock and time.'**
  String get settingsAppearanceBody;

  /// Settings group heading for reminder controls.
  ///
  /// In en, this message translates to:
  /// **'Alerts'**
  String get alerts;

  /// Reminders row helper in Settings.
  ///
  /// In en, this message translates to:
  /// **'Notification settings and checks.'**
  String get settingsRemindersBody;

  /// Settings group heading for report, export, backup and restore routes.
  ///
  /// In en, this message translates to:
  /// **'Data'**
  String get data;

  /// Reports row label, shown only when the report capability is available.
  ///
  /// In en, this message translates to:
  /// **'Reports'**
  String get reports;

  /// Reports row helper in Settings.
  ///
  /// In en, this message translates to:
  /// **'Review your substance reports.'**
  String get settingsReportsBody;

  /// Exports row label, shown only when the export capability is available.
  ///
  /// In en, this message translates to:
  /// **'Exports'**
  String get exports;

  /// Exports row helper in Settings.
  ///
  /// In en, this message translates to:
  /// **'Save your records as structured data.'**
  String get settingsExportsBody;

  /// Backup row label, shown only when the backup capability is available.
  ///
  /// In en, this message translates to:
  /// **'Backup'**
  String get backup;

  /// Backup row helper in Settings.
  ///
  /// In en, this message translates to:
  /// **'Create a protected full copy.'**
  String get settingsBackupBody;

  /// Restore row label, shown only when the restore capability is available.
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get restore;

  /// Restore row helper in Settings.
  ///
  /// In en, this message translates to:
  /// **'Replace this installation from a backup.'**
  String get settingsRestoreBody;

  /// Settings group heading for diagnostics, help and licence information.
  ///
  /// In en, this message translates to:
  /// **'Support'**
  String get support;

  /// Diagnostics screen heading and Settings row label.
  ///
  /// In en, this message translates to:
  /// **'Diagnostics'**
  String get diagnostics;

  /// Diagnostics row helper in Settings.
  ///
  /// In en, this message translates to:
  /// **'Recent local error codes.'**
  String get settingsDiagnosticsBody;

  /// Help screen heading and Settings row label.
  ///
  /// In en, this message translates to:
  /// **'Help'**
  String get help;

  /// Help row helper in Settings.
  ///
  /// In en, this message translates to:
  /// **'Recovery, privacy and sources.'**
  String get settingsHelpBody;

  /// Licence screen heading and Settings row label.
  ///
  /// In en, this message translates to:
  /// **'Licences'**
  String get licences;

  /// Licence row helper in Settings and Help.
  ///
  /// In en, this message translates to:
  /// **'Bundled open-source notices.'**
  String get settingsLicencesBody;

  /// Privacy screen heading and Settings row label.
  ///
  /// In en, this message translates to:
  /// **'Privacy'**
  String get privacy;

  /// Privacy screen introduction.
  ///
  /// In en, this message translates to:
  /// **'Records stay on this device. They leave only when you export or back up.'**
  String get privacyBody;

  /// Truthful limit of local adult profiles: they express relationship and ownership, not separate access rights.
  ///
  /// In en, this message translates to:
  /// **'Anyone who can unlock Vital on this device can see your records.'**
  String get privacyOperator;

  /// Explains the difference between archive and delete without exposing another person’s data.
  ///
  /// In en, this message translates to:
  /// **'Archive keeps history and stops reminders. Delete removes only that person’s records, files and drafts. Me stays available.'**
  String get privacyArchiveHelp;

  /// Privacy section heading for already-shared and stale backup copies.
  ///
  /// In en, this message translates to:
  /// **'Copies'**
  String get copies;

  /// Explains stale backup and already-shared copy limits.
  ///
  /// In en, this message translates to:
  /// **'Copies you saved or shared are outside Vital’s control. Restoring an old backup can bring back records you deleted here.'**
  String get privacyCopies;

  /// Privacy section heading listing retained archived adults.
  ///
  /// In en, this message translates to:
  /// **'Archived people'**
  String get archivedPeople;

  /// Explains retained history and stopped reminders until the operator explicitly resumes plans.
  ///
  /// In en, this message translates to:
  /// **'History is kept. Reminders stay stopped until you set them again.'**
  String get privacyArchivedHelp;

  /// Empty state for the archived people section.
  ///
  /// In en, this message translates to:
  /// **'No archived people.'**
  String get privacyNoneArchived;

  /// Explains that Me is retained when its records are deleted.
  ///
  /// In en, this message translates to:
  /// **'Your profile stays available after deletion.'**
  String get privacyMeOwner;

  /// Ownership label for another adult in the privacy list.
  ///
  /// In en, this message translates to:
  /// **'Records for this adult.'**
  String get privacyOtherOwner;

  /// Confirms deletion of only the main user’s records.
  ///
  /// In en, this message translates to:
  /// **'Delete all your saved records, files and drafts? This cannot be undone. Saved or shared copies outside Vital remain.'**
  String get deleteMeBody;

  /// Live result after archiving one adult.
  ///
  /// In en, this message translates to:
  /// **'{person} archived. History is kept and reminders are stopped.'**
  String privacyArchived(String person);

  /// Accessible name for the visible one-word Archive command, naming the selected adult.
  ///
  /// In en, this message translates to:
  /// **'Archive {person}'**
  String privacyArchiveSemantic(String person);

  /// Accessible name for the visible one-word Reactivate command, naming the selected adult.
  ///
  /// In en, this message translates to:
  /// **'Reactivate {person}'**
  String privacyReactivateSemantic(String person);

  /// Accessible name for the visible one-word Delete command, naming the selected adult.
  ///
  /// In en, this message translates to:
  /// **'Delete {person}'**
  String privacyDeleteSemantic(String person);

  /// Accessible name for deleting only the main user’s records while Me stays available.
  ///
  /// In en, this message translates to:
  /// **'Delete records for {person}'**
  String privacyDeleteRecordsSemantic(String person);

  /// Live result after reactivating one adult.
  ///
  /// In en, this message translates to:
  /// **'{person} reactivated. Reminders stay stopped until you set them again.'**
  String privacyReactivated(String person);

  /// Live result after deleting the main user’s records.
  ///
  /// In en, this message translates to:
  /// **'Records deleted. Your profile is still available.'**
  String get privacyMeDeleted;

  /// Live result after deleting another adult.
  ///
  /// In en, this message translates to:
  /// **'{person} deleted.'**
  String privacyDeleted(String person);

  /// Failure result for an archive, reactivation or deletion write.
  ///
  /// In en, this message translates to:
  /// **'Could not confirm the change. Review your records before trying again.'**
  String get privacyNotSaved;

  /// Explains the bounded content of local diagnostics.
  ///
  /// In en, this message translates to:
  /// **'Diagnostics stay on this device. They contain error codes and the platform only.'**
  String get diagnosticsBody;

  /// Truthfully states that no remote diagnostic sender exists.
  ///
  /// In en, this message translates to:
  /// **'Nothing is sent automatically. This build has no diagnostic uploader.'**
  String get diagnosticsNoSend;

  /// Empty state for the bounded local diagnostic log.
  ///
  /// In en, this message translates to:
  /// **'No recent issues.'**
  String get diagnosticsEmpty;

  /// Live result after clearing the local diagnostic log.
  ///
  /// In en, this message translates to:
  /// **'Diagnostics cleared.'**
  String get diagnosticsCleared;

  /// Failure result when clearing the local diagnostic log did not persist.
  ///
  /// In en, this message translates to:
  /// **'Not cleared. Try again.'**
  String get diagnosticsClearFailure;

  /// Local diagnostic event label for a data load failure.
  ///
  /// In en, this message translates to:
  /// **'Data load failed'**
  String get diagnosticDataLoad;

  /// Local diagnostic event label for an unavailable bundled notice.
  ///
  /// In en, this message translates to:
  /// **'Licence notice failed'**
  String get diagnosticLicenceNotice;

  /// Local diagnostic event label for a profile archive or reactivation failure.
  ///
  /// In en, this message translates to:
  /// **'Archive failed'**
  String get diagnosticProfileArchive;

  /// Local diagnostic event label for a scoped deletion failure.
  ///
  /// In en, this message translates to:
  /// **'Delete failed'**
  String get diagnosticProfileDelete;

  /// Help screen introduction.
  ///
  /// In en, this message translates to:
  /// **'Recovery, privacy and source information for this device.'**
  String get helpBody;

  /// Help section heading for truthful recovery steps.
  ///
  /// In en, this message translates to:
  /// **'Recovery'**
  String get recovery;

  /// Recovery explanation for an unopened dataset.
  ///
  /// In en, this message translates to:
  /// **'If Vital cannot open your records, it never starts an empty replacement. Unlock your device and retry.'**
  String get recoveryOpen;

  /// Linux-specific keyring recovery step.
  ///
  /// In en, this message translates to:
  /// **'On Linux, unlock the login keyring so Vital can reach its key.'**
  String get recoveryKeyring;

  /// Recovery explanation for app lock authentication failure.
  ///
  /// In en, this message translates to:
  /// **'If app lock fails, records stay hidden. Retry after your device unlocks.'**
  String get recoveryLock;

  /// Local-only privacy statement that avoids certification claims.
  ///
  /// In en, this message translates to:
  /// **'Vital has no accounts, ads or analytics. Your records stay here unless you save or share a copy.'**
  String get privacyLocal;

  /// Explains generic notification text.
  ///
  /// In en, this message translates to:
  /// **'Reminders use a generic message without names or amounts.'**
  String get privacyNotifications;

  /// Explains app-switcher preview protection when app lock is enabled.
  ///
  /// In en, this message translates to:
  /// **'Recent-app previews are hidden while app lock is on.'**
  String get privacySwitcher;

  /// Explains the limit of an already-shared copy.
  ///
  /// In en, this message translates to:
  /// **'Copies you share are outside Vital’s control.'**
  String get privacyShared;

  /// Help section heading for catalogue source metadata.
  ///
  /// In en, this message translates to:
  /// **'Sources'**
  String get sources;

  /// Truthful source empty state when no catalogue is admitted.
  ///
  /// In en, this message translates to:
  /// **'No catalogue is installed. Custom items are still available.'**
  String get sourcesNone;

  /// Failure result when catalogue metadata cannot be read.
  ///
  /// In en, this message translates to:
  /// **'Catalogue source details are unavailable.'**
  String get sourcesUnavailable;

  /// Help section heading for the product description.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get about;

  /// Short truthful product description without a medical claim.
  ///
  /// In en, this message translates to:
  /// **'Vital keeps your substance records on this device.'**
  String get aboutBody;

  /// Truthful intended-purpose limit without claiming certification or clinical authority.
  ///
  /// In en, this message translates to:
  /// **'This is a personal record, not a clinical record or an emergency monitor.'**
  String get aboutLimit;

  /// Licence row label for the application’s own MIT licence.
  ///
  /// In en, this message translates to:
  /// **'Vital licence'**
  String get appLicence;

  /// Licence row helper for the application licence.
  ///
  /// In en, this message translates to:
  /// **'MIT licence text.'**
  String get appLicenceBody;

  /// Licence list heading for adopted open-source package notices.
  ///
  /// In en, this message translates to:
  /// **'Package notices'**
  String get packageNotices;

  /// Explains the bundled licence information without claiming certification.
  ///
  /// In en, this message translates to:
  /// **'Vital is open source under the MIT licence. Adopted package notices are bundled with the app.'**
  String get licencesBody;

  /// Detail screen heading for one bundled licence notice.
  ///
  /// In en, this message translates to:
  /// **'Licence'**
  String get licence;

  /// Licence list row helper for one package notice.
  ///
  /// In en, this message translates to:
  /// **'Bundled licence text.'**
  String get licenceDetailBody;

  /// Failure result when bundled licence notices cannot be read.
  ///
  /// In en, this message translates to:
  /// **'Licence notices are unavailable in this build.'**
  String get licencesUnavailable;

  /// Page heading and History entry for person-scoped report selection.
  ///
  /// In en, this message translates to:
  /// **'Reports'**
  String get reportsTitle;

  /// Plain explanation of the report selection before generation.
  ///
  /// In en, this message translates to:
  /// **'Choose exact dates and whether to include private context.'**
  String get reportScopeHelp;

  /// Adult selection label.
  ///
  /// In en, this message translates to:
  /// **'Person'**
  String get reportPerson;

  /// Start date label.
  ///
  /// In en, this message translates to:
  /// **'From'**
  String get reportFrom;

  /// Inclusive end date label.
  ///
  /// In en, this message translates to:
  /// **'Through'**
  String get reportThrough;

  /// Exact date entry format.
  ///
  /// In en, this message translates to:
  /// **'Use YYYY-MM-DD.'**
  String get reportDateHelp;

  /// Explains that the end date is included.
  ///
  /// In en, this message translates to:
  /// **'The end date is included.'**
  String get reportThroughHelp;

  /// Explains the optional report identity.
  ///
  /// In en, this message translates to:
  /// **'Optional. Shown on the first page.'**
  String get reportNameHelp;

  /// Heading for item content selection.
  ///
  /// In en, this message translates to:
  /// **'Content'**
  String get reportContent;

  /// Explains the default all-items scope.
  ///
  /// In en, this message translates to:
  /// **'All items are included unless you choose specific items.'**
  String get reportContentHelp;

  /// Selects every recorded item.
  ///
  /// In en, this message translates to:
  /// **'All items'**
  String get reportAllItems;

  /// Empty item content state.
  ///
  /// In en, this message translates to:
  /// **'No recorded items in this period.'**
  String get reportNoItems;

  /// Toggle label for supporting context.
  ///
  /// In en, this message translates to:
  /// **'Supporting records'**
  String get reportContext;

  /// Explains supporting context inclusion.
  ///
  /// In en, this message translates to:
  /// **'Include supporting records with saved categories and accession or report identifiers from the selected period.'**
  String get reportContextHelp;

  /// Toggle label for private notes.
  ///
  /// In en, this message translates to:
  /// **'Private notes'**
  String get reportNotes;

  /// Explains private note inclusion.
  ///
  /// In en, this message translates to:
  /// **'Include substance instructions and notes. Detailed history also includes skip reasons.'**
  String get reportNotesHelp;

  /// Toggle label for source files.
  ///
  /// In en, this message translates to:
  /// **'Source files'**
  String get reportSources;

  /// Explains source file listing without embedding contents.
  ///
  /// In en, this message translates to:
  /// **'List attached source file names. File contents stay separate.'**
  String get reportSourcesHelp;

  /// Heading for the selection review panel.
  ///
  /// In en, this message translates to:
  /// **'Review'**
  String get reportReview;

  /// Selected adult in the review summary.
  ///
  /// In en, this message translates to:
  /// **'Person: {name}'**
  String reportPersonValue(String name);

  /// Selected period and shown time zone.
  ///
  /// In en, this message translates to:
  /// **'Period: {from} to {to}. Times shown in {zone}.'**
  String reportPeriodValue(String from, String to, String zone);

  /// Selected item count.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 selected item} other{{count} selected items}}'**
  String reportItemCount(int count);

  /// Template identifier and version.
  ///
  /// In en, this message translates to:
  /// **'Template {id} version {version}'**
  String reportTemplateValue(String id, String version);

  /// Progress state while reading records.
  ///
  /// In en, this message translates to:
  /// **'Reading records'**
  String get reportCapturing;

  /// Progress state while building the PDF.
  ///
  /// In en, this message translates to:
  /// **'Building report'**
  String get reportRendering;

  /// One-word command to generate and preview the report.
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get reportPreview;

  /// Cancellation result with unchanged choices.
  ///
  /// In en, this message translates to:
  /// **'Report cancelled. Your choices are unchanged.'**
  String get reportCancelled;

  /// Generic report failure with a recovery step.
  ///
  /// In en, this message translates to:
  /// **'Report not created. Try again.'**
  String get reportFailure;

  /// Source limit failure with a recovery step.
  ///
  /// In en, this message translates to:
  /// **'Too many doses for one summary. Narrow the dates or items, then try again.'**
  String get reportSourceLimit;

  /// Attachment limit failure with a recovery step.
  ///
  /// In en, this message translates to:
  /// **'Too many source files for one summary. Choose fewer items, then try again.'**
  String get reportAttachmentLimit;

  /// Missing adult recovery.
  ///
  /// In en, this message translates to:
  /// **'Your profile is unavailable. Reopen Vital and try again.'**
  String get reportPersonMissing;

  /// Archived adult recovery.
  ///
  /// In en, this message translates to:
  /// **'Your profile is unavailable. Reopen Vital and try again.'**
  String get reportPersonArchived;

  /// Unavailable time zone recovery.
  ///
  /// In en, this message translates to:
  /// **'The time zone is unavailable. Choose the device time zone, then try again.'**
  String get reportZoneUnavailable;

  /// Locked app recovery.
  ///
  /// In en, this message translates to:
  /// **'Vital is locked. Unlock it, then try again.'**
  String get reportLocked;

  /// Artifact ready state.
  ///
  /// In en, this message translates to:
  /// **'Report ready.'**
  String get reportGenerated;

  /// Preview page heading.
  ///
  /// In en, this message translates to:
  /// **'Report preview'**
  String get reportPreviewTitle;

  /// Empty preview state.
  ///
  /// In en, this message translates to:
  /// **'No report is ready. Return to Reports and preview one.'**
  String get reportUnavailable;

  /// Preview mode label.
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get reportPreviewMode;

  /// Structured text alternative mode label.
  ///
  /// In en, this message translates to:
  /// **'Text'**
  String get reportText;

  /// Page count and file size.
  ///
  /// In en, this message translates to:
  /// **'{pages, plural, =1{1 page} other{{pages} pages}} · {kilobytes} KB'**
  String reportArtifactValue(int pages, int kilobytes);

  /// Truthful unavailable save and share notice.
  ///
  /// In en, this message translates to:
  /// **'Save and share are unavailable in this build. The preview is complete.'**
  String get reportHandoffUnavailable;

  /// Truthful unavailable save notice.
  ///
  /// In en, this message translates to:
  /// **'Save is unavailable in this build.'**
  String get reportSaveUnavailable;

  /// Truthful unavailable share notice.
  ///
  /// In en, this message translates to:
  /// **'Share is unavailable in this build.'**
  String get reportShareUnavailable;

  /// Completed handoff result.
  ///
  /// In en, this message translates to:
  /// **'Report saved to the chosen location.'**
  String get reportHandoffComplete;

  /// Cancelled handoff result.
  ///
  /// In en, this message translates to:
  /// **'Handoff cancelled.'**
  String get reportHandoffCancelled;

  /// Failed handoff result with a recovery step.
  ///
  /// In en, this message translates to:
  /// **'Handoff failed. Try again.'**
  String get reportHandoffFailed;

  /// Neutral report id and document fingerprint.
  ///
  /// In en, this message translates to:
  /// **'Report {id} · Fingerprint {hash}'**
  String reportArtifactIdentity(String id, String hash);

  /// Accessibility and recipient-copy limitations.
  ///
  /// In en, this message translates to:
  /// **'The PDF is not tagged. Use Text for the accessible structured version. Recipients\' copies are outside this app\'s control.'**
  String get reportArtifactLimits;

  /// One-word share command.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get share;

  /// Optional report identity field label.
  ///
  /// In en, this message translates to:
  /// **'Report name'**
  String get reportIdentity;

  /// Source changed during capture; recovery step is to retry.
  ///
  /// In en, this message translates to:
  /// **'Records changed while the report was prepared. Try again.'**
  String get reportSourceChanged;

  /// Page/item count limit with a recovery step.
  ///
  /// In en, this message translates to:
  /// **'This report is too large. Narrow the dates or items, then try again.'**
  String get reportPageLimit;

  /// Share-sheet handoff does not prove receipt.
  ///
  /// In en, this message translates to:
  /// **'Report offered to the chosen app. Vital cannot confirm receipt.'**
  String get reportShareOffered;

  /// Report selection or validation message.
  ///
  /// In en, this message translates to:
  /// **'Substance summary'**
  String get reportSummaryTemplate;

  /// Report selection or validation message.
  ///
  /// In en, this message translates to:
  /// **'Detailed history'**
  String get reportHistoryTemplate;

  /// Report selection or validation message.
  ///
  /// In en, this message translates to:
  /// **'Event review'**
  String get reportEventTemplate;

  /// Report selection or validation message.
  ///
  /// In en, this message translates to:
  /// **'Skipped entries'**
  String get reportSkippedRows;

  /// Report selection or validation message.
  ///
  /// In en, this message translates to:
  /// **'Include entries marked as skipped.'**
  String get reportSkippedRowsHelp;

  /// Report selection or validation message.
  ///
  /// In en, this message translates to:
  /// **'Unrecorded entries'**
  String get reportUnrecordedRows;

  /// Report selection or validation message.
  ///
  /// In en, this message translates to:
  /// **'Include past planned entries with no recorded action. These do not prove a missed dose.'**
  String get reportUnrecordedRowsHelp;

  /// Report selection or validation message.
  ///
  /// In en, this message translates to:
  /// **'Choose an event to review.'**
  String get reportEventRequired;

  /// Report selection or validation message.
  ///
  /// In en, this message translates to:
  /// **'This event is no longer available. Choose another event.'**
  String get reportEventMissing;

  /// Report selection or validation message.
  ///
  /// In en, this message translates to:
  /// **'Choose dates that cover the event’s recorded start and end.'**
  String get reportEventRange;

  /// Report selection or validation message.
  ///
  /// In en, this message translates to:
  /// **'Choose one event and dates that cover its recorded start and end. Dates without a known boundary stay uncertain.'**
  String get reportEventRangeHelp;

  /// Selected event identity above its recorded dates.
  ///
  /// In en, this message translates to:
  /// **'Event: {name}'**
  String reportEventSelected(String name);

  /// Zone used for the selected event's recorded boundaries.
  ///
  /// In en, this message translates to:
  /// **'Event zone: {zone}'**
  String reportEventZoneValue(String zone);

  /// Actionable range explanation when both event boundaries are known.
  ///
  /// In en, this message translates to:
  /// **'The selected dates do not include this event. Apply {from} to {through} to cover its recorded start and end.'**
  String reportEventRangeAction(String from, String through);

  /// Actionable range explanation when at least one event boundary is unknown.
  ///
  /// In en, this message translates to:
  /// **'The selected dates do not include this event. Apply {from} to {through} to cover its recorded dates.'**
  String reportEventRangePartialAction(String from, String through);

  /// Accessible name for the one-word Apply date action.
  ///
  /// In en, this message translates to:
  /// **'Apply report dates from {from} to {through}'**
  String reportEventApplyRangeLabel(String from, String through);

  /// Report selection or validation message.
  ///
  /// In en, this message translates to:
  /// **'No events are available.'**
  String get reportNoEvents;

  /// Report selection or validation message.
  ///
  /// In en, this message translates to:
  /// **'Use a report name of 120 characters or fewer.'**
  String get reportNameLimit;

  /// Section heading above the backup password fields.
  ///
  /// In en, this message translates to:
  /// **'Create backup'**
  String get backupCreateHeading;

  /// Prominent scope label; a full backup is not single-person.
  ///
  /// In en, this message translates to:
  /// **'All your records'**
  String get backupAllAdults;

  /// Prominent label that attached files are inside the full backup.
  ///
  /// In en, this message translates to:
  /// **'Attached files included'**
  String get backupIncludesFiles;

  /// Visible label for the password used to protect a backup.
  ///
  /// In en, this message translates to:
  /// **'Backup password'**
  String get backupPasswordLabel;

  /// Visible label for repeating the backup password.
  ///
  /// In en, this message translates to:
  /// **'Confirm password'**
  String get backupConfirmLabel;

  /// Password length requirement shown before entry.
  ///
  /// In en, this message translates to:
  /// **'Use at least 12 characters.'**
  String get backupPasswordHelper;

  /// Essential consequence before creating a password-protected backup.
  ///
  /// In en, this message translates to:
  /// **'You need this password to restore your records. It cannot be recovered.'**
  String get backupPasswordLoss;

  /// Confirms that the backup password is not persisted.
  ///
  /// In en, this message translates to:
  /// **'The password is not stored.'**
  String get backupPasswordNotStored;

  /// Progress state while a coherent database snapshot is captured.
  ///
  /// In en, this message translates to:
  /// **'Preparing records'**
  String get backupPreparing;

  /// Progress state while the archive is authenticated and encrypted.
  ///
  /// In en, this message translates to:
  /// **'Encrypting backup'**
  String get backupEncrypting;

  /// Progress state while the completed archive is reopened and verified.
  ///
  /// In en, this message translates to:
  /// **'Checking backup'**
  String get backupChecking;

  /// Result heading after a complete validated archive exists.
  ///
  /// In en, this message translates to:
  /// **'Backup ready'**
  String get backupReadyHeading;

  /// Verified full-backup scope counts.
  ///
  /// In en, this message translates to:
  /// **'Includes {people, plural, =1{1 adult} other{{people} adults}} and {attachments, plural, =1{1 file} other{{attachments} files}}.'**
  String backupContents(int people, int attachments);

  /// Neutral archive size.
  ///
  /// In en, this message translates to:
  /// **'Size {size}.'**
  String backupSize(String size);

  /// Local creation date and time for the archive.
  ///
  /// In en, this message translates to:
  /// **'Created {date}.'**
  String backupCreated(String date);

  /// Recovery explanation after a backup is ready.
  ///
  /// In en, this message translates to:
  /// **'Keep the file and password safe. Restore needs both.'**
  String get backupKeepSafe;

  /// Consequence of leaving a ready backup without saving it.
  ///
  /// In en, this message translates to:
  /// **'Save before leaving. An unsaved backup is deleted at the next launch.'**
  String get backupUnsavedWarning;

  /// Short heading when no generated-artifact save handoff is integrated.
  ///
  /// In en, this message translates to:
  /// **'Cannot save'**
  String get backupCannotSave;

  /// Truthful capability statement when no save handoff is integrated.
  ///
  /// In en, this message translates to:
  /// **'Saving backup files is unavailable on this device.'**
  String get backupSavingUnavailable;

  /// Result heading after the destination confirms a completed save.
  ///
  /// In en, this message translates to:
  /// **'Backup saved'**
  String get backupSavedHeading;

  /// Neutral saved file name shown after the destination confirms the copy.
  ///
  /// In en, this message translates to:
  /// **'Saved as {name}.'**
  String backupSavedBody(String name);

  /// Confirmation title before deleting the staged backup file.
  ///
  /// In en, this message translates to:
  /// **'Delete backup?'**
  String get backupDeleteHeading;

  /// Consequence before deleting an unsaved backup file.
  ///
  /// In en, this message translates to:
  /// **'The backup file will be deleted. Your records are not changed.'**
  String get backupDeleteBody;

  /// Result heading after a user cancellation.
  ///
  /// In en, this message translates to:
  /// **'Backup cancelled'**
  String get backupCancelled;

  /// Confirms cancellation left no reported archive.
  ///
  /// In en, this message translates to:
  /// **'No backup was created.'**
  String get backupCancelledBody;

  /// Generic failure heading.
  ///
  /// In en, this message translates to:
  /// **'Backup failed'**
  String get backupFailedHeading;

  /// Recovery step and live-data assurance after a failed backup.
  ///
  /// In en, this message translates to:
  /// **'Your records were not changed. Try again.'**
  String get backupFailedBody;

  /// Failure heading for a storage-capacity problem.
  ///
  /// In en, this message translates to:
  /// **'Not enough space'**
  String get backupNoSpaceHeading;

  /// Recovery step and live-data assurance after low storage.
  ///
  /// In en, this message translates to:
  /// **'Free some space and try again. Your records were not changed.'**
  String get backupNoSpaceBody;

  /// Failure heading when archive authentication rejects the password.
  ///
  /// In en, this message translates to:
  /// **'Password not accepted'**
  String get backupWrongPassword;

  /// Recovery step after a rejected backup password.
  ///
  /// In en, this message translates to:
  /// **'Check the password and try again.'**
  String get backupWrongPasswordBody;

  /// Failure heading when a file is not a valid or intact Vital backup.
  ///
  /// In en, this message translates to:
  /// **'Backup damaged'**
  String get backupDamagedHeading;

  /// Truthful cause for rejected archive bytes.
  ///
  /// In en, this message translates to:
  /// **'The file is damaged or not a Vital backup.'**
  String get backupDamagedBody;

  /// Failure heading for a format or database version this build cannot open.
  ///
  /// In en, this message translates to:
  /// **'Newer backup'**
  String get backupNewerHeading;

  /// Explains a version mismatch without inventing an upgrade path.
  ///
  /// In en, this message translates to:
  /// **'This backup needs a newer version of Vital.'**
  String get backupNewerBody;

  /// Failure heading when the archive does not match its own records.
  ///
  /// In en, this message translates to:
  /// **'Backup incomplete'**
  String get backupIncompleteHeading;

  /// Integrity failure explanation and live-data assurance.
  ///
  /// In en, this message translates to:
  /// **'The file did not match its records. Your records were not changed.'**
  String get backupIncompleteBody;

  /// Instruction when app lock prevents a protected snapshot.
  ///
  /// In en, this message translates to:
  /// **'Unlock to create a backup.'**
  String get backupLocked;

  /// Short failure heading for a locked app.
  ///
  /// In en, this message translates to:
  /// **'Unlock first'**
  String get backupLockedHeading;

  /// Validation error for a short backup password.
  ///
  /// In en, this message translates to:
  /// **'Use at least 12 characters.'**
  String get backupShortPassword;

  /// Validation error when the confirmation differs.
  ///
  /// In en, this message translates to:
  /// **'Passwords do not match.'**
  String get backupPasswordMismatch;

  /// Validation error for an unreasonably long password.
  ///
  /// In en, this message translates to:
  /// **'Use a shorter password.'**
  String get backupPasswordLong;

  /// Failure heading when another backup operation is already running.
  ///
  /// In en, this message translates to:
  /// **'Backup busy'**
  String get backupBusyHeading;

  /// Recovery step for a concurrent backup attempt.
  ///
  /// In en, this message translates to:
  /// **'Finish the current backup before starting another.'**
  String get backupBusyBody;

  /// Heading when protected storage or the backup service is not ready.
  ///
  /// In en, this message translates to:
  /// **'Backup unavailable'**
  String get backupUnavailableHeading;

  /// Guidance when the record store cannot provide a protected snapshot.
  ///
  /// In en, this message translates to:
  /// **'Open your records before creating a backup.'**
  String get backupUnavailableBody;

  /// Heading when the destination did not confirm the save; the staged archive remains.
  ///
  /// In en, this message translates to:
  /// **'Not saved'**
  String get backupSaveFailedHeading;

  /// Recovery step after the save handoff fails or is interrupted.
  ///
  /// In en, this message translates to:
  /// **'The backup file is still here. Try again.'**
  String get backupSaveFailedBody;

  /// One-word action that closes a completed result state.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// A backup exceeds the actual destination transfer limit; do not suggest a retry can fix it.
  ///
  /// In en, this message translates to:
  /// **'This backup is larger than this device’s save limit. The staged backup is kept.'**
  String get backupSaveLimit;

  /// Heading for replacing this installation from a protected backup.
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get restoreTitle;

  /// Explains the restore scope before choosing an archive.
  ///
  /// In en, this message translates to:
  /// **'Use a Vital backup to replace every record on this device. You review the backup before anything changes.'**
  String get restoreIntro;

  /// One-word button that opens the file picker for a backup archive.
  ///
  /// In en, this message translates to:
  /// **'Choose'**
  String get restoreChoose;

  /// Label for the chosen backup archive name.
  ///
  /// In en, this message translates to:
  /// **'Backup file'**
  String get restoreArchiveLabel;

  /// Empty state for the backup file selection.
  ///
  /// In en, this message translates to:
  /// **'No backup chosen'**
  String get restoreArchiveNone;

  /// Label for the password that opens the chosen backup.
  ///
  /// In en, this message translates to:
  /// **'Backup password'**
  String get restorePasswordLabel;

  /// Helper for the backup password field.
  ///
  /// In en, this message translates to:
  /// **'Enter the password used when this backup was created.'**
  String get restorePasswordHelp;

  /// One-word button that validates the archive into protected staging.
  ///
  /// In en, this message translates to:
  /// **'Check'**
  String get restoreCheck;

  /// Status while the archive is decrypted, verified and inspected.
  ///
  /// In en, this message translates to:
  /// **'Checking archive'**
  String get restoreChecking;

  /// Heading for the validated archive contents before replacement.
  ///
  /// In en, this message translates to:
  /// **'Backup contents'**
  String get restorePreviewTitle;

  /// Shows the archive creation date.
  ///
  /// In en, this message translates to:
  /// **'Created {date}'**
  String restoreCreated(String date);

  /// Label for the people represented in the archive.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get restorePeople;

  /// Count of people represented in the archive.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No people} =1{1 person} other{{count} people}}'**
  String restorePeopleCount(int count);

  /// Explains that the preview list is bounded.
  ///
  /// In en, this message translates to:
  /// **'Showing the first {count} people.'**
  String restorePeopleMore(int count);

  /// Suffix for an archived adult in the backup preview.
  ///
  /// In en, this message translates to:
  /// **'Archived'**
  String get restoreArchived;

  /// Label for the earliest and latest dated records in the archive.
  ///
  /// In en, this message translates to:
  /// **'Record dates'**
  String get restoreCoverage;

  /// Exact date range for restored records.
  ///
  /// In en, this message translates to:
  /// **'{from} to {to}'**
  String restoreCoverageRange(String from, String to);

  /// States that the archive contains no records with dates.
  ///
  /// In en, this message translates to:
  /// **'No dated records'**
  String get restoreCoverageEmpty;

  /// Clarifies the time zone used for coverage dates.
  ///
  /// In en, this message translates to:
  /// **'Dates use this device\'s time zone.'**
  String get restoreLocalDates;

  /// Count of current non-voided administration records in the archive.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No records} =1{1 record} other{{count} records}}'**
  String restoreRecords(int count);

  /// Count of tracked substances in the archive.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No substances} =1{1 substance} other{{count} substances}}'**
  String restoreSubstances(int count);

  /// Count of non-voided supporting records in the archive.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No supporting records} =1{1 supporting record} other{{count} supporting records}}'**
  String restoreSupporting(int count);

  /// Count of ready linked attachments in the archive.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No attachments} =1{1 attachment} other{{count} attachments}}'**
  String restoreAttachments(int count);

  /// Warns that an older schema is migrated during restore.
  ///
  /// In en, this message translates to:
  /// **'This backup uses older app data. Vital will update it during restore.'**
  String get restoreOlderWarning;

  /// Explains that a full backup keeps adult records separate.
  ///
  /// In en, this message translates to:
  /// **'This backup contains {count} people. Their records stay separate.'**
  String restoreMultipleWarning(int count);

  /// States the full-replacement consequence and rollback boundary.
  ///
  /// In en, this message translates to:
  /// **'Replacing removes your current records, drafts and reminder settings on this device. A rollback copy is kept until the restored records open.'**
  String get restoreConsequence;

  /// Positive confirmation switch for a full replacement.
  ///
  /// In en, this message translates to:
  /// **'Replace all records'**
  String get restoreReplaceAll;

  /// Helper for the full replacement confirmation switch.
  ///
  /// In en, this message translates to:
  /// **'Current records will be replaced. Switch this on only after reviewing the backup contents.'**
  String get restoreReplaceAllHelp;

  /// One-word button that starts the confirmed full replacement.
  ///
  /// In en, this message translates to:
  /// **'Replace'**
  String get restoreReplace;

  /// One-word button that abandons the current restore attempt.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get restoreCancel;

  /// Status while the staged dataset is re-keyed and scrubbed.
  ///
  /// In en, this message translates to:
  /// **'Preparing records'**
  String get restorePreparing;

  /// Status while the live dataset is replaced and verified.
  ///
  /// In en, this message translates to:
  /// **'Replacing records'**
  String get restoreReplacing;

  /// Explains that replacement must not be interrupted.
  ///
  /// In en, this message translates to:
  /// **'Keep Vital open while this finishes.'**
  String get restoreWorking;

  /// Heading after the replacement dataset opened successfully.
  ///
  /// In en, this message translates to:
  /// **'Restore complete'**
  String get restoreCompleteTitle;

  /// Confirms which archive now supplies this device's records.
  ///
  /// In en, this message translates to:
  /// **'This device now uses the records from {name}.'**
  String restoreCompleteBody(String name);

  /// Confirms device-local state was invalidated after replacement.
  ///
  /// In en, this message translates to:
  /// **'Old drafts and reminder actions were cleared.'**
  String get restoreCompleteCleared;

  /// Explains reminder intention rebuilding after restore.
  ///
  /// In en, this message translates to:
  /// **'Reminders will be rebuilt when you continue.'**
  String get restoreCompleteReminder;

  /// Truthful warning when the native reminder epoch could not be retired.
  ///
  /// In en, this message translates to:
  /// **'Records were restored. Reminder schedules could not be cleared. Check reminder settings after reopening Vital.'**
  String get restoreReminderWarning;

  /// One-word button that leaves the completed restore.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get restoreDone;

  /// Heading when the archive or replacement could not complete.
  ///
  /// In en, this message translates to:
  /// **'Restore failed'**
  String get restoreFailedTitle;

  /// One-word button that returns to the chooser with the same file.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get restoreRetry;

  /// Heading when this host cannot run restore.
  ///
  /// In en, this message translates to:
  /// **'Restore unavailable'**
  String get restoreUnavailable;

  /// Truthful explanation for unavailable restore.
  ///
  /// In en, this message translates to:
  /// **'Restore needs the protected record store. Open Vital again and retry.'**
  String get restoreUnavailableBody;

  /// Shown when the app lock prevents restore.
  ///
  /// In en, this message translates to:
  /// **'Unlock Vital to restore records.'**
  String get restoreLocked;

  /// Recovery step after an incorrect backup password.
  ///
  /// In en, this message translates to:
  /// **'That password does not open this backup. Check the password and try again.'**
  String get restoreWrongPassword;

  /// Safe failure for a damaged or unverifiable archive.
  ///
  /// In en, this message translates to:
  /// **'This backup cannot be opened safely. Current records were kept. Choose another backup.'**
  String get restoreCorrupt;

  /// Failure for an archive from a newer schema.
  ///
  /// In en, this message translates to:
  /// **'This backup was made by a newer version of Vital. Update Vital before restoring it.'**
  String get restoreUnsupportedVersion;

  /// Failure for an archive above the bounded intake or database limit.
  ///
  /// In en, this message translates to:
  /// **'This backup is too large to restore on this device.'**
  String get restoreTooLarge;

  /// Validation message when no archive is selected.
  ///
  /// In en, this message translates to:
  /// **'Choose a backup first.'**
  String get restoreChooseArchive;

  /// Validation message for an empty backup password.
  ///
  /// In en, this message translates to:
  /// **'Enter the backup password.'**
  String get restorePasswordRequired;

  /// Validation message for a password above the byte limit.
  ///
  /// In en, this message translates to:
  /// **'That password is too long.'**
  String get restorePasswordLong;

  /// Validation message when full replacement was not confirmed.
  ///
  /// In en, this message translates to:
  /// **'Switch on Replace all records before replacing.'**
  String get restoreConfirmationRequired;

  /// Failure when a rollback copy and journal must be resolved at startup.
  ///
  /// In en, this message translates to:
  /// **'Vital could not finish the last restore safely. Reopen Vital before trying again.'**
  String get restoreRecoveryRequired;

  /// Failure when staging or the rollback copy cannot be written.
  ///
  /// In en, this message translates to:
  /// **'There is not enough protected storage to replace these records. Free some space and try again.'**
  String get restoreStorage;

  /// Failure when the picked archive byte count no longer matches.
  ///
  /// In en, this message translates to:
  /// **'The backup changed while it was being read. Choose it again.'**
  String get restoreArchiveChanged;

  /// Generic safe failure after a rejected or incomplete replacement.
  ///
  /// In en, this message translates to:
  /// **'Nothing was replaced. Check the backup and try again.'**
  String get restoreFailedBody;

  /// States that a cancelled check left current records unchanged.
  ///
  /// In en, this message translates to:
  /// **'Restore cancelled. Current records were not changed.'**
  String get restoreCancelled;

  /// Shown when another restore action is still running.
  ///
  /// In en, this message translates to:
  /// **'Restore is already running.'**
  String get restoreBusy;

  /// Truthful in-memory notice after verified dataset recovery.
  ///
  /// In en, this message translates to:
  /// **'Restore complete. Vital is using the restored records.'**
  String get restoreRecoveryCompleted;

  /// Truthful in-memory notice after verified dataset recovery.
  ///
  /// In en, this message translates to:
  /// **'Vital recovered the previous records after an interrupted restore.'**
  String get restoreRecoveryRolledBack;

  /// Truthful in-memory notice after verified dataset recovery.
  ///
  /// In en, this message translates to:
  /// **'An interrupted restore was cleared. Your existing records are still in use.'**
  String get restoreRecoveryCleaned;

  /// Settings and setup page for the sole local user.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get profile;

  /// Opens the sole local user profile.
  ///
  /// In en, this message translates to:
  /// **'Your name and report details.'**
  String get settingsProfileBody;

  /// Fail-closed recovery for an unexpected multi-person prototype dataset.
  ///
  /// In en, this message translates to:
  /// **'This older dataset contains other people. Open it with the previous version of Vital. Your records have not been deleted.'**
  String get singleUserRequired;

  /// Rejects a legacy multi-person backup before replacing any live records.
  ///
  /// In en, this message translates to:
  /// **'This backup contains other people. Choose a backup containing only your records.'**
  String get restoreSingleUserRequired;

  /// Visible label of the persistent Substances name search field.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get designSubstancesSearchLabel;

  /// Example placeholder, not a label, for the Substances name search.
  ///
  /// In en, this message translates to:
  /// **'Name of a substance'**
  String get designSubstancesSearchHint;

  /// Item-type filter choice that never filters away an item type; counts are shown beside it.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get designSubstancesAllFilter;

  /// Count of substances sharing an item-type filter, stated in items.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one {1 item} other {{count} items}}'**
  String designSubstancesItemCount(int count);

  /// One-word command that removes the active search text and item-type filter.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get designSubstancesClear;

  /// Filtered-empty heading when a search or item-type filter hides every item.
  ///
  /// In en, this message translates to:
  /// **'No matches'**
  String get designSubstancesNoMatchesTitle;

  /// Recovery hint for the filtered-empty state; the Clear command sits with it.
  ///
  /// In en, this message translates to:
  /// **'Try another name or clear the filter.'**
  String get designSubstancesNoMatchesBody;

  /// Accessible name for the tappable identity row of a substance card.
  ///
  /// In en, this message translates to:
  /// **'Open {name}'**
  String designSubstancesOpenItem(String name);

  /// Failure message for the stored substance list, shown while search and filters stay reachable; a Retry command sits with it.
  ///
  /// In en, this message translates to:
  /// **'The substance list is unavailable right now.'**
  String get designSubstancesUnavailable;

  /// Factual replacement shown by summary components for a value that is genuinely unknown; not zero or an estimate.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get designComponentsUnknown;

  /// Substance summary section heading. The collection below describes stored plans without treatment advice.
  ///
  /// In en, this message translates to:
  /// **'Schedules'**
  String get designSubstancesSchedulesHeading;

  /// Substance summary factual empty state. Distinct from paused, as-needed and ended schedules.
  ///
  /// In en, this message translates to:
  /// **'No schedule recorded.'**
  String get designSubstancesNoSchedule;

  /// Stock tracking is optional. Never invents a balance or dose equivalence.
  ///
  /// In en, this message translates to:
  /// **'No stock recorded.'**
  String get designSubstancesNoStock;

  /// A plan whose start date is after the current plan-zone date.
  ///
  /// In en, this message translates to:
  /// **'Not started.'**
  String get designSubstancesNotStarted;

  /// The last included date has passed. Does not imply recording stopped.
  ///
  /// In en, this message translates to:
  /// **'This schedule has ended.'**
  String get designSubstancesEnded;

  /// Untimed daily count plan. The count counts planned slots, not recorded doses.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{Planned once a day, {amount} {unit} each} other{Planned {count} times a day, {amount} {unit} each}}'**
  String designSubstancesScheduleCount(int count, String amount, String unit);

  /// A plan with explicitly chosen times. Each time keeps its entered amount and unit.
  ///
  /// In en, this message translates to:
  /// **'Planned times: {times}'**
  String designSubstancesScheduleSlots(String times);

  /// One chosen slot joined into the slots list; amounts stay exact.
  ///
  /// In en, this message translates to:
  /// **'{time} {amount} {unit}'**
  String designSubstancesScheduleSlot(String time, String amount, String unit);

  /// A plan with date windows. Windows use the expectation's real bounds and amounts.
  ///
  /// In en, this message translates to:
  /// **'Planned windows: {windows}'**
  String designSubstancesScheduleWindows(String windows);

  /// One window joined into the windows list.
  ///
  /// In en, this message translates to:
  /// **'{start} to {end}: {amount} {unit}'**
  String designSubstancesScheduleWindow(
    String start,
    String end,
    String amount,
    String unit,
  );

  /// An untimed count with explicitly chosen slots. Slot counts stay distinct from recorded doses.
  ///
  /// In en, this message translates to:
  /// **'{slots}, plus {count, plural, =1{1 untimed slot} other{{count} untimed slots}} ({amount} {unit} each)'**
  String designSubstancesMixedSchedule(
    String slots,
    int count,
    String amount,
    String unit,
  );

  /// Elapsed-interval plan. Hours repeat the stored exact value; occurrence truth stays with the resolver.
  ///
  /// In en, this message translates to:
  /// **'Every {hours} h, {amount} {unit} each'**
  String designSubstancesIntervalSchedule(
    String hours,
    String amount,
    String unit,
  );

  /// Restates the stored weekday selection; occurrence truth stays with the resolver.
  ///
  /// In en, this message translates to:
  /// **'Days of week: {days}'**
  String designSubstancesCalendarWeekdays(String days);

  /// Restates the stored date anchor and interval.
  ///
  /// In en, this message translates to:
  /// **'Every {interval, plural, =1{1 day} other{{interval} days}} from {date}'**
  String designSubstancesCalendarDays(int interval, String date);

  /// Restates the stored week anchor and interval.
  ///
  /// In en, this message translates to:
  /// **'Every {interval, plural, =1{1 week} other{{interval} weeks}} from {date}'**
  String designSubstancesCalendarWeeks(int interval, String date);

  /// Restates the stored month anchor and interval without an invented precise recurrence claim.
  ///
  /// In en, this message translates to:
  /// **'Every {interval, plural, =1{1 month} other{{interval} months}} {selector} from {date}'**
  String designSubstancesCalendarMonths(
    int interval,
    String selector,
    String date,
  );

  /// Stored day-of-month selector.
  ///
  /// In en, this message translates to:
  /// **'on day {day}'**
  String designSubstancesMonthDay(int day);

  /// Stored weekday/month selector stated without false precision.
  ///
  /// In en, this message translates to:
  /// **'on a selected weekday'**
  String get designSubstancesMonthWeekday;

  /// Effective plan bounds. The end is the exclusive bound, not a stop promise.
  ///
  /// In en, this message translates to:
  /// **'{start} to {end}'**
  String designSubstancesPlanBounds(String start, String end);

  /// A plan with no end bound.
  ///
  /// In en, this message translates to:
  /// **'From {start}'**
  String designSubstancesPlanStart(String start);

  /// Names the plan's real zone basis; never an invented local conversion.
  ///
  /// In en, this message translates to:
  /// **'Time zone: {zone}'**
  String designSubstancesZone(String zone);

  /// The resolver's next expectation with its real zone. An expectation is not proof of actual use.
  ///
  /// In en, this message translates to:
  /// **'Next planned dose: {amount} {unit} at {time} ({zone})'**
  String designSubstancesNextDose(
    String amount,
    String unit,
    String time,
    String zone,
  );

  /// Untimed expectations have no invented exact times.
  ///
  /// In en, this message translates to:
  /// **'Next planned dose: {amount} {unit} on {date}, untimed ({zone})'**
  String designSubstancesNextUntimed(
    String amount,
    String unit,
    String date,
    String zone,
  );

  /// A stored expectation whose local time needs an explicit clock choice.
  ///
  /// In en, this message translates to:
  /// **'Clock review: {date} {time} ({zone})'**
  String designSubstancesReviewClock(String date, String time, String zone);

  /// One stock container's own balance in its own unit; separate containers are never added together.
  ///
  /// In en, this message translates to:
  /// **'{label} · {balance}'**
  String designSubstancesContainerEntry(String label, String balance);

  /// Recorded stock is below zero; recorded use remains saved.
  ///
  /// In en, this message translates to:
  /// **'Deficit'**
  String get designSubstancesDeficit;

  /// The summary shows the first few containers; the overflow stays factual and bounded.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 more container.} other{{count} more containers.}}'**
  String designSubstancesMoreStock(int count);

  /// The summary bounds its slot list; every stored slot stays in the schedule pages.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 more slot.} other{{count} more slots.}}'**
  String designSubstancesMoreSlots(int count);

  /// Design-batch substance summary failure. A factual scoped message: these live summary reads failed; the Retry action re-requests them. Never describes history or implies data loss.
  ///
  /// In en, this message translates to:
  /// **'The substance summary could not be loaded.'**
  String get designSubstancesSummaryUnavailable;

  /// Substance overview section heading for linked supporting, file and use-history records.
  ///
  /// In en, this message translates to:
  /// **'Context'**
  String get designOverviewContext;

  /// Substance overview schedule empty state; recording stays available.
  ///
  /// In en, this message translates to:
  /// **'No plan yet'**
  String get designOverviewNoPlan;

  /// Substance overview schedule empty state; recording stays available.
  ///
  /// In en, this message translates to:
  /// **'Add a schedule to see planned doses. Recording stays available without one.'**
  String get designOverviewNoPlanHelp;

  /// Substance overview bounded saved-plan list; the working schedule editor stays reachable for every plan.
  ///
  /// In en, this message translates to:
  /// **'This summary shows the first plans. Open Schedule to review the rest.'**
  String get designOverviewPlansBound;

  /// Reported when a shown plan has no row in the bounded next-dose calculation; this cannot state or deny a next planned date.
  ///
  /// In en, this message translates to:
  /// **'This plan is not in the bounded next-dose summary. Open Schedule to review it.'**
  String get designOverviewNextMissing;

  /// Substance overview schedule start date; preserve the full date value.
  ///
  /// In en, this message translates to:
  /// **'Starts {date}'**
  String designOverviewStart(String date);

  /// Substance overview selected-weekday dates; the weekday names are separate translated words.
  ///
  /// In en, this message translates to:
  /// **'On {weekdays}'**
  String designOverviewWeekdays(String weekdays);

  /// Substance overview day interval; the anchor date is visible in the schedule editor.
  ///
  /// In en, this message translates to:
  /// **'Every {count} days'**
  String designOverviewEveryDays(int count);

  /// Substance overview week interval; the anchor and chosen days appear beside it.
  ///
  /// In en, this message translates to:
  /// **'Every {count} weeks'**
  String designOverviewEveryWeeks(int count);

  /// Substance overview month interval; the anchor and month rule appear beside it.
  ///
  /// In en, this message translates to:
  /// **'Every {count} months'**
  String designOverviewEveryMonths(int count);

  /// Substance overview stock empty state; balances remain optional.
  ///
  /// In en, this message translates to:
  /// **'No stock recorded'**
  String get designOverviewStockEmpty;

  /// Substance overview stock empty state; balances remain optional.
  ///
  /// In en, this message translates to:
  /// **'Stock is optional. Add a container to track the remaining amount.'**
  String get designOverviewStockHelp;

  /// Substance overview bounded recent-record list; the full history route stays available.
  ///
  /// In en, this message translates to:
  /// **'Older records stay in the full history.'**
  String get designOverviewHistoryHint;

  /// Accessible name for the bounded stock review link in a substance overview.
  ///
  /// In en, this message translates to:
  /// **'Review the stock for {name}'**
  String designOverviewStockReview(String name);

  /// Accessible name for the bounded history review link in a substance overview.
  ///
  /// In en, this message translates to:
  /// **'Review the full history for {name}'**
  String designOverviewHistoryReview(String name);

  /// Substance overview bounded event list; the Events destination stays available.
  ///
  /// In en, this message translates to:
  /// **'This summary shows the first events. Open Events to review them all.'**
  String get designOverviewEventsHint;

  /// Today hero heading for the day's expected doses.
  ///
  /// In en, this message translates to:
  /// **'Daily schedule'**
  String get designTodayHeading;

  /// Count of planned doses still awaiting a decision after recording and skips.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 remaining} other{{count} remaining}}'**
  String designTodayRemaining(int count);

  /// Truthful day summary recorded, skipped and planned are separate counts.
  ///
  /// In en, this message translates to:
  /// **'{taken} of {planned} doses recorded, {skipped} skipped.'**
  String designTodayRecorded(int taken, int planned, int skipped);

  /// Day with zero planned doses; never shown as full completion.
  ///
  /// In en, this message translates to:
  /// **'No doses are planned today.'**
  String get designTodayNothingPlanned;

  /// Heading above the next expected dose block.
  ///
  /// In en, this message translates to:
  /// **'Next dose'**
  String get designTodayNext;

  /// Minute countdown once the next dose is within an hour.
  ///
  /// In en, this message translates to:
  /// **'{minutes, plural, =1{Next dose in 1 minute.} other{Next dose in {minutes} minutes.}}'**
  String designTodayNextInMinutes(int minutes);

  /// The expected start passed and the dose has no recorded decision yet.
  ///
  /// In en, this message translates to:
  /// **'Next dose is due now.'**
  String get designTodayNextDue;

  /// Pending untimed expectation; no countdown can be claimed.
  ///
  /// In en, this message translates to:
  /// **'The next dose has no expected time.'**
  String get designTodayNextUntimed;

  /// Partial-day counts over the rows shown so far. The day is not fully calculated or some action history is still loading, so no whole-day total or ratio is claimed.
  ///
  /// In en, this message translates to:
  /// **'{taken, plural, =1{1 dose recorded} other{{taken} doses recorded}}, {skipped, plural, =1{1 skipped} other{{skipped} skipped}} so far.'**
  String designTodayRecordedSoFar(int taken, int skipped);

  /// Shown hero date when the device time zone is not observed. Labels the explicit UTC fallback instead of implying a known local date.
  ///
  /// In en, this message translates to:
  /// **'{date} (UTC)'**
  String designTodayUtcDate(String date);

  /// Hero summary label naming what the day summary measures: recorded doses against planned doses.
  ///
  /// In en, this message translates to:
  /// **'Recorded doses'**
  String get designTodayProgressLabel;

  /// Recorded share of the day summary when the row set and action history are complete.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 recorded} other{{count} recorded}}'**
  String designTodayRecordedCount(num count);

  /// Denominator of the measured day summary. Stated in doses, never proof of use.
  ///
  /// In en, this message translates to:
  /// **'of {count, plural, =1{1 dose} other{{count} doses}}'**
  String designTodayPlannedTotal(num count);

  /// Skipped decisions shown beside the day summary. Skips stay distinct from recorded doses.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 skipped} other{{count} skipped}}'**
  String designTodaySkippedCount(num count);

  /// A shown row's action history is incomplete, so its recorded and skipped counts may still change.
  ///
  /// In en, this message translates to:
  /// **'Some dose actions are still loading. Counts may change.'**
  String get designTodayActionsIncomplete;

  /// Next expectation from today's shown rows or a future plan, with its substance, exact planned amount and shown time.
  ///
  /// In en, this message translates to:
  /// **'Next planned dose: {name}, {amount} {unit}, {when}.'**
  String designTodayNextPlanNamed(
    String name,
    String amount,
    String unit,
    String when,
  );

  /// Future expectation whose substance name is not currently available. No name is invented.
  ///
  /// In en, this message translates to:
  /// **'Next planned dose: {amount} {unit}, {when}.'**
  String designTodayNextPlanUnnamed(String amount, String unit, String when);

  /// Less than one minute remains before the expected start. The dose is not due yet.
  ///
  /// In en, this message translates to:
  /// **'Next dose in under a minute.'**
  String get designTodayUnderMinute;

  /// Stitch dashboard and substance layout. Placeholder state for a feature that is not implemented.
  ///
  /// In en, this message translates to:
  /// **'This feature is not available yet.'**
  String get stitchPlaceholderBody;

  /// Stitch dashboard and substance layout. Short visible label or explanation.
  ///
  /// In en, this message translates to:
  /// **'Daily progress'**
  String get stitchDailyProgress;

  /// Stitch dashboard and substance layout. Short visible label or explanation.
  ///
  /// In en, this message translates to:
  /// **'Partial'**
  String get stitchPartial;

  /// Stitch dashboard and substance layout. Short visible label or explanation.
  ///
  /// In en, this message translates to:
  /// **'Weekly overview'**
  String get stitchWeek;

  /// Stitch dashboard and substance layout. Short visible label or explanation.
  ///
  /// In en, this message translates to:
  /// **'Next dose'**
  String get stitchNextDose;

  /// Stitch dashboard and substance layout. Short visible label or explanation.
  ///
  /// In en, this message translates to:
  /// **'No upcoming dose'**
  String get stitchNoNext;

  /// Stitch dashboard and substance layout. Short visible label or explanation.
  ///
  /// In en, this message translates to:
  /// **'Add a substance and schedule to see your next dose here.'**
  String get stitchNextHelp;

  /// Stitch dashboard and substance layout. Short visible label or explanation.
  ///
  /// In en, this message translates to:
  /// **'Configure'**
  String get stitchConfigure;

  /// Stitch dashboard and substance layout. Short visible label or explanation.
  ///
  /// In en, this message translates to:
  /// **'Today’s sequence'**
  String get stitchSequence;

  /// Stitch dashboard and substance layout. Short visible label or explanation.
  ///
  /// In en, this message translates to:
  /// **'Manage'**
  String get stitchScheduleManage;

  /// Stitch dashboard and substance layout. Short visible label or explanation.
  ///
  /// In en, this message translates to:
  /// **'Blood pressure'**
  String get stitchBloodPressure;

  /// Stitch dashboard and substance layout. Short visible label or explanation.
  ///
  /// In en, this message translates to:
  /// **'Refill buffer'**
  String get stitchRefillBuffer;

  /// Stitch dashboard and substance layout. Short visible label or explanation.
  ///
  /// In en, this message translates to:
  /// **'Forecast not available yet'**
  String get stitchForecastPending;

  /// Stitch dashboard and substance layout. Short visible label or explanation.
  ///
  /// In en, this message translates to:
  /// **'Encrypted on device'**
  String get stitchStored;

  /// Stitch dashboard and substance layout. Short visible label or explanation.
  ///
  /// In en, this message translates to:
  /// **'Your records stay on this device unless you export or share them.'**
  String get stitchLocalBody;

  /// Stitch dashboard and substance layout. Short visible label or explanation.
  ///
  /// In en, this message translates to:
  /// **'Paused'**
  String get stitchPaused;

  /// Stitch dashboard and substance layout. Short visible label or explanation.
  ///
  /// In en, this message translates to:
  /// **'Design preview'**
  String get stitchPreview;

  /// Stitch dashboard and substance layout. Short visible label or explanation.
  ///
  /// In en, this message translates to:
  /// **'Filters'**
  String get stitchFilter;

  /// Stitch dashboard and substance layout. Short visible label or explanation.
  ///
  /// In en, this message translates to:
  /// **'Anytime'**
  String get stitchUntimed;

  /// Stitch dashboard and substance layout. Short visible label or explanation.
  ///
  /// In en, this message translates to:
  /// **'As needed'**
  String get stitchPrn;

  /// Stitch dashboard and substance layout. Short visible label or explanation.
  ///
  /// In en, this message translates to:
  /// **'Search by name…'**
  String get stitchSearch;

  /// Complete localisable Stitch screen message.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 substance} other{{count} substances}}'**
  String stitchSubstanceCount(int count);

  /// Complete localisable Stitch screen message.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 planned} other{{count} planned}}'**
  String stitchGroupCount(int count);

  /// Complete localisable Stitch screen message.
  ///
  /// In en, this message translates to:
  /// **'{amount} {unit} · {form}'**
  String stitchAmountForm(String amount, String unit, String form);

  /// Complete localisable Stitch screen message.
  ///
  /// In en, this message translates to:
  /// **'Daily at {time}'**
  String stitchDailyAt(String time);

  /// Complete localisable Stitch screen message.
  ///
  /// In en, this message translates to:
  /// **'{name} ({count})'**
  String stitchFilterCount(String name, int count);

  /// Complete localisable Stitch screen message.
  ///
  /// In en, this message translates to:
  /// **'{amount} {unit} remaining'**
  String stitchStockRemaining(String amount, String unit);

  /// Complete localisable Stitch screen message.
  ///
  /// In en, this message translates to:
  /// **'Next: {time}'**
  String stitchNextAt(String time);

  /// One-word action opening the existing supporting records.
  ///
  /// In en, this message translates to:
  /// **'Observation'**
  String get stitchObservation;

  /// Truthful unavailable-state explanation; does not promise native delivery.
  ///
  /// In en, this message translates to:
  /// **'Snooze is available when reminders are enabled for this schedule.'**
  String get stitchSnoozeUnavailable;

  /// Heading for the optional steps after identity creation.
  ///
  /// In en, this message translates to:
  /// **'Setup'**
  String get featureSetupTitle;

  /// Identity form card heading for the optional setup steps.
  ///
  /// In en, this message translates to:
  /// **'Next steps'**
  String get featureSetupNextTitle;

  /// Explains that identity saves first and no plan, stock or note is created automatically.
  ///
  /// In en, this message translates to:
  /// **'Save this identity first. Schedule, stock and details are separate optional steps and nothing is assumed.'**
  String get featureSetupNextBody;

  /// Badge for optional setup steps.
  ///
  /// In en, this message translates to:
  /// **'Optional'**
  String get featureSetupOptional;

  /// Confirms the identity is committed before optional steps.
  ///
  /// In en, this message translates to:
  /// **'{detail} saved.'**
  String featureSetupIdentitySaved(String detail);

  /// Explains that identity is committed and later steps are optional.
  ///
  /// In en, this message translates to:
  /// **'The substance is saved. The next steps are optional and can be resumed later.'**
  String get featureSetupIdentityHelp;

  /// Help for the optional schedule step.
  ///
  /// In en, this message translates to:
  /// **'Add a schedule now or skip this step.'**
  String get featureSetupScheduleHelp;

  /// Help for the optional opening stock step.
  ///
  /// In en, this message translates to:
  /// **'Add opening stock now or skip this step.'**
  String get featureSetupStockHelp;

  /// Help for the optional details step.
  ///
  /// In en, this message translates to:
  /// **'Add your own instructions or private notes.'**
  String get featureSetupDetailsHelp;

  /// Button that resumes optional setup.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get featureSetupContinue;

  /// Explains the resumable setup card on the overview.
  ///
  /// In en, this message translates to:
  /// **'Continue where you left off.'**
  String get featureSetupContinueHelp;

  /// Explicitly skips one optional setup step.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get featureSetupSkip;

  /// Badge for an explicitly skipped step.
  ///
  /// In en, this message translates to:
  /// **'Skipped'**
  String get featureSetupSkipped;

  /// Badge for a step whose real record exists.
  ///
  /// In en, this message translates to:
  /// **'Added'**
  String get featureSetupAdded;

  /// Completes the optional setup marker.
  ///
  /// In en, this message translates to:
  /// **'Finish'**
  String get featureSetupFinish;

  /// Heading for authored instructions and private notes.
  ///
  /// In en, this message translates to:
  /// **'Details'**
  String get featureSetupDetails;

  /// Empty state for substance details.
  ///
  /// In en, this message translates to:
  /// **'No details added'**
  String get featureSetupNoDetails;

  /// Empty state help for substance details.
  ///
  /// In en, this message translates to:
  /// **'Add your own instructions or a private note.'**
  String get featureSetupNoDetailsHelp;

  /// Explains that authored details are not medical advice.
  ///
  /// In en, this message translates to:
  /// **'Write your own instructions and notes.'**
  String get featureSetupDetailsFormHelp;

  /// Label for user-authored instructions.
  ///
  /// In en, this message translates to:
  /// **'Instructions'**
  String get featureSetupInstructions;

  /// Instructions field help that preserves the entered text without advice.
  ///
  /// In en, this message translates to:
  /// **'Keep your wording, quantities and units.'**
  String get featureSetupInstructionsHelp;

  /// Label for user-authored private notes.
  ///
  /// In en, this message translates to:
  /// **'Private notes'**
  String get featureSetupNotes;

  /// Explains the explicit private-content selection for notes.
  ///
  /// In en, this message translates to:
  /// **'Included in reports and exports only when notes are selected.'**
  String get featureSetupNotesHelp;

  /// Saves substance details.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get featureSetupSave;

  /// Validation when authored details exceed the stored bound.
  ///
  /// In en, this message translates to:
  /// **'Keep instructions and notes within 8000 characters each.'**
  String get featureSetupDetailsTooLong;

  /// Create substance screen. A local encrypted draft is kept while this form is unfinished.
  ///
  /// In en, this message translates to:
  /// **'Drafting'**
  String get screenCreateDrafting;

  /// Create substance screen. Group label above the saved personal type choices.
  ///
  /// In en, this message translates to:
  /// **'Classification'**
  String get screenCreateClassification;

  /// Create substance screen. Card heading for the name, form, unit and type controls.
  ///
  /// In en, this message translates to:
  /// **'Identity'**
  String get screenCreateIdentity;

  /// Create substance screen. Form chips fill the free-text form field; they are not dose advice.
  ///
  /// In en, this message translates to:
  /// **'Tap a common form or enter your own.'**
  String get screenCreateFormHelp;

  /// Create substance screen. Form choice written to the item's existing form field.
  ///
  /// In en, this message translates to:
  /// **'Capsule'**
  String get screenCreateFormCapsule;

  /// Create substance screen. Form choice written to the item's existing form field.
  ///
  /// In en, this message translates to:
  /// **'Softgel'**
  String get screenCreateFormSoftgel;

  /// Create substance screen. Form choice written to the item's existing form field.
  ///
  /// In en, this message translates to:
  /// **'Powder'**
  String get screenCreateFormPowder;

  /// Create substance screen. The item record has no strength field; do not imply one was saved.
  ///
  /// In en, this message translates to:
  /// **'Strength belongs to a stock container. Add it from the substance overview after you save.'**
  String get screenCreateStrengthLater;

  /// Create substance screen. Schedule editing needs the saved item identity.
  ///
  /// In en, this message translates to:
  /// **'Frequency and dose times are added from the substance overview after you save.'**
  String get screenCreateScheduleLater;

  /// Create substance screen. Stock editing needs the saved item identity.
  ///
  /// In en, this message translates to:
  /// **'Opening quantity, low-stock threshold and strength are added from the substance overview after you save.'**
  String get screenCreateStockLater;

  /// Create substance screen. Heading for unavailable free-text substance notes.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get screenCreateNotes;

  /// Create substance screen. Truthful unavailable state; no note is saved or invented.
  ///
  /// In en, this message translates to:
  /// **'Substance notes are not available in this version.'**
  String get screenCreateNotesUnavailable;

  /// Create substance screen. Badge marking a section that opens only once the item exists.
  ///
  /// In en, this message translates to:
  /// **'After save'**
  String get screenCreateAfterSave;

  /// Create substance screen. Badge for a feature this version does not record.
  ///
  /// In en, this message translates to:
  /// **'Unavailable'**
  String get screenCreateUnavailable;

  /// Schedule editor subline. Describes the task without clinical claims.
  ///
  /// In en, this message translates to:
  /// **'Set the days, times and amounts for this plan. Preview before saving.'**
  String get screenScheduleSubtitle;

  /// Status badge for a schedule that has no saved version yet.
  ///
  /// In en, this message translates to:
  /// **'New plan'**
  String get screenScheduleNew;

  /// Section heading for the six real cadence choices.
  ///
  /// In en, this message translates to:
  /// **'Recurrence'**
  String get screenScheduleRecurrence;

  /// Section heading for the effective start and optional end.
  ///
  /// In en, this message translates to:
  /// **'Plan dates'**
  String get screenScheduleDates;

  /// Section heading for the explicitly chosen planned times.
  ///
  /// In en, this message translates to:
  /// **'Dose windows'**
  String get screenScheduleDoseWindows;

  /// Section heading for explicitly entered times within a partly timed plan.
  ///
  /// In en, this message translates to:
  /// **'Chosen times'**
  String get screenScheduleChosenTimes;

  /// The number of entered planned times, not recorded doses.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 time} other{{count} times}}'**
  String screenScheduleSlotCount(int count);

  /// The number of entered time windows.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 window} other{{count} windows}}'**
  String screenScheduleWindowCount(int count);

  /// Labelled preview inside a time slot. No tolerance rule is stored or promised.
  ///
  /// In en, this message translates to:
  /// **'Timing tolerance is not available yet. This plan saves only the chosen time.'**
  String get screenScheduleTolerancePreview;

  /// Section heading for the unavailable food and timing requirements.
  ///
  /// In en, this message translates to:
  /// **'Requirements'**
  String get screenScheduleRequirements;

  /// Explicit preview state. Does not offer clinical advice or save example requirements.
  ///
  /// In en, this message translates to:
  /// **'Food and timing requirements are not available yet. Nothing from this preview is saved.'**
  String get screenScheduleRequirementsBody;

  /// Explains why pause and reminder actions are unavailable on a new plan.
  ///
  /// In en, this message translates to:
  /// **'Save this plan before using pause or reminders.'**
  String get screenScheduleSaveFirst;

  /// Section heading for plan reminder controls.
  ///
  /// In en, this message translates to:
  /// **'Reminders'**
  String get screenScheduleAlerts;

  /// Short caveat beside the reminder section. Does not promise delivery.
  ///
  /// In en, this message translates to:
  /// **'Device support applies.'**
  String get screenScheduleAlertsMeta;

  /// Reminder placeholder before a plan has a saved revision.
  ///
  /// In en, this message translates to:
  /// **'Save this plan to set reminders. Alerts also depend on device support.'**
  String get screenScheduleRemindersAfterSave;

  /// Label for the unavailable follow-up reminder preview row.
  ///
  /// In en, this message translates to:
  /// **'Follow-up'**
  String get screenScheduleFollowUp;

  /// Truthful preview state for a capability that is not implemented.
  ///
  /// In en, this message translates to:
  /// **'Follow-up alerts are not available yet.'**
  String get screenScheduleFollowUpBody;

  /// Explains the required preview step before saving a schedule.
  ///
  /// In en, this message translates to:
  /// **'Preview checks the next planned doses before saving.'**
  String get screenSchedulePreviewHelp;

  /// Heading for the preview result, distinct from the Preview action.
  ///
  /// In en, this message translates to:
  /// **'Planned doses'**
  String get screenSchedulePreviewResult;

  /// One-word action scrolling to the visible actual date and time fields.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get screenRecordEditTime;

  /// Accessible label for the unit shown beside the exact quantity.
  ///
  /// In en, this message translates to:
  /// **'Unit {unit}'**
  String screenRecordUnitValue(String unit);

  /// Complete item classification under the product name.
  ///
  /// In en, this message translates to:
  /// **'{type} · {form}'**
  String screenRecordTypeForm(String type, String form);

  /// Chosen actual date and wall time shown in the sheet header.
  ///
  /// In en, this message translates to:
  /// **'{date} at {time}'**
  String screenRecordTimestamp(String date, String time);

  /// Header state when the entered actual date or time is not valid yet.
  ///
  /// In en, this message translates to:
  /// **'Time not set'**
  String get screenRecordTimeUnset;

  /// Section heading above the exact amount field and its unit.
  ///
  /// In en, this message translates to:
  /// **'Quantity'**
  String get screenRecordQuantity;

  /// Section heading above the editable actual date and time fields.
  ///
  /// In en, this message translates to:
  /// **'When'**
  String get screenRecordWhen;

  /// Section heading for unavailable food, water and symptom tags.
  ///
  /// In en, this message translates to:
  /// **'Context & conditions'**
  String get screenRecordContext;

  /// Clearly labelled preview; D10 context tags are not implemented and must not write example data.
  ///
  /// In en, this message translates to:
  /// **'Food, water and symptom tags are not saved yet.'**
  String get screenRecordContextHelp;

  /// Section heading for unavailable dose-attached vitals and notes.
  ///
  /// In en, this message translates to:
  /// **'Vitals & observations'**
  String get screenRecordVitals;

  /// Clearly labelled preview; no invented measurements are shown.
  ///
  /// In en, this message translates to:
  /// **'Vitals and notes are not attached to this dose yet.'**
  String get screenRecordVitalsHelp;

  /// One-word action opening the existing supporting observation records.
  ///
  /// In en, this message translates to:
  /// **'Observations'**
  String get screenRecordObservations;

  /// Badge marking a capability that is not saved by this build.
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get screenRecordPreview;

  /// Exact stock consequence in the container's own unit. Both amounts include their units.
  ///
  /// In en, this message translates to:
  /// **'Deducts {deducted}, leaving {remaining}.'**
  String screenRecordStockDeducts(String deducted, String remaining);

  /// The deduction is convertible but the current balance is unknown.
  ///
  /// In en, this message translates to:
  /// **'Deducts {deducted}. Remaining balance is unknown.'**
  String screenRecordStockUnknownDeduction(String deducted);

  /// The entered quantity cannot be converted to this source's stock unit, or a replacement choice is still required.
  ///
  /// In en, this message translates to:
  /// **'The stock deduction cannot be calculated for these units.'**
  String get screenRecordStockNotCalculated;

  /// The aggregate stock calculation limit was reached; the dose itself can still be recorded.
  ///
  /// In en, this message translates to:
  /// **'The stock total is unavailable. Saving still records this dose.'**
  String get screenRecordStockLimitPreview;

  /// The exact post-dose balance is negative; the recorded use is not blocked.
  ///
  /// In en, this message translates to:
  /// **'This leaves the balance below zero.'**
  String get screenRecordStockDeficitPreview;

  /// Uses the container's stored threshold rather than a hardcoded count.
  ///
  /// In en, this message translates to:
  /// **'Low stock at or below {threshold}.'**
  String screenRecordStockLow(String threshold);

  /// Explains that skip belongs to a planned occurrence, not this generic route.
  ///
  /// In en, this message translates to:
  /// **'Skip is available on Today for a scheduled dose.'**
  String get screenRecordSkipNote;

  /// Stock screen. Section heading for a bounded notice page from the collection-wide query, ordered by urgency within the loaded page.
  ///
  /// In en, this message translates to:
  /// **'Action needed'**
  String get screenStockActionNeeded;

  /// Stock screen. A container needs the saved substance identity, so the unscoped vault opens the substance list.
  ///
  /// In en, this message translates to:
  /// **'Open a substance to add its container.'**
  String get screenStockAddAllHelp;

  /// Stock screen. Heading for the manual container section. The visible command stays Add.
  ///
  /// In en, this message translates to:
  /// **'Add container'**
  String get screenStockAddHeading;

  /// Stock screen. Manual container creation for the substance this vault is scoped to.
  ///
  /// In en, this message translates to:
  /// **'Add a physical container for this substance.'**
  String get screenStockAddItemHelp;

  /// Stock screen. Archived profiles keep their balances visible without stock or notice changes.
  ///
  /// In en, this message translates to:
  /// **'This profile is archived. Stock is read only.'**
  String get screenStockArchived;

  /// Stock screen. Section heading for the bounded container page.
  ///
  /// In en, this message translates to:
  /// **'Active containers'**
  String get screenStockContainers;

  /// Stock screen. Names the remaining D15 capabilities; lot, expiry, capacity and run-out forecasts are implemented.
  ///
  /// In en, this message translates to:
  /// **'Pack scanning and refill delivery are not available yet.'**
  String get screenStockGaps;

  /// Stock screen. Truthful paging caption because no whole-collection stock filter is applied.
  ///
  /// In en, this message translates to:
  /// **'Only the loaded page is shown.'**
  String get screenStockLoadedOnly;

  /// Stock screen. Further notice rows exist beyond the shown ones.
  ///
  /// In en, this message translates to:
  /// **'More containers need attention.'**
  String get screenStockMoreNotices;

  /// Stock screen. Empty state heading when no stock containers are stored.
  ///
  /// In en, this message translates to:
  /// **'No containers'**
  String get screenStockNoContainers;

  /// Stock screen. Empty state help. Stock stays optional.
  ///
  /// In en, this message translates to:
  /// **'Add a container when you need to track its supply.'**
  String get screenStockNoContainersHelp;

  /// Stock screen. Opens the existing notice settings route for this container.
  ///
  /// In en, this message translates to:
  /// **'Notices'**
  String get screenStockNoticesAction;

  /// Stock screen. Status when the container has no active notice. A zero balance with notices disabled is not described as stocked.
  ///
  /// In en, this message translates to:
  /// **'No notice'**
  String get screenStockStocked;

  /// Stock screen. The aggregate stock total could not be calculated; this is not zero.
  ///
  /// In en, this message translates to:
  /// **'Unavailable'**
  String get screenStockUnavailable;

  /// Stock screen. The remaining balance is unknown; this is not zero.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get screenStockUnknown;

  /// History subtitle. Local storage is factual; no sync or integrity claim.
  ///
  /// In en, this message translates to:
  /// **'Recorded use and skipped plans kept on this device.'**
  String get screenHistorySubtitle;

  /// Heading for the seven real day markers ending today.
  ///
  /// In en, this message translates to:
  /// **'Last 7 days'**
  String get screenHistoryLastSevenDays;

  /// Factual count of recorded entries in the seven-day strip. Not an adherence percentage.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No recorded entries} one{1 recorded} other{{count} recorded}}'**
  String screenHistoryRecordedCount(int count);

  /// Number of history entries shown for one day.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{1 entry} other{{count} entries}}'**
  String screenHistoryEntryCount(int count);

  /// Recorded time for one history entry.
  ///
  /// In en, this message translates to:
  /// **'Recorded at {time}'**
  String screenHistoryRecordedAt(String time);

  /// Planned time for a skipped occurrence. Does not imply a recorded dose.
  ///
  /// In en, this message translates to:
  /// **'Scheduled {time}'**
  String screenHistoryScheduledAt(String time);

  /// Supporting line for the real reports, charts and supporting actions.
  ///
  /// In en, this message translates to:
  /// **'Build a report or open related records.'**
  String get screenHistoryReportsHelp;

  /// Heading for the clearly labelled audit preview.
  ///
  /// In en, this message translates to:
  /// **'Audit'**
  String get screenHistoryAudit;

  /// Explicit preview. Does not invent adherence, integrity, hash or delivery claims.
  ///
  /// In en, this message translates to:
  /// **'Adherence and integrity measures are not available yet. Your records are unchanged.'**
  String get screenHistoryAuditPreview;

  /// Accessible name for one entry's View action.
  ///
  /// In en, this message translates to:
  /// **'View {name}'**
  String screenHistoryViewEntry(String name);

  /// Accessible date label while its calendar counts are loading or unavailable. Never announces zero counts before a successful read.
  ///
  /// In en, this message translates to:
  /// **'{date}. {state}'**
  String screenHistoryDayUnavailable(String date, String state);

  /// Accessible name for the one-word Open action beside a complete linked item or event name.
  ///
  /// In en, this message translates to:
  /// **'Open linked record {name}'**
  String screenLabsOpenLinked(String name);

  /// Clarifies that date filters affect the paged records, while the bounded latest-value summary always uses collection or measured dates.
  ///
  /// In en, this message translates to:
  /// **'Latest results use collection or measured dates across all dates. Date filters apply to the records below.'**
  String get screenLabsLatestDateScope;

  /// Compact indication that advanced History filters are active.
  ///
  /// In en, this message translates to:
  /// **'Filtered'**
  String get calendarFiltered;

  /// Explains that Export opens the existing report-selection workflow for the displayed calendar month.
  ///
  /// In en, this message translates to:
  /// **'Monthly summary (PDF)'**
  String get calendarMonthlySummary;

  /// Accessible name for the monthly report selection action.
  ///
  /// In en, this message translates to:
  /// **'Export {month} summary'**
  String calendarExportMonth(String month);

  /// Counts calendar days with saved recorded use in the displayed month and current non-date filters; not planned adherence.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 day recorded this month} other{{count} days recorded this month}}'**
  String calendarRecordedDays(int count);

  /// Compact saved-entry state and recorded or scheduled time; no adherence judgement.
  ///
  /// In en, this message translates to:
  /// **'{status} · {time}'**
  String calendarEntryState(String status, String time);

  /// Short description under the Events page title.
  ///
  /// In en, this message translates to:
  /// **'Courses and cycles add context to your recorded use.'**
  String get screenEventsDescription;

  /// Event status for an event that has started and is not marked complete.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get screenEventsActive;

  /// Event status for an event whose start date is still in the future.
  ///
  /// In en, this message translates to:
  /// **'Upcoming'**
  String get screenEventsUpcoming;

  /// Filter choice that shows every loaded event.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get screenEventsAll;

  /// Loaded active event count for the Events header.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 active} other{{count} active}}'**
  String screenEventsActiveCount(int count);

  /// Loaded upcoming event count for the Events header.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 upcoming} other{{count} upcoming}}'**
  String screenEventsUpcomingCount(int count);

  /// Loaded completed event count for the Events header.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 completed} other{{count} completed}}'**
  String screenEventsCompletedCount(int count);

  /// Header count when more than one page of events exists, so the shown number is not presented as a whole-collection count.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 shown} other{{count} shown}}'**
  String screenEventsShown(int count);

  /// Explains that status filters cover only the loaded event page, not the whole collection.
  ///
  /// In en, this message translates to:
  /// **'Filters only cover the events shown.'**
  String get screenEventsLoadedOnly;

  /// Filtered empty state for the Events list.
  ///
  /// In en, this message translates to:
  /// **'No events match this filter.'**
  String get screenEventsNoMatches;

  /// Event date range. Values keep their recorded precision.
  ///
  /// In en, this message translates to:
  /// **'{start} to {end}'**
  String screenEventsRange(String start, String end);

  /// Saved start boundary without claiming that a planned start actually occurred.
  ///
  /// In en, this message translates to:
  /// **'Start: {date}'**
  String screenEventsStarted(String date);

  /// Future event start date.
  ///
  /// In en, this message translates to:
  /// **'Starts {date}'**
  String screenEventsStarts(String date);

  /// Event has neither a usable start nor end date.
  ///
  /// In en, this message translates to:
  /// **'No dates recorded'**
  String get screenEventsNoDates;

  /// Elapsed day position in an event whose start and end both resolve. This describes time, not adherence.
  ///
  /// In en, this message translates to:
  /// **'Day {day} of {total}'**
  String screenEventsDayOf(int day, int total);

  /// Time elapsed in the event date range. Never an adherence percentage.
  ///
  /// In en, this message translates to:
  /// **'{percent}% elapsed'**
  String screenEventsPercentElapsed(int percent);

  /// Label for elapsed time across an event's date range.
  ///
  /// In en, this message translates to:
  /// **'Date progress'**
  String get screenEventsHorizon;

  /// Items recorded as members of an active or completed event.
  ///
  /// In en, this message translates to:
  /// **'Linked items'**
  String get screenEventsLinkedItems;

  /// Items recorded as members of a future event.
  ///
  /// In en, this message translates to:
  /// **'Planned items'**
  String get screenEventsPlannedItems;

  /// Short warning when an event date boundary cannot resolve, so timing and the derived status stay uncertain.
  ///
  /// In en, this message translates to:
  /// **'Dates need review'**
  String get screenEventsDatesReview;

  /// The event end date has passed and its end review has not been dismissed or completed.
  ///
  /// In en, this message translates to:
  /// **'End review due'**
  String get screenEventsReviewDue;

  /// Accessible label for the event card overflow control.
  ///
  /// In en, this message translates to:
  /// **'More actions for {name}'**
  String screenEventsMoreFor(String name);

  /// Accessible label for opening an event's details. It contains the visible Details command.
  ///
  /// In en, this message translates to:
  /// **'Details for {name}'**
  String screenEventsDetailsFor(String name);

  /// Accessible label for editing an event. It contains the visible Edit command.
  ///
  /// In en, this message translates to:
  /// **'Edit {name}'**
  String screenEventsEditFor(String name);

  /// Accessible label for adding an event to the combined history selection.
  ///
  /// In en, this message translates to:
  /// **'Select {name} for combined history'**
  String screenEventsSelectFor(String name);

  /// Accessible label when an event is already in the combined history selection.
  ///
  /// In en, this message translates to:
  /// **'Selected {name} for combined history'**
  String screenEventsSelectedFor(String name);

  /// Accessible label for opening an upcoming event's configuration.
  ///
  /// In en, this message translates to:
  /// **'Configure {name}'**
  String screenEventsConfigureFor(String name);

  /// Accessible label for the end review action.
  ///
  /// In en, this message translates to:
  /// **'Review the end of {name}'**
  String screenEventsReviewFor(String name);

  /// Accessible label for an event's revision history.
  ///
  /// In en, this message translates to:
  /// **'Revisions for {name}'**
  String screenEventsRevisionsFor(String name);

  /// Accessible label for the unavailable event note preview.
  ///
  /// In en, this message translates to:
  /// **'Add a note for {name}'**
  String screenEventsNoteFor(String name);

  /// One-word visible label for the event note preview.
  ///
  /// In en, this message translates to:
  /// **'Note'**
  String get screenEventsNote;

  /// Title for the unavailable event notes preview.
  ///
  /// In en, this message translates to:
  /// **'Event notes'**
  String get screenEventsNotes;

  /// Truthful preview state. Does not claim saved notes exist.
  ///
  /// In en, this message translates to:
  /// **'Saved event notes are not available in this version. Nothing is added.'**
  String get screenEventsNotesUnavailable;

  /// Factual completion state. Does not claim that every item was audited.
  ///
  /// In en, this message translates to:
  /// **'Marked complete. Recorded history stays available.'**
  String get screenEventsCompletedNote;

  /// Title for the factual notice about what events do and do not change.
  ///
  /// In en, this message translates to:
  /// **'Event context'**
  String get screenEventsContext;

  /// Heading for event dates and timing on the detail page.
  ///
  /// In en, this message translates to:
  /// **'Dates'**
  String get screenEventsDates;

  /// Label for the planned event date range.
  ///
  /// In en, this message translates to:
  /// **'Planned'**
  String get screenEventsPlanned;

  /// Label for the actual event date range.
  ///
  /// In en, this message translates to:
  /// **'Actual'**
  String get screenEventsActual;

  /// Accessible label for the event status filter strip.
  ///
  /// In en, this message translates to:
  /// **'Event status'**
  String get screenEventsFilterLabel;

  /// An event with an end date but no saved start.
  ///
  /// In en, this message translates to:
  /// **'Ends {date}'**
  String screenEventsEnds(String date);

  /// Saved events whose current phase cannot be resolved from their recorded dates.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 needs date review} other{{count} need date review}}'**
  String screenEventsReviewCount(int count);

  /// A linked substance name could not be loaded or no longer resolves. Saved membership identity remains available in event detail.
  ///
  /// In en, this message translates to:
  /// **'Substance unavailable'**
  String get screenEventsItemUnavailable;

  /// Settings hub filter that shows every group. Keeping it as the default hides no destination.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get screenSettingsGroupAll;

  /// Settings hub group holding profile, appearance, reminders and support links.
  ///
  /// In en, this message translates to:
  /// **'General'**
  String get screenSettingsGroupGeneral;

  /// Helper for the General group. Names the real destinations it holds.
  ///
  /// In en, this message translates to:
  /// **'Profile, appearance, reminders and help.'**
  String get screenSettingsGeneralBody;

  /// Helper for the Data group. Names the real destinations it holds.
  ///
  /// In en, this message translates to:
  /// **'Reports, exports, backups and restore.'**
  String get screenSettingsDataBody;

  /// Factual storage badge. Does not claim a cipher, version or remote custody.
  ///
  /// In en, this message translates to:
  /// **'On this device'**
  String get screenSettingsVaultBadge;

  /// Title of the factual storage summary. No size, count or cipher is invented.
  ///
  /// In en, this message translates to:
  /// **'Local storage'**
  String get screenSettingsStorageTitle;

  /// Explicit limitation for the storage summary. Never shows a fabricated size or count.
  ///
  /// In en, this message translates to:
  /// **'Database size and record totals are not available yet.'**
  String get screenSettingsStorageBody;

  /// Badge marking a capability that is not available yet. Never a working switch or command.
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get screenSettingsPreviewBadge;

  /// Labelled preview for unattended backups, which are not implemented.
  ///
  /// In en, this message translates to:
  /// **'Automatic backups'**
  String get screenSettingsAutoBackup;

  /// Points to the real manual backup instead of promising unattended backups.
  ///
  /// In en, this message translates to:
  /// **'Not available yet. Create a backup when you need one.'**
  String get screenSettingsAutoBackupBody;

  /// Labelled preview for a clinical export format, which is not implemented.
  ///
  /// In en, this message translates to:
  /// **'FHIR export'**
  String get screenSettingsFhir;

  /// Points to the real structured export instead of implying FHIR or HL7 support.
  ///
  /// In en, this message translates to:
  /// **'Not available yet. Use Exports for structured data.'**
  String get screenSettingsFhirBody;

  /// Complete form and recorded unit beneath the substance name. The type badge already names the type.
  ///
  /// In en, this message translates to:
  /// **'{form} · {unit}'**
  String screenOverviewFormUnit(String form, String unit);

  /// Section jump back to the identity and commands at the top of the substance overview.
  ///
  /// In en, this message translates to:
  /// **'Overview'**
  String get screenOverviewSectionOverview;

  /// One-word action opening this substance’s existing recorded-use periods.
  ///
  /// In en, this message translates to:
  /// **'Periods'**
  String get screenOverviewPeriods;

  /// Lab panel detail. Authored page heading for a saved lab panel.
  ///
  /// In en, this message translates to:
  /// **'Panel detail'**
  String get screenPanelPanelDetail;

  /// Lab panel detail. Authored page heading for a saved observation.
  ///
  /// In en, this message translates to:
  /// **'Observation detail'**
  String get screenPanelObservationDetail;

  /// Lab panel detail. The saved collection date, shown without inventing a time or zone.
  ///
  /// In en, this message translates to:
  /// **'Collected {date}'**
  String screenPanelCollected(String date);

  /// Lab panel detail. Count caption for the saved results.
  ///
  /// In en, this message translates to:
  /// **'Recorded'**
  String get screenPanelRecorded;

  /// Lab panel detail. Short label for the saved revision number.
  ///
  /// In en, this message translates to:
  /// **'Revision'**
  String get screenPanelRevision;

  /// Lab panel detail. Caption confirming the revision number is a saved revision.
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get screenPanelSaved;

  /// Lab panel detail. Timestamp label when the current revision corrected the record.
  ///
  /// In en, this message translates to:
  /// **'Revised'**
  String get screenPanelRevised;

  /// Lab panel detail. Filter pill showing every saved result.
  ///
  /// In en, this message translates to:
  /// **'All ({count})'**
  String screenPanelFilterAll(int count);

  /// Lab panel detail. Filter pill for results that include saved source range text.
  ///
  /// In en, this message translates to:
  /// **'With range ({count})'**
  String screenPanelFilterRange(int count);

  /// Lab panel detail. Filter pill for results that have no saved source range text.
  ///
  /// In en, this message translates to:
  /// **'No range ({count})'**
  String screenPanelFilterNoRange(int count);

  /// Lab panel detail. Truthful empty state when the chosen factual filter has no matching results.
  ///
  /// In en, this message translates to:
  /// **'No results in this filter.'**
  String get screenPanelNoFilteredResults;

  /// Lab panel detail. Kind label for a linked substance.
  ///
  /// In en, this message translates to:
  /// **'Substance'**
  String get screenPanelSubstance;

  /// Lab panel detail. Kind label for a linked event.
  ///
  /// In en, this message translates to:
  /// **'Event'**
  String get screenPanelEvent;

  /// Lab panel detail. The stored link id no longer resolves to a saved substance or event. Do not show the raw id.
  ///
  /// In en, this message translates to:
  /// **'Linked record unavailable'**
  String get screenPanelLinkGone;

  /// Lab panel detail. Section for checksums recorded against saved source files.
  ///
  /// In en, this message translates to:
  /// **'File checksums'**
  String get screenPanelFileChecksums;

  /// Lab panel detail. States that a saved file hash is not a complete ledger or clinical verification claim.
  ///
  /// In en, this message translates to:
  /// **'Recorded when each file was saved. This does not verify the whole record.'**
  String get screenPanelFileChecksumsHelp;

  /// Lab panel detail. Checksum read failure.
  ///
  /// In en, this message translates to:
  /// **'Saved checksums could not be loaded. Retry.'**
  String get screenPanelChecksumsUnavailable;

  /// Lab panel detail. Labels a saved file beside its recorded checksum without impersonating a source reference.
  ///
  /// In en, this message translates to:
  /// **'File: {name}'**
  String screenPanelFileLabel(String name);

  /// Lab panel detail. Truthful limit note when the bounded checksum list reaches 25 files.
  ///
  /// In en, this message translates to:
  /// **'Checksums use up to 25 saved files. Open Files to review all files.'**
  String get screenPanelChecksumLimit;

  /// Lab panel detail. Empty state for saved file checksums. No example hash is shown.
  ///
  /// In en, this message translates to:
  /// **'No saved files. Add a source file to record its checksum.'**
  String get screenPanelNoFiles;

  /// Lab panel detail. Button that copies a recorded checksum.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get screenPanelCopy;

  /// Lab panel detail. Copy button state after the checksum is placed on the clipboard.
  ///
  /// In en, this message translates to:
  /// **'Copied'**
  String get screenPanelCopied;

  /// Lab panel detail. Polite live update after copying a checksum.
  ///
  /// In en, this message translates to:
  /// **'Checksum copied.'**
  String get screenPanelChecksumCopied;

  /// Lab panel detail. Clipboard failure with a retry instruction.
  ///
  /// In en, this message translates to:
  /// **'Copy failed. Try again.'**
  String get screenPanelCopyFailed;

  /// Lab panel detail. Accessible name for a copy button, including the saved file name.
  ///
  /// In en, this message translates to:
  /// **'Copy checksum for {name}'**
  String screenPanelCopyChecksum(String name);

  /// Lab panel detail. Truthful state for the missing FHIR export capability. Export opens the existing formats only.
  ///
  /// In en, this message translates to:
  /// **'FHIR export is not available in this build. Use Export for the formats Vital supports.'**
  String get screenPanelFhirUnavailable;

  /// Saved files exist in the bounded page but none have stored inspection hashes.
  ///
  /// In en, this message translates to:
  /// **'The files shown have no recorded checksum. Open Files to review them.'**
  String get screenPanelNoChecksums;

  /// Exact dose preset selection and management.
  ///
  /// In en, this message translates to:
  /// **'Saved amounts'**
  String get featurePresetHeading;

  /// Exact dose preset selection and management.
  ///
  /// In en, this message translates to:
  /// **'Choose a saved amount or enter your own. Schedule amounts come from the latest saved schedule.'**
  String get featurePresetHelp;

  /// Exact dose preset selection and management.
  ///
  /// In en, this message translates to:
  /// **'Enter an amount above, then Add to keep it for this substance. This does not record a dose.'**
  String get featurePresetManageHelp;

  /// Exact dose preset selection and management.
  ///
  /// In en, this message translates to:
  /// **'Unable to load saved amounts. Retry.'**
  String get featurePresetLoadFailed;

  /// Exact dose preset selection and management.
  ///
  /// In en, this message translates to:
  /// **'Unable to save the change. Retry.'**
  String get featurePresetSaveFailed;

  /// Exact dose preset selection and management.
  ///
  /// In en, this message translates to:
  /// **'Unable to load schedule amounts. Retry.'**
  String get featurePresetPlanFailed;

  /// Exact dose preset selection and management.
  ///
  /// In en, this message translates to:
  /// **'You can save up to 8 amounts. Remove one to add another.'**
  String get featurePresetLimit;

  /// Exact dose preset selection and management.
  ///
  /// In en, this message translates to:
  /// **'Less'**
  String get featurePresetLess;

  /// Exact dose preset selection and management.
  ///
  /// In en, this message translates to:
  /// **'Choose {amount} {unit}'**
  String featurePresetSelect(String amount, String unit);

  /// Exact dose preset selection and management.
  ///
  /// In en, this message translates to:
  /// **'Remove saved amount {amount} {unit}'**
  String featurePresetRemove(String amount, String unit);

  /// Dashboard week navigation. The localised first and last date of the shown week. The word to joins them without a dash.
  ///
  /// In en, this message translates to:
  /// **'{start} to {end}'**
  String featureWeekRange(String start, String end);

  /// Accessible name for the previous-week arrow on the dashboard.
  ///
  /// In en, this message translates to:
  /// **'Previous week'**
  String get featureWeekPrevious;

  /// Accessible name for the next-week arrow on the dashboard.
  ///
  /// In en, this message translates to:
  /// **'Next week'**
  String get featureWeekNext;

  /// Dashboard weekly summary heading.
  ///
  /// In en, this message translates to:
  /// **'Week summary'**
  String get featureWeekSummary;

  /// Dashboard weekly summary. States that the totals count planned dose slots, not every kind of record.
  ///
  /// In en, this message translates to:
  /// **'Counts cover planned doses.'**
  String get featureWeekSummaryHelp;

  /// Dashboard weekly summary metric label.
  ///
  /// In en, this message translates to:
  /// **'Planned'**
  String get featureWeekPlanned;

  /// Dashboard weekly summary metric label.
  ///
  /// In en, this message translates to:
  /// **'Recorded'**
  String get featureWeekRecorded;

  /// Dashboard weekly summary metric label.
  ///
  /// In en, this message translates to:
  /// **'Skipped'**
  String get featureWeekSkipped;

  /// Dashboard weekly summary. Truthful partial state when a calculation or action-history limit was reached.
  ///
  /// In en, this message translates to:
  /// **'Some days could not be calculated. This summary is incomplete.'**
  String get featureWeekIncomplete;

  /// Dashboard weekly summary. Empty week state. No zero ratio is shown.
  ///
  /// In en, this message translates to:
  /// **'No doses are planned this week.'**
  String get featureWeekNoPlans;

  /// Dashboard badge for a selected day that is not today.
  ///
  /// In en, this message translates to:
  /// **'Viewing'**
  String get featureWeekViewing;

  /// Dashboard browsed-day note. Explains that one-tap current-time actions remain on today and the record form takes an explicit time.
  ///
  /// In en, this message translates to:
  /// **'Taken, Skip and Snooze stay on today. Record uses the time you enter.'**
  String get featureWeekViewingHelp;

  /// Dashboard heading replacing Today's sequence while another date is browsed.
  ///
  /// In en, this message translates to:
  /// **'Day sequence'**
  String get featureWeekDaySequence;

  /// Dashboard browsed-day empty state.
  ///
  /// In en, this message translates to:
  /// **'No doses are planned for this day.'**
  String get featureWeekNothingPlanned;

  /// Dashboard browsed-day recorded section empty state.
  ///
  /// In en, this message translates to:
  /// **'No doses recorded on this day.'**
  String get featureWeekNoRecorded;

  /// Dashboard quick-record configuration dialog heading.
  ///
  /// In en, this message translates to:
  /// **'Quick record'**
  String get featureWeekQuickRecord;

  /// Dashboard quick-record configuration. Explains the saved subset and order.
  ///
  /// In en, this message translates to:
  /// **'Choose as-needed plans and their order.'**
  String get featureWeekFavouritesHelp;

  /// Dashboard quick-record configuration. Explains the default when no saved subset exists.
  ///
  /// In en, this message translates to:
  /// **'With nothing chosen, every as-needed plan appears.'**
  String get featureWeekFavouritesEmptyHelp;

  /// Dashboard quick-record configuration. Saved plans deleted or changed away from as-needed are reported instead of silently replaced.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 saved choice is no longer available.} other{{count} saved choices are no longer available.}}'**
  String featureWeekFavouritesStale(int count);

  /// Dashboard quick-record configuration. States the effect of saving after unavailable choices were found.
  ///
  /// In en, this message translates to:
  /// **'Saving removes them.'**
  String get featureWeekFavouritesStaleHelp;

  /// Dashboard quick-record configuration. Storage failure with the last committed selection preserved.
  ///
  /// In en, this message translates to:
  /// **'Not saved. Your saved choices are unchanged.'**
  String get featureWeekFavouriteSaveFailure;

  /// Dashboard quick-record row. Non-blocking load failure for the saved subset.
  ///
  /// In en, this message translates to:
  /// **'Saved choices could not be loaded.'**
  String get featureWeekFavouriteLoadFailure;

  /// Dashboard quick-record row. Non-blocking plan load failure.
  ///
  /// In en, this message translates to:
  /// **'Plans could not be loaded.'**
  String get featureWeekPlansLoadFailure;

  /// Dashboard quick-record configuration. Saving is disabled when the full collection could not be read.
  ///
  /// In en, this message translates to:
  /// **'The plan list is incomplete. Reload before saving.'**
  String get featureWeekFavouriteListIncomplete;

  /// Dashboard quick-record row. Saved plans that no longer exist or are no longer as-needed.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 saved choice is unavailable.} other{{count} saved choices are unavailable.}}'**
  String featureWeekFavouriteUnavailable(int count);

  /// Accessible name for moving one saved quick-record choice earlier.
  ///
  /// In en, this message translates to:
  /// **'Move up'**
  String get featureWeekMoveUp;

  /// Accessible name for moving one saved quick-record choice later.
  ///
  /// In en, this message translates to:
  /// **'Move down'**
  String get featureWeekMoveDown;

  /// Accessible name for the quick-record choice checkbox, including the full plan name.
  ///
  /// In en, this message translates to:
  /// **'Include {name}'**
  String featureWeekInclude(String name);

  /// Dashboard quick-record row when no as-needed plan exists.
  ///
  /// In en, this message translates to:
  /// **'No as-needed plans.'**
  String get featureWeekNoAsNeeded;

  /// Dashboard week navigation. Visible fallback when no device zone was observed.
  ///
  /// In en, this message translates to:
  /// **'Times shown in UTC.'**
  String get featureWeekUtc;

  /// Substances list. Accessible name for the row of plan-status filters.
  ///
  /// In en, this message translates to:
  /// **'Plan status'**
  String get featureStatusFiltersLabel;

  /// Substances list. Clears the plan-status filter only. Kept distinct from the item-type All filter.
  ///
  /// In en, this message translates to:
  /// **'All statuses'**
  String get featureStatusAll;

  /// Substances list. At least one current nonpaused scheduled plan applies.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get featureStatusActive;

  /// Substances list. At least one current plan is paused. A paused As needed plan counts only as paused while paused.
  ///
  /// In en, this message translates to:
  /// **'Paused'**
  String get featureStatusPaused;

  /// Substances list. At least one current nonpaused As needed plan applies.
  ///
  /// In en, this message translates to:
  /// **'As needed'**
  String get featureStatusAsNeeded;

  /// Substances list. No plan applies now. Future-only, ended and absent plans count here.
  ///
  /// In en, this message translates to:
  /// **'Unscheduled'**
  String get featureStatusUnscheduled;

  /// Substances list. Explains that status filters may overlap and what Unscheduled means. Not an adherence statement.
  ///
  /// In en, this message translates to:
  /// **'An item with more than one plan can appear under each matching status. Future and ended plans count as unscheduled.'**
  String get featureStatusMixedHelp;

  /// Substances list. Truthful note when a stored plan's date or time zone cannot be evaluated. No guessed status.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 item is only in All because its plan could not be checked.} other{{count} items are only in All because their plans could not be checked.}}'**
  String featureStatusUnresolvedHelp(int count);

  /// No description provided for @featureVaultTitle.
  ///
  /// In en, this message translates to:
  /// **'Local data'**
  String get featureVaultTitle;

  /// No description provided for @featureVaultDatabase.
  ///
  /// In en, this message translates to:
  /// **'Database files'**
  String get featureVaultDatabase;

  /// No description provided for @featureVaultBody.
  ///
  /// In en, this message translates to:
  /// **'Includes saved files, drafts and retained history. Excludes exported files and backups.'**
  String get featureVaultBody;

  /// No description provided for @featureVaultCountsHelp.
  ///
  /// In en, this message translates to:
  /// **'Current doses and supporting records exclude voided entries.'**
  String get featureVaultCountsHelp;

  /// No description provided for @featureVaultDoses.
  ///
  /// In en, this message translates to:
  /// **'Recorded doses'**
  String get featureVaultDoses;

  /// Measured physical database storage size. Unit is bytes, KiB, MiB or GiB.
  ///
  /// In en, this message translates to:
  /// **'{value} {unit}'**
  String featureVaultSize(String value, String unit);

  /// Exact measured size for accessibility.
  ///
  /// In en, this message translates to:
  /// **'{count} bytes'**
  String featureVaultExactBytes(String count);

  /// No description provided for @featureVaultUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Size unavailable'**
  String get featureVaultUnavailable;

  /// No description provided for @featureVaultFailed.
  ///
  /// In en, this message translates to:
  /// **'Local data could not be read. Try again.'**
  String get featureVaultFailed;

  /// No description provided for @featureVaultReportDates.
  ///
  /// In en, this message translates to:
  /// **'Report dates'**
  String get featureVaultReportDates;

  /// No description provided for @featureVaultThirty.
  ///
  /// In en, this message translates to:
  /// **'30d'**
  String get featureVaultThirty;

  /// No description provided for @featureVaultNinety.
  ///
  /// In en, this message translates to:
  /// **'90d'**
  String get featureVaultNinety;

  /// No description provided for @featureVaultYear.
  ///
  /// In en, this message translates to:
  /// **'Year'**
  String get featureVaultYear;

  /// No description provided for @featureVaultThirtyLabel.
  ///
  /// In en, this message translates to:
  /// **'Last 30 days, including today'**
  String get featureVaultThirtyLabel;

  /// No description provided for @featureVaultNinetyLabel.
  ///
  /// In en, this message translates to:
  /// **'Last 90 days, including today'**
  String get featureVaultNinetyLabel;

  /// No description provided for @featureVaultYearLabel.
  ///
  /// In en, this message translates to:
  /// **'Year to date'**
  String get featureVaultYearLabel;

  /// Inclusive dates displayed before opening the report selection.
  ///
  /// In en, this message translates to:
  /// **'{from} to {through}'**
  String featureVaultRange(String from, String through);

  /// Optional disclosure heading on the dose sheet.
  ///
  /// In en, this message translates to:
  /// **'Dose context'**
  String get featureContextHeading;

  /// Explains that dose context is optional and never inferred.
  ///
  /// In en, this message translates to:
  /// **'Optional. Add only the context you choose. It is saved with this dose.'**
  String get featureContextHelp;

  /// Field label for an optional private note on one dose.
  ///
  /// In en, this message translates to:
  /// **'Note (optional)'**
  String get featureContextNotes;

  /// Explains the existing notes privacy option for a dose note.
  ///
  /// In en, this message translates to:
  /// **'Stays private in exports and reports unless you choose to include notes.'**
  String get featureContextNotesHelp;

  /// Validation message when a dose note is too long.
  ///
  /// In en, this message translates to:
  /// **'Use a note of 2000 characters or fewer.'**
  String get featureContextNoteInvalid;

  /// Field label for optional neutral context tags on one dose.
  ///
  /// In en, this message translates to:
  /// **'Tags (optional)'**
  String get featureContextTags;

  /// Explains that tags are user-chosen context, never inferred instructions.
  ///
  /// In en, this message translates to:
  /// **'Separate tags with commas. Tags describe this dose and are not instructions.'**
  String get featureContextTagsHelp;

  /// Validation message for too many or too-long context tags.
  ///
  /// In en, this message translates to:
  /// **'Use up to 12 tags of 40 characters or fewer.'**
  String get featureContextTagsInvalid;

  /// Optional context tag chosen by the person, never inferred.
  ///
  /// In en, this message translates to:
  /// **'With food'**
  String get featureContextTagWithFood;

  /// Optional context tag chosen by the person, never inferred.
  ///
  /// In en, this message translates to:
  /// **'Empty stomach'**
  String get featureContextTagEmptyStomach;

  /// Optional context tag chosen by the person.
  ///
  /// In en, this message translates to:
  /// **'Morning'**
  String get featureContextTagMorning;

  /// Optional context tag chosen by the person.
  ///
  /// In en, this message translates to:
  /// **'Evening'**
  String get featureContextTagEvening;

  /// Read-only context tags shown with a saved dose.
  ///
  /// In en, this message translates to:
  /// **'Tags: {tags}.'**
  String featureContextTagsValue(String tags);

  /// Read-only private note shown with a saved dose.
  ///
  /// In en, this message translates to:
  /// **'Note: {note}.'**
  String featureContextNoteValue(String note);

  /// One-word disclosure button that reveals the optional skip reason field.
  ///
  /// In en, this message translates to:
  /// **'Reason'**
  String get featureContextSkipReasonAction;

  /// Field label for an optional reason saved only with a skip.
  ///
  /// In en, this message translates to:
  /// **'Skip reason (optional)'**
  String get featureContextSkipReason;

  /// Explains that a skip reason is optional and does not alter the plan.
  ///
  /// In en, this message translates to:
  /// **'Saved only with this skip. It does not change the planned dose.'**
  String get featureContextSkipReasonHelp;

  /// Validation message when a skip reason is too long.
  ///
  /// In en, this message translates to:
  /// **'Use a skip reason of 500 characters or fewer.'**
  String get featureContextSkipReasonInvalid;

  /// Read-only skip reason shown in action and skip history.
  ///
  /// In en, this message translates to:
  /// **'Reason: {reason}.'**
  String featureContextSkipReasonValue(String reason);

  /// Count of explicit skip actions in the reviewed export, separate from dose records and revisions.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No skipped actions} =1{1 skipped action} other{{count} skipped actions}}'**
  String featureContextExportSkipCount(int count);

  /// Event overview: Event totals
  ///
  /// In en, this message translates to:
  /// **'Event totals'**
  String get featureEventsTotals;

  /// Event overview: Recorded doses
  ///
  /// In en, this message translates to:
  /// **'Recorded doses'**
  String get featureEventsRecorded;

  /// Event overview: Skipped actions
  ///
  /// In en, this message translates to:
  /// **'Skipped actions'**
  String get featureEventsSkipped;

  /// Event overview: Linked substances
  ///
  /// In en, this message translates to:
  /// **'Linked substances'**
  String get featureEventsLinked;

  /// Event overview: Current records within the event and membership dates. These counts do not measure adherence.
  ///
  /// In en, this message translates to:
  /// **'Current records within the event and membership dates. These counts do not measure adherence.'**
  String get featureEventsCountsHelp;

  /// Event overview: Review the event dates to see totals.
  ///
  /// In en, this message translates to:
  /// **'Review the event dates to see totals.'**
  String get featureEventsCountsReview;

  /// Event overview: Some skipped times need review.
  ///
  /// In en, this message translates to:
  /// **'Some skipped times need review.'**
  String get featureEventsSkippedReview;

  /// Event overview: Totals could not be read. Try again.
  ///
  /// In en, this message translates to:
  /// **'Totals could not be read. Try again.'**
  String get featureEventsCountsFailed;

  /// Event overview: Notes
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get featureEventsNotes;

  /// Event overview: Private event notes. Included in event reports only when notes are selected.
  ///
  /// In en, this message translates to:
  /// **'Private event notes. Included in event reports only when notes are selected.'**
  String get featureEventsNotesHelp;

  /// Event overview: Use 8000 characters or fewer for event notes.
  ///
  /// In en, this message translates to:
  /// **'Use 8000 characters or fewer for event notes.'**
  String get featureEventsNotesLong;

  /// Whole-event current dose and explicit skip counts, distinct from adherence.
  ///
  /// In en, this message translates to:
  /// **'{recorded} recorded · {skipped} skipped'**
  String featureEventsCounts(int recorded, int skipped);

  /// Lab categories, factual trends and source comparison.
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get screenLabsCategory;

  /// Lab categories, factual trends and source comparison.
  ///
  /// In en, this message translates to:
  /// **'Copy a category from the source, or enter your own. Leave blank to group as Other.'**
  String get screenLabsCategoryHelp;

  /// Lab categories, factual trends and source comparison.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get screenLabsCategoryOther;

  /// Lab categories, factual trends and source comparison.
  ///
  /// In en, this message translates to:
  /// **'Accession'**
  String get supportingAccession;

  /// Lab categories, factual trends and source comparison.
  ///
  /// In en, this message translates to:
  /// **'Report identifier'**
  String get supportingReportId;

  /// Lab categories, factual trends and source comparison.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 exact result} other{{count} exact results}} from {first} to {last}. Open Table for dates and values.'**
  String screenLabsSparklineSummary(int count, String first, String last);

  /// Lab categories, factual trends and source comparison.
  ///
  /// In en, this message translates to:
  /// **'Dated exact values with matching units, laboratory, method and specimen.'**
  String get screenLabsSparklineExactOnly;

  /// Lab categories, factual trends and source comparison.
  ///
  /// In en, this message translates to:
  /// **'Show trend dates and exact values'**
  String get screenLabsSparklineTable;

  /// Lab categories, factual trends and source comparison.
  ///
  /// In en, this message translates to:
  /// **'Date'**
  String get screenLabsSparklineDate;

  /// Lab categories, factual trends and source comparison.
  ///
  /// In en, this message translates to:
  /// **'Value'**
  String get screenLabsSparklineValue;

  /// Lab categories, factual trends and source comparison.
  ///
  /// In en, this message translates to:
  /// **'Previous result'**
  String get featureLabsEarlier;

  /// Lab categories, factual trends and source comparison.
  ///
  /// In en, this message translates to:
  /// **'Previous: {value}. Collected {date}.'**
  String featureLabsEarlierValue(String value, String date);

  /// Lab categories, factual trends and source comparison.
  ///
  /// In en, this message translates to:
  /// **'Change: {value}.'**
  String featureLabsChange(String value);

  /// Lab categories, factual trends and source comparison.
  ///
  /// In en, this message translates to:
  /// **'The exact change has no short decimal form.'**
  String get featureLabsChangeUnavailable;

  /// Lab categories, factual trends and source comparison.
  ///
  /// In en, this message translates to:
  /// **'No comparable earlier result in the loaded window.'**
  String get featureLabsNoEarlier;

  /// Lab categories, factual trends and source comparison.
  ///
  /// In en, this message translates to:
  /// **'Earlier results are limited to 50 saved records before this panel. Older records may be outside this window.'**
  String get featureLabsEarlierLimited;

  /// Lab categories, factual trends and source comparison.
  ///
  /// In en, this message translates to:
  /// **'Collection dates do not establish an unambiguous previous result.'**
  String get featureLabsEarlierIncomplete;

  /// Lab categories, factual trends and source comparison.
  ///
  /// In en, this message translates to:
  /// **'Comparison needs an exact or qualitative value and matching units, laboratory, method and specimen.'**
  String get featureLabsEarlierIncompatible;

  /// Lab categories, factual trends and source comparison.
  ///
  /// In en, this message translates to:
  /// **'Previous results could not load. Try again.'**
  String get featureLabsEarlierFailure;

  /// Lab categories, factual trends and source comparison.
  ///
  /// In en, this message translates to:
  /// **'Loading previous results.'**
  String get featureLabsEarlierLoading;

  /// Discloses source metadata included with selected lab records in reports and exports.
  ///
  /// In en, this message translates to:
  /// **'Selected lab records include saved categories and accession or report identifiers. Notes stay private unless selected.'**
  String get featureLabsMetadataHelp;

  /// Disclosure heading and page heading for optional pack facts such as lot, expiry and capacity.
  ///
  /// In en, this message translates to:
  /// **'Container details'**
  String get featureStockDetails;

  /// Explains that lot, expiry and capacity are descriptive and never limit stock or recording.
  ///
  /// In en, this message translates to:
  /// **'Optional facts about this pack. They do not change its recorded balance.'**
  String get featureStockDetailsHelp;

  /// Optional field label for a user-entered lot or batch printed on the container.
  ///
  /// In en, this message translates to:
  /// **'Lot or batch'**
  String get featureStockLot;

  /// Helper text for the optional lot or batch field.
  ///
  /// In en, this message translates to:
  /// **'Optional. Leave blank when no lot or batch is printed.'**
  String get featureStockLotHelp;

  /// Validation message for a lot or batch entry that is too long.
  ///
  /// In en, this message translates to:
  /// **'Use a lot or batch of 200 characters or fewer.'**
  String get featureStockLotInvalid;

  /// Field label for the optional civil expiry date printed on the pack.
  ///
  /// In en, this message translates to:
  /// **'Expiry date'**
  String get featureStockExpiry;

  /// Helper text for the optional expiry date field.
  ///
  /// In en, this message translates to:
  /// **'Optional. Use YYYY-MM-DD.'**
  String get featureStockExpiryHelp;

  /// Validation message for an invalid expiry date.
  ///
  /// In en, this message translates to:
  /// **'Enter a real date as YYYY-MM-DD.'**
  String get featureStockExpiryInvalid;

  /// Field label for the optional full pack amount in the container unit.
  ///
  /// In en, this message translates to:
  /// **'Pack capacity'**
  String get featureStockCapacity;

  /// Explains that capacity is descriptive and never a balance cap.
  ///
  /// In en, this message translates to:
  /// **'Optional. The full pack amount in {unit}. Use a number or a fraction such as 1/3. It does not limit recorded stock.'**
  String featureStockCapacityHelp(String unit);

  /// Validation message for an invalid pack capacity.
  ///
  /// In en, this message translates to:
  /// **'Enter a capacity greater than zero as a number or fraction, up to 9,000,000,000.'**
  String get featureStockCapacityInvalid;

  /// Confirmation after saving pack details.
  ///
  /// In en, this message translates to:
  /// **'Container details saved.'**
  String get featureStockMetadataSaved;

  /// Disclosure heading for saved pack-detail revisions.
  ///
  /// In en, this message translates to:
  /// **'Details history'**
  String get featureStockMetadataHistory;

  /// Source label for the first saved pack details.
  ///
  /// In en, this message translates to:
  /// **'Added'**
  String get featureStockMetadataCreated;

  /// Source label for an edited pack-detail revision.
  ///
  /// In en, this message translates to:
  /// **'Edited'**
  String get featureStockMetadataEdited;

  /// Source label for pack details carried forward by the schema migration.
  ///
  /// In en, this message translates to:
  /// **'Carried forward'**
  String get featureStockMetadataMigrated;

  /// One pack-detail history line with source, revision and recorded time.
  ///
  /// In en, this message translates to:
  /// **'{source}, version {revision}, {date}'**
  String featureStockMetadataEntry(String source, int revision, String date);

  /// Read-only lot or batch value.
  ///
  /// In en, this message translates to:
  /// **'Lot: {lot}'**
  String featureStockLotValue(String lot);

  /// Expiry badge for a date before today.
  ///
  /// In en, this message translates to:
  /// **'Expired {date}'**
  String featureStockExpiryExpired(String date);

  /// Expiry badge for the current local day.
  ///
  /// In en, this message translates to:
  /// **'Expires today'**
  String get featureStockExpiryToday;

  /// Expiry badge for a future date.
  ///
  /// In en, this message translates to:
  /// **'Expires {date}'**
  String featureStockExpiryFuture(String date);

  /// Read-only pack capacity with its exact amount and unit.
  ///
  /// In en, this message translates to:
  /// **'Capacity: {amount}'**
  String featureStockCapacityValue(String amount);

  /// Shown when no pack capacity is recorded. No proportion is invented.
  ///
  /// In en, this message translates to:
  /// **'Capacity not set'**
  String get featureStockCapacityUnknown;

  /// Exact remaining amount against exact pack capacity.
  ///
  /// In en, this message translates to:
  /// **'{balance} of {capacity}'**
  String featureStockCapacityProgress(String balance, String capacity);

  /// Factual note when the exact balance exceeds the descriptive capacity.
  ///
  /// In en, this message translates to:
  /// **'Above pack capacity'**
  String get featureStockAboveCapacity;

  /// Explains that restocking the same container never changes its lot or strength snapshots.
  ///
  /// In en, this message translates to:
  /// **'Adds supply to this container and keeps its lot and strength. Add a container when the lot or strength changes.'**
  String get featureStockRestockHelp;

  /// Accessible label for the inventory search field.
  ///
  /// In en, this message translates to:
  /// **'Search stock'**
  String get featureStockSearchLabel;

  /// Placeholder example for the inventory search field.
  ///
  /// In en, this message translates to:
  /// **'Search containers'**
  String get featureStockSearchHint;

  /// Accessible label for the inventory state filter group.
  ///
  /// In en, this message translates to:
  /// **'Stock filters'**
  String get featureStockFilters;

  /// Inventory filter showing every container.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get featureStockFilterAll;

  /// Inventory filter for a known balance at or below its low or refill state.
  ///
  /// In en, this message translates to:
  /// **'Low'**
  String get featureStockFilterLow;

  /// Inventory filter for a known positive balance above its low or refill state.
  ///
  /// In en, this message translates to:
  /// **'Adequate'**
  String get featureStockFilterAdequate;

  /// Inventory filter for a container whose substance schedule is paused or mixed.
  ///
  /// In en, this message translates to:
  /// **'Paused'**
  String get featureStockFilterPaused;

  /// Inventory filter for an unknown or aggregate-limited stock balance.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get featureStockFilterUnknown;

  /// Explains overlapping paused and balance filter counts.
  ///
  /// In en, this message translates to:
  /// **'Paused counts the schedule, so a container can also count as low, adequate or unknown.'**
  String get featureStockFilterOverlapHelp;

  /// Filtered-empty heading for the stock inventory.
  ///
  /// In en, this message translates to:
  /// **'No matches'**
  String get featureStockFilterEmptyTitle;

  /// Recovery guidance when no container matches the current search and filter.
  ///
  /// In en, this message translates to:
  /// **'Try another name or clear the stock filter.'**
  String get featureStockFilterEmptyBody;

  /// Disclosure when the bounded inventory read cannot guarantee whole-collection totals.
  ///
  /// In en, this message translates to:
  /// **'Some stock totals are unavailable. Narrow the search.'**
  String get featureStockCountsIncomplete;

  /// Counts containers deliberately left out of paused and unscheduled totals because their plan could not be read.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 container has a plan that could not be read.} other{{count} containers have a plan that could not be read.}}'**
  String featureStockUnresolvedHelp(int count);

  /// Factual schedule badge for a container whose substance plan is paused.
  ///
  /// In en, this message translates to:
  /// **'Plan paused'**
  String get featureStockPlanPaused;

  /// Factual schedule badge when paused and active plans both apply to the substance.
  ///
  /// In en, this message translates to:
  /// **'Mixed plans'**
  String get featureStockPlanMixed;

  /// Factual schedule badge when the substance has no current plan.
  ///
  /// In en, this message translates to:
  /// **'No schedule'**
  String get featureStockPlanUnscheduled;

  /// Factual schedule badge when the stored plan could not be read.
  ///
  /// In en, this message translates to:
  /// **'Plan unavailable'**
  String get featureStockPlanUnresolved;

  /// Label for the conditional schedule-based run-out projection.
  ///
  /// In en, this message translates to:
  /// **'Run-out'**
  String get featureStockRunOut;

  /// Conditional run-out date. The date is exact; 'around' acknowledges untimed daily plans.
  ///
  /// In en, this message translates to:
  /// **'Around {date}'**
  String featureStockRunOutEstimate(String date);

  /// Essential assumption behind the run-out estimate. No dose is shared across containers.
  ///
  /// In en, this message translates to:
  /// **'Planned doses only. Starts tomorrow, so today\'s remaining planned use is excluded. Assumes this container supplies all of them.'**
  String get featureStockRunOutHelp;

  /// Heading when the conditional run-out projection cannot be calculated.
  ///
  /// In en, this message translates to:
  /// **'Run-out unavailable'**
  String get featureStockRunOutUnavailable;

  /// Unavailable reason for a PRN-only schedule.
  ///
  /// In en, this message translates to:
  /// **'As-needed use has no run-out date.'**
  String get featureStockRunOutAsNeeded;

  /// Unavailable reason when the substance has no current plan.
  ///
  /// In en, this message translates to:
  /// **'No schedule gives a run-out estimate.'**
  String get featureStockRunOutUnscheduled;

  /// Unavailable reason for an indefinite pause.
  ///
  /// In en, this message translates to:
  /// **'The schedule is paused.'**
  String get featureStockRunOutPaused;

  /// Unavailable reason when the balance is unknown.
  ///
  /// In en, this message translates to:
  /// **'Measure the remaining amount to estimate run-out.'**
  String get featureStockRunOutUnknown;

  /// Unavailable reason when the stored balance is a deficit.
  ///
  /// In en, this message translates to:
  /// **'The balance is below zero.'**
  String get featureStockRunOutDeficit;

  /// Unavailable reason when the exact remaining balance is zero.
  ///
  /// In en, this message translates to:
  /// **'The balance is empty.'**
  String get featureStockRunOutEmpty;

  /// Unavailable reason when the exact aggregate reached its calculation limit.
  ///
  /// In en, this message translates to:
  /// **'The stock total is unavailable.'**
  String get featureStockRunOutLimit;

  /// Unavailable reason for a planned dose without a usable amount.
  ///
  /// In en, this message translates to:
  /// **'A planned dose has no amount.'**
  String get featureStockRunOutMissingAmount;

  /// Unavailable reason when exact unit conversion is not possible.
  ///
  /// In en, this message translates to:
  /// **'The plan units do not convert to this container\'s unit.'**
  String get featureStockRunOutIncompatible;

  /// Unavailable reason when the plan zone is missing or invalid.
  ///
  /// In en, this message translates to:
  /// **'The plan time zone could not be resolved.'**
  String get featureStockRunOutZone;

  /// Unavailable reason for a missing or repeated local clock time.
  ///
  /// In en, this message translates to:
  /// **'The plan clock could not be resolved.'**
  String get featureStockRunOutClock;

  /// Unavailable reason for an unsupported or ambiguous schedule composition.
  ///
  /// In en, this message translates to:
  /// **'This schedule cannot be forecast reliably.'**
  String get featureStockRunOutUnsupported;

  /// Unavailable reason for elapsed interval schedules.
  ///
  /// In en, this message translates to:
  /// **'Interval schedules have no fixed dates to forecast.'**
  String get featureStockRunOutInterval;

  /// No run-out occurs before a finite plan ends.
  ///
  /// In en, this message translates to:
  /// **'Planned doses end on {date}.'**
  String featureStockRunOutPlanEnds(String date);

  /// Unavailable reason when the bounded forecast window is exceeded.
  ///
  /// In en, this message translates to:
  /// **'No run-out within the one-year calculation.'**
  String get featureStockRunOutHorizon;

  /// Unavailable reason when the saved schedule has no planned doses in the bounded window.
  ///
  /// In en, this message translates to:
  /// **'No planned doses in the next year.'**
  String get featureStockRunOutNoPlanned;

  /// Saved expiry date in a historical container details revision. No current expiry status is inferred.
  ///
  /// In en, this message translates to:
  /// **'Expiry date: {date}'**
  String featureStockExpiryValue(String date);

  /// A metadata history row created from an older database, without a known original timestamp.
  ///
  /// In en, this message translates to:
  /// **'Carried forward, version {revision}. Time not recorded.'**
  String featureStockMetadataUndated(int revision);

  /// Empty container details history. Does not claim a migration or invented timestamp.
  ///
  /// In en, this message translates to:
  /// **'No saved details versions.'**
  String get featureStockMetadataEmpty;

  /// Protected backup receipt history. Local metadata only; no destination, password or private record content.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get featureBackupHistory;

  /// Protected backup receipt history. Local metadata only; no destination, password or private record content.
  ///
  /// In en, this message translates to:
  /// **'The latest 20 local receipts for this dataset. Dates use this device’s time zone. Receipts do not confirm that an external file still exists or can be restored now.'**
  String get featureBackupHistoryHelp;

  /// Protected backup receipt history. Local metadata only; no destination, password or private record content.
  ///
  /// In en, this message translates to:
  /// **'No backup receipts yet. Create and save a protected backup to record a confirmed save here.'**
  String get featureBackupHistoryEmpty;

  /// Protected backup receipt history. Local metadata only; no destination, password or private record content.
  ///
  /// In en, this message translates to:
  /// **'Loading backup history.'**
  String get featureBackupHistoryLoading;

  /// Protected backup receipt history. Local metadata only; no destination, password or private record content.
  ///
  /// In en, this message translates to:
  /// **'Backup history could not be loaded. Retry to check it.'**
  String get featureBackupHistoryFailed;

  /// Protected backup receipt history. Local metadata only; no destination, password or private record content.
  ///
  /// In en, this message translates to:
  /// **'The backup step succeeded, but its history could not be saved. A receipt may be missing.'**
  String get featureBackupHistoryWriteFailed;

  /// Protected backup receipt history. Local metadata only; no destination, password or private record content.
  ///
  /// In en, this message translates to:
  /// **'Last save'**
  String get featureBackupHistoryLastSave;

  /// Protected backup receipt history. Local metadata only; no destination, password or private record content.
  ///
  /// In en, this message translates to:
  /// **'No confirmed save in the retained history.'**
  String get featureBackupHistoryNoSave;

  /// Protected backup receipt history. Local metadata only; no destination, password or private record content.
  ///
  /// In en, this message translates to:
  /// **'Save confirmed: {date}'**
  String featureBackupHistorySaved(String date);

  /// Protected backup receipt history. Local metadata only; no destination, password or private record content.
  ///
  /// In en, this message translates to:
  /// **'Archive checked: {date}'**
  String featureBackupHistoryChecked(String date);

  /// Protected backup receipt history. Local metadata only; no destination, password or private record content.
  ///
  /// In en, this message translates to:
  /// **'No save confirmation. The staged file may have been discarded.'**
  String get featureBackupHistoryUnsaved;

  /// Protected backup receipt history. Local metadata only; no destination, password or private record content.
  ///
  /// In en, this message translates to:
  /// **'{bytes} bytes · schema {schema}. Recorded doses: {records}. Substances: {items}. Files: {attachments}.'**
  String featureBackupHistoryFacts(
    int bytes,
    int schema,
    int records,
    int items,
    int attachments,
  );

  /// Protected backup receipt history. Local metadata only; no destination, password or private record content.
  ///
  /// In en, this message translates to:
  /// **'SHA-256: {hash}'**
  String featureBackupHistoryHash(String hash);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
