part of 'plan_form.dart';

extension _SimplePlanEditor on _DailyPlanFormState {
  CivilDate? _civilOrNull(String value) {
    try {
      return CivilDate.parse(value);
    } catch (_) {
      return null;
    }
  }

  String _displayAmount(ExactAmount value, String from) {
    final converted = convertScheduleAmount(
      value,
      from,
      doseUnit ?? item!.unit,
      doseStrength,
    );
    if (converted == null) throw const FormatException('schedule_conversion');
    return exactScheduleEntry(converted);
  }

  List<String> get _units => {
    doseUnit ?? item!.unit,
    item!.unit,
    for (final unit in ['mg', 'ml', 'count', 'mcg'])
      if (convertScheduleAmount(
            ExactAmount(BigInt.one),
            item!.unit,
            unit,
            doseStrength,
          ) !=
          null)
        unit,
  }.toList();

  void _unitChanged(String next) {
    final previous = doseUnit ?? item!.unit;
    final replacements = <TextEditingController, String>{};
    try {
      for (final controller in [
        amount,
        ...slots.map((s) => s.amount),
        totalAmount,
      ]) {
        if (controller.text.trim().isEmpty) continue;
        final value = convertScheduleAmount(
          ExactAmount.parseEntry(stockDecimal(controller.text)),
          previous,
          next,
          doseStrength,
        );
        if (value == null) throw const FormatException('schedule_conversion');
        replacements[controller] = exactScheduleEntry(value);
      }
      _edit(() {
        doseUnit = next;
        for (final entry in replacements.entries) {
          entry.key.text = entry.value;
        }
        error = null;
      });
    } catch (_) {
      _edit(() => error = AppLocalizations.of(context).simpleSchedulePrecision);
    }
  }

  CivilDate? _durationEnd() {
    if (durationMode == 'range') {
      return CivilDate.parse(end.text.trim()).addDays(1);
    }
    if (durationMode != 'length') return null;
    final length = int.parse(durationCount.text.trim());
    if (length < 1 || length > 36500) throw const FormatException('duration');
    return CivilDate.parse(start.text.trim())
        .addDays(length * (durationUnit == 'weeks' ? 7 : 1));
  }

  PlanStopCondition? _stopCondition() {
    if (durationMode != 'total' && durationMode != 'container') return null;
    final zone = basis == 'home'
        ? home.text.trim()
        : ref.read(observedDeviceZoneProvider).value?.zoneId;
    if (zone == null) throw const FormatException('zone');
    final candidates = DailyResolver().clock.candidates(
      CivilDate.parse(start.text.trim()),
      WallTime(0, 0),
      zone,
    );
    if (candidates.length != 1) throw const FormatException('date_boundary');
    final total = durationMode == 'total'
        ? parseAmount(totalAmount.text)
        : null;
    return PlanStopCondition(
      from: candidates.single,
      zone: zone,
      total: total == null ? null : ExactAmount.parseEntry(total.enteredText),
      unit: total?.unit,
      strength: doseStrength,
      containerId: durationMode == 'container' ? endContainer ?? '' : null,
    );
  }

  String get _repeatKey {
    if (mode == 'interval') return 'hours';
    if (mode == 'count' && calendar.pattern == 'daily') return 'untimed';
    if (mode != 'slots') return 'custom';
    if (calendar.pattern == 'daily' &&
        durationMode == 'range' &&
        start.text == end.text) {
      return 'once';
    }
    return switch (calendar.pattern) {
      'daily' => 'daily',
      'weekdays' => 'weekdays',
      'days' => 'days',
      'weeks' => 'weeks',
      'months' => 'months',
      'years' => 'years',
      _ => 'custom',
    };
  }

