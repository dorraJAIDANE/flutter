import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart'
    show GlobalWidgetsLocalizations;
import 'package:material_ui/material_ui.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/login_screen.dart';
import 'features/shell/main_shell.dart';
import 'state/app_state.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.white,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );
  runApp(const XfyMobileApp());
}

class XfyMobileApp extends StatefulWidget {
  const XfyMobileApp({super.key});

  @override
  State<XfyMobileApp> createState() => _XfyMobileAppState();
}

class _XfyMobileAppState extends State<XfyMobileApp>
    with WidgetsBindingObserver {
  final AppState _state = AppState();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _state.bootstrap();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _state.onAppLifecycleChanged(state);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Écoute UNIQUEMENT appRootVersion (init / auth / langue) :
    // MaterialApp ne se reconstruit plus jamais lors du changement d'onglet ou du chargement des commandes !
    return ValueListenableBuilder<int>(
      valueListenable: _state.appRootVersion,
      builder: (context, _, _) {
        final locale = Locale(_state.languageCode);
        return MaterialApp(
          title: 'XFY',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          locale: locale,
          supportedLocales: const [
            Locale('fr'),
            Locale('en'),
            Locale('ar'),
          ],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          builder: (context, child) {
            return Directionality(
              textDirection:
                  _state.isRtl ? TextDirection.rtl : TextDirection.ltr,
              child: child ?? const SizedBox.shrink(),
            );
          },
          home: _state.isInitializing
              ? const _SplashView()
              : AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  child: _state.isAuthenticated
                      ? MainShell(key: const ValueKey('shell'), state: _state)
                      : LoginScreen(
                          key: const ValueKey('login'),
                          state: _state,
                        ),
                ),
        );
      },
    );
  }
}

class _SplashView extends StatelessWidget {
  const _SplashView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/images/logoXFY.png',
              height: 68,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => const Icon(
                Icons.storefront_rounded,
                size: 56,
                color: XfyColors.primary,
              ),
            ),
            const SizedBox(height: 22),
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: XfyColors.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
