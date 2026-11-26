import 'dart:math' as math;
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import '../../core/l10n/app_l10n.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../data/services/xfy_api_service.dart';
import '../../state/app_state.dart';

/// Écran de connexion XFY — Design fidèle au Login Web (`signin.component.html` & `.scss`) :
/// Fond lumineux #F8FAFC avec halos orange/indigo, globe filaire 3D + particules flottantes,
/// badge pulsant « Plateforme mondiale active », titre « Connectez-vous à votre univers. »,
/// carte blanche givrée, focus orange #FF6B35, « Oublié ? », bouton CTA dégradé orange XFY.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.state});

  final AppState state;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  static const Color _navyPrimary = Color(0xFF1E2847);
  static const Color _orangePrimary = Color(0xFFFF6B35);
  static const Color _orangeDark = Color(0xFFE85A2B);
  static const Color _pageBg = Color(0xFFF8FAFC);

  final _formKey = GlobalKey<FormState>();
  final _identifierCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  late final AnimationController _ambientCtrl;
  bool _obscurePassword = true;
  bool _rememberMe = true;
  String? _localError;

  @override
  void initState() {
    super.initState();
    _ambientCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 26),
    )..repeat();
    _loadRememberedIdentifier();
  }

  Future<void> _loadRememberedIdentifier() async {
    final saved = await widget.state.getRememberedIdentifier();
    if (mounted && saved != null && saved.isNotEmpty) {
      _identifierCtrl.text = saved;
    }
  }

  @override
  void dispose() {
    _ambientCtrl.dispose();
    _identifierCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    HapticFeedback.lightImpact();

    setState(() => _localError = null);

    try {
      if (_rememberMe) {
        await widget.state.saveRememberedIdentifier(_identifierCtrl.text);
      } else {
        await widget.state.saveRememberedIdentifier(null);
      }
      await widget.state.login(_identifierCtrl.text, _passwordCtrl.text);
    } on SmsVerificationRequiredException catch (smsEx) {
      if (!mounted) return;
      await _showSmsVerificationDialog(smsEx.email, smsEx.phoneNumber);
    } catch (e) {
      if (!mounted) return;
      setState(() => _localError = e.toString());
    }
  }

  Future<void> _showForgotPasswordSheet() async {
    final emailCtrl = TextEditingController(
      text: _identifierCtrl.text.contains('@')
          ? _identifierCtrl.text.trim()
          : '',
    );
    final forgotKey = GlobalKey<FormState>();
    bool sending = false;
    String? errorMsg;
    String? successMsg;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  22,
                  12,
                  22,
                  MediaQuery.of(ctx).viewInsets.bottom + 22,
                ),
                child: Form(
                  key: forgotKey,
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
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [_orangePrimary, _orangeDark],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.lock_reset_rounded,
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
                                  AppL10n.t('forgot_title'),
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w900,
                                    color: _navyPrimary,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  AppL10n.t('forgot_sub'),
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    color: XfyColors.inkSecondary,
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
                      TextFormField(
                        controller: emailCtrl,
                        keyboardType: TextInputType.emailAddress,
                        autofocus: true,
                        decoration: _webInputDecoration(
                          hint: 'votre.email@exemple.com',
                          prefixIcon: Icons.email_outlined,
                        ),
                        validator: (v) {
                          final txt = (v ?? '').trim();
                          if (txt.isEmpty ||
                              !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                                  .hasMatch(txt)) {
                            return 'Veuillez entrer une adresse email valide.';
                          }
                          return null;
                        },
                      ),
                      if (errorMsg != null) ...[
                        const SizedBox(height: 12),
                        _ErrorBanner(message: errorMsg!),
                      ],
                      if (successMsg != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: XfyColors.emeraldSoft,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: XfyColors.emerald.withValues(alpha: 0.35),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.check_circle_rounded,
                                color: XfyColors.emerald,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  successMsg!,
                                  style: const TextStyle(
                                    color: Color(0xFF047857),
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      _OrangeCtaButton(
                        label: sending
                            ? AppL10n.t('forgot_sending')
                            : AppL10n.t('forgot_cta'),
                        loading: sending,
                        onPressed: sending
                            ? null
                            : () async {
                                if (!forgotKey.currentState!.validate()) return;
                                setModalState(() {
                                  sending = true;
                                  errorMsg = null;
                                  successMsg = null;
                                });
                                try {
                                  final msg = await widget.state
                                      .sendForgotPasswordEmail(emailCtrl.text);
                                  setModalState(() {
                                    sending = false;
                                    successMsg = msg;
                                  });
                                } catch (e) {
                                  setModalState(() {
                                    sending = false;
                                    errorMsg = e.toString();
                                  });
                                }
                              },
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

    emailCtrl.dispose();
  }

  Future<void> _showSmsVerificationDialog(String email, String phone) async {
    final codeCtrl = TextEditingController();
    String? dialogError;
    String? infoMsg;
    bool verifying = false;
    bool resending = false;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  22,
                  12,
                  22,
                  MediaQuery.of(ctx).viewInsets.bottom + 22,
                ),
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
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [_orangePrimary, _orangeDark],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: _orangePrimary.withValues(alpha: 0.35),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.sms_outlined,
                            color: Colors.white,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            AppL10n.t('sms_title'),
                            style: const TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w900,
                              color: _navyPrimary,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(ctx),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      phone.isNotEmpty
                          ? AppL10n.t('sms_desc_phone', {'phone': phone})
                          : AppL10n.t('sms_desc_generic'),
                      style: TextStyle(
                        fontSize: 13.5,
                        color: _navyPrimary.withValues(alpha: 0.7),
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      AppL10n.t('sms_code_label'),
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                        color: XfyColors.inkSecondary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: codeCtrl,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      autofocus: true,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 10,
                        color: _navyPrimary,
                      ),
                      decoration: _webInputDecoration(
                        hint: '••••••',
                      ).copyWith(counterText: ''),
                    ),
                    if (dialogError != null) ...[
                      const SizedBox(height: 10),
                      _ErrorBanner(message: dialogError!),
                    ],
                    if (infoMsg != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        infoMsg!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: XfyColors.emerald,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    _OrangeCtaButton(
                      label: verifying
                          ? AppL10n.t('sms_verifying')
                          : AppL10n.t('sms_verify'),
                      loading: verifying,
                      onPressed: verifying
                          ? null
                          : () async {
                              setModalState(() {
                                verifying = true;
                                dialogError = null;
                              });
                              try {
                                await widget.state.verifySmsAndFinishLogin(
                                  email: email,
                                  code: codeCtrl.text,
                                );
                                if (ctx.mounted) Navigator.pop(ctx);
                              } catch (e) {
                                setModalState(() {
                                  verifying = false;
                                  dialogError = e.toString();
                                });
                              }
                            },
                    ),
                    if (phone.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: resending
                            ? null
                            : () async {
                                setModalState(() {
                                  resending = true;
                                  dialogError = null;
                                  infoMsg = null;
                                });
                                try {
                                  await widget.state.resendSmsCode(
                                    email: email,
                                    phoneNumber: phone,
                                  );
                                  setModalState(() {
                                    resending = false;
                                    infoMsg = AppL10n.t('sms_resent_ok');
                                  });
                                } catch (e) {
                                  setModalState(() {
                                    resending = false;
                                    dialogError = e.toString();
                                  });
                                }
                              },
                        child: Text(
                          resending
                              ? AppL10n.t('sms_resending')
                              : AppL10n.t('sms_resend'),
                          style: const TextStyle(
                            color: _orangePrimary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    codeCtrl.dispose();
  }

  InputDecoration _webInputDecoration({
    required String hint,
    IconData? prefixIcon,
    Widget? suffixIcon,
  }) {
    final defaultBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(
        color: _navyPrimary.withValues(alpha: 0.13),
        width: 1.4,
      ),
    );
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(
        color: _navyPrimary.withValues(alpha: 0.35),
        fontSize: 14,
      ),
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.9),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      prefixIcon: prefixIcon != null
          ? Icon(
              prefixIcon,
              size: 19,
              color: _navyPrimary.withValues(alpha: 0.45),
            )
          : null,
      suffixIcon: suffixIcon,
      border: defaultBorder,
      enabledBorder: defaultBorder,
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _orangePrimary, width: 1.6),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFEF4444), width: 1.4),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFEF4444), width: 1.6),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _pageBg,
      body: Stack(
        children: [
          // Couche 1 : Halos lumineux exacts de `.xfy-page` (orange haut-gauche + indigo bas-droite)
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: _pageBg,
                gradient: RadialGradient(
                  center: const Alignment(-0.85, -0.75),
                  radius: 1.05,
                  colors: [
                    _orangePrimary.withValues(alpha: 0.09),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0.85, 0.8),
                  radius: 1.1,
                  colors: [
                    const Color(0xFF6366F1).withValues(alpha: 0.09),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          // Couche 2 : Globe filaire 3D orange + particules flottantes (isolé dans RepaintBoundary)
          Positioned.fill(
            child: IgnorePointer(
              child: RepaintBoundary(
                child: AnimatedBuilder(
                  animation: _ambientCtrl,
                  builder: (_, _) => CustomPaint(
                    painter: _XfyGlobeParticlesPainter(
                      progress: _ambientCtrl.value,
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Couche 3 : Contenu principal
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 22),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Barre top logo xfy. + badge pulsant Web
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 42,
                                height: 42,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  boxShadow: [
                                    BoxShadow(
                                      color: _navyPrimary.withValues(alpha: 0.22),
                                      blurRadius: 10,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: Image.asset(
                                  'assets/images/logoXFY.png',
                                  width: 42,
                                  height: 42,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, _, _) => const SizedBox(),
                                ),
                              ),
                              const SizedBox(width: 9),
                              RichText(
                                text: const TextSpan(
                                  style: TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.w900,
                                    color: _navyPrimary,
                                    letterSpacing: -0.6,
                                  ),
                                  children: [
                                    TextSpan(text: 'xfy'),
                                    TextSpan(
                                      text: '.',
                                      style: TextStyle(color: Color(0xFFFF6B35)),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          _PulsingWebBadge(animation: _ambientCtrl),
                        ],
                      ),

                      const SizedBox(height: 18),

                      // Titre héro exact du Web XFY (« Connectez-vous à votre univers. »)
                      RichText(
                        text: TextSpan(
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                            color: _navyPrimary,
                            height: 1.12,
                            letterSpacing: -1.1,
                          ),
                          children: [
                            TextSpan(text: AppL10n.t('login_hero_line')),
                            const TextSpan(
                              text: '.',
                              style: TextStyle(color: _orangePrimary),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        AppL10n.t('login_hero_sub'),
                        style: TextStyle(
                          fontSize: 13.5,
                          color: _navyPrimary.withValues(alpha: 0.62),
                          height: 1.45,
                        ),
                      ),

                      const SizedBox(height: 18),

                      // Carte de connexion givrée Web (`.xfy-card`)
                      Container(
                        padding: const EdgeInsets.fromLTRB(22, 24, 22, 22),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.90),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: _navyPrimary.withValues(alpha: 0.08),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF0F172A)
                                  .withValues(alpha: 0.08),
                              blurRadius: 36,
                              offset: const Offset(0, 18),
                            ),
                            BoxShadow(
                              color: _orangePrimary.withValues(alpha: 0.05),
                              blurRadius: 32,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                AppL10n.t('login_title'),
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w900,
                                  color: _navyPrimary,
                                  letterSpacing: -0.6,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                AppL10n.t('login_subtitle'),
                                style: TextStyle(
                                  fontSize: 13,
                                  color: _navyPrimary.withValues(alpha: 0.52),
                                ),
                              ),
                              const SizedBox(height: 18),

                              if (_localError != null) ...[
                                _ErrorBanner(message: _localError!),
                                const SizedBox(height: 16),
                              ],

                              // Champ Identifiant
                              Text(
                                AppL10n.t('login_id_label'),
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.75,
                                  color: _navyPrimary.withValues(alpha: 0.6),
                                ),
                              ),
                              const SizedBox(height: 7),
                              TextFormField(
                                controller: _identifierCtrl,
                                keyboardType: TextInputType.emailAddress,
                                textInputAction: TextInputAction.next,
                                autofillHints: const [AutofillHints.username],
                                style: const TextStyle(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w600,
                                  color: _navyPrimary,
                                ),
                                decoration: _webInputDecoration(
                                  hint: AppL10n.t('login_id_hint'),
                                  prefixIcon: Icons.person_outline_rounded,
                                ),
                                validator: (v) {
                                  if (v == null || v.trim().isEmpty) {
                                    return AppL10n.t('login_id_required');
                                  }
                                  return null;
                                },
                              ),

                              const SizedBox(height: 15),

                              // Champ Mot de passe + « Oublié ? »
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    AppL10n.t('login_pw_label'),
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.75,
                                      color:
                                          _navyPrimary.withValues(alpha: 0.6),
                                    ),
                                  ),
                                  GestureDetector(
                                    onTap: _showForgotPasswordSheet,
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 2,
                                        horizontal: 2,
                                      ),
                                      child: Text(
                                        AppL10n.t('login_forgot'),
                                        style: const TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w800,
                                          color: _orangePrimary,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 7),
                              TextFormField(
                                controller: _passwordCtrl,
                                obscureText: _obscurePassword,
                                textInputAction: TextInputAction.done,
                                autofillHints: const [AutofillHints.password],
                                onFieldSubmitted: (_) => _submit(),
                                style: const TextStyle(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w600,
                                  color: _navyPrimary,
                                ),
                                decoration: _webInputDecoration(
                                  hint: '••••••••••',
                                  prefixIcon: Icons.lock_outline_rounded,
                                  suffixIcon: IconButton(
                                    icon: Icon(
                                      _obscurePassword
                                          ? Icons.visibility_outlined
                                          : Icons.visibility_off_outlined,
                                      size: 19,
                                      color:
                                          _navyPrimary.withValues(alpha: 0.45),
                                    ),
                                    onPressed: () => setState(
                                      () =>
                                          _obscurePassword = !_obscurePassword,
                                    ),
                                  ),
                                ),
                                validator: (v) {
                                  if (v == null || v.isEmpty) {
                                    return AppL10n.t('login_pw_required');
                                  }
                                  return null;
                                },
                              ),

                              const SizedBox(height: 12),

                              // Case « Se souvenir de moi » style Web orange
                              InkWell(
                                borderRadius: BorderRadius.circular(8),
                                onTap: () =>
                                    setState(() => _rememberMe = !_rememberMe),
                                child: Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 4),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      AnimatedContainer(
                                        duration:
                                            const Duration(milliseconds: 160),
                                        width: 19,
                                        height: 19,
                                        decoration: BoxDecoration(
                                          color: _rememberMe
                                              ? _orangePrimary
                                              : Colors.white,
                                          borderRadius:
                                              BorderRadius.circular(5),
                                          border: Border.all(
                                            color: _rememberMe
                                                ? _orangePrimary
                                                : _navyPrimary
                                                    .withValues(alpha: 0.25),
                                            width: 1.5,
                                          ),
                                        ),
                                        child: _rememberMe
                                            ? const Icon(
                                                Icons.check_rounded,
                                                size: 14,
                                                color: Colors.white,
                                              )
                                            : null,
                                      ),
                                      const SizedBox(width: 9),
                                      Text(
                                        AppL10n.t('login_remember'),
                                        style: TextStyle(
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.w500,
                                          color: _navyPrimary
                                              .withValues(alpha: 0.65),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),

                              const SizedBox(height: 16),

                              // Bouton principal dégradé orange XFY (`.xfy-btn-cta`)
                              ListenableBuilder(
                                listenable: widget.state,
                                builder: (_, _) {
                                  final isBusy = widget.state.isAuthLoading;
                                  return _OrangeCtaButton(
                                    label: isBusy
                                        ? AppL10n.t('login_loading')
                                        : AppL10n.t('login_cta'),
                                    loading: isBusy,
                                    showArrow: !isBusy,
                                    onPressed: isBusy ? null : _submit,
                                  );
                                },
                              ),

                              const SizedBox(height: 16),

                              // Lien inscription (`.xfy-signup`)
                              Wrap(
                                alignment: WrapAlignment.center,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Text(
                                    AppL10n.t('login_no_account'),
                                    style: TextStyle(
                                      fontSize: 13,
                                      color:
                                          _navyPrimary.withValues(alpha: 0.58),
                                    ),
                                  ),
                                  GestureDetector(
                                    onTap: () =>
                                        XfyFormatters.launchExternalWeb(
                                      'https://xfy.tn/auth/sign-up',
                                    ),
                                    child: Text(
                                      AppL10n.t('login_signup'),
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w800,
                                        color: _orangePrimary,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 18),

                      // Mini compteurs Web (`.xfy-counters`)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _MiniCounter(
                            value: '24k+',
                            label: AppL10n.t('login_users'),
                          ),
                          Container(
                            width: 1,
                            height: 28,
                            color: _navyPrimary.withValues(alpha: 0.12),
                          ),
                          _MiniCounter(
                            value: '150+',
                            label: AppL10n.t('login_countries'),
                          ),
                          Container(
                            width: 1,
                            height: 28,
                            color: _navyPrimary.withValues(alpha: 0.12),
                          ),
                          _MiniCounter(
                            value: '99.9%',
                            label: AppL10n.t('login_uptime'),
                          ),
                        ],
                      ),

                      const SizedBox(height: 14),

                      // Sélecteur rapide de langue FR / EN / العربية
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          for (final item in const [
                            ('fr', 'Français'),
                            ('en', 'English'),
                            ('ar', 'العربية'),
                          ]) ...[
                            GestureDetector(
                              onTap: () => widget.state.setLanguage(item.$1),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: widget.state.languageCode == item.$1
                                      ? _orangePrimary.withValues(alpha: 0.12)
                                      : Colors.white.withValues(alpha: 0.75),
                                  borderRadius: BorderRadius.circular(99),
                                  border: Border.all(
                                    color: widget.state.languageCode == item.$1
                                        ? _orangePrimary
                                        : _navyPrimary.withValues(alpha: 0.12),
                                  ),
                                ),
                                child: Text(
                                  item.$2,
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                    color: widget.state.languageCode == item.$1
                                        ? _orangePrimary
                                        : _navyPrimary.withValues(alpha: 0.65),
                                  ),
                                ),
                              ),
                            ),
                            if (item.$1 != 'ar') const SizedBox(width: 8),
                          ],
                        ],
                      ),

                      const SizedBox(height: 12),

                      // Barre de statut SSL (`.xfy-statusbar`)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: XfyColors.emerald,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color:
                                      XfyColors.emerald.withValues(alpha: 0.55),
                                  blurRadius: 6,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 7),
                          Text(
                            AppL10n.t('login_ssl'),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: _navyPrimary.withValues(alpha: 0.52),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PulsingWebBadge extends StatelessWidget {
  const _PulsingWebBadge({required this.animation});

  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (_, child) {
        final pulse = (math.sin(animation.value * math.pi * 16) + 1) / 2;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFFFF6B35).withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(99),
            border: Border.all(
              color: const Color(0xFFFF6B35).withValues(alpha: 0.25),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: const Color(0xFFFF6B35),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFFF6B35)
                          .withValues(alpha: 0.45 * (1 - pulse)),
                      blurRadius: 4 + 6 * pulse,
                      spreadRadius: 2 * pulse,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 7),
              child!,
            ],
          ),
        );
      },
      child: Text(
        AppL10n.t('login_badge'),
        style: const TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: Color(0xFFFF6B35),
        ),
      ),
    );
  }
}

