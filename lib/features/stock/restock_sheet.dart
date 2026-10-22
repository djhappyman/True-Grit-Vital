import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../app/app_lock.dart';
import '../../data/record_store.dart';
import '../../l10n/app_localizations.dart';
import '../../ui/stitch_ui.dart';
import '../profiles/profile_pages.dart';
import '../recording/record_pages.dart';
import 'stock_providers.dart';
import 'stock_widgets.dart';

/// Chooses the physical destination of supply before opening a durable editor.
/// The chooser makes no stock changes and never copies another pack's facts.
class RestockSheet extends ConsumerWidget {
  const RestockSheet({super.key, required this.containerId});
  final String containerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(appLockProvider).locked) return const SizedBox.shrink();
    final t = AppLocalizations.of(context);
    final owner = ref.watch(profilesProvider);
    final query = (personId: meId, containerId: containerId);
    final source = ref.watch(stockContainerProvider(query));
    if (owner.hasError || source.hasError) {
      return EntryPage(
        children: [
          LoadFailure(
            onRetry: () {
              ref.invalidate(profilesProvider);
              ref.invalidate(stockContainerProvider(query));
            },
          ),
        ],
      );
    }
    if (owner.isLoading || source.isLoading) {
      return EntryPage(children: [Text(t.loadingRecords)]);
    }
    final person = owner.value?.where((p) => p.id == meId).firstOrNull;
    final container = source.value;
    if (person == null || person.isArchived || container == null) {
      return EntryPage(children: [Text(t.draftUnavailable)]);
    }
    return EntryPage(
      panelled: false,
      children: [
        Heading(t.directRestockTitle),
        StockItemName(itemId: container.itemId),
        Text(container.label, style: StitchType.name),
        Text(t.stockStrengthValue(container.strength.label)),
        const SizedBox(height: 20),
        StitchSectionCard(
          title: t.directRestockNewPack,
          icon: LucideIcons.packagePlus,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(t.directRestockNewHelp, style: StitchType.body),
              const SizedBox(height: 12),
              StitchButton(
                outlined: true,
                onPressed: () => context.replace(
                  Uri(
                    path: '/stock/$meId/create',
                    queryParameters: {'item': container.itemId},
                  ).toString(),
                ),
                child: Text(t.create),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        StitchSectionCard(
          title: t.directRestockSameContainer,
          icon: LucideIcons.packageOpen,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                t.directRestockSameHelp(container.label),
                style: StitchType.body,
              ),
              const SizedBox(height: 12),
              StitchButton(
                outlined: true,
                onPressed: () => context.replace(
                  Uri(
                    path: '/stock/$meId/adjust/$containerId',
                    queryParameters: {'restock': 'true'},
                  ).toString(),
                ),
                child: Text(t.add),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
