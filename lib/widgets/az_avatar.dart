// =============================================================================
// AZ AVATAR  (NEW-K)
//
// Canonical avatar name for new code. ChatAvatar remains the implementation and
// remains source-compatible for existing call sites.
//
// When the last legacy ChatAvatar call site is migrated in a future cleanup,
// the alias can be retired separately.
// =============================================================================
import 'package:azaman/widgets/chat_avatar.dart';
export 'package:azaman/widgets/chat_avatar.dart' show ChatAvatar;

typedef AzAvatar = ChatAvatar;
