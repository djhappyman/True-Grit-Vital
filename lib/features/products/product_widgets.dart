import '../substances/substance_profile_editor.dart';
import '../../ui/vital_ui.dart';

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../app/settings_toggle_row.dart';
import '../../app/storage.dart';
import '../../data/record_store.dart';
import '../../l10n/app_localizations.dart';
import '../recording/record_pages.dart';
import '../stock/stock_providers.dart';
import '../stock/stock_widgets.dart';

final productLabelProvider = StreamProvider.autoDispose
    .family<ProductLabelSnapshot?, ({String personId, String itemId})>(
      retry: (_, _) => null,
      (ref, q) async* {
        yield* (await ref.watch(recordStoreProvider.future))
            .watchProductLabel(personId: q.personId, itemId: q.itemId);
      },
    );

/// Ephemeral controls. Only their closed JSON snapshot is persisted in the
/// encrypted ordinary draft; no widget/controller is shared between adults.
class ProductComponentEntry {
  ProductComponentEntry({
    String? id,
    String name = '',
    String concentration = '',
    String massUnit = 'mg',
    String volumeUnit = 'ml',
    this.known = false,
  }) : id = id ?? newCommandId(),
       name = TextEditingController(text: name),
       concentration = TextEditingController(text: concentration),
       massUnit = TextEditingController(text: massUnit),
       volumeUnit = TextEditingController(text: volumeUnit);
  final String id;
  final TextEditingController name, concentration, massUnit, volumeUnit;
  final halfLife = HalfLifeEditorData(() {});
  bool known;
  Iterable<TextEditingController> get controls => [
    name,
    concentration,
    massUnit,
    volumeUnit,
    ...halfLife.controls,
  ];
  Map<String, Object?> toJson() => {
    'id': id,
    'name': name.text,
    'concentration': concentration.text,
    'massUnit': massUnit.text,
    'volumeUnit': volumeUnit.text,
    'known': known,
    'halfLife': halfLife.capture(),
  };
  void dispose() {
    for (final c in controls) {
      c.dispose();
    }
  }
}

class ProductEditorData {
  ProductEditorData(this.changed);
  final VoidCallback changed;
  final entries = <ProductComponentEntry>[];
  void add([ProductComponentEntry? entry]) {
    final row = entry ?? ProductComponentEntry();
    for (final c in row.controls) {
      c.addListener(changed);
    }
    entries.add(row);
  }

  void initialise([List<ProductComponent>? components]) {
    if (entries.isNotEmpty) return;
    if (components != null) {
      for (final c in components) {
        final entry = ProductComponentEntry(
          id: c.ingredientId,
          name: c.name,
          concentration: c.concentrationText ?? '',
          massUnit: c.massUnit,
          volumeUnit: c.volumeUnit,
          known: c.concentrationText != null,
        );
        if (c.halfLife != null) entry.halfLife.restore(c.halfLife!.toJson());
        add(entry);
      }
    } else {
      add();
      add();
    }
  }

  String encode() => jsonEncode([for (final row in entries) row.toJson()]);
  void restore(String text) {
    for (final row in entries) {
      row.dispose();
    }
    entries.clear();
    final rows = jsonDecode(text) as List<dynamic>;
    if (rows.length > 32) throw const FormatException('product_components');
    for (final value in rows) {
      final row = value as Map<String, dynamic>;
      final entry = ProductComponentEntry(
        id: row['id'] as String,
        name: row['name'] as String,
        concentration: row['concentration'] as String,
        massUnit: row['massUnit'] as String,
        volumeUnit: row['volumeUnit'] as String,
        known: row['known'] == true,
      );
      if (row['halfLife'] != null) {
        entry.halfLife.restore(
          Map<String, dynamic>.from(row['halfLife'] as Map),
        );
      }
      add(entry);
    }
  }

  List<ProductComponent> components() {
    if (entries.length < 2 || entries.length > 32) {
      throw const FormatException('product_components');
    }
    return [
      for (final row in entries)
        ProductComponent(
          ingredientId: row.id,
          name: row.name.text.trim(),
          concentrationText: row.known
              ? stockDecimal(row.concentration.text)
              : null,
          massUnit: row.massUnit.text.trim(),
          volumeUnit: row.volumeUnit.text.trim(),
          halfLife: row.halfLife.read(),
        ),
    ];
  }

  void dispose() {
    for (final row in entries) {
      row.dispose();
    }
  }
}

