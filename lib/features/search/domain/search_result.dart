import '../../campaigns/data/campaign_repository.dart' show Campaign;
import '../../contacts/domain/contact.dart';
import '../../inbox/domain/conversation.dart';

/// Which slice of the workspace a search covers — the scope chips on 281:2.
enum SearchScope {
  all,
  chats,
  contacts,
  campaigns;

  /// Whether this scope includes [slice]. `all` merges the other three, so the
  /// fan-out asks the scope instead of repeating that special case at every
  /// call site.
  bool covers(SearchScope slice) => this == SearchScope.all || this == slice;
}

/// One row of the merged result list.
///
/// The three slices render differently — a chat carries a timestamp, a contact
/// a phone number, a campaign a status pill — but the frame's result count is a
/// single total, so they have to live in one ordered list. A sealed union keeps
/// the per-slice difference in one exhaustive switch at the render site rather
/// than in three parallel lists the heading would then have to add up by hand.
sealed class SearchResult {
  const SearchResult();
}

final class ChatResult extends SearchResult {
  const ChatResult(this.conversation);

  final Conversation conversation;
}

final class ContactResult extends SearchResult {
  const ContactResult(this.contact);

  final Contact contact;
}

final class CampaignResult extends SearchResult {
  const CampaignResult(this.campaign);

  final Campaign campaign;
}
