import 'package:ads_admin_panel/app_theme.dart';
import 'package:ads_admin_panel/config/supabase_config.dart';
import 'package:ads_admin_panel/screens/auth_screen.dart';
import 'package:ads_admin_panel/screens/home_screen.dart';
import 'package:flutter/material.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await SupabaseConfig.initialize();
  } catch (e) {
    debugPrint('Failed to initialize Supabase: $e');
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MVC Admin Panel',
      theme: AppTheme.lightTheme,
      debugShowCheckedModeBanner: false,
      home: const AuthWrapper(),
    );
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return SupabaseConfig.isAuthenticated ? const HomeScreen() : const AuthScreen();
  }
}
