enum Flavor {
  development,
  production,
}

class FlavorConfig {
  static Flavor? appFlavor;

  static String get name => appFlavor?.name ?? '';

  static String get title {
    switch (appFlavor) {
      case Flavor.development:
        return 'MVC Dev';
      case Flavor.production:
        return 'MVC';
      default:
        return 'title';
    }
  }

  static String get supabaseEnvironment {
    switch (appFlavor) {
      case Flavor.development:
        return 'qa';
      case Flavor.production:
        return 'prod';
      default:
        return 'prod';
    }
  }

  static bool get isDevelopment => appFlavor == Flavor.development;
  static bool get isProduction => appFlavor == Flavor.production;
}
