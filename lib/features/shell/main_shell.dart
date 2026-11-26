import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import '../../core/l10n/app_l10n.dart';
import '../../core/theme/app_theme.dart';
import '../../data/services/order_notification_service.dart';
import '../../state/app_state.dart';
import '../chatbot/xfy_chatbot_sheet.dart';
import '../dashboard/dashboard_screen.dart';
import '../orders/orders_screen.dart';
import '../products/products_screen.dart';
import '../scanner/scan_qr_screen.dart';
import '../settings/settings_screen.dart';

/// Navigation principale à 5 onglets ultra-fluide :
/// • Chargement paresseux (lazy) des onglets non encore visités
/// • Isolation `RepaintBoundary` + rebuild ciblé UNIQUEMENT de l'onglet visible
/// • Logo XFY centré qui ouvre Statistiques / Analytics (index 2)
/// • Bandeau de notification temps réel animé lorsqu'une nouvelle commande arrive
class MainShell extends StatefulWidget {
  const MainShell({super.key, required this.state});

  final AppState state;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  final Set<int> _visitedTabs = {2};

  Widget _buildTab(int index, bool isActive) {
    if (!_visitedTabs.contains(index)) {
      return const SizedBox.shrink();
    }
    return RepaintBoundary(
      child: _ActiveTabGate(
        isActive: isActive,
        child: switch (index) {
          0 => OrdersScreen(state: widget.state),
          1 => ProductsScreen(state: widget.state),
          2 => DashboardScreen(state: widget.state),
          3 => ScanQrScreen(state: widget.state, isActive: isActive),
          _ => SettingsScreen(state: widget.state),
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.state,
      builder: (context, _) {
        final state = widget.state;
        final pendingCount = state.pendingOrdersCount;
        final activeIndex = state.currentTabIndex;
        final incoming = state.latestIncomingOrder;
        _visitedTabs.add(activeIndex);

        return Scaffold(
          extendBody: false,
          body: Stack(
            children: [
              IndexedStack(
                index: activeIndex,
                children: [
                  _buildTab(0, activeIndex == 0),
                  _buildTab(1, activeIndex == 1),
                  _buildTab(2, activeIndex == 2),
                  _buildTab(3, activeIndex == 3),
                  _buildTab(4, activeIndex == 4),
                ],
              ),

              // Bandeau animé "Nouvelle commande • PRIX"
              if (incoming != null)
                Positioned(
                  top: MediaQuery.of(context).padding.top + 8,
                  left: 14,
                  right: 14,
                  child: Material(
                    color: Colors.transparent,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        gradient: XfyColors.statsGradient,
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: [
                          BoxShadow(
                            color: XfyColors.primaryVibrant
                                .withValues(alpha: 0.30),
                            blurRadius: 12,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.22),
                              borderRadius: BorderRadius.circular(11),
                            ),
                            child: const Icon(
                              Icons.notifications_active_rounded,
                              color: Colors.white,
                              size: 21,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  OrderNotificationService
                                      .formatOrderAlertTitle(
                                    incoming.effectiveTotal,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                Text(
                                  '${incoming.nom}${incoming.produit != null ? ' • ${incoming.produit}' : ''}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.9),
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          TextButton(
                            style: TextButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: XfyColors.primaryVibrant,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              minimumSize: Size.zero,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            onPressed: () {
                              state.dismissIncomingBanner();
                              state.setTab(0);
                            },
                            child: Text(
                              AppL10n.t('view'),
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              // Bulle flottante Assistant IA — Design 100 % identique au Web (`.chatbot-toggle`)
              AnimatedPositionedDirectional(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                end: 16,
                bottom: (activeIndex == 1 || activeIndex == 3) ? 84 : 18,
                child: _WebChatbotToggleBubble(
                  onTap: () {
                    HapticFeedback.mediumImpact();
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.white,
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(20),
                        ),
                      ),
                      builder: (_) => XfyChatbotSheet(state: state),
                    );
                  },
                ),
              ),
            ],
          ),
          bottomNavigationBar: _XfyCenterLogoBottomBar(
            activeIndex: activeIndex,
            pendingOrdersCount: pendingCount,
            onSelect: (index) {
              HapticFeedback.selectionClick();
              state.setTab(index);
            },
          ),
        );
      },
    );
  }
}

/// Empêche les onglets masqués de l'`IndexedStack` de se reconstruire lorsque l'utilisateur
/// interagit avec un autre onglet (évite de recalculer Dashboard/Charts en arrière-plan).
class _ActiveTabGate extends StatefulWidget {
  const _ActiveTabGate({
    required this.isActive,
    required this.child,
  });

  final bool isActive;
  final Widget child;

  @override
  State<_ActiveTabGate> createState() => _ActiveTabGateState();
}

class _ActiveTabGateState extends State<_ActiveTabGate> {
  late Widget _cachedChild;

  @override
  void initState() {
    super.initState();
    _cachedChild = widget.child;
  }

  @override
  void didUpdateWidget(covariant _ActiveTabGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive) {
      _cachedChild = widget.child;
    }
  }

  @override
  Widget build(BuildContext context) => _cachedChild;
}

class _XfyCenterLogoBottomBar extends StatelessWidget {
  const _XfyCenterLogoBottomBar({
    required this.activeIndex,
    required this.pendingOrdersCount,
    required this.onSelect,
  });

  final int activeIndex;
  final int pendingOrdersCount;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final isCenterSelected = activeIndex == 2;

    return Container(
      height: 70 + bottomInset,
      decoration: BoxDecoration(
        color: XfyColors.surface,
        border: const Border(
          top: BorderSide(color: XfyColors.border, width: 1),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6366F1).withValues(alpha: 0.07),
            blurRadius: 12,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Row(
            children: [
              Expanded(
                child: _NavItem(
                  icon: Icons.shopping_bag_outlined,
                  activeIcon: Icons.shopping_bag_rounded,
                  label: AppL10n.t('nav_orders'),
                  selected: activeIndex == 0,
                  badgeCount: pendingOrdersCount,
                  onTap: () => onSelect(0),
                ),
              ),
              Expanded(
                child: _NavItem(
                  icon: Icons.inventory_2_outlined,
                  activeIcon: Icons.inventory_2_rounded,
                  label: AppL10n.t('nav_products'),
                  selected: activeIndex == 1,
                  onTap: () => onSelect(1),
                ),
              ),
              const SizedBox(width: 78),
              Expanded(
                child: _NavItem(
                  icon: Icons.qr_code_scanner_outlined,
                  activeIcon: Icons.qr_code_scanner_rounded,
                  label: AppL10n.t('nav_scanner'),
                  selected: activeIndex == 3,
                  onTap: () => onSelect(3),
                ),
              ),
              Expanded(
                child: _NavItem(
                  icon: Icons.settings_outlined,
                  activeIcon: Icons.settings_rounded,
                  label: AppL10n.t('nav_settings'),
                  selected: activeIndex == 4,
                  onTap: () => onSelect(4),
                ),
              ),
            ],
          ),

          // Bouton Central Surélevé — Logo XFY -> Statistiques / Analytics
          Positioned(
            top: -18,
            child: GestureDetector(
              onTap: () {
                HapticFeedback.mediumImpact();
                onSelect(2);
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: 60,
                    height: 60,
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: isCenterSelected
                          ? XfyColors.statsGradient
                          : const LinearGradient(
                              colors: [Color(0xFFC7D2FE), Color(0xFFE0E7FF)],
                            ),
                      boxShadow: [
                        BoxShadow(
                          color: XfyColors.primaryVibrant
                              .withValues(alpha: isCenterSelected ? 0.28 : 0.12),
                          blurRadius: isCenterSelected ? 10 : 6,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Container(
                      decoration: const BoxDecoration(
                        color: Color(0xFF02020A),
                        shape: BoxShape.circle,
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Image.asset(
                        'assets/images/logoXFY.png',
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const Icon(
                          Icons.bar_chart_rounded,
                          color: Colors.white,
                          size: 26,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    AppL10n.t('nav_stats'),
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight:
                          isCenterSelected ? FontWeight.w800 : FontWeight.w600,
                      color: isCenterSelected
                          ? XfyColors.primaryVibrant
                          : XfyColors.inkSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.badgeCount = 0,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int badgeCount;

  @override
  Widget build(BuildContext context) {
    final color = selected ? XfyColors.primaryVibrant : XfyColors.inkSecondary;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: selected ? XfyColors.primarySoft : Colors.transparent,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Icon(
                    selected ? activeIcon : icon,
                    size: 22,
                    color: color,
                  ),
                ),
                if (badgeCount > 0)
                  Positioned(
                    right: 2,
                    top: -4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1.5,
                      ),
                      decoration: BoxDecoration(
                        color: XfyColors.accent,
                        borderRadius: BorderRadius.circular(99),
                        border: Border.all(color: Colors.white, width: 1.5),
                      ),
                      child: Text(
                        badgeCount > 99 ? '99+' : '$badgeCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bulle flottante Chatbot 100 % identique à `.chatbot-toggle` du Web XFY :
/// • Cercle bleu dégradé `#4A90E2 → #357ABD` (60×60)
/// • Halo pulsant bleu (`rgba(74, 144, 226, 0.4)`, cycle 2,5 s)
/// • Flottement vertical doux (`0 → -6 px`, cycle 3 s)
/// • Icône bulle de message blanche à 3 lignes identique au SVG Web
class _WebChatbotToggleBubble extends StatefulWidget {
  const _WebChatbotToggleBubble({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_WebChatbotToggleBubble> createState() =>
      _WebChatbotToggleBubbleState();
}

class _WebChatbotToggleBubbleState extends State<_WebChatbotToggleBubble>
    with TickerProviderStateMixin {
  late final AnimationController _floatCtrl;
  late final AnimationController _pulseCtrl;
  late final Animation<double> _floatY;
  late final Animation<double> _pulseScale;
  late final Animation<double> _pulseOpacity;

  @override
  void initState() {
    super.initState();
    _floatCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _floatY = Tween<double>(begin: 0, end: -6).animate(
      CurvedAnimation(parent: _floatCtrl, curve: Curves.easeInOut),
    );

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1250),
    )..repeat(reverse: true);
    _pulseScale = Tween<double>(begin: 1.0, end: 1.36).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
    _pulseOpacity = Tween<double>(begin: 0.45, end: 0.14).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _floatCtrl.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: Listenable.merge([_floatCtrl, _pulseCtrl]),
        builder: (context, child) {
          return Transform.translate(
            offset: Offset(0, _floatY.value),
            child: SizedBox(
              width: 68,
              height: 68,
              child: Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  Transform.scale(
                    scale: _pulseScale.value,
                    child: Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFF4A90E2)
                            .withValues(alpha: _pulseOpacity.value),
                      ),
                    ),
                  ),
                  child!,
                ],
              ),
            ),
          );
        },
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: widget.onTap,
            child: Ink(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [Color(0xFF4A90E2), Color(0xFF357ABD)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF4A90E2).withValues(alpha: 0.36),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Center(
                child: CustomPaint(
                  size: const Size(27, 27),
                  painter: _WebChatBubbleIconPainter(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WebChatBubbleIconPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / 24.0;
    final sy = size.height / 24.0;

    final path = Path()..fillType = PathFillType.evenOdd;

    // Bulle principale avec coins arrondis et pointe en bas à gauche (SVG Web exact)
    path.moveTo(4 * sx, 2 * sy);
    path.lineTo(20 * sx, 2 * sy);
    path.quadraticBezierTo(22 * sx, 2 * sy, 22 * sx, 4 * sy);
    path.lineTo(22 * sx, 16 * sy);
    path.quadraticBezierTo(22 * sx, 18 * sy, 20 * sx, 18 * sy);
    path.lineTo(6 * sx, 18 * sy);
    path.lineTo(2 * sx, 22 * sy);
    path.lineTo(2 * sx, 4 * sy);
    path.quadraticBezierTo(2 * sx, 2 * sy, 4 * sx, 2 * sy);
    path.close();

    // 3 lignes de texte découpées à l'intérieur (identiques au SVG Web)
    path.addRect(Rect.fromLTWH(6 * sx, 6.2 * sy, 12 * sx, 1.8 * sy));
    path.addRect(Rect.fromLTWH(6 * sx, 9.6 * sy, 12 * sx, 1.8 * sy));
    path.addRect(Rect.fromLTWH(6 * sx, 13.0 * sy, 8 * sx, 1.8 * sy));

    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
