// =============================================================================
// AZAMAN — GATEWAYS: CAPABILITY-AWARE RESULT
//
// Typed interfaces sit where backend support is missing, real services where
// it exists. `AzUnsupported` lets UI *hide* an action instead of rendering a
// dead button (brief §13 "Do not build dead buttons").
// =============================================================================

/// A capability-aware result.
sealed class AzGatewayResult<T> {
  const AzGatewayResult();
}

/// The operation succeeded.
class AzOk<T> extends AzGatewayResult<T> {
  final T value;
  const AzOk(this.value);
}

/// The operation is supported but failed at runtime (network, 4xx/5xx, …).
class AzFailed<T> extends AzGatewayResult<T> {
  final String message;
  final Object? cause;
  const AzFailed(this.message, {this.cause});
}

/// The operation is not available on this backend. [reason] names the exact
/// missing capability (e.g. `'POST /stories/:id/react'`) so it can be surfaced
/// in diagnostics and in the gateway's `capabilities` set.
class AzUnsupported<T> extends AzGatewayResult<T> {
  final String reason;
  const AzUnsupported(this.reason);
}

extension AzGatewayResultX<T> on AzGatewayResult<T> {
  T? get valueOrNull => switch (this) {
        AzOk<T>(:final value) => value,
        _ => null,
      };

  bool get isOk => this is AzOk<T>;
  bool get isFailed => this is AzFailed<T>;
  bool get isUnsupported => this is AzUnsupported<T>;

  /// Human-readable failure/unsupported reason, or null when ok.
  String? get errorMessage => switch (this) {
        AzOk<T>() => null,
        AzFailed<T>(:final message) => message,
        AzUnsupported<T>(:final reason) => reason,
      };

  /// Transforms the success value, preserving failure/unsupported as-is.
  AzGatewayResult<R> map<R>(R Function(T value) f) => switch (this) {
        AzOk<T>(:final value) => AzOk<R>(f(value)),
        AzFailed<T>(:final message, :final cause) =>
          AzFailed<R>(message, cause: cause),
        AzUnsupported<T>(:final reason) => AzUnsupported<R>(reason),
      };
}