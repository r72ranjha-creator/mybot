import 'dart:convert';

/// A daily token ceiling per bot role.
///
/// A limit of `0` (or less) means "no ceiling" — the app defaults to
/// unlimited so nothing changes for a user who never opens the guard. The
/// check is deliberately conservative: it refuses a plan only when the
/// estimate clearly does not fit in what is left for today, so an ordinary
/// chat is never blocked by rounding.
class TokenBudget {
  const TokenBudget({
    this.perRole = const <String, int>{},
    this.defaultDaily = 0,
  });

  /// Role id -> daily token ceiling. See [BotRole].
  final Map<String, int> perRole;

  /// Ceiling for roles without an explicit entry. `0` = unlimited.
  final int defaultDaily;

  static const int unlimited = 0;

  static const TokenBudget off = TokenBudget();

  bool get isOff {
    if (defaultDaily > 0) return false;
    return perRole.values.every((value) => value <= 0);
  }

  int limitFor(String role) {
    final explicit = perRole[role];
    if (explicit != null) return explicit;
    return defaultDaily;
  }

  bool isUnlimited(String role) => limitFor(role) <= 0;

  /// Tokens still available today, or `-1` when the role is unlimited.
  int remaining(String role, int usedToday) {
    final limit = limitFor(role);
    if (limit <= 0) return -1;
    final left = limit - usedToday;
    return left < 0 ? 0 : left;
  }

  /// Whether a plan estimated at [estimatedTokens] may start now.
  TokenDecision check(
    String role, {
    required int usedToday,
    required int estimatedTokens,
  }) {
    final limit = limitFor(role);
    if (limit <= 0) {
      return TokenDecision(
        allowed: true,
        role: role,
        limit: 0,
        usedToday: usedToday,
        estimatedTokens: estimatedTokens,
      );
    }
    if (usedToday >= limit) {
      return TokenDecision(
        allowed: false,
        role: role,
        limit: limit,
        usedToday: usedToday,
        estimatedTokens: estimatedTokens,
        reason: 'Today\'s budget for $role is used up ($usedToday of $limit).',
      );
    }
    if (usedToday + estimatedTokens > limit) {
      final left = limit - usedToday;
      return TokenDecision(
        allowed: false,
        role: role,
        limit: limit,
        usedToday: usedToday,
        estimatedTokens: estimatedTokens,
        reason: 'This looks like about $estimatedTokens tokens but only $left '
            'are left in today\'s $role budget.',
      );
    }
    return TokenDecision(
      allowed: true,
      role: role,
      limit: limit,
      usedToday: usedToday,
      estimatedTokens: estimatedTokens,
    );
  }

  TokenBudget withRole(String role, int dailyLimit) {
    final next = Map<String, int>.from(perRole);
    if (dailyLimit <= 0) {
      next.remove(role);
    } else {
      next[role] = dailyLimit;
    }
    return TokenBudget(perRole: next, defaultDaily: defaultDaily);
  }

  Map<String, Object?> toJson() => {
        'perRole': perRole,
        'defaultDaily': defaultDaily,
      };

  factory TokenBudget.fromJson(Map<String, Object?> json) {
    final raw = json['perRole'];
    final perRole = <String, int>{};
    if (raw is Map) {
      raw.forEach((key, value) {
        if (key is String && value is num) {
          final limit = value.toInt();
          if (limit > 0) perRole[key] = limit;
        }
      });
    }
    return TokenBudget(
      perRole: perRole,
      defaultDaily: (json['defaultDaily'] as num?)?.toInt() ?? 0,
    );
  }

  String encode() => jsonEncode(toJson());

  /// Never throws: a corrupted stored value falls back to "off".
  factory TokenBudget.decode(String? raw) {
    if (raw == null || raw.trim().isEmpty) return TokenBudget.off;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) return TokenBudget.fromJson(decoded.cast<String, Object?>());
    } catch (_) {
      // fall through
    }
    return TokenBudget.off;
  }

  static const String storageKey = 'token_budget';
}

class TokenDecision {
  const TokenDecision({
    required this.allowed,
    required this.role,
    required this.limit,
    required this.usedToday,
    required this.estimatedTokens,
    this.reason,
  });

  final bool allowed;
  final String role;
  final int limit;
  final int usedToday;
  final int estimatedTokens;
  final String? reason;

  bool get unlimited => limit <= 0;
}

/// Rough token estimate for a prompt, without a tokenizer on the phone.
/// Four characters per token is close enough for a guard that only needs to
/// catch a plan that is obviously far too large.
int estimateTokens(String text) {
  if (text.isEmpty) return 0;
  return (text.length / 4).ceil();
}

/// The estimate for a whole plan: the user's request plus every step's
/// instruction plus the answer the merge step will need to write.
int estimatePlanTokens(String input, List<String> stepInstructions) {
  var total = estimateTokens(input);
  for (final instruction in stepInstructions) {
    total += estimateTokens(instruction);
  }
  // Room for the final merged answer.
  total += 600;
  return total;
}
