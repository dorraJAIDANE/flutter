import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import '../../core/l10n/app_l10n.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/store_settings_model.dart';
import '../../data/services/order_notification_service.dart';
import '../../state/app_state.dart';
import '../widgets/store_switcher_sheet.dart';

/// Page Paramètres — Design calqué sur `parametres-overview` & `parametres-boutique` Web XFY :
/// Dégradé bleu marine #3F51B5 → #283593 · Cartes blanches arrondies 20px · Édition en direct via /api/parametres.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.state});

  final AppState state;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _savingSwitch = false;

  Future<void> _updateQuickToggle(
    StoreSettingsModel current,
    StoreSettingsModel next, {
    String? successMessage,
  }) async {
    if (_savingSwitch) return;
    HapticFeedback.selectionClick();
    setState(() => _savingSwitch = true);
    try {
      await widget.state.saveStoreSettings(next);
      if (!mounted) return;
      if (successMessage != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(successMessage)),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: XfyColors.rose, content: Text('Erreur : $e')),
      );
    } finally {
      if (mounted) setState(() => _savingSwitch = false);
    }
  }

  Future<void> _toggleStockZero(bool value) async {
    if (_savingSwitch) return;
    HapticFeedback.selectionClick();
    setState(() => _savingSwitch = true);
    try {
      await widget.state.toggleStockZeroBehavior(value);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            value
                ? 'Rupture affichée quand stock = 0'
                : 'Commande autorisée même si stock = 0',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: XfyColors.rose, content: Text('Erreur : $e')),
      );
    } finally {
      if (mounted) setState(() => _savingSwitch = false);
    }
  }

  Future<void> _openEditCoordonneesSheet(StoreSettingsModel settings) async {
    final nameCtrl = TextEditingController(text: settings.nomBoutique);
    final tel1Ctrl = TextEditingController(text: settings.telephone1);
    final tel2Ctrl = TextEditingController(text: settings.telephone2);
    final emailCtrl = TextEditingController(text: settings.email);
    final addrCtrl = TextEditingController(text: settings.adresse);
    final mfCtrl = TextEditingController(text: settings.matriculeFiscal);

    await _showEditSheet(
      title: 'Coordonnées de la boutique',
      icon: Icons.store_mall_directory_outlined,
      fields: [
        _SheetField(controller: nameCtrl, label: 'Nom de la boutique', icon: Icons.storefront_outlined),
        _SheetField(controller: tel1Ctrl, label: 'Téléphone 1', icon: Icons.phone_outlined, keyboardType: TextInputType.phone),
        _SheetField(controller: tel2Ctrl, label: 'Téléphone 2 (optionnel)', icon: Icons.phone_android_outlined, keyboardType: TextInputType.phone),
        _SheetField(controller: emailCtrl, label: 'Email de contact', icon: Icons.email_outlined, keyboardType: TextInputType.emailAddress),
        _SheetField(controller: addrCtrl, label: 'Adresse', icon: Icons.location_on_outlined),
        _SheetField(controller: mfCtrl, label: 'Matricule fiscal', icon: Icons.badge_outlined),
      ],
      onSave: () async {
        final updated = settings.copyWith(
          nomBoutique: nameCtrl.text.trim(),
          telephone1: tel1Ctrl.text.trim(),
          telephone2: tel2Ctrl.text.trim(),
          email: emailCtrl.text.trim(),
          adresse: addrCtrl.text.trim(),
          matriculeFiscal: mfCtrl.text.trim(),
        );
        await widget.state.saveStoreSettings(updated);
      },
    );
  }

  Future<void> _openEditDeliverySheet(StoreSettingsModel settings) async {
    final clientFeeCtrl = TextEditingController(
      text: settings.fraisLivraison.toStringAsFixed(2),
    );
    final companyFeeCtrl = TextEditingController(
      text: settings.fraisLivraisonSociete.toStringAsFixed(2),
    );
    final returnFeeCtrl = TextEditingController(
      text: settings.fraisRetourSociete.toStringAsFixed(2),
    );

    await _showEditSheet(
      title: 'Frais de livraison (TND)',
      icon: Icons.local_shipping_outlined,
      fields: [
        _SheetField(
          controller: clientFeeCtrl,
          label: 'Frais de livraison client (DT)',
          icon: Icons.payments_outlined,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
        ),
        _SheetField(
          controller: companyFeeCtrl,
          label: 'Coût livraison transporteur (DT)',
          icon: Icons.local_shipping_outlined,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
        ),
        _SheetField(
          controller: returnFeeCtrl,
          label: 'Coût retour transporteur (DT)',
          icon: Icons.assignment_return_outlined,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
        ),
      ],
      onSave: () async {
        double parse(String raw) =>
            double.tryParse(raw.trim().replaceAll(',', '.')) ?? 0;
        final updated = settings.copyWith(
          fraisLivraison: parse(clientFeeCtrl.text),
          fraisLivraisonSociete: parse(companyFeeCtrl.text),
          fraisRetourSociete: parse(returnFeeCtrl.text),
        );
        await widget.state.saveStoreSettings(updated);
      },
    );
  }

  Future<void> _openEditSocialsSheet(StoreSettingsModel settings) async {
    final fbCtrl = TextEditingController(text: settings.facebookUrl);
    final igCtrl = TextEditingController(text: settings.instagramUrl);
    final ttCtrl = TextEditingController(text: settings.tiktokUrl);
    final ytCtrl = TextEditingController(text: settings.youtubeUrl);

    await _showEditSheet(
      title: 'Réseaux sociaux',
      icon: Icons.share_outlined,
      fields: [
        _SheetField(controller: fbCtrl, label: 'Lien Facebook', icon: Icons.facebook_outlined, keyboardType: TextInputType.url),
        _SheetField(controller: igCtrl, label: 'Lien Instagram', icon: Icons.camera_alt_outlined, keyboardType: TextInputType.url),
        _SheetField(controller: ttCtrl, label: 'Lien TikTok', icon: Icons.music_note_outlined, keyboardType: TextInputType.url),
        _SheetField(controller: ytCtrl, label: 'Lien YouTube', icon: Icons.play_circle_outline_rounded, keyboardType: TextInputType.url),
      ],
      onSave: () async {
        final updated = settings.copyWith(
          facebookUrl: fbCtrl.text.trim(),
          instagramUrl: igCtrl.text.trim(),
          tiktokUrl: ttCtrl.text.trim(),
          youtubeUrl: ytCtrl.text.trim(),
        );
        await widget.state.saveStoreSettings(updated);
      },
    );
  }

  Future<void> _showEditSheet({
    required String title,
    required IconData icon,
    required List<_SheetField> fields,
    required Future<void> Function() onSave,
  }) async {
    bool saving = false;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  20,
                  12,
                  20,
                  MediaQuery.of(ctx).viewInsets.bottom + 20,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
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
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              gradient: XfyColors.brandGradient,
                              borderRadius: BorderRadius.circular(11),
                            ),
                            child: Icon(icon, color: Colors.white, size: 20),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              title,
                              style: const TextStyle(
                                fontSize: 17.5,
                                fontWeight: FontWeight.w800,
                                color: XfyColors.ink,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(ctx),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      ...fields.map(
                        (f) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: TextField(
                            controller: f.controller,
                            keyboardType: f.keyboardType,
                            decoration: InputDecoration(
                              labelText: f.label,
                              prefixIcon: Icon(
                                f.icon,
                                size: 20,
                                color: XfyColors.primary,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      FilledButton(
                        onPressed: saving
                            ? null
                            : () async {
                                setModalState(() => saving = true);
                                try {
                                  await onSave();
                                  if (ctx.mounted) Navigator.pop(ctx);
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Paramètres enregistrés !'),
                                      ),
                                    );
                                  }
                                } catch (e) {
                                  setModalState(() => saving = false);
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        backgroundColor: XfyColors.rose,
                                        content: Text('Erreur : $e'),
                                      ),
                                    );
                                  }
                                }
                              },
                        child: saving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('Enregistrer'),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  static int _computePasswordStrength(String pwd) {
    if (pwd.isEmpty) return 0;
    int strength = 0;
    if (pwd.length >= 6) strength += 1;
    if (pwd.length >= 8) strength += 1;
    if (RegExp(r'[A-Z]').hasMatch(pwd)) strength += 1;
    if (RegExp(r'[0-9]').hasMatch(pwd) &&
        RegExp(r'[^A-Za-z0-9]').hasMatch(pwd)) {
      strength += 1;
    }
    return strength.clamp(0, 4);
  }

  static String _passwordStrengthHint(int strength) {
    switch (strength) {
      case 0:
        return AppL10n.t('pw_hint_0');
      case 1:
        return AppL10n.t('pw_hint_1');
      case 2:
        return AppL10n.t('pw_hint_2');
      case 3:
        return AppL10n.t('pw_hint_3');
      default:
        return AppL10n.t('pw_hint_4');
    }
  }

  Future<void> _openPersonalInfoSheet() async {
    final user = widget.state.user;
    if (user == null) return;

    final firstNameCtrl = TextEditingController(text: user.uiFirstName);
    final lastNameCtrl = TextEditingController(text: user.uiLastName);
    final emailCtrl = TextEditingController(text: user.email);
    final phoneCtrl = TextEditingController(text: user.phoneNumber ?? '');
    final formKey = GlobalKey<FormState>();
    bool saving = false;
    String? errorMsg;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  20,
                  12,
                  20,
                  MediaQuery.of(ctx).viewInsets.bottom + 20,
                ),
                child: SingleChildScrollView(
                  child: Form(
                    key: formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
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
                        const SizedBox(height: 16),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                gradient: XfyColors.brandGradient,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                Icons.person_outline_rounded,
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
                                    AppL10n.t('settings_personal_info'),
                                    style: const TextStyle(
                                      fontSize: 17.5,
                                      fontWeight: FontWeight.w800,
                                      color: XfyColors.ink,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    AppL10n.t('settings_personal_info_desc'),
                                    style: const TextStyle(
                                      fontSize: 12.5,
                                      color: XfyColors.inkSecondary,
                                      height: 1.35,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              onPressed: () => Navigator.pop(ctx),
                              icon: const Icon(Icons.close_rounded),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: firstNameCtrl,
                                textCapitalization: TextCapitalization.words,
                                decoration: InputDecoration(
                                  labelText: AppL10n.t('profile_first_name'),
                                  hintText: AppL10n.t('profile_first_name_hint'),
                                  prefixIcon: const Icon(
                                    Icons.badge_outlined,
                                    size: 20,
                                    color: XfyColors.primary,
                                  ),
                                ),
                                validator: (v) {
                                  if (v == null || v.trim().isEmpty) {
                                    return AppL10n.t('profile_first_name_req');
                                  }
                                  return null;
                                },
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextFormField(
                                controller: lastNameCtrl,
                                textCapitalization: TextCapitalization.words,
                                decoration: InputDecoration(
                                  labelText: AppL10n.t('profile_last_name'),
                                  hintText: AppL10n.t('profile_last_name_hint'),
                                ),
                                validator: (v) {
                                  if (v == null || v.trim().isEmpty) {
                                    return AppL10n.t('profile_last_name_req');
                                  }
                                  return null;
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: emailCtrl,
                          keyboardType: TextInputType.emailAddress,
                          decoration: InputDecoration(
                            labelText: AppL10n.t('profile_email'),
                            hintText: 'votre.email@exemple.com',
                            prefixIcon: const Icon(
                              Icons.email_outlined,
                              size: 20,
                              color: XfyColors.primary,
                            ),
                          ),
                          validator: (v) {
                            final text = (v ?? '').trim();
                            if (text.isEmpty ||
                                !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                                    .hasMatch(text)) {
                              return AppL10n.t('profile_email_req');
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: phoneCtrl,
                          keyboardType: TextInputType.phone,
                          decoration: InputDecoration(
                            labelText: AppL10n.t('profile_phone'),
                            hintText: '+216 XX XXX XXX',
                            prefixIcon: const Icon(
                              Icons.phone_outlined,
                              size: 20,
                              color: XfyColors.primary,
                            ),
                          ),
                        ),
                        if (errorMsg != null) ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: XfyColors.roseSoft,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: XfyColors.rose.withValues(alpha: 0.3),
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.error_outline_rounded,
                                  color: XfyColors.rose,
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    errorMsg!,
                                    style: const TextStyle(
                                      color: XfyColors.rose,
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 18),
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFFFF6B35),
                            foregroundColor: Colors.white,
                          ),
                          onPressed: saving
                              ? null
                              : () async {
                                  if (!formKey.currentState!.validate()) return;
                                  setModalState(() {
                                    saving = true;
                                    errorMsg = null;
                                  });
                                  try {
                                    await widget.state.updatePersonalInfo(
                                      firstName: firstNameCtrl.text,
                                      lastName: lastNameCtrl.text,
                                      email: emailCtrl.text,
                                      phoneNumber: phoneCtrl.text,
                                    );
                                    if (ctx.mounted) Navigator.pop(ctx);
                                    if (mounted) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        SnackBar(
                                          backgroundColor: XfyColors.emerald,
                                          content: Text(
                                            AppL10n.t('profile_updated_ok'),
                                          ),
                                        ),
                                      );
                                    }
                                  } catch (e) {
                                    setModalState(() {
                                      saving = false;
                                      errorMsg = e.toString();
                                    });
                                  }
                                },
                          icon: saving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.save_outlined, size: 19),
                          label: Text(
                            saving
                                ? AppL10n.t('profile_saving')
                                : AppL10n.t('profile_save_btn'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    firstNameCtrl.dispose();
    lastNameCtrl.dispose();
    emailCtrl.dispose();
    phoneCtrl.dispose();
  }

  Future<void> _openChangePasswordSheet() async {
    final currentCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    bool saving = false;
    bool obscureCurrent = true;
    bool obscureNew = true;
    bool obscureConfirm = true;
    String? errorMsg;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final strength = _computePasswordStrength(newCtrl.text);
            final strengthColor =
                strength < 3 ? const Color(0xFFFBBF24) : XfyColors.emerald;

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  20,
                  12,
                  20,
                  MediaQuery.of(ctx).viewInsets.bottom + 20,
                ),
                child: SingleChildScrollView(
                  child: Form(
                    key: formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
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
                        const SizedBox(height: 16),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFF3E8),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                Icons.shield_outlined,
                                color: Color(0xFFFF6600),
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    AppL10n.t('settings_change_pw'),
                                    style: const TextStyle(
                                      fontSize: 17.5,
                                      fontWeight: FontWeight.w800,
                                      color: XfyColors.ink,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    AppL10n.t('pw_sheet_sub'),
                                    style: const TextStyle(
                                      fontSize: 12.5,
                                      color: XfyColors.inkSecondary,
                                      height: 1.35,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              onPressed: () => Navigator.pop(ctx),
                              icon: const Icon(Icons.close_rounded),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        // Bannière niveau de sécurité (calquée sur profile-settings Web)
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: XfyColors.canvasAlt,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: XfyColors.border),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  gradient: XfyColors.brandGradient,
                                  borderRadius: BorderRadius.circular(11),
                                ),
                                child: const Icon(
                                  Icons.verified_user_outlined,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      AppL10n.t('pw_strength_title'),
                                      style: const TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w700,
                                        color: XfyColors.ink,
                                      ),
                                    ),
                                    const SizedBox(height: 7),
                                    Row(
                                      children: List.generate(4, (i) {
                                        final active = strength >= i + 1;
                                        return Expanded(
                                          child: Container(
                                            height: 5,
                                            margin: EdgeInsets.only(
                                              right: i < 3 ? 6 : 0,
                                            ),
                                            decoration: BoxDecoration(
                                              color: active
                                                  ? strengthColor
                                                  : XfyColors.border,
                                              borderRadius:
                                                  BorderRadius.circular(99),
                                            ),
                                          ),
                                        );
                                      }),
                                    ),
                                    const SizedBox(height: 5),
                                    Text(
                                      _passwordStrengthHint(strength),
                                      style: const TextStyle(
                                        fontSize: 11.5,
                                        color: XfyColors.inkSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: currentCtrl,
                          obscureText: obscureCurrent,
                          decoration: InputDecoration(
                            labelText: AppL10n.t('pw_current'),
                            hintText: '••••••••••••',
                            prefixIcon: const Icon(
                              Icons.lock_outline_rounded,
                              size: 20,
                              color: XfyColors.primary,
                            ),
                            suffixIcon: IconButton(
                              onPressed: () => setModalState(
                                () => obscureCurrent = !obscureCurrent,
                              ),
                              icon: Icon(
                                obscureCurrent
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                                size: 20,
                              ),
                            ),
                          ),
                          validator: (v) {
                            if (v == null || v.isEmpty) {
                              return AppL10n.t('pw_current_req');
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: newCtrl,
                          obscureText: obscureNew,
                          onChanged: (_) => setModalState(() {}),
                          decoration: InputDecoration(
                            labelText: AppL10n.t('pw_new'),
                            hintText: AppL10n.t('pw_new_hint'),
                            prefixIcon: const Icon(
                              Icons.lock_open_rounded,
                              size: 20,
                              color: XfyColors.primary,
                            ),
                            suffixIcon: IconButton(
                              onPressed: () =>
                                  setModalState(() => obscureNew = !obscureNew),
                              icon: Icon(
                                obscureNew
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                                size: 20,
                              ),
                            ),
                          ),
                          validator: (v) {
                            if (v == null || v.length < 6) {
                              return AppL10n.t('pw_new_min');
                            }
                            if (v == currentCtrl.text) {
                              return AppL10n.t('pw_same');
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: confirmCtrl,
                          obscureText: obscureConfirm,
                          decoration: InputDecoration(
                            labelText: AppL10n.t('pw_confirm'),
                            hintText: AppL10n.t('pw_confirm_hint'),
                            prefixIcon: const Icon(
                              Icons.check_circle_outline_rounded,
                              size: 20,
                              color: XfyColors.primary,
                            ),
                            suffixIcon: IconButton(
                              onPressed: () => setModalState(
                                () => obscureConfirm = !obscureConfirm,
                              ),
                              icon: Icon(
                                obscureConfirm
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                                size: 20,
                              ),
                            ),
                          ),
                          validator: (v) {
                            if (v == null || v.isEmpty) {
                              return AppL10n.t('pw_confirm_req');
                            }
                            if (v != newCtrl.text) {
                              return AppL10n.t('pw_mismatch');
                            }
                            return null;
                          },
                        ),
                        if (errorMsg != null) ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: XfyColors.roseSoft,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: XfyColors.rose.withValues(alpha: 0.3),
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.error_outline_rounded,
                                  color: XfyColors.rose,
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    errorMsg!,
                                    style: const TextStyle(
                                      color: XfyColors.rose,
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 18),
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: XfyColors.primary,
                            foregroundColor: Colors.white,
                          ),
                          onPressed: saving
                              ? null
                              : () async {
                                  if (!formKey.currentState!.validate()) return;
                                  setModalState(() {
                                    saving = true;
                                    errorMsg = null;
                                  });
                                  try {
                                    await widget.state.changePassword(
                                      currentPassword: currentCtrl.text,
                                      newPassword: newCtrl.text,
                                    );
                                    if (ctx.mounted) Navigator.pop(ctx);
                                    if (mounted) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        SnackBar(
                                          backgroundColor: XfyColors.emerald,
                                          content: Text(
                                            AppL10n.t('pw_updated_ok'),
                                          ),
                                        ),
                                      );
                                    }
                                  } catch (e) {
                                    setModalState(() {
                                      saving = false;
                                      errorMsg = e.toString();
                                    });
                                  }
                                },
                          icon: saving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.lock_reset_rounded, size: 20),
                          label: Text(
                            saving
                                ? AppL10n.t('pw_updating')
                                : AppL10n.t('pw_update_btn'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    currentCtrl.dispose();
    newCtrl.dispose();
    confirmCtrl.dispose();
  }

  Future<void> _confirmLogout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppL10n.t('settings_logout_title')),
        content: Text(AppL10n.t('settings_logout_confirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(AppL10n.t('cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: XfyColors.rose,
              minimumSize: const Size(0, 42),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(AppL10n.t('settings_logout_title')),
          ),
        ],
      ),
    );
    if (ok == true) {
      await widget.state.logout();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAndroid =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    final store = widget.state.selectedStore;
    final user = widget.state.user;
    final settings = widget.state.storeSettings ??
        StoreSettingsModel(
          storeId: store?.id ?? 0,
          nomBoutique: store?.name ?? '',
        );

    return Scaffold(
      backgroundColor: XfyColors.canvas,
      body: SafeArea(
        child: RefreshIndicator(
          color: XfyColors.primary,
          onRefresh: () => widget.state.refreshSettings(),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              // 1. Header Paramètres Web XFY (exactement comme parametres-overview)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: XfyColors.surface,
                  borderRadius: BorderRadius.circular(20),
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
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: XfyColors.primary.withValues(alpha: 0.28),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.settings_rounded,
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
                            AppL10n.t('settings_title'),
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: XfyColors.ink,
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            AppL10n.t('settings_sub'),
                            style: const TextStyle(
                              fontSize: 12.5,
                              color: XfyColors.inkSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (widget.state.isSettingsLoading)
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: XfyColors.primary,
                        ),
                      ),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              // 2. Boutique active & Domaine
              _SettingsCard(
                children: [
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    leading: Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: XfyColors.primarySoft,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: store?.resolvedLogoUrl != null
                          ? Image.network(
                              store!.resolvedLogoUrl!,
                              fit: BoxFit.cover,
                              cacheWidth: 120,
                              cacheHeight: 120,
                              filterQuality: FilterQuality.low,
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
                    title: Text(
                      store?.name ?? AppL10n.t('my_store'),
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15.5,
                        color: XfyColors.ink,
                      ),
                    ),
                    subtitle: Text(
                      store?.publicUrl?.replaceFirst('https://', '') ??
                          'Domaine XFY',
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: XfyColors.primaryVibrant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    trailing: widget.state.stores.length > 1
                        ? TextButton(
                            onPressed: () => showModalBottomSheet(
                              context: context,
                              builder: (_) =>
                                  StoreSwitcherSheet(state: widget.state),
                            ),
                            child: Text(
                              AppL10n.t('settings_change_store'),
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                          )
                        : null,
                  ),
                  if (store?.publicUrl != null) ...[
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(
                        Icons.public_rounded,
                        color: XfyColors.primaryBlue,
                      ),
                      title: Text(
                        AppL10n.t('settings_open_store'),
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      trailing: const Icon(Icons.open_in_new_rounded, size: 18),
                      onTap: () =>
                          XfyFormatters.launchExternalWeb(store!.publicUrl!),
                    ),
                  ],
                ],
              ),

              const SizedBox(height: 16),
              _SectionLabel(title: AppL10n.t('settings_section_profile')),
              const SizedBox(height: 8),

              // 2b. Profil utilisateur + Informations personnelles + Changer mot de passe
              _SettingsCard(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                    child: Row(
                      children: [
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            gradient: XfyColors.brandGradient,
                            borderRadius: BorderRadius.circular(15),
                            boxShadow: [
                              BoxShadow(
                                color: XfyColors.primary.withValues(alpha: 0.25),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            user?.initials ?? 'X',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                        const SizedBox(width: 13),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                user?.displayName ?? 'Vendeur XFY',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15.5,
                                  color: XfyColors.ink,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                user?.email ?? '',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  color: XfyColors.inkSecondary,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 6,
                                runSpacing: 4,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 9,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFFF3E8),
                                      borderRadius: BorderRadius.circular(99),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(
                                          Icons.circle,
                                          size: 6,
                                          color: Color(0xFFFF6600),
                                        ),
                                        const SizedBox(width: 5),
                                        Text(
                                          AppL10n.t('settings_active_account'),
                                          style: const TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                            color: Color(0xFFFF6600),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (user?.phoneNumber != null &&
                                      user!.phoneNumber!.trim().isNotEmpty)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: XfyColors.primarySoft,
                                        borderRadius: BorderRadius.circular(99),
                                      ),
                                      child: Text(
                                        user.phoneNumber!.trim(),
                                        style: const TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          color: XfyColors.primary,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  _SettingsNavTile(
                    icon: Icons.person_outline_rounded,
                    iconBg: XfyColors.primarySoft,
                    iconColor: XfyColors.primary,
                    title: AppL10n.t('settings_personal_info'),
                    subtitle: AppL10n.t('settings_personal_info_desc'),
                    onTap: _openPersonalInfoSheet,
                  ),
                  const Divider(height: 1),
                  _SettingsNavTile(
                    icon: Icons.lock_reset_rounded,
                    iconBg: const Color(0xFFFFF3E8),
                    iconColor: const Color(0xFFFF6600),
                    title: AppL10n.t('settings_change_pw'),
                    subtitle: AppL10n.t('settings_change_pw_desc'),
                    onTap: _openChangePasswordSheet,
                  ),
                ],
              ),

              const SizedBox(height: 16),
              _SectionLabel(title: AppL10n.t('settings_section_lang')),
              const SizedBox(height: 8),

              // 2c. Sélecteur de Langue : Français / English / العربية
              _SettingsCard(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: XfyColors.primarySoft,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                Icons.translate_rounded,
                                color: XfyColors.primaryVibrant,
                                size: 21,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    AppL10n.t('settings_lang_title'),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 14.5,
                                      color: XfyColors.ink,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    AppL10n.t('settings_lang_desc'),
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: XfyColors.inkSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            for (final entry in const [
                              ('fr', 'FR', 'Français'),
                              ('en', 'EN', 'English'),
                              ('ar', 'AR', 'العربية'),
                            ]) ...[
                              Expanded(
                                child: _LanguageOptionPill(
                                  codeBadge: entry.$2,
                                  label: entry.$3,
                                  selected: widget.state.languageCode == entry.$1,
                                  onTap: () async {
                                    HapticFeedback.selectionClick();
                                    await widget.state.setLanguage(entry.$1);
                                    if (!context.mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        backgroundColor: XfyColors.primary,
                                        content: Text(
                                          AppL10n.t('settings_lang_updated', {
                                            'lang': entry.$3,
                                          }),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                              if (entry.$1 != 'ar') const SizedBox(width: 8),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),
              _SectionLabel(title: AppL10n.t('settings_section_notif')),
              const SizedBox(height: 8),

              _SettingsCard(
                children: [
                  // État en direct des alertes & permission Android
                  Container(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
                    decoration: BoxDecoration(
                      color: widget.state.systemNotificationsAllowed
                          ? XfyColors.emeraldSoft
                          : XfyColors.roseSoft,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(18),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          widget.state.systemNotificationsAllowed
                              ? Icons.check_circle_rounded
                              : Icons.notifications_off_rounded,
                          size: 18,
                          color: widget.state.systemNotificationsAllowed
                              ? XfyColors.emerald
                              : XfyColors.rose,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            widget.state.systemNotificationsAllowed
                                ? (isAndroid
                                    ? AppL10n.t('settings_notif_live', {
                                        'live': widget.state.isStompConnected
                                            ? AppL10n.t('settings_notif_connected')
                                            : AppL10n.t('settings_notif_polling'),
                                        'bg': widget.state.isBackgroundMonitorRunning
                                            ? AppL10n.t('settings_notif_active')
                                            : AppL10n.t('settings_notif_stopped'),
                                      })
                                    : (widget.state.isStompConnected
                                        ? AppL10n.t('settings_notif_connected')
                                        : AppL10n.t('settings_notif_polling')))
                                : AppL10n.t('settings_notif_blocked'),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: widget.state.systemNotificationsAllowed
                                  ? XfyColors.emerald
                                  : XfyColors.rose,
                            ),
                          ),
                        ),
                        if (!widget.state.systemNotificationsAllowed)
                          TextButton(
                            onPressed: () =>
                                widget.state.requestNotificationPermission(),
                            child: Text(
                              AppL10n.t('settings_notif_allow'),
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                color: XfyColors.rose,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  SwitchListTile(
                    title: Text(
                      AppL10n.t('settings_notif_alerts'),
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    subtitle: Text(
                      AppL10n.t('settings_notif_alerts_sub'),
                      style: const TextStyle(
                        fontSize: 12,
                        color: XfyColors.inkSecondary,
                      ),
                    ),
                    value: widget.state.notificationsEnabled,
                    onChanged: (v) => widget.state.setNotificationsEnabled(v),
                  ),
                  const Divider(height: 1),
                  SwitchListTile(
                    title: Text(
                      AppL10n.t('settings_notif_sound'),
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    subtitle: Text(
                      AppL10n.t('settings_notif_sound_sub'),
                      style: const TextStyle(
                        fontSize: 12,
                        color: XfyColors.inkSecondary,
                      ),
                    ),
                    value: widget.state.soundEnabled,
                    onChanged: widget.state.notificationsEnabled
                        ? (v) => widget.state.setSoundEnabled(v)
                        : null,
                  ),
                  if (widget.state.notificationsEnabled &&
                      widget.state.soundEnabled) ...[
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            AppL10n.t('settings_ringtone_title'),
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 13.5,
                              color: XfyColors.ink,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            AppL10n.t('settings_ringtone_sub'),
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: XfyColors.inkSecondary,
                            ),
                          ),
                          const SizedBox(height: 10),
                          ...OrderNotificationService.ringtones.map((tone) {
                            final selected =
                                widget.state.selectedRingtoneId == tone.id;
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(14),
                                onTap: () {
                                  HapticFeedback.selectionClick();
                                  widget.state.setSelectedRingtone(tone.id);
                                },
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 160),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: selected
                                        ? XfyColors.primarySoft
                                        : XfyColors.canvas,
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: selected
                                          ? XfyColors.primaryVibrant
                                          : XfyColors.border,
                                      width: selected ? 1.5 : 1,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 34,
                                        height: 34,
                                        decoration: BoxDecoration(
                                          color: selected
                                              ? XfyColors.primaryVibrant
                                              : XfyColors.surface,
                                          borderRadius:
                                              BorderRadius.circular(10),
                                          border: Border.all(
                                            color: selected
                                                ? Colors.transparent
                                                : XfyColors.border,
                                          ),
                                        ),
                                        child: Icon(
                                          selected
                                              ? Icons.music_note_rounded
                                              : Icons.notifications_active_outlined,
                                          size: 18,
                                          color: selected
                                              ? Colors.white
                                              : XfyColors.primaryVibrant,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Flexible(
                                                  child: Text(
                                                    AppL10n.t(tone.titleKey),
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: TextStyle(
                                                      fontSize: 13,
                                                      fontWeight:
                                                          FontWeight.w800,
                                                      color: selected
                                                          ? XfyColors.primaryDark
                                                          : XfyColors.ink,
                                                    ),
                                                  ),
                                                ),
                                                if (tone.isDefault) ...[
                                                  const SizedBox(width: 6),
                                                  Container(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                      horizontal: 6,
                                                      vertical: 2,
                                                    ),
                                                    decoration: BoxDecoration(
                                                      color: const Color(
                                                          0xFFFFF3E8),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              99),
                                                    ),
                                                    child: Text(
                                                      AppL10n.t(
                                                        'settings_ringtone_default_badge',
                                                      ),
                                                      style: const TextStyle(
                                                        fontSize: 9.5,
                                                        fontWeight:
                                                            FontWeight.w800,
                                                        color:
                                                            Color(0xFFFF6600),
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ],
                                            ),
                                            const SizedBox(height: 1),
                                            Text(
                                              AppL10n.t(tone.subtitleKey),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontSize: 11,
                                                color: XfyColors.inkSecondary,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: 'Écouter',
                                        visualDensity: VisualDensity.compact,
                                        onPressed: () {
                                          HapticFeedback.lightImpact();
                                          widget.state
                                              .previewRingtone(tone.id);
                                        },
                                        icon: Icon(
                                          Icons.volume_up_rounded,
                                          size: 20,
                                          color: selected
                                              ? XfyColors.primaryVibrant
                                              : XfyColors.inkSecondary,
                                        ),
                                      ),
                                      if (selected)
                                        const Icon(
                                          Icons.check_circle_rounded,
                                          size: 20,
                                          color: XfyColors.primaryVibrant,
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
                  ],
                  if (isAndroid) ...[
                    const Divider(height: 1),
                    SwitchListTile(
                      title: Text(
                        AppL10n.t('settings_notif_bg'),
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      subtitle: Text(
                        AppL10n.t('settings_notif_bg_sub'),
                        style: const TextStyle(
                          fontSize: 12,
                          color: XfyColors.inkSecondary,
                        ),
                      ),
                      value: widget.state.backgroundMonitorEnabled,
                      onChanged: widget.state.notificationsEnabled
                          ? (v) => widget.state.setBackgroundMonitorEnabled(v)
                          : null,
                    ),
                  ],
                  if (isAndroid && !widget.state.isIgnoringBatteryOptimizations) ...[
                    const Divider(height: 1),
                    ListTile(
                      leading: Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: XfyColors.amberSoft,
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: const Icon(
                          Icons.battery_saver_rounded,
                          color: XfyColors.amber,
                          size: 20,
                        ),
                      ),
                      title: Text(
                        AppL10n.t('settings_battery_title'),
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13.5,
                          color: XfyColors.ink,
                        ),
                      ),
                      subtitle: Text(
                        AppL10n.t('settings_battery_sub'),
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: XfyColors.inkSecondary,
                        ),
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () =>
                          widget.state.requestBatteryOptimizationExemption(),
                    ),
                  ],
                  const Divider(height: 1),
                  ListTile(
                    leading: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: XfyColors.emeraldSoft,
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: const Icon(
                        Icons.payments_rounded,
                        color: XfyColors.emerald,
                        size: 20,
                      ),
                    ),
                    title: Text(
                      AppL10n.t('settings_test_notif'),
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: XfyColors.primaryVibrant,
                      ),
                    ),
                    trailing: const Icon(
                      Icons.play_arrow_rounded,
                      color: XfyColors.primaryVibrant,
                    ),
                    onTap: () => widget.state.testOrderNotification(),
                  ),
                ],
              ),

              const SizedBox(height: 16),
              _SectionLabel(title: AppL10n.t('settings_section_store')),
              const SizedBox(height: 8),

              // 3. Cartes Paramètres éditables (Coordonnées, Livraison, Réseaux)
              _SettingsCard(
                children: [
                  _SettingsNavTile(
                    icon: Icons.store_mall_directory_outlined,
                    iconBg: XfyColors.primarySoft,
                    iconColor: XfyColors.primary,
                    title: AppL10n.t('settings_store_contact'),
                    subtitle: [
                      if (settings.telephone1.isNotEmpty) settings.telephone1,
                      if (settings.email.isNotEmpty) settings.email,
                      if (settings.adresse.isNotEmpty) settings.adresse,
                    ].isEmpty
                        ? AppL10n.t('settings_store_contact_sub')
                        : [
                            if (settings.telephone1.isNotEmpty) settings.telephone1,
                            if (settings.email.isNotEmpty) settings.email,
                          ].join(' • '),
                    onTap: () => _openEditCoordonneesSheet(settings),
                  ),
                  const Divider(height: 1),
                  _SettingsNavTile(
                    icon: Icons.local_shipping_outlined,
                    iconBg: XfyColors.accentSoft,
                    iconColor: XfyColors.accent,
                    title: AppL10n.t('settings_delivery_fees'),
                    subtitle:
                        '${XfyFormatters.formatTnd(settings.fraisLivraison)} • ${XfyFormatters.formatTnd(settings.fraisLivraisonSociete)}',
                    onTap: () => _openEditDeliverySheet(settings),
                  ),
                  const Divider(height: 1),
                  _SettingsNavTile(
                    icon: Icons.share_outlined,
                    iconBg: XfyColors.violetSoft,
                    iconColor: XfyColors.violet,
                    title: AppL10n.t('settings_socials'),
                    subtitle: 'Facebook, Instagram, TikTok, YouTube',
                    onTap: () => _openEditSocialsSheet(settings),
                  ),
                  if (widget.state.deliveryCompanies.isNotEmpty) ...[
                    const Divider(height: 1),
                    ListTile(
                      leading: Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: XfyColors.emeraldSoft,
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: const Icon(
                          Icons.verified_outlined,
                          color: XfyColors.emerald,
                          size: 20,
                        ),
                      ),
                      title: Text(
                        AppL10n.t('settings_carriers'),
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14.5,
                        ),
                      ),
                      subtitle: Text(
                        widget.state.deliveryCompanies.join(', '),
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: XfyColors.inkSecondary,
                        ),
                      ),
                    ),
                  ],
                ],
              ),

              const SizedBox(height: 16),
              _SectionLabel(title: AppL10n.t('settings_section_payment')),
              const SizedBox(height: 8),

              // 4. Switches rapides enregistrés en direct sur Spring Boot
              _SettingsCard(
                children: [
                  SwitchListTile(
                    title: Text(
                      AppL10n.t('settings_cod'),
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    subtitle: Text(
                      AppL10n.t('settings_cod_sub'),
                      style: const TextStyle(
                        fontSize: 12,
                        color: XfyColors.inkSecondary,
                      ),
                    ),
                    value: settings.paiementALaLivraison,
                    onChanged: _savingSwitch
                        ? null
                        : (v) => _updateQuickToggle(
                              settings,
                              settings.copyWith(paiementALaLivraison: v),
                              successMessage: AppL10n.t('settings_saved'),
                            ),
                  ),
                  const Divider(height: 1),
                  SwitchListTile(
                    title: Text(
                      AppL10n.t('settings_online_pay'),
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    subtitle: Text(
                      AppL10n.t('settings_online_pay_sub'),
                      style: const TextStyle(
                        fontSize: 12,
                        color: XfyColors.inkSecondary,
                      ),
                    ),
                    value: settings.paiementEnLigne,
                    onChanged: _savingSwitch
                        ? null
                        : (v) => _updateQuickToggle(
                              settings,
                              settings.copyWith(paiementEnLigne: v),
                              successMessage: AppL10n.t('settings_saved'),
                            ),
                  ),
                  const Divider(height: 1),
                  SwitchListTile(
                    title: Text(
                      AppL10n.t('settings_invoices'),
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    value: settings.genererFacture,
                    onChanged: _savingSwitch
                        ? null
                        : (v) => _updateQuickToggle(
                              settings,
                              settings.copyWith(genererFacture: v),
                              successMessage: AppL10n.t('settings_saved'),
                            ),
                  ),
                  const Divider(height: 1),
                  SwitchListTile(
                    title: Text(
                      AppL10n.t('settings_email_notif'),
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    value: settings.notificationsEmail,
                    onChanged: _savingSwitch
                        ? null
                        : (v) => _updateQuickToggle(
                              settings,
                              settings.copyWith(notificationsEmail: v),
                              successMessage: AppL10n.t('settings_saved'),
                            ),
                  ),
                  const Divider(height: 1),
                  SwitchListTile(
                    title: Text(
                      AppL10n.t('settings_stock_zero'),
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    subtitle: Text(
                      AppL10n.t('settings_stock_zero_sub'),
                      style: const TextStyle(
                        fontSize: 12,
                        color: XfyColors.inkSecondary,
                      ),
                    ),
                    value: settings.afficherRuptureStockZero,
                    onChanged: _savingSwitch ? null : _toggleStockZero,
                  ),
                ],
              ),

              const SizedBox(height: 16),
              _SectionLabel(title: AppL10n.t('settings_section_web')),
              const SizedBox(height: 8),

              // 5. Accès Web complet
              _SettingsCard(
                children: [
                  ListTile(
                    leading: const Icon(
                      Icons.laptop_mac_rounded,
                      color: XfyColors.primary,
                    ),
                    title: Text(
                      AppL10n.t('settings_open_web'),
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    subtitle: Text(
                      AppL10n.t('settings_open_web_sub'),
                      style: const TextStyle(fontSize: 12),
                    ),
                    trailing: const Icon(Icons.open_in_new_rounded, size: 18),
                    onTap: () => XfyFormatters.launchExternalWeb('https://xfy.tn'),
                  ),
                ],
              ),

              const SizedBox(height: 18),

              // 6. Déconnexion
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: XfyColors.rose,
                  side: const BorderSide(color: Color(0xFFFECACA)),
                  backgroundColor: XfyColors.roseSoft,
                  minimumSize: const Size.fromHeight(50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: _confirmLogout,
                icon: const Icon(Icons.logout_rounded),
                label: Text(
                  AppL10n.t('settings_logout'),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 13.5,
          fontWeight: FontWeight.w800,
          color: XfyColors.primaryDark,
          letterSpacing: -0.1,
        ),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: XfyColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: XfyColors.border),
        boxShadow: XfyColors.cardShadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }
}

class _SettingsNavTile extends StatelessWidget {
  const _SettingsNavTile({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: iconBg,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: iconColor, size: 20),
      ),
      title: Text(
        title,
        style: const TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 14.5,
          color: XfyColors.ink,
        ),
      ),
      subtitle: Text(
        subtitle,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 12.5,
          color: XfyColors.inkSecondary,
          height: 1.3,
        ),
      ),
      trailing: const Icon(
        Icons.chevron_right_rounded,
        color: XfyColors.inkMuted,
      ),
      onTap: onTap,
    );
  }
}

class _LanguageOptionPill extends StatelessWidget {
  const _LanguageOptionPill({
    required this.codeBadge,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String codeBadge;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          gradient: selected ? XfyColors.statsGradient : null,
          color: selected ? null : XfyColors.canvasAlt,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(
            color: selected ? Colors.transparent : XfyColors.border,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: XfyColors.primaryVibrant.withValues(alpha: 0.25),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              codeBadge,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.6,
                color: selected
                    ? Colors.white.withValues(alpha: 0.85)
                    : XfyColors.primaryVibrant,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: selected ? Colors.white : XfyColors.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SheetField {
  const _SheetField({
    required this.controller,
    required this.label,
    required this.icon,
    this.keyboardType = TextInputType.text,
  });

  final TextEditingController controller;
  final String label;
  final IconData icon;
  final TextInputType keyboardType;
}
