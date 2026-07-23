// =============================================================================
// Storefront SDUI Models
//
// Data models for the Server-Driven UI storefront system.
// Mirrors the backend Prisma models for themes, widgets, layouts, and stakes.
// =============================================================================

import 'dart:convert';

// ── Enums ────────────────────────────────────────────────────────────────────

enum StorefrontTier { FREE, NITRO_BRONZE, NITRO_SILVER, NITRO_GOLD }

enum StorefrontLayoutStatus { DRAFT, PUBLISHED }

enum StorefrontWidgetCategory { HEADER, CONTENT, COMMERCE, MEDIA, SOCIAL }

enum AzmStakeStatus { ACTIVE, UNSTAKING, COMPLETED }

// ── Theme ────────────────────────────────────────────────────────────────────

class StorefrontTheme {
  final String id;
  final String key;
  final String name;
  final String? description;
  final StorefrontTier tier;
  final int minAzmStake;
  final String? category;
  final ThemeTokenSet? tokenSet;
  final Map<String, dynamic>? typography;
  final String? borderRadius;
  final double? spacingScale;
  final bool isActive;
  final int displayOrder;

  StorefrontTheme({
    required this.id,
    required this.key,
    required this.name,
    this.description,
    required this.tier,
    required this.minAzmStake,
    this.category,
    this.tokenSet,
    this.typography,
    this.borderRadius,
    this.spacingScale,
    this.isActive = true,
    this.displayOrder = 0,
  });

  factory StorefrontTheme.fromJson(Map<String, dynamic> json) {
    return StorefrontTheme(
      id: json['id'] ?? '',
      key: json['key'] ?? '',
      name: json['name'] ?? '',
      description: json['description'],
      tier: StorefrontTier.values.firstWhere(
        (e) => e.name == json['tier'],
        orElse: () => StorefrontTier.FREE,
      ),
      minAzmStake: json['minAzmStake'] ?? 0,
      category: json['category'],
      tokenSet: json['tokenSet'] != null
          ? ThemeTokenSet.fromJson(json['tokenSet'])
          : null,
      typography: json['typography'] != null
          ? Map<String, dynamic>.from(json['typography'])
          : null,
      borderRadius: json['borderRadius'],
      spacingScale: (json['spacingScale'] ?? 1.0).toDouble(),
      isActive: json['isActive'] ?? true,
      displayOrder: json['displayOrder'] ?? 0,
    );
  }
}

class ThemeTokenSet {
  final String? background;
  final String? surface;
  final String? surfaceSolid;
  final String? border;
  final String? textPrimary;
  final String? textSecondary;
  final String? textMuted;
  final String accent;
  final String? accentHover;
  final String? success;
  final String? warning;
  final String? danger;
  final String? info;

  ThemeTokenSet({
    this.background,
    this.surface,
    this.surfaceSolid,
    this.border,
    this.textPrimary,
    this.textSecondary,
    this.textMuted,
    required this.accent,
    this.accentHover,
    this.success,
    this.warning,
    this.danger,
    this.info,
  });

  factory ThemeTokenSet.fromJson(Map<String, dynamic> json) {
    return ThemeTokenSet(
      background: json['background'],
      surface: json['surface'],
      surfaceSolid: json['surfaceSolid'],
      border: json['border'],
      textPrimary: json['textPrimary'],
      textSecondary: json['textSecondary'],
      textMuted: json['textMuted'],
      accent: json['accent'] ?? '#6C4FD1',
      accentHover: json['accentHover'],
      success: json['success'],
      warning: json['warning'],
      danger: json['danger'],
      info: json['info'],
    );
  }
}

// ── Widget Catalog ───────────────────────────────────────────────────────────

class StorefrontWidget {
  final String id;
  final String widgetType;
  final String displayName;
  final String? description;
  final StorefrontTier tier;
  final int minAzmStake;
  final String? category;
  final String? icon;
  final Map<String, dynamic>? configSchema;
  final Map<String, dynamic>? defaultProps;
  final int minRowSpan;
  final int maxRowSpan;
  final int minColSpan;
  final int maxColSpan;
  final bool isActive;
  final int displayOrder;

  StorefrontWidget({
    required this.id,
    required this.widgetType,
    required this.displayName,
    this.description,
    required this.tier,
    required this.minAzmStake,
    this.category,
    this.icon,
    this.configSchema,
    this.defaultProps,
    this.minRowSpan = 1,
    this.maxRowSpan = 6,
    this.minColSpan = 2,
    this.maxColSpan = 4,
    this.isActive = true,
    this.displayOrder = 0,
  });