class ProductComponentEditor extends StatelessWidget {
  const ProductComponentEditor({
    super.key,
    required this.data,
    required this.onChanged,
    this.enabled = true,
    this.error,
  });
  final ProductEditorData data;
  final VoidCallback onChanged;
  final bool enabled;
  final String? error;
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Heading(t.productIngredients),
        if (error != null) Semantics(liveRegion: true, child: Text(error!)),
        for (var index = 0; index < data.entries.length; index++)
          Padding(
            key: ValueKey(data.entries[index].id),
            padding: const EdgeInsets.only(bottom: 24),
            child: _ProductComponentFields(
              entry: data.entries[index],
              number: index + 1,
              enabled: enabled,
              onChanged: () {
                data.changed();
                onChanged();
              },
              onRemove: data.entries.length <= 2
                  ? null
                  : () {
                      final removed = data.entries.removeAt(index);
                      removed.dispose();
                      data.changed();
                      onChanged();
                    },
            ),
          ),
        if (data.entries.length < 32)
          VitalButton.secondary(
            onPressed: !enabled
                ? null
                : () {
                    data.add();
                    data.changed();
                    onChanged();
                  },
            child: Text(t.productAdd),
          ),
        const SizedBox(height: 20),
      ],
    );
  }
}

class _ProductComponentFields extends StatelessWidget {
  const _ProductComponentFields({
    required this.entry,
    required this.number,
    required this.enabled,
    required this.onChanged,
    required this.onRemove,
  });
  final ProductComponentEntry entry;
  final int number;
  final bool enabled;
  final VoidCallback onChanged;
  final VoidCallback? onRemove;
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Heading(t.productIngredientNumber(number)),
        LabelledInput(
          label: t.productIngredientName,
          semanticLabel: t.productFieldContext(number, t.productIngredientName),
          controller: entry.name,
          enabled: enabled,
        ),
        SettingsToggleRow(
          label: t.productKnownStrength,
          description: t.productKnownStrengthHelp,
          value: entry.known,
          enabled: enabled,
          reduceMotion: MediaQuery.disableAnimationsOf(context),
          onChanged: (value) {
            entry.known = value;
            onChanged();
          },
        ),
        if (entry.known)
          LabelledInput(
            label: t.productConcentration,
            semanticLabel: t.productFieldContext(
              number,
              t.productConcentration,
            ),
            controller: entry.concentration,
            helper: t.stockDecimalHelp,
            enabled: enabled,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
        LabelledInput(
          label: t.productMassUnit,
          semanticLabel: t.productFieldContext(number, t.productMassUnit),
          controller: entry.massUnit,
          enabled: enabled,
        ),
        LabelledInput(
          label: t.productVolumeUnit,
          semanticLabel: t.productFieldContext(number, t.productVolumeUnit),
          controller: entry.volumeUnit,
          enabled: enabled,
        ),
        Text(t.productUnitsHelp),
        HalfLifeEditor(
          data: entry.halfLife,
          enabled: enabled,
          onChanged: onChanged,
        ),
        if (onRemove != null)
          Semantics(
            label: t.productRemoveContext(number),
            child: VitalButton.secondary(
              onPressed: enabled ? onRemove : null,
              child: Text(t.productRemove),
            ),
          ),
      ],
    );
  }
}

class ProductLabelView extends StatelessWidget {
  const ProductLabelView({super.key, required this.label, this.volume});
  final ProductLabelSnapshot label;
  final ExactAmount? volume;
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < label.components.length; index++)
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(t.productIngredientNumber(index + 1)),
                Text(
                  label.components[index].name,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  label.components[index].concentrationText == null
                      ? t.productUnknownStrength(
                          label.components[index].massUnit,
                          label.components[index].volumeUnit,
                        )
                      : t.productStrengthValue(
                          label.components[index].concentrationText!,
                          label.components[index].massUnit,
                          label.components[index].volumeUnit,
                        ),
                ),
                if (label.components[index].halfLife case final h?) ...[
                  Text(
                    t.substanceHalfLifeSummary(
                      h.value,
                      h.unit == 'days' ? t.substanceDays : t.substanceHours,
                    ),
                  ),
                  if (h.context.isNotEmpty) Text(h.context),
                  if (h.source.isNotEmpty)
                    Text(t.substanceSourceValue(h.source)),
                ],
                if (volume != null)
                  Text(
                    label.components[index].mgPerMl == null
                        ? t.productUnknownAmount
                        : t.productAmountValue(
                            stockAmountText(
                              t,
                              volume! * label.components[index].mgPerMl!,
                              'mg',
                            ),
                          ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class ProductRecordDetails extends StatelessWidget {
  const ProductRecordDetails({super.key, required this.record});
  final UseRecord record;
  @override
  Widget build(BuildContext context) {
    final product = record.product;
    if (product == null) return const SizedBox.shrink();
    final t = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Heading(t.productIngredients),
        Text(t.productSnapshotHelp),
        Text(t.productVolumeValue(stockAmountText(t, product.volume, 'ml'))),
        if (jsonEncode(product.defaultLabel.toJson()) !=
            jsonEncode(product.label.toJson())) ...[
          Heading(t.productOldLabel),
          ProductLabelView(label: product.defaultLabel, volume: product.volume),
          Heading(t.productNewLabel),
        ],
        ProductLabelView(label: product.label, volume: product.volume),
      ],
    );
  }
}
