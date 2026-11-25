import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../state/app_state.dart';

/// Page Clients dédiée — style Web XFY (#F0F4FF + cartes blanches bleutées).
class ClientsAccountScreen extends StatefulWidget {
  const ClientsAccountScreen({super.key, required this.state});

  final AppState state;

  @override
  State<ClientsAccountScreen> createState() => _ClientsAccountScreenState();
}

class _ClientsAccountScreenState extends State<ClientsAccountScreen> {
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = _searchCtrl.text.trim().toLowerCase();
    final clients = widget.state.clients.where((c) {
      if (q.isEmpty) return true;
      return c.nom.toLowerCase().contains(q) ||
          (c.numeroTelephone ?? '').toLowerCase().contains(q) ||
          (c.email ?? '').toLowerCase().contains(q) ||
          (c.adresse ?? '').toLowerCase().contains(q);
    }).toList();

    return Scaffold(
      backgroundColor: XfyColors.canvas,
      appBar: AppBar(
        title: Row(
          children: [
            const Text('Clients'),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: XfyColors.primarySoft,
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(
                '${clients.length}',
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: XfyColors.primaryVibrant,
                ),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Actualiser',
            onPressed: () => widget.state.refreshClients(),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            color: XfyColors.surface,
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Rechercher un client, numéro, email...',
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  size: 20,
                  color: XfyColors.primary,
                ),
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close_rounded, size: 18),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() {});
                        },
                      )
                    : null,
                fillColor: XfyColors.canvas,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: RefreshIndicator(
              color: XfyColors.primary,
              onRefresh: () => widget.state.refreshClients(),
              child: widget.state.isClientsLoading && widget.state.clients.isEmpty
                  ? const Center(
                      child: CircularProgressIndicator(color: XfyColors.primary),
                    )
                  : clients.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: const [
                            SizedBox(height: 90),
                            Icon(
                              Icons.people_outline_rounded,
                              size: 48,
                              color: XfyColors.inkMuted,
                            ),
                            SizedBox(height: 12),
                            Text(
                              'Aucun client trouvé',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: XfyColors.ink,
                              ),
                            ),
                          ],
                        )
                      : ListView.separated(
                          physics: const AlwaysScrollableScrollPhysics(
                            parent: BouncingScrollPhysics(),
                          ),
                          padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
                          itemCount: clients.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 10),
                          itemBuilder: (_, idx) {
                            final c = clients[idx];
                            final hasPhone = (c.numeroTelephone ?? '').isNotEmpty;
                            return Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: XfyColors.surface,
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(color: XfyColors.border),
                                boxShadow: XfyColors.cardShadow,
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 44,
                                    height: 44,
                                    decoration: BoxDecoration(
                                      gradient: XfyColors.brandGradient,
                                      borderRadius: BorderRadius.circular(13),
                                    ),
                                    alignment: Alignment.center,
                                    child: Text(
                                      c.initials,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          c.nom,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w700,
                                            color: XfyColors.ink,
                                          ),
                                        ),
                                        if (hasPhone)
                                          Text(
                                            c.numeroTelephone!,
                                            style: const TextStyle(
                                              fontSize: 13,
                                              color: XfyColors.inkSecondary,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        if ((c.adresse ?? '').isNotEmpty)
                                          Text(
                                            c.adresse!,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: XfyColors.inkMuted,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  if (hasPhone) ...[
                                    IconButton(
                                      tooltip: 'Appeler',
                                      color: XfyColors.primary,
                                      onPressed: () {
                                        HapticFeedback.lightImpact();
                                        XfyFormatters.launchPhoneCall(
                                          c.numeroTelephone,
                                        );
                                      },
                                      icon: const Icon(Icons.call_outlined, size: 20),
                                    ),
                                    IconButton(
                                      tooltip: 'WhatsApp',
                                      color: const Color(0xFF16A34A),
                                      onPressed: () {
                                        HapticFeedback.lightImpact();
                                        XfyFormatters.launchWhatsApp(
                                          c.numeroTelephone,
                                        );
                                      },
                                      icon: const Icon(Icons.chat_outlined, size: 20),
                                    ),
                                  ],
                                ],
                              ),
                            );
                          },
                        ),
            ),
          ),
        ],
      ),
    );
  }
}