  factory StorefrontWidget.fromJson(Map<String, dynamic> json) {
    return StorefrontWidget(
      id: json['id'] ?? '',
      widgetType: json['widgetType'] ?? '',
      displayName: json['displayName'] ?? '',
      description: json['description'],
      tier: StorefrontTier.values.firstWhere(
        (e) => e.name == json['tier'],
        orElse: () => StorefrontTier.FREE,
      ),
      minAzmStake: json['minAzmStake'] ?? 0,
      category: json['category'],
      icon: json['icon'],
      configSchema: json['configSchema'] != null
          ? Map<String, dynamic>.from(json['configSchema'])
          : null,
      defaultProps: json['defaultProps'] != null
          ? Map<String, dynamic>.from(json['defaultProps'])
          : null,
      minRowSpan: json['minRowSpan'] ?? 1,
      maxRowSpan: json['maxRowSpan'] ?? 6,
      minColSpan: json['minColSpan'] ?? 2,
      maxColSpan: json['maxColSpan'] ?? 4,
      isActive: json['isActive'] ?? true,
      displayOrder: json['displayOrder'] ?? 0,
    );
  }
}

// ── Layout ───────────────────────────────────────────────────────────────────

class StorefrontLayout {
  final String? id;
  final String? businessProfileId;
  final StorefrontLayoutStatus status;
  final String? themeId;
  final StorefrontTheme? theme;
  final LayoutJson layoutJson;
  final DateTime? publishedAt;
  final String? publishedBy;
  final DateTime? updatedAt;

  StorefrontLayout({
    this.id,
    this.businessProfileId,
    required this.status,
    this.themeId,
    this.theme,
    required this.layoutJson,
    this.publishedAt,
    this.publishedBy,
    this.updatedAt,
  });

  factory StorefrontLayout.fromJson(Map<String, dynamic> json) {
    return StorefrontLayout(
      id: json['id'],
      businessProfileId: json['businessProfileId'],
      status: StorefrontLayoutStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => StorefrontLayoutStatus.DRAFT,
      ),
      themeId: json['themeId'],
      theme: json['theme'] != null
          ? StorefrontTheme.fromJson(json['theme'])
          : null,
      layoutJson: LayoutJson.fromJson(json['layoutJson'] ?? {}),
      publishedAt: json['publishedAt'] != null
          ? DateTime.parse(json['publishedAt'])
          : null,
      publishedBy: json['publishedBy'],
      updatedAt: json['updatedAt'] != null
          ? DateTime.parse(json['updatedAt'])
          : null,
    );
  }
}

class LayoutJson {
  final int schemaVersion;
  final int gridColumns;
  final List<LayoutTile> tiles;

  LayoutJson({
    this.schemaVersion = 1,
    this.gridColumns = 4,
    this.tiles = const [],
  });

