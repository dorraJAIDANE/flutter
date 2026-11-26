import 'dart:io';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';
import '../../core/l10n/app_l10n.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../data/services/order_notification_service.dart';
import '../../state/app_state.dart';

class XfyBotChoice {
  const XfyBotChoice({
    required this.label,
    required this.action,
    required this.icon,
  });

  final String label;
  final String action;
  final IconData icon;
}

class XfyBotMessage {
  XfyBotMessage({
    required this.isBot,
    this.lines = const [],
    this.localImagePath,
    this.choices,
    this.messengerUrl,
    this.copyableText,
  });

  final bool isBot;
  final List<String> lines;
  final String? localImagePath;
  List<XfyBotChoice>? choices;
  final String? messengerUrl;
  final String? copyableText;
}

/// État persistant du Bot IA XFY (comme `ChatbotService` singleton sur le Web).
class XfyChatbotSession {
  XfyChatbotSession._();
  static final XfyChatbotSession instance = XfyChatbotSession._();

  final List<XfyBotMessage> messages = [];
  String chatState = 'awaiting_choice';
  final List<XFile> selectedImages = [];
  bool initialized = false;

  static const List<XfyBotChoice> mainChoices = [
    XfyBotChoice(
      label: 'Commande',
      action: 'orders',
      icon: Icons.shopping_bag_outlined,
    ),
    XfyBotChoice(
      label: 'Retour',
      action: 'returns',
      icon: Icons.assignment_return_outlined,
    ),
    XfyBotChoice(
      label: 'Autre Question',
      action: 'communication',
      icon: Icons.help_outline_rounded,
    ),
    XfyBotChoice(
      label: 'Support',
      action: 'support',
      icon: Icons.support_agent_rounded,
    ),
  ];

  void ensureInitialized() {
    if (initialized) return;
    initialized = true;
    messages.add(
      XfyBotMessage(
        isBot: true,
        lines: const [
          '👋 Bienvenue sur votre Assistant IA XFY !',
          'Envoyez-moi vos captures d\'écran de commandes, vos retours ou posez-moi vos questions.',
        ],
      ),
    );
    pushModePrompt();
  }

  void pushModePrompt() {
    chatState = 'awaiting_choice';
    messages.add(
      XfyBotMessage(
        isBot: true,
        lines: const ['Comment puis-je vous aider ?'],
        choices: List<XfyBotChoice>.from(mainChoices),
      ),
    );
  }

  void reset() {
    messages.clear();
    selectedImages.clear();
    chatState = 'awaiting_choice';
    initialized = false;
    ensureInitialized();
  }
}

/// Assistant IA Mobile XFY — 100 % aligné avec `ChatbotComponent` Web :
/// • Extraction IA de commandes depuis captures d'écran (`handling_orders`)
/// • Traitement des retours (`handling_returns`)
/// • Questions libres (`communication`)
/// • Support direct Messenger avec infos boutique pré-remplies (`support`)
class XfyChatbotSheet extends StatefulWidget {
  const XfyChatbotSheet({super.key, required this.state});

  final AppState state;

  @override
  State<XfyChatbotSheet> createState() => _XfyChatbotSheetState();
}

class _XfyChatbotSheetState extends State<XfyChatbotSheet> {
  static const int _maxImages = 50;
  static const String _messengerPageId = '998009233405901';

