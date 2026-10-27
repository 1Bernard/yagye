# frozen_string_literal: true

# Value object passed from InvitationsController to AcceptView and related views.
# Provides a uniform interface regardless of whether the invitation is for a
# merchant user (token on MerchantMembership) or internal staff (token on User).
InvitationContext = Struct.new(
  :user,             # User being invited
  :invited_by_name,  # Full name of the person who sent the invite
  :expires_at,       # Token expiry timestamp
  :context_name,     # Merchant name for merchant invites; "Yagye Operations" for staff
  :is_staff,         # true for internal staff invites
  keyword_init: true
)