  void _repeatChanged(String value) {
    _edit(() {
      if (value == 'custom') return;
      if (value == 'once') {
        mode = 'slots';
        calendar.pattern = 'daily';
        durationMode = 'range';
        end.text = start.text;
      } else if (value == 'hours') {
        mode = 'interval';
        if (interval.duration.text.isEmpty) interval.duration.text = '8';
        if (interval.anchor.text.isEmpty) _setIntervalAnchor();
      } else if (value == 'untimed') {
        mode = 'count';
        calendar.pattern = 'daily';
        if (count.text.isEmpty) count.text = '1';
      } else {
        mode = 'slots';
        calendar.anchor.text = start.text;
        calendar.choosePattern(value);
        if (value == 'weekdays' && calendar.weekdays.isEmpty) {
          calendar.weekdays.add(
            CivilDate.parse(start.text).calendarValue.weekday,
          );
        }
      }
    });
    if (value == 'custom') _showPatterns();
  }

  void _setIntervalAnchor() {
    final zone = basis == 'home'
        ? home.text.trim()
        : ref.read(observedDeviceZoneProvider).value?.zoneId;
    if (zone == null) return;
    final date = CivilDate.parse(start.text);
    final time = parseTime(
      slots.first.time.text.isEmpty ? '08:00' : slots.first.time.text,
    );
    final candidates = DailyResolver().clock.candidates(date, time, zone);
    interval.anchor.text = candidates.length == 1
        ? candidates.single.toIso8601String()
        : '';
  }

  bool get _canEdit =>
      mounted &&
      !busy &&
      !uncertain &&
      !conflict &&
      !ref.read(appLockProvider).locked &&
      (capturedGeneration == null ||
          ref.read(recordStoreProvider).value?.generation ==
              capturedGeneration);

  Future<void> _pickDate(TextEditingController controller, String label) async {
    final current =
        _civilOrNull(controller.text) ?? CivilDate.parse(start.text);
    final selected = await showVitalDatePicker(
      context: context,
      initialDate: current.calendarValue,
      firstDate: DateTime(1),
      lastDate: DateTime(9999, 12, 31),
      title: label,
    );
    if (selected != null && _canEdit) {
      _edit(() {
        controller.text = CivilDate.fromDateTime(selected).toString();
        if (identical(controller, start) && original == null) {
          calendar.anchor.text = start.text;
          calendar.choosePattern(calendar.pattern);
          if (mode == 'interval' &&
              interval.mode == IntervalMode.fixedPlanned) {
            _setIntervalAnchor();
          }
        }
      });
    }
  }

  Future<void> _pickTime(PlanSlotEntry slot) async {
    final t = AppLocalizations.of(context);
    final initial = parseTime(
      slot.time.text.isEmpty ? '08:00' : slot.time.text,
    );
    final selected = await showVitalTimePicker(
      context: context,
      initialTime: material.TimeOfDay(
        hour: initial.hour,
        minute: initial.minute,
      ),
      title: t.planTime,
    );
    if (selected != null && _canEdit) {
      _edit(() {
        slot.time.text = wallLabel(WallTime(selected.hour, selected.minute));
        if (mode == 'interval' && interval.mode == IntervalMode.fixedPlanned) {
          _setIntervalAnchor();
        }
      });
    }
  }