  final _session = XfyChatbotSession.instance;
  final _picker = ImagePicker();
  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _session.ensureInitialized();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtrl.hasClients) return;
      _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent + 120,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  String _buildSupportMessage(String? userText) {
    final store = widget.state.selectedStore;
    final user = widget.state.user;
    final lines = <String>[
      '🚨 [SUPPORT XFY - Demande d\'assistance]',
      '🏪 Boutique : ${store?.name ?? 'Boutique XFY'}',
    ];
    final url = store?.publicUrl;
    if (url != null && url.isNotEmpty) {
      lines.add('🌐 URL Boutique : $url');
    }
    if (user != null) {
      final parts = <String>[
        if (user.displayName.isNotEmpty) user.displayName,
        if (user.email.isNotEmpty) '<${user.email}>',
        if (user.phoneNumber != null && user.phoneNumber!.trim().isNotEmpty)
          '(Tél: ${user.phoneNumber!.trim()})',
      ];
      if (parts.isNotEmpty) {
        lines.add('👤 Utilisateur : ${parts.join(' ')}');
      }
    }
    final cleanMsg = (userText != null && userText.trim().isNotEmpty)
        ? userText.trim()
        : 'Bonjour, j\'ai besoin d\'assistance pour ma boutique.';
    lines.add('💬 Message : $cleanMsg');
    return lines.join('\n');
  }

  void _onChoiceSelected(XfyBotChoice choice) {
    HapticFeedback.selectionClick();
    setState(() {
      _session.messages.add(XfyBotMessage(isBot: false, lines: [choice.label]));
      for (final m in _session.messages) {
        if (m.isBot && m.choices != null) {
          m.choices = null;
        }
      }

      if (choice.action == 'orders') {
        _session.chatState = 'handling_orders';
        _session.messages.add(
          XfyBotMessage(
            isBot: true,
            lines: const [
              'Parfait ! Envoyez-moi vos captures d\'écran (Galerie ou Caméra) et je créerai/analyserai les commandes automatiquement.',
            ],
          ),
        );
      } else if (choice.action == 'returns') {
        _session.chatState = 'handling_returns';
        _session.messages.add(
          XfyBotMessage(
            isBot: true,
            lines: const [
              'Pour les retours, envoyez-moi les photos ou captures de vos bordereaux.',
            ],
          ),
        );
      } else if (choice.action == 'communication') {
        _session.chatState = 'communication';
        _session.messages.add(
          XfyBotMessage(
            isBot: true,
            lines: const ['Je vous écoute ! Posez-moi votre question.'],
          ),
        );
      } else if (choice.action == 'support') {
        _session.chatState = 'support';
        _session.selectedImages.clear();
        final autoMsg = _buildSupportMessage(null);
        final messengerUrl =
            'https://m.me/$_messengerPageId?text=${Uri.encodeComponent(autoMsg)}';
        Clipboard.setData(ClipboardData(text: autoMsg));
        _session.messages.add(
          XfyBotMessage(
            isBot: true,
            lines: [
              '💬 Support Direct sur Messenger',
              'Les informations de votre boutique sont déjà copiées dans votre presse-papiers.',
              autoMsg,
              'Écrivez votre question ci-dessous ou démarrez directement sur Messenger :',
            ],
            messengerUrl: messengerUrl,
            copyableText: autoMsg,
          ),
        );
      }
    });
    _scrollToBottom();
  }

  Future<void> _pickImages({required bool fromCamera}) async {
    if (_session.chatState == 'support') {
      setState(() {
        _session.messages.add(
          XfyBotMessage(
            isBot: true,
            lines: const [
              'L\'envoi d\'images n\'est pas disponible en mode Support. Écrivez votre message ou utilisez Messenger.',
            ],
          ),
        );
      });
      _scrollToBottom();
      return;
    }

    if (_session.chatState == 'awaiting_choice') {
      // Par défaut, si le vendeur choisit une image directement, basculer sur Commande
      _session.chatState = 'handling_orders';
    }

    try {
      if (fromCamera) {
        final photo = await _picker.pickImage(
          source: ImageSource.camera,
          imageQuality: 85,
        );
        if (photo != null && mounted) {
          setState(() => _session.selectedImages.add(photo));
        }
      } else {
        final photos = await _picker.pickMultiImage(imageQuality: 85);
        if (photos.isNotEmpty && mounted) {
          setState(() => _session.selectedImages.addAll(photos));
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: XfyColors.rose,
          content: Text('Impossible de sélectionner l\'image : $e'),
        ),
      );
    }
  }

  Future<void> _onSubmit() async {
    if (_isLoading) return;
    final text = _inputCtrl.text.trim();
    final images = List<XFile>.from(_session.selectedImages);

    if (text.isEmpty && images.isEmpty) return;

    // Mode Support Messenger
    if (_session.chatState == 'support') {
      if (text.isEmpty) return;
      final fullMsg = _buildSupportMessage(text);
      final messengerUrl =
          'https://m.me/$_messengerPageId?text=${Uri.encodeComponent(fullMsg)}';
      await Clipboard.setData(ClipboardData(text: fullMsg));
      setState(() {
        _session.messages.add(XfyBotMessage(isBot: false, lines: [text]));
        _inputCtrl.clear();
        _session.messages.add(
          XfyBotMessage(
            isBot: true,
            lines: [
              '✅ Message préparé et copié dans le presse-papiers !',
              fullMsg,
            ],
            messengerUrl: messengerUrl,
            copyableText: fullMsg,
          ),
        );
      });
      _scrollToBottom();
      XfyFormatters.launchExternalWeb(messengerUrl);
      // Sauvegarde backend en arrière-plan
      final storeId = widget.state.selectedStore?.id ?? 0;
      widget.state.api
          .chatbotExtractInfo(
            imagePaths: const [],
            storeId: storeId,
            action: 'support',
            message: fullMsg,
          )
          .catchError((_) => null);
      return;
    }

    final storeId = widget.state.selectedStore?.id;
    if (storeId == null || storeId <= 0) {
      setState(() {
        _session.messages.add(
          XfyBotMessage(
            isBot: true,
            lines: const [
              '❌ Impossible d\'identifier votre boutique active. Sélectionnez une boutique puis réessayez.',
            ],
          ),
        );
      });
      _scrollToBottom();
      return;
    }

    if (images.length > _maxImages) {
      setState(() {
        _session.messages.add(
          XfyBotMessage(
            isBot: true,
            lines: [
              '❌ Vous avez sélectionné ${images.length} images. La limite est de $_maxImages images par envoi.',
            ],
          ),
        );
      });
      _scrollToBottom();
      return;
    }

    HapticFeedback.lightImpact();
    setState(() {
      for (final img in images) {
        _session.messages.add(
          XfyBotMessage(isBot: false, localImagePath: img.path),
        );
      }
      if (text.isNotEmpty) {
        _session.messages.add(XfyBotMessage(isBot: false, lines: [text]));
      }
      _inputCtrl.clear();
      _session.selectedImages.clear();
      _isLoading = true;
    });
    _scrollToBottom();

    try {
      final response = await widget.state.api.chatbotExtractInfo(
        imagePaths: images.map((e) => e.path).toList(),
        storeId: storeId,
        action: _session.chatState == 'awaiting_choice'
            ? 'handling_orders'
            : _session.chatState,
        message: text,
      );

      final botLines = _formatBotResponse(response, _session.chatState);
      if (!mounted) return;
      setState(() {
        _session.messages.add(XfyBotMessage(isBot: true, lines: botLines));
        _isLoading = false;
      });
      OrderNotificationService.instance.playRingtone();
      _scrollToBottom();

      // Recharger les commandes immédiatement après extraction commandes / retours
      if (_session.chatState == 'handling_orders' ||
          _session.chatState == 'handling_returns') {
        widget.state.refreshOrders(silent: true);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _session.messages.add(
          XfyBotMessage(
            isBot: true,
            lines: ['❌ Erreur serveur : $e'],
          ),
        );
        _isLoading = false;
      });
      _scrollToBottom();
    }
  }

  List<String> _formatBotResponse(dynamic response, String mode) {
    if (response is Map && response['chatLines'] is List) {
      final lines = (response['chatLines'] as List)
          .map((e) => e.toString())
          .where((s) => s.trim().isNotEmpty)
          .toList();
      if (lines.isNotEmpty) return lines;
    }

    if (response is List) {
      final lines = <String>['✨ Analyse des commandes terminée !'];
      int errorCount = 0;

      for (int i = 0; i < response.length; i++) {
        final item = response[i];
        if (item is! Map) continue;
        final err = item['erreur']?.toString();
        if (err != null && err.trim().isNotEmpty) {
          errorCount++;
          lines.add('⚠️ Image ${i + 1} : $err');
          continue;
        }
        final nom =
            (item['Nom'] ?? item['nom'] ?? 'Non spécifié').toString().trim();
        final addr = (item['Adresse'] ?? item['adresse'] ?? 'Non spécifié')
            .toString()
            .trim();
        final phone = (item['Numéro de téléphone'] ??
                item['phone_number'] ??
                'Non spécifié')
            .toString()
            .trim();
        final rawProds =
            (item['Produits'] ?? item['produit'] ?? '').toString().trim();
        final dateLiv = (item['Date de livraison'] ??
                item['date_livraison'] ??
                'Non spécifiée')
            .toString()
            .trim();

        String prodFormatted = 'Non spécifié';
        if (rawProds.isNotEmpty && rawProds.toLowerCase() != 'non spécifié') {
          prodFormatted = rawProds.split(';').map((p) {
            final parts = p.split(',');
            final pName =
                parts.isNotEmpty && parts[0].trim().isNotEmpty
                    ? parts[0].trim()
                    : 'Produit';
            final qty = parts.length > 1
                ? (int.tryParse(parts[1].trim()) ?? 1)
                : 1;
            return '$pName (x$qty)';
          }).join(', ');
        }

        lines.add('— Commande ${i + 1} —');
        lines.add('👤 Client : $nom');
        lines.add('📍 Adresse : $addr');
        lines.add('📞 Téléphone : $phone');
        lines.add('🛍️ Produits : $prodFormatted');
        lines.add('🗓️ Livraison : $dateLiv');
      }

      lines.add(
        '📊 Résumé : ${response.length - errorCount} commande(s) valide(s), $errorCount erreur(s).',
      );
      lines.add(
        '💡 Retrouvez ces commandes dans l\'onglet Commandes pour compléter les champs manquants et expédier.',
      );
      return lines;
    }

    if (response is String && response.trim().isNotEmpty) {
      return [response.trim()];
    }
    return const ['✅ Traitement terminé.'];
  }

  String _modeBadgeLabel() {
    switch (_session.chatState) {
      case 'handling_orders':
        return 'Mode : Commandes (Captures)';
      case 'handling_returns':
        return 'Mode : Retours';
      case 'communication':
        return 'Mode : Question IA';
      case 'support':
        return 'Mode : Support Messenger';
      default:
        return 'En ligne • Prêt à aider';
    }
  }

  @override
  Widget build(BuildContext context) {
    final canInput = _session.chatState != 'awaiting_choice';

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.90,
      minChildSize: 0.60,
      maxChildSize: 0.96,
      builder: (context, _) {
        return SafeArea(
          child: Column(
            children: [
              // Header Bot IA
              Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                decoration: const BoxDecoration(
                  gradient: XfyColors.statsGradient,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.smart_toy_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            AppL10n.t('bot_title'),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Row(
                            children: [
                              Container(
                                width: 7,
                                height: 7,
                                decoration: const BoxDecoration(
                                  color: Color(0xFF4ADE80),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  _modeBadgeLabel(),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.9),
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Changer de mode',
                      onPressed: () {
                        HapticFeedback.selectionClick();
                        setState(() => _session.pushModePrompt());
                        _scrollToBottom();
                      },
                      icon: const Icon(
                        Icons.apps_rounded,
                        color: Colors.white,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Nouvelle discussion',
                      onPressed: () {
                        HapticFeedback.selectionClick();
                        setState(() => _session.reset());
                        _scrollToBottom();
                      },
                      icon: const Icon(
                        Icons.refresh_rounded,
                        color: Colors.white,
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),

              // Liste des messages
              Expanded(
                child: Container(
                  color: XfyColors.canvas,
                  child: ListView.builder(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                    itemCount: _session.messages.length + (_isLoading ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (_isLoading && index == _session.messages.length) {
                        return _buildLoadingBubble();
                      }
                      return _buildMessageBubble(_session.messages[index]);
                    },
                  ),
                ),
              ),

              // Zone de saisie & pièces jointes
              Container(
                decoration: const BoxDecoration(
                  color: XfyColors.surface,
                  border: Border(top: BorderSide(color: XfyColors.border)),
                ),
                padding: EdgeInsets.fromLTRB(
                  12,
                  10,
                  12,
                  MediaQuery.of(context).viewInsets.bottom + 10,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_session.selectedImages.isNotEmpty) ...[
                      SizedBox(
                        height: 68,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: _session.selectedImages.length,
                          separatorBuilder: (_, _) => const SizedBox(width: 8),
                          itemBuilder: (_, idx) {
                            final file = _session.selectedImages[idx];
                            return Stack(
                              children: [
                                Container(
                                  width: 64,
                                  height: 64,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(10),
                                    border:
                                        Border.all(color: XfyColors.border),
                                  ),
                                  clipBehavior: Clip.antiAlias,
                                  child: Image.file(
                                    File(file.path),
                                    fit: BoxFit.cover,
                                    cacheWidth: 160,
                                    cacheHeight: 160,
                                  ),
                                ),
                                Positioned(
                                  top: 2,
                                  right: 2,
                                  child: GestureDetector(
                                    onTap: () => setState(() =>
                                        _session.selectedImages.removeAt(idx)),
                                    child: Container(
                                      width: 20,
                                      height: 20,
                                      decoration: const BoxDecoration(
                                        color: Colors.black87,
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.close_rounded,
                                        size: 13,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    if (canInput)
                      Row(
                        children: [
                          if (_session.chatState != 'support') ...[
                            IconButton(
                              tooltip: 'Galerie (captures)',
                              onPressed: _isLoading
                                  ? null
                                  : () => _pickImages(fromCamera: false),
                              icon: const Icon(
                                Icons.photo_library_outlined,
                                color: XfyColors.primaryVibrant,
                              ),
                            ),
                            IconButton(
                              tooltip: 'Caméra',
                              onPressed: _isLoading
                                  ? null
                                  : () => _pickImages(fromCamera: true),
                              icon: const Icon(
                                Icons.photo_camera_outlined,
                                color: XfyColors.primaryVibrant,
                              ),
                            ),
                          ],
                          Expanded(
                            child: TextField(
                              controller: _inputCtrl,
                              minLines: 1,
                              maxLines: 3,
                              textInputAction: TextInputAction.send,
                              onSubmitted: (_) => _onSubmit(),
                              decoration: InputDecoration(
                                hintText: _session.chatState == 'support'
                                    ? 'Écrivez votre message au support...'
                                    : 'Écrivez ou joignez des captures...',
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 10,
                                ),
                                fillColor: XfyColors.canvas,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton.filled(
                            style: IconButton.styleFrom(
                              backgroundColor: XfyColors.primaryVibrant,
                              foregroundColor: Colors.white,
                              fixedSize: const Size(44, 44),
                            ),
                            onPressed: _isLoading ? null : _onSubmit,
                            icon: const Icon(Icons.send_rounded, size: 20),
                          ),
                        ],
                      )
                    else
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        alignment: WrapAlignment.center,
                        children: XfyChatbotSession.mainChoices.map((c) {
                          return ActionChip(
                            avatar: Icon(
                              c.icon,
                              size: 16,
                              color: XfyColors.primaryVibrant,
                            ),
                            label: Text(
                              c.label,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 12.5,
                              ),
                            ),
                            backgroundColor: XfyColors.primarySoft,
                            side: BorderSide.none,
                            onPressed: () => _onChoiceSelected(c),
                          );
                        }).toList(),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMessageBubble(XfyBotMessage msg) {
    final isBot = msg.isBot;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment:
            isBot ? MainAxisAlignment.start : MainAxisAlignment.end,
        children: [
          if (isBot) ...[
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                gradient: XfyColors.statsGradient,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.smart_toy_rounded,
                size: 17,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isBot ? XfyColors.surface : XfyColors.primaryVibrant,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(isBot ? 4 : 16),
                  topRight: Radius.circular(isBot ? 16 : 4),
                  bottomLeft: const Radius.circular(16),
                  bottomRight: const Radius.circular(16),
                ),
                border: isBot ? Border.all(color: XfyColors.border) : null,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (msg.localImagePath != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.file(
                        File(msg.localImagePath!),
                        width: 190,
                        height: 190,
                        fit: BoxFit.cover,
                        cacheWidth: 320,
                      ),
                    ),
                  if (msg.lines.isNotEmpty)
                    ...msg.lines.map(
                      (line) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          line,
                          style: TextStyle(
                            fontSize: 13.5,
                            height: 1.38,
                            color: isBot ? XfyColors.ink : Colors.white,
                            fontWeight:
                                line.startsWith('✨') || line.startsWith('—')
                                    ? FontWeight.w800
                                    : FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  if (msg.choices != null && msg.choices!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: msg.choices!.map((c) {
                        return FilledButton.tonalIcon(
                          style: FilledButton.styleFrom(
                            backgroundColor: XfyColors.primarySoft,
                            foregroundColor: XfyColors.primaryDark,
                            minimumSize: const Size(0, 38),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                          ),
                          onPressed: () => _onChoiceSelected(c),
                          icon: Icon(c.icon, size: 16),
                          label: Text(
                            c.label,
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                  if (msg.messengerUrl != null) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF0084FF),
                            foregroundColor: Colors.white,
                            minimumSize: const Size(0, 38),
                          ),
                          onPressed: () => XfyFormatters.launchExternalWeb(
                            msg.messengerUrl!,
                          ),
                          icon: const Icon(Icons.message_rounded, size: 16),
                          label: const Text('Ouvrir Messenger'),
                        ),
                        if (msg.copyableText != null)
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size(0, 38),
                            ),
                            onPressed: () {
                              Clipboard.setData(
                                ClipboardData(text: msg.copyableText!),
                              );
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Message copié')),
                              );
                            },
                            icon: const Icon(Icons.copy_rounded, size: 15),
                            label: const Text('Copier'),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingBubble() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              gradient: XfyColors.statsGradient,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.smart_toy_rounded,
              size: 17,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: XfyColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: XfyColors.border),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 15,
                  height: 15,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: XfyColors.primaryVibrant,
                  ),
                ),
                SizedBox(width: 10),
                Text(
                  '🧠 Analyse IA en cours...',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: XfyColors.ink,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