  factory LayoutJson.fromJson(Map<String, dynamic> json) {
    return LayoutJson(
      schemaVersion: json['schemaVersion'] ?? 1,
      gridColumns: json['gridColumns'] ?? 4,
      tiles: (json['tiles'] as List<dynamic>?)
              ?.map((t) => LayoutTile.fromJson(t as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'schemaVersion': schemaVersion,
      'gridColumns': gridColumns,
      'tiles': tiles.map((t) => t.toJson()).toList(),
    };
  }
}

class LayoutTile {
  final String id;
  final String widgetType;
  final TilePosition position;
  final Map<String, dynamic> props;

  LayoutTile({
    required this.id,
    required this.widgetType,
    required this.position,
    this.props = const {},
  });

  factory LayoutTile.fromJson(Map<String, dynamic> json) {
    return LayoutTile(
      id: json['id'] ?? '',
      widgetType: json['widgetType'] ?? '',
      position: TilePosition.fromJson(json['position'] ?? {}),
      props: json['props'] != null
          ? Map<String, dynamic>.from(json['props'])
          : {},
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'widgetType': widgetType,
      'position': position.toJson(),
      'props': props,
    };
  }
}

class TilePosition {
  final int row;
  final int col;
  final int rowSpan;
  final int colSpan;

  TilePosition({
    this.row = 0,
    this.col = 0,
    this.rowSpan = 1,
    this.colSpan = 4,
  });

  factory TilePosition.fromJson(Map<String, dynamic> json) {
    return TilePosition(
      row: json['row'] ?? 0,
      col: json['col'] ?? 0,
      rowSpan: json['rowSpan'] ?? 1,
      colSpan: json['colSpan'] ?? 4,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'row': row,
      'col': col,
      'rowSpan': rowSpan,
      'colSpan': colSpan,
    };
  }
}

// ── Layout Version ───────────────────────────────────────────────────────────

class StorefrontLayoutVersion {
  final String id;
  final String businessProfileId;
  final int version;
  final String? themeId;
  final StorefrontTheme? theme;
  final LayoutJson layoutJson;
  final DateTime? publishedAt;
  final String? publishedBy;

  StorefrontLayoutVersion({
    required this.id,
    required this.businessProfileId,
    required this.version,
    this.themeId,
    this.theme,
    required this.layoutJson,
    this.publishedAt,
    this.publishedBy,
  });

  factory StorefrontLayoutVersion.fromJson(Map<String, dynamic> json) {
    return StorefrontLayoutVersion(
      id: json['id'] ?? '',
      businessProfileId: json['businessProfileId'] ?? '',
      version: json['version'] ?? 0,
      themeId: json['themeId'],
      theme: json['theme'] != null
          ? StorefrontTheme.fromJson(json['theme'])
          : null,
      layoutJson: LayoutJson.fromJson(json['layoutJson'] ?? {}),
      publishedAt: json['publishedAt'] != null
          ? DateTime.parse(json['publishedAt'])
          : null,
      publishedBy: json['publishedBy'],
    );
  }
}

// ── Layout Template ──────────────────────────────────────────────────────────

class StorefrontLayoutTemplate {
  final String id;
  final String name;
  final String? description;
  final String? category;
  final StorefrontTier tier;
  final int minAzmStake;
  final String? themeId;
  final StorefrontTheme? theme;
  final LayoutJson layoutJson;
  final bool isActive;
  final int displayOrder;

  StorefrontLayoutTemplate({
    required this.id,
    required this.name,
    this.description,
    this.category,
    required this.tier,
    required this.minAzmStake,
    this.themeId,
    this.theme,
    required this.layoutJson,
    this.isActive = true,
    this.displayOrder = 0,
  });

  factory StorefrontLayoutTemplate.fromJson(Map<String, dynamic> json) {
    return StorefrontLayoutTemplate(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      description: json['description'],
      category: json['category'],
      tier: StorefrontTier.values.firstWhere(
        (e) => e.name == json['tier'],
        orElse: () => StorefrontTier.FREE,
      ),
      minAzmStake: json['minAzmStake'] ?? 0,
      themeId: json['themeId'],
      theme: json['theme'] != null
          ? StorefrontTheme.fromJson(json['theme'])
          : null,
      layoutJson: LayoutJson.fromJson(json['layoutJson'] ?? {}),
      isActive: json['isActive'] ?? true,
      displayOrder: json['displayOrder'] ?? 0,
    );
  }
}

// ── AZM Stake ────────────────────────────────────────────────────────────────

class AzmStake {
  final String id;
  final String userId;
  final double amountAzm;
  final AzmStakeStatus status;
  final String tierAtStake;
  final int cooldownDays;
  final DateTime stakedAt;
  final DateTime? unstakeRequestedAt;
  final DateTime? unstakeAvailableAt;
  final DateTime? completedAt;

  AzmStake({
    required this.id,
    required this.userId,
    required this.amountAzm,
    required this.status,
    required this.tierAtStake,
    required this.cooldownDays,
    required this.stakedAt,
    this.unstakeRequestedAt,
    this.unstakeAvailableAt,
    this.completedAt,
  });

  factory AzmStake.fromJson(Map<String, dynamic> json) {
    return AzmStake(
      id: json['id'] ?? '',
      userId: json['userId'] ?? '',
      amountAzm: (json['amountAzm'] ?? 0).toDouble(),
      status: AzmStakeStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => AzmStakeStatus.ACTIVE,
      ),
      tierAtStake: json['tierAtStake'] ?? 'FREE',
      cooldownDays: json['cooldownDays'] ?? 7,
      stakedAt: json['stakedAt'] != null
          ? DateTime.parse(json['stakedAt'])
          : DateTime.now(),
      unstakeRequestedAt: json['unstakeRequestedAt'] != null
          ? DateTime.parse(json['unstakeRequestedAt'])
          : null,
      unstakeAvailableAt: json['unstakeAvailableAt'] != null
          ? DateTime.parse(json['unstakeAvailableAt'])
          : null,
      completedAt: json['completedAt'] != null
          ? DateTime.parse(json['completedAt'])
          : null,
    );
  }
}

// ── Render Response ──────────────────────────────────────────────────────────

class StorefrontRenderResponse {
  final StorefrontBusinessInfo business;
  final StorefrontThemeInfo theme;
  final RenderLayout layout;
  final DateTime? publishedAt;