class _OrangeCtaButton extends StatelessWidget {
  const _OrangeCtaButton({
    required this.label,
    required this.loading,
    required this.onPressed,
    this.showArrow = false,
  });

  final String label;
  final bool loading;
  final VoidCallback? onPressed;
  final bool showArrow;

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null;
    return Opacity(
      opacity: disabled ? 0.7 : 1,
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFFF6B35), Color(0xFFE85A2B)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(13),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFFF6B35).withValues(alpha: 0.42),
              blurRadius: 22,
              offset: const Offset(0, 7),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(13),
            onTap: onPressed,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (loading) ...[
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.3,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.1,
                  ),
                ),
                if (showArrow) ...[
                  const SizedBox(width: 8),
                  const Icon(
                    Icons.arrow_forward_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: BoxDecoration(
        color: const Color(0xFFEF4444).withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFFEF4444).withValues(alpha: 0.30),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            color: Color(0xFFDC2626),
            size: 18,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Color(0xFFB91C1C),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniCounter extends StatelessWidget {
  const _MiniCounter({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w900,
            color: Color(0xFF1E2847),
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 1),
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: 9.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
            color: const Color(0xFF1E2847).withValues(alpha: 0.5),
          ),
        ),
      ],
    );
  }
}

/// Peint le globe filaire 3D orange et les particules navy légères de la page Login Web XFY.
class _XfyGlobeParticlesPainter extends CustomPainter {
  _XfyGlobeParticlesPainter({required this.progress});