  Future<void> _showPatterns() async {
    final t = AppLocalizations.of(context);
    await showVitalDialog<void>(
      context: context,
      builder: (dialogContext) => VitalDialog(
        title: Text(t.simpleSchedulePatterns),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final option in [
              ('slots', t.planTimes),
              ('count', t.simpleScheduleUntimed),
              ('mixed', t.phaseMixed),
              ('windows', t.phaseWindows),
              ('prn', t.dashboardUnplanned),
            ])
              VitalNavigationRow(
                label: option.$2,
                quiet: true,
                onPressed: () {
                  if (_canEdit) _edit(() => mode = option.$1);
                  Navigator.of(dialogContext).pop();
                },
              ),
          ],
        ),
        actions: [
          VitalButton.secondary(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(t.cancel),
          ),
        ],
      ),
    );
  }

  Widget _selectRow<T>({
    required String label,
    required T value,
    required List<T> values,
    required String Function(T) labelOf,
    required ValueChanged<T> onChanged,
    required bool enabled,
  }) => LayoutBuilder(
    builder: (context, constraints) {
      final select = VitalSelect<T>(
        label: label,
        value: value,
        values: values,
        labelOf: labelOf,
        onChanged: onChanged,
        enabled: enabled,
      );
      return constraints.maxWidth < 300 ||
              MediaQuery.textScalerOf(context).scale(14) > 20
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(label, style: VitalType.label),
                const SizedBox(height: 8),
                select,
              ],
            )
          : Row(
              children: [
                Expanded(
                  flex: 2,
                  child: Text(
                    label,
                    style: VitalType.body,
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(flex: 3, child: select),
              ],
            );
    },
  );

  Widget _card({String? title, required List<Widget> children}) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: StitchSurface(
      radius: VitalLayout.sectionRadius,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null) ...[
            ScheduleSectionHeader(title: title),
            const SizedBox(height: 4),
          ],
          ...children,
        ],
      ),
    ),
  );

  Widget _amountField(
    TextEditingController controller,
    bool enabled, {
    bool selector = false,
  }) {
    final t = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Semantics(
                label: t.amountLabel,
                child: TextField(
                  controller: controller,
                  enabled: enabled,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  placeholder: Text(t.amountLabel),
                ),
              ),
            ),
            const SizedBox(width: 8),
            if (selector)
              VitalSelect<String>(
                label: t.simpleScheduleUnit,
                value: doseUnit ?? item!.unit,
                values: _units,
                labelOf: (unit) => unit,
                onChanged: _unitChanged,
                enabled: enabled,
              )
            else
              Text(doseUnit ?? item!.unit, style: VitalType.control),
          ],
        ),
        if (doseStrength case final strength?)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: DefaultTextStyle.merge(
              style: VitalType.metadata.copyWith(
                color: VitalColors(context).muted,
              ),
              child: StrengthEquivalent(
                strength: strength,
                amount: controller.text,
                unit: doseUnit ?? item!.unit,
                showPreparation: false,
              ),
            ),
          ),
      ],
    );
  }

  List<Widget> _simpleEditor({
    required bool enabled,
    required bool paused,
    required bool valid,
  }) {
    final t = AppLocalizations.of(context);
    final containers = ref.watch(
      stockContainersProvider((
        personId: owner!.id,
        itemId: item!.id,
        offset: 0,
      )),
    );
    final durationLabels = {
      'ongoing': t.simpleScheduleOngoing,
      'length': t.simpleScheduleLength,
      'range': t.simpleScheduleRange,
      'total': t.simpleScheduleTotal,
      'container': t.simpleScheduleEmpty,
    };
    final repeatLabels = {
      'once': t.repeatOnce,
      'daily': t.simpleScheduleDaily,
      'weekdays': t.simpleScheduleWeekdays,
      'days': t.simpleScheduleDays,
      'hours': t.simpleScheduleHours,
      'untimed': t.simpleScheduleUntimed,
      'weeks': t.repeatWeeks,
      'months': t.repeatMonths,
      'years': t.repeatYears,
      'custom': t.simpleSchedulePatterns,
    };
    if (reviewing && preview != null) {
      return _reviewWidgets(
        enabled,
        repeatLabels[_repeatKey]!,
        durationLabels[durationMode]!,
      );
    }
    return [
      Text(item!.name, style: VitalType.section),
      const SizedBox(height: 20),
      if (!valid) Text(t.profileChanged),
      _card(
        title: t.amountLabel,
        children: [_amountField(amount, enabled, selector: true)],
      ),
      _card(
        title: t.schedule,
        children: [
          if (durationMode == 'range')
            VitalDateRangeField(
              textOnly: true,
              start: start,
              end: end,
              startLabel: t.simpleScheduleStarts,
              endLabel: t.simpleScheduleUntil,
              enabled: enabled,
            )
          else
            _dateRow(t.simpleScheduleStarts, start, enabled),
          const SizedBox(height: 16),

          _selectRow(
            label: t.simpleScheduleRepeat,
            value: _repeatKey,
            values: repeatLabels.keys.toList(),
            labelOf: (String key) => repeatLabels[key]!,
            onChanged: _repeatChanged,
            enabled: enabled,
          ),
          if (const [
            'weekdays',
            'days',
            'weeks',
            'months',
            'years',
          ].contains(_repeatKey))
            CalendarRepeatDetails(
              fields: calendar,
              enabled: enabled,
              onChanged: changed,
            ),
          if (_repeatKey == 'hours')
            LabelledInput(
              label: t.simpleScheduleEveryHours,
              controller: interval.duration,
              enabled: enabled,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
            ),
          if (mode == 'count' || mode == 'mixed')
            LabelledInput(
              label: t.simpleScheduleDailyCount,
              controller: count,
              enabled: enabled,
              keyboardType: TextInputType.number,
            ),
          const SizedBox(height: 16),
          if (mode == 'slots' ||
              mode == 'interval' &&
                  interval.mode == IntervalMode.fixedPlanned) ...[
            ScheduleSectionHeader(title: t.simpleScheduleTimes),

            VitalAnimatedRows(
              rows: [
                for (final slot in (mode == 'interval' ? slots.take(1) : slots))
                  VitalAnimatedRow(
                    id: slot.id,
                    child: _timeRow(slot, enabled),
                    exitChild: _timeRow(slot, false, snapshot: true),
                  ),
              ],
            ),
            if (mode == 'slots')
              Align(
                alignment: Alignment.center,
                child: VitalControlStyle(
                  quiet: true,
                  child: Button(
                    style: ButtonVariance.ghost,
                    onPressed: !enabled
                        ? null
                        : () => _edit(
                            () => addSlot(time: '08:00', amount: amount.text),
                          ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(LucideIcons.plus, size: 18),
                        const SizedBox(width: 8),
                        Text(t.add),
                      ],
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 16),
          ],

          const SizedBox(height: 16),

          _selectRow(
            label: t.simpleScheduleDuration,
            value: durationMode,
            values: durationLabels.keys.toList(),
            labelOf: (String key) => durationLabels[key]!,
            onChanged: (String key) => _edit(() => durationMode = key),
            enabled: enabled,
          ),
          const SizedBox(height: 8),
          if (durationMode == 'length') ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Semantics(
                    label: t.simpleScheduleDuration,
                    child: TextField(
                      controller: durationCount,
                      enabled: enabled,
                      keyboardType: TextInputType.number,
                      placeholder: Text(t.simpleScheduleDuration),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                VitalSelect<String>(
                  label: t.simpleScheduleDuration,
                  value: durationUnit,
                  values: const ['days', 'weeks'],
                  labelOf: (unit) => unit == 'days'
                      ? t.simpleScheduleDayUnit
                      : t.simpleScheduleWeekUnit,
                  onChanged: (unit) => _edit(() => durationUnit = unit),
                  enabled: enabled,
                ),
              ],
            ),
          ],
          if (durationMode == 'total') ...[
            const SizedBox(height: 8),
            _amountField(totalAmount, enabled),
            const SizedBox(height: 8),
            Text(t.simpleScheduleTotalHelp, style: VitalType.metadata),
          ],
          if (durationMode == 'container') ...[
            const SizedBox(height: 8),
            if (containers.isLoading)
              Text(t.loadingRecords)
            else if (containers.hasError)
              LoadFailure(
                onRetry: () => ref.invalidate(
                  stockContainersProvider((
                    personId: owner!.id,
                    itemId: item!.id,
                    offset: 0,
                  )),
                ),
              )
            else if (containers.requireValue.isEmpty)
              Text(t.simpleScheduleNoContainer, style: VitalType.metadata)
            else
              VitalSelect<String>(
                label: t.simpleScheduleContainer,
                value: endContainer ?? '',
                values: [
                  '',
                  ...containers.requireValue.take(50).map((c) => c.id),
                ],
                labelOf: (id) => id.isEmpty
                    ? t.simpleScheduleContainer
                    : containers.requireValue
                              .where((c) => c.id == id)
                              .firstOrNull
                              ?.label ??
                          t.noItem,
                onChanged: (id) =>
                    _edit(() => endContainer = id.isEmpty ? null : id),
                enabled: enabled,
              ),
            const SizedBox(height: 8),
            Text(t.simpleScheduleEmptyHelp, style: VitalType.metadata),
          ],
          const SizedBox(height: 16),
          _selectRow(
            label: t.simpleScheduleWhen,
            value: _whenValue,
            values: [
              'anytime',
              'bedtime',
              ...FoodRequirement.values.map((v) => v.name),
              if (requirementBedtime && requirementFood != null) _whenValue,
            ],
            labelOf: (String key) => _whenLabel(t, key),
            onChanged: (String key) => _edit(() {
              requirementBedtime =
                  key == 'bedtime' || key.startsWith('bedtime:');
              final food = key.startsWith('bedtime:') ? key.substring(8) : key;
              requirementFood = FoodRequirement.values
                  .where((v) => v.name == food)
                  .firstOrNull;
            }),
            enabled: enabled,
          ),
        ],
      ),
      Semantics(
        label: t.featurePlanInstructionsLabel,
        child: TextField(
          controller: instructions,
          enabled: enabled,
          minLines: 3,
          maxLines: 5,
          borderRadius: BorderRadius.circular(VitalLayout.multilineRadius),
          placeholder: Text(t.featurePlanInstructionsLabel),
        ),
      ),
      const SizedBox(height: 6),
      Text(
        t.simpleScheduleInstructionExample,
        style: VitalType.metadata.copyWith(color: VitalColors(context).muted),
      ),
      if (instructionsTooLong)
        Semantics(
          liveRegion: true,
          child: Text(
            t.featurePlanInstructionsTooLong(
              DailyPlanVersion.maxInstructionsLength,
            ),
          ),
        ),
      const SizedBox(height: 16),
      _card(
        title: t.finishR05Timing,
        children: [
          PlanTimingEditor(
            fields: timingFields,
            enabled: enabled,
            onChanged: changed,
            collapsible: false,
          ),
        ],
      ),
      const SizedBox(height: 12),
      VitalDisclosure(
        title: t.simpleScheduleMore,
        initiallyExpanded: _repeatKey == 'custom',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (mode == 'slots')
              SettingsToggleRow(
                label: t.simpleScheduleDifferentAmounts,
                description: t.simpleScheduleDifferentHelp,
                value: differentAmounts,
                enabled: enabled,
                reduceMotion: VitalMotion.reduced(context),
                onChanged: (value) => _edit(() {
                  differentAmounts = value;
                  if (value) {
                    for (final slot in slots) {
                      if (slot.amount.text.isEmpty) {
                        slot.amount.text = amount.text;
                      }
                    }
                  }
                }),
              ),
            if (_repeatKey == 'custom') ...[
              VitalButton.secondary(
                onPressed: !enabled ? null : _showPatterns,
                child: Text(t.edit),
              ),
              CalendarEditor(
                fields: calendar,
                enabled: enabled,
                onChanged: changed,
              ),
              if (mode == 'mixed' || mode == 'windows')
                for (final slot in slots) ...[
                  LabelledInput(
                    picker: VitalPickerKind.time,
                    label: t.planTime,
                    controller: slot.time,
                    enabled: enabled,
                  ),
                  if (mode == 'windows') ...[
                    LabelledInput(
                      picker: VitalPickerKind.time,
                      label: t.phaseWindowEnd,
                      controller: slot.end,
                      enabled: enabled,
                    ),
                    LabelledInput(
                      picker: VitalPickerKind.time,
                      label: t.phaseWindowAnchor,
                      controller: slot.anchor,
                      enabled: enabled,
                    ),
                  ],
                  _amountField(slot.amount, enabled),
                ],
            ],
            if (mode == 'interval')
              IntervalEditor(
                fields: interval,
                enabled: enabled,
                onChanged: changed,
              ),
            if (mode != 'prn')
              OnOffEditor(fields: blocks, enabled: enabled, onChanged: changed),
            if (valid && original != null) ...[
              PlanReminderControl(saved: original!),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  VitalButton.secondary(
                    onPressed: !enabled
                        ? null
                        : () => context.push(
                            '/pause/${item!.id}?plan=${original!.plan.planId}',
                          ),
                    child: Text(paused ? t.resume : t.pauseAction),
                  ),
                  VitalButton.secondary(
                    onPressed: !enabled
                        ? null
                        : () => context.push(
                            '/phases/${item!.id}?plan=${original!.plan.planId}',
                          ),
                    child: Text(t.phaseHeading),
                  ),
                ],
              ),
            ] else
              Text(
                t.screenScheduleRemindersAfterSave,
                style: VitalType.metadata,
              ),
          ],
        ),
      ),
      const SizedBox(height: 20),
      ?failure(),
      VitalButton(
        expand: true,
        onPressed: enabled
            ? _review
            : uncertain
            ? save
            : null,
        child: Text(uncertain ? t.retry : t.review),
      ),
    ];
  }

  String get _whenValue => requirementBedtime
      ? requirementFood == null
            ? 'bedtime'
            : 'bedtime:${requirementFood!.name}'
      : requirementFood?.name ?? 'anytime';

  String _whenLabel(AppLocalizations t, String key) {
    final food = key.startsWith('bedtime:') ? key.substring(8) : key;
    final label = switch (food) {
      'beforeFood' => t.finishR01FoodBefore,
      'withFood' => t.finishR01FoodWith,
      'afterFood' => t.finishR01FoodAfter,
      'emptyStomach' => t.finishR01FoodEmptyStomach,
      'bedtime' => t.finishR01AtBedtime,
      _ => t.simpleScheduleAnytime,
    };
    return key.startsWith('bedtime:')
        ? t.simpleScheduleWhenCombined(t.finishR01AtBedtime, label)
        : label;
  }

  Widget _timeRow(PlanSlotEntry slot, bool enabled, {bool snapshot = false}) {
    final t = AppLocalizations.of(context);
    final label = displayWallTime(
      context,
      ref,
      parseTime(slot.time.text.isEmpty ? '08:00' : slot.time.text),
    );
    final amountText = slot.amount.text;
    final removable = mode == 'slots' && slots.length > 1;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: VitalButton.secondary(
                  onPressed: !enabled ? null : () => _pickTime(slot),
                  leading: const Icon(LucideIcons.clock3),
                  child: Text(label),
                ),
              ),
              if (removable) ...[
                const SizedBox(width: 8),
                VitalIconButton(
                  label: t.remove,
                  icon: LucideIcons.x,
                  onPressed: !enabled
                      ? null
                      : () => _edit(() {
                          slots.remove(slot);
                          slot.dispose();
                        }),
                ),
              ],
            ],
          ),
          if (differentAmounts) ...[
            const SizedBox(height: 8),
            if (snapshot)
              Text(
                '$amountText ${doseUnit ?? item!.unit}',
                style: VitalType.body,
              )
            else
              _amountField(slot.amount, enabled),
          ],
        ],
      ),
    );
  }

  Widget _dateRow(
    String label,
    TextEditingController controller,
    bool enabled,
  ) {
    final date = _civilOrNull(controller.text);
    return Row(
      children: [
        Expanded(
          flex: 2,
          child: Text(
            label,
            style: VitalType.body,
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 3,
          child: VitalControlStyle(
            quiet: true,
            child: Button(
              style: ButtonVariance.ghost,
              onPressed: !enabled ? null : () => _pickDate(controller, label),
              child: DefaultTextStyle.merge(
                style: VitalType.body,
                child: Text(
                  date == null
                      ? AppLocalizations.of(context).simpleScheduleChoose
                      : DateFormat.yMMMd(
                          Localizations.localeOf(context).toString(),
                        ).format(date.calendarValue),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _reviewWidgets(bool enabled, String repeat, String duration) {
    final t = AppLocalizations.of(context), plan = preview!;
    final zone = previewZone!;
    final resolver = DailyResolver();
    final now = DateTime.now().toUtc();
    final current = resolver.currentDate(plan, now: now, observedZone: zone);
    final from = current.compareTo(plan.start) < 0 ? plan.start : current;
    final rows = plan.timing is ElapsedInterval
        ? null
        : resolver.expand(
            plan,
            from: from,
            toExclusive: from.addDays(7),
            observedZone: zone,
            maxRows: 1000,
            maxDates: 7,
          );
    return [
      Text(item!.name, style: VitalType.section),
      const SizedBox(height: 16),
      _card(
        title: t.review,
        children: [
          Text(
            '${amount.text} ${doseUnit ?? item!.unit}',
            style: VitalType.metric,
          ),
          const SizedBox(height: 12),
          Text(repeat, style: VitalType.body),
          Text(duration, style: VitalType.body),
          if (plan.endExclusive != null)
            Text(
              t.planEnds(plan.endExclusive!.addDays(-1).toString()),
              style: VitalType.metadata,
            ),
          if (plan.stopCondition?.total != null)
            Text(
              t.simpleScheduleTotalReview(
                totalAmount.text,
                doseUnit ?? item!.unit,
              ),
              style: VitalType.metadata,
            ),
          if (plan.stopCondition?.containerId != null)
            Text(t.simpleScheduleEmptyHelp, style: VitalType.metadata),
          if (doseStrength case final strength?)
            StrengthEquivalent(
              strength: strength,
              amount: amount.text,
              unit: doseUnit ?? item!.unit,
              showPreparation: false,
            ),
          if (plan.requirements?.isNotEmpty == true)
            PlanRequirementBadges(requirements: plan.requirements),
          if (plan.onOff case final block?)
            Text(
              t.pauseBlockSummary(
                block.onDays,
                block.offDays,
                block.anchor.toString(),
              ),
            ),
        ],
      ),
      if (plan.timing is ElapsedInterval)
        IntervalPlanPreview(plan: plan, observedZone: zone)
      else if (rows != null) ...[
        ScheduleSectionHeader(title: t.simpleScheduleNext),
        for (final row in rows.rows.take(5))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              t.simpleScheduleNextDose(
                row.identity.originalDate.toString(),
                row.originalTime == null
                    ? t.simpleScheduleUntimed
                    : displayWallTime(context, ref, row.originalTime!),
                _displayAmount(
                  ExactAmount.parseEntry(row.amount.enteredText),
                  row.amount.unit,
                ),
                doseUnit ?? item!.unit,
              ),
            ),
          ),
        if (!rows.complete ||
            rows.rows.any(
              (r) =>
                  r.resolution == DailyResolution.missingClock ||
                  r.resolution == DailyResolution.repeatedClock,
            ))
          Text(t.planIncomplete),
        if (rows.rows.isEmpty) Text(t.planNoNext),
      ],
      if (plan.instructions.isNotEmpty)
        Text(plan.instructions, style: VitalType.body),
      const SizedBox(height: 20),
      ?failure(),
      VitalButton(
        expand: true,
        onPressed: enabled || uncertain ? save : null,
        child: Text(
          busy
              ? t.saving
              : uncertain
              ? t.retry
              : t.save,
        ),
      ),
      const SizedBox(height: 8),
      VitalButton.secondary(
        onPressed: !enabled ? null : () => _setReview(false),
        child: Text(t.edit),
      ),
    ];
  }
}
