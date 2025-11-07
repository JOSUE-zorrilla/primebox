class AppVersion {
  // Lee en tiempo de compilación, no requiere async ni plugins.
  static const String value =
      String.fromEnvironment('APP_VERSION', defaultValue: '500.0.0');
}