  final double progress;

  static final List<(double lat, double lon)> _globeNodes = List.generate(
    24,
    (i) {
      final lat = ((i * 53) % 140) - 70.0;
      final lon = (i * 37.5) % 360.0;
      return (lat, lon);
    },
  );

  @override
  void paint(Canvas canvas, Size size) {
    final rotY = progress * math.pi * 2;
    final radius = math.min(size.width, size.height) * 0.44;
    final cx = size.width * 0.52;
    final cy = size.height * 0.42;

    Offset? project(double latDeg, double lonDeg) {
      final phi = latDeg * math.pi / 180;
      final theta = lonDeg * math.pi / 180 + rotY;
      final z = radius * math.cos(phi) * math.cos(theta);
      if (z < 0) return null;
      final x = cx + radius * math.cos(phi) * math.sin(theta);
      final y = cy - radius * math.sin(phi);
      return Offset(x, y);
    }

    // Lignes de latitude (orange subtil)
    final latPaint = Paint()
      ..color = const Color(0xFFFF6B35).withValues(alpha: 0.14)
      ..strokeWidth = 0.7
      ..style = PaintingStyle.stroke;

    for (double lat = -60; lat <= 60; lat += 30) {
      final path = Path();
      bool started = false;
      for (double lon = 0; lon <= 360; lon += 15) {
        final p = project(lat, lon);
        if (p == null) {
          started = false;
          continue;
        }
        if (!started) {
          path.moveTo(p.dx, p.dy);
          started = true;
        } else {
          path.lineTo(p.dx, p.dy);
        }
      }
      canvas.drawPath(path, latPaint);
    }

    // Lignes de longitude (orange subtil)
    final lonPaint = Paint()
      ..color = const Color(0xFFFF6B35).withValues(alpha: 0.16)
      ..strokeWidth = 0.7
      ..style = PaintingStyle.stroke;

    for (double lon = 0; lon < 360; lon += 45) {
      final path = Path();
      bool started = false;
      for (double lat = -80; lat <= 80; lat += 16) {
        final p = project(lat, lon);
        if (p == null) {
          started = false;
          continue;
        }
        if (!started) {
          path.moveTo(p.dx, p.dy);
          started = true;
        } else {
          path.lineTo(p.dx, p.dy);
        }
      }
      canvas.drawPath(path, lonPaint);
    }

    // Points lumineux sur le globe
    final nodePaint = Paint()
      ..color = const Color(0xFFFF6B35).withValues(alpha: 0.32);
    final nodeGlowPaint = Paint()
      ..color = const Color(0xFFFF6B35).withValues(alpha: 0.11);

    for (final (lat, lon) in _globeNodes) {
      final p = project(lat, lon);
      if (p == null) continue;
      canvas.drawCircle(p, 4.5, nodeGlowPaint);
      canvas.drawCircle(p, 1.6, nodePaint);
    }

    // Particules flottantes navy très douces
    final particlePaint = Paint()
      ..color = const Color(0xFF1E2847).withValues(alpha: 0.08);
    for (int i = 0; i < 26; i++) {
      final bx = ((i * 97.3) % size.width + progress * (i.isEven ? 38 : -28)) %
          size.width;
      final by = ((i * 131.7) % size.height + progress * (i % 3 == 0 ? 24 : -20)) %
          size.height;
      final r = 1.0 + (i % 3) * 0.55;
      canvas.drawCircle(Offset(bx, by), r, particlePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _XfyGlobeParticlesPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
