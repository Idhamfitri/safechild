// lib/utils/app_utils.dart

class AppUtils {
  /// Converts an Android package name into a human-readable app name.
  static String getFriendlyAppName(String packageName) {
    final pkg = packageName.toLowerCase();
    
    if (pkg.contains('whatsapp')) return 'WhatsApp';
    if (pkg.contains('chrome')) return 'Chrome';
    if (pkg.contains('instagram')) return 'Instagram';
    if (pkg.contains('tiktok') || pkg.contains('trill')) return 'TikTok';
    if (pkg.contains('telegram')) return 'Telegram';
    if (pkg.contains('youtube')) return 'YouTube';
    if (pkg.contains('facebook')) {
      if (pkg.contains('orca')) return 'Messenger';
      return 'Facebook';
    }
    if (pkg.contains('twitter') || pkg.contains('x.com')) return 'X / Twitter';
    if (pkg.contains('snapchat')) return 'Snapchat';
    if (pkg.contains('discord')) return 'Discord';
    if (pkg.contains('reddit')) return 'Reddit';
    if (pkg.contains('netflix')) return 'Netflix';
    if (pkg.contains('spotify')) return 'Spotify';
    
    final parts = packageName.split('.');
    if (parts.isNotEmpty) {
      final lastPart = parts.last;
      if (lastPart.isNotEmpty) {
        return lastPart[0].toUpperCase() + lastPart.substring(1);
      }
    }
    return packageName;
  }
}
