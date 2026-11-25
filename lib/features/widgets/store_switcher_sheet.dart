import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import '../../core/theme/app_theme.dart';
import '../../state/app_state.dart';

class StoreSwitcherSheet extends StatelessWidget {
  const StoreSwitcherSheet({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: XfyColors.border,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Changer de boutique',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: XfyColors.ink,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${state.stores.length} boutique(s) disponible(s)',
              style: const TextStyle(fontSize: 13, color: XfyColors.inkSecondary),
            ),
            const SizedBox(height: 16),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: state.stores.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final store = state.stores[index];
                  final isSelected = state.selectedStore?.id == store.id;
                  return InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () {
                      HapticFeedback.selectionClick();
                      Navigator.pop(context);
                      state.selectStore(store);
                    },
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: isSelected ? XfyColors.primarySoft : XfyColors.canvas,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isSelected ? XfyColors.primary : XfyColors.border,
                          width: isSelected ? 1.5 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: XfyColors.border),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: store.resolvedLogoUrl != null
                                ? Image.network(
                                    store.resolvedLogoUrl!,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, _, _) => const Icon(
                                      Icons.storefront_rounded,
                                      color: XfyColors.primary,
                                    ),
                                  )
                                : const Icon(
                                    Icons.storefront_rounded,
                                    color: XfyColors.primary,
                                  ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  store.name,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: XfyColors.ink,
                                  ),
                                ),
                                if (store.publicUrl != null)
                                  Text(
                                    store.publicUrl!.replaceFirst('https://', ''),
                                    style: const TextStyle(
                                      fontSize: 12.5,
                                      color: XfyColors.inkSecondary,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          if (isSelected)
                            const Icon(
                              Icons.check_circle_rounded,
                              color: XfyColors.primary,
                              size: 22,
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
