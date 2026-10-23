import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../app/settings_toggle_row.dart';
import '../../domain/scheduling/plan_timing_policy.dart';
import '../../l10n/app_localizations.dart';
import '../../ui/vital_ui.dart';
import '../recording/record_pages.dart' show LabelledInput;

class PlanTimingFields {
  final allowance = TextEditingController(), delay = TextEditingController();
  bool labels = false, followUp = false;
  List<TextEditingController> get controllers => [allowance, delay];
  Map<String, String> capture() => {
    'timingLabels': labels.toString(),
    'timingAllowance': allowance.text,
    'timingFollowUp': followUp.toString(),
    'timingDelay': delay.text,
  };
  void restore(Map<String, String> fields) {
    labels = fields['timingLabels'] == 'true';
    followUp = fields['timingFollowUp'] == 'true';
    allowance.text = fields['timingAllowance'] ?? '';
    delay.text = fields['timingDelay'] ?? '';
  }

  void load(PlanTimingPolicy? value) {
    labels = value?.allowanceMinutes != null;
    followUp = value?.followUpMinutes != null;
    allowance.text = value?.allowanceMinutes?.toString() ?? '';
    delay.text = value?.followUpMinutes?.toString() ?? '';
  }

  PlanTimingPolicy? candidate() => !labels && !followUp
      ? null
      : PlanTimingPolicy(
          allowanceMinutes: labels ? _minutes(allowance.text) : null,
          followUpMinutes: followUp ? _minutes(delay.text) : null,
        );
  int _minutes(String value) {
    final text = value.trim();
    if (!RegExp(r'^\d{1,5}$').hasMatch(text)) {
      throw const FormatException('timing_minutes');
    }
    return int.parse(text);
  }

  bool get valid {
    try {
      candidate();
      return true;
    } on FormatException {
      return false;
    }
  }

  void dispose() {
    for (final c in controllers) {
      c.dispose();
    }
  }
}

class PlanTimingEditor extends StatelessWidget {
  const PlanTimingEditor({
    super.key,
    required this.fields,
    required this.enabled,
    required this.onChanged,
    this.collapsible = true,
  });
  final PlanTimingFields fields;
  final bool enabled;
  final VoidCallback onChanged;
  final bool collapsible;
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          t.finishR05TimingHelp,
          style: VitalType.metadata.copyWith(color: VitalColors(context).muted),
        ),
        SettingsToggleRow(
          reduceMotion: MediaQuery.disableAnimationsOf(context),
          label: t.finishR05Labels,
          description: t.finishR05LabelsHelp,
          value: fields.labels,
          enabled: enabled,
          onChanged: (value) {
            fields.labels = value;
            onChanged();
          },
        ),
        if (fields.labels)
          LabelledInput(
            label: t.finishR05Allowance,
            controller: fields.allowance,
            helper: t.finishR05AllowanceHelp,
            enabled: enabled,
            keyboardType: TextInputType.number,
          ),
        SettingsToggleRow(
          reduceMotion: MediaQuery.disableAnimationsOf(context),
          label: t.finishR05FollowUp,
          description: t.finishR05FollowUpHelp,
          value: fields.followUp,
          enabled: enabled,
          onChanged: (value) {
            fields.followUp = value;
            onChanged();
          },
        ),
        if (fields.followUp)
          LabelledInput(
            label: t.finishR05Delay,
            controller: fields.delay,
            helper: t.finishR05DelayHelp,
            enabled: enabled,
            keyboardType: TextInputType.number,
          ),
        if (!fields.valid) Text(t.finishR05Invalid),
      ],
    );
    return collapsible
        ? VitalDisclosure(title: t.finishR05Timing, child: content)
        : content;
  }
}

String timingLabelText(AppLocalizations t, DoseTimingLabel label) =>
    switch (label) {
      DoseTimingLabel.earlier => t.finishR05Earlier,
      DoseTimingLabel.withinWindow => t.finishR05Within,
      DoseTimingLabel.later => t.finishR05Later,
    };

class PlanTimingSummary extends StatelessWidget {
  const PlanTimingSummary({super.key, required this.policy});
  final PlanTimingPolicy? policy;
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (policy?.allowanceMinutes case final int minutes)
          Text(t.finishR05WindowSummary(minutes), style: VitalType.body),
        if (policy?.followUpMinutes case final int minutes)
          Text(t.finishR05FollowUpSummary(minutes), style: VitalType.body),
      ],
    );
  }
}
