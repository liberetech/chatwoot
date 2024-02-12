class Mailbox::ConversationFinderStrategies::NewConversationStrategy < Mailbox::ConversationFinderStrategies::BaseStrategy
  include MailboxHelper
  include IncomingEmailValidityHelper

  attr_accessor :processed_mail, :account, :inbox, :contact, :contact_inbox, :conversation, :channel

  def initialize(mail)
    super(mail)
    @channel = EmailChannelFinder.new(mail).perform
    return unless @channel

    @account = @channel.account
    @inbox = @channel.inbox
    @processed_mail = MailPresenter.new(mail, @account)
  end

  # This strategy prepares a new conversation but doesn't persist it yet.
  # Why we don't use create! here:
  # - Avoids orphan conversations if message/attachment creation fails later
  # - Prevents duplicate conversations on job retry (no idempotency issue)
  # - Follows the pattern from old SupportMailbox where everything was in one transaction
  # The actual persistence happens in ReplyMailbox within a transaction that includes message creation.
  def find
    return nil unless @channel # No valid channel found
    return nil unless incoming_email_from_valid_email? # Skip edge cases

    # Check if conversation already exists by in_reply_to
    existing_conversation = find_conversation_by_in_reply_to
    return existing_conversation if existing_conversation

    # Prepare contact (persisted) and build conversation (not persisted)
    find_or_create_contact
    build_conversation
  end

  private

  def find_or_create_contact
    @contact = @inbox.contacts.from_email(original_sender_email)
    if @contact.present?
      @contact_inbox = ContactInbox.find_by(inbox: @inbox, contact: @contact)
    else
      create_contact
    end
  end

  def original_sender_email
    @processed_mail.original_sender&.downcase
  end

  def identify_contact_name
    @processed_mail.sender_name || @processed_mail.from.first.split('@').first
  end

  def build_conversation
    # Build but don't persist - ReplyMailbox will save in transaction with message
    @conversation = ::Conversation.new(
      account_id: @account.id,
      inbox_id: @inbox.id,
      contact_id: @contact.id,
      contact_inbox_id: @contact_inbox.id,
      additional_attributes: {
        in_reply_to: in_reply_to,
        source: 'email',
        auto_reply: @processed_mail.auto_reply?,
        mail_subject: @processed_mail.subject,
        initiated_at: {
          timestamp: Time.now.utc
        }
      }
    )
  end

  BOOKING_CHAT_GROUPING = /(\d+)-.+@mchat.booking.com/

  def booking_grouping_key
    grouping_key = @processed_mail.from.map { |f| BOOKING_CHAT_GROUPING.match(f) }.find(&:itself)
    "#{grouping_key[1]}@mchat.booking.com" if grouping_key
  end

  AIRBNB_CHAT = /.+@reply.airbnb.com>/

  def airbnb_grouping_key
    # Airbnb subject looks like 'Re: Reserva en Estudio para el 27 de enero de 2024 - 28 de enero de 2024'
    # We need a combination of subject and inhabitant's name
    # since reply-to email ("Pepe (Airbnb)" <4z8kvv4vb0duoemgwzhdax39vft4s1rznedx@reply.airbnb.com>) changes on each message
    reply_to = mail['Reply-To'].try(:value)
    return nil unless reply_to

    airbnb_match = AIRBNB_CHAT.match(reply_to)
    return unless airbnb_match && @processed_mail.sender_name && @processed_mail.subject

    "[#{@processed_mail.sender_name}@reply.airbnb.com] #{@processed_mail.subject}"
  end

  def in_reply_to
    mail['In-Reply-To'].try(:value) || booking_grouping_key || airbnb_grouping_key
  end

  def find_conversation_by_in_reply_to
    return if in_reply_to.blank?

    @account.conversations.where("additional_attributes->>'in_reply_to' = ?", in_reply_to).first
  end
end
