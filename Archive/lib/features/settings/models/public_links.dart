class PublicLinks {
  static const shop = 'https://www.hajecamell.store/shop';
  static const agent = 'https://www.hajecamell.store/agent';
  static const photos = 'https://www.hajecamell.store/photos';
  static const follow = 'https://www.hajecamell.store/follow';

  final String shopUrl;
  final String agentUrl;
  final String photosUrl;
  final String followUrl;

  const PublicLinks({
    this.shopUrl = shop,
    this.agentUrl = agent,
    this.photosUrl = photos,
    this.followUrl = follow,
  });

  static PublicLinks fromSettings(Object? settings) {
    final root = settings is Map ? settings['public_links'] : null;
    String read(String key, String fallback) {
      if (root is! Map) return fallback;
      final value = '${root[key] ?? ''}'.trim();
      return value.isEmpty ? fallback : value;
    }

    return PublicLinks(
      shopUrl: read('shop', shop),
      agentUrl: read('agent', agent),
      photosUrl: read('photos', photos),
      followUrl: read('follow', follow),
    );
  }

  Map<String, String> toSettings() {
    return {
      'shop': shopUrl,
      'agent': agentUrl,
      'photos': photosUrl,
      'follow': followUrl,
    };
  }
}