  StorefrontRenderResponse({
    required this.business,
    required this.theme,
    required this.layout,
    this.publishedAt,
  });

  factory StorefrontRenderResponse.fromJson(Map<String, dynamic> json) {
    return StorefrontRenderResponse(
      business: StorefrontBusinessInfo.fromJson(json['business'] ?? {}),
      theme: StorefrontThemeInfo.fromJson(json['theme'] ?? {}),
      layout: RenderLayout.fromJson(json['layout'] ?? {}),
      publishedAt: json['publishedAt'] != null
          ? DateTime.parse(json['publishedAt'])
          : null,
    );
  }
}

class StorefrontBusinessInfo {
  final String name;
  final String? category;
  final String? logoUrl;
  final String? coverPhotoUrl;
  final double? averageRating;
  final String? phoneNumber;

  StorefrontBusinessInfo({
    required this.name,
    this.category,
    this.logoUrl,
    this.coverPhotoUrl,
    this.averageRating,
    this.phoneNumber,
  });

  factory StorefrontBusinessInfo.fromJson(Map<String, dynamic> json) {
    return StorefrontBusinessInfo(
      name: json['name'] ?? '',
      category: json['category'],
      logoUrl: json['logoUrl'],
      coverPhotoUrl: json['coverPhotoUrl'],
      averageRating: json['averageRating'] != null
          ? (json['averageRating'] as num).toDouble()
          : null,
      phoneNumber: json['phoneNumber'],
    );
  }
}

class StorefrontThemeInfo {
  final String id;
  final String key;
  final String name;
  final ThemeTokenSet? tokenSet;
  final Map<String, dynamic>? typography;
  final String? borderRadius;
  final double? spacingScale;

  StorefrontThemeInfo({
    required this.id,
    required this.key,
    required this.name,
    this.tokenSet,
    this.typography,
    this.borderRadius,
    this.spacingScale,
  });

  factory StorefrontThemeInfo.fromJson(Map<String, dynamic> json) {
    return StorefrontThemeInfo(
      id: json['id'] ?? '',
      key: json['key'] ?? '',
      name: json['name'] ?? '',
      tokenSet: json['tokenSet'] != null
          ? ThemeTokenSet.fromJson(json['tokenSet'])
          : null,
      typography: json['typography'] != null
          ? Map<String, dynamic>.from(json['typography'])
          : null,
      borderRadius: json['borderRadius'],
      spacingScale: (json['spacingScale'] ?? 1.0).toDouble(),
    );
  }
}

class RenderLayout {
  final int schemaVersion;
  final int gridColumns;
  final List<RenderTile> tiles;

  RenderLayout({
    this.schemaVersion = 1,
    this.gridColumns = 4,
    this.tiles = const [],
  });

  factory RenderLayout.fromJson(Map<String, dynamic> json) {
    return RenderLayout(
      schemaVersion: json['schemaVersion'] ?? 1,
      gridColumns: json['gridColumns'] ?? 4,
      tiles: (json['tiles'] as List<dynamic>?)
              ?.map((t) => RenderTile.fromJson(t as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}

class RenderTile {
  final String id;
  final String widgetType;
  final TilePosition position;
  final Map<String, dynamic> props;

  RenderTile({
    required this.id,
    required this.widgetType,
    required this.position,
    this.props = const {},
  });

  factory RenderTile.fromJson(Map<String, dynamic> json) {
    return RenderTile(
      id: json['id'] ?? '',
      widgetType: json['widgetType'] ?? '',
      position: TilePosition.fromJson(json['position'] ?? {}),
      props: json['props'] != null
          ? Map<String, dynamic>.from(json['props'])
          : {},
    );
  }
}

// ── Eligibility ──────────────────────────────────────────────────────────────

class StorefrontEligibility {
  final double stakedBalance;
  final StorefrontTier tier;
  final bool storefrontDisabled;

  StorefrontEligibility({
    required this.stakedBalance,
    required this.tier,
    required this.storefrontDisabled,
  });

  factory StorefrontEligibility.fromJson(Map<String, dynamic> json) {
    return StorefrontEligibility(
      stakedBalance: (json['stakedBalance'] ?? 0).toDouble(),
      tier: StorefrontTier.values.firstWhere(
        (e) => e.name == json['tier'],
        orElse: () => StorefrontTier.FREE,
      ),
      storefrontDisabled: json['storefrontDisabled'] ?? false,
    );
  }
}
