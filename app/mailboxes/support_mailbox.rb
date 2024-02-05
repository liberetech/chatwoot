class SupportMailbox < ApplicationMailbox
  attr_accessor :channel, :account, :inbox, :conversation, :processed_mail

  before_processing :find_channel,
                    :load_account,
                    :load_inbox,
                    :decorate_mail

  def process
    # to turn off spam conversation creation
    return unless @account.active?
    # prevent loop from chatwoot notification emails
    return if notification_email_from_chatwoot?

    ActiveRecord::Base.transaction do
      find_or_create_contact
      find_or_create_conversation
      create_message
      add_attachments_to_message
    end
  end

  private

  def find_channel
    find_channel_with_to_mail if @channel.blank?

    raise 'Email channel/inbox not found' if @channel.nil?

    @channel
  end

  def find_channel_with_to_mail
    @channel = EmailChannelFinder.new(mail).perform
  end

  def load_account
    @account = @channel.account
  end

  def load_inbox
    @inbox = @channel.inbox
  end

  def decorate_mail
    @processed_mail = MailPresenter.new(mail, @account)
  end

  def find_conversation_by_in_reply_to
    return if in_reply_to.blank?

    @account.conversations.where("additional_attributes->>'in_reply_to' = ?", in_reply_to).first
  end

  BOOKING_CHAT_GROUPING = /(\d+)-.+@mchat.booking.com/

  def in_reply_to
    in_reply_to = mail['In-Reply-To'].try(:value)
    return in_reply_to if in_reply_to

    grouping_key = @processed_mail.from.map { |f| BOOKING_CHAT_GROUPING.match(f) }.find(&:itself)
    return "#{grouping_key[1]}@mchat.booking.com" if grouping_key

    nil
  end

  def find_or_create_conversation
    @conversation = find_conversation_by_in_reply_to || ::Conversation.create!({
                                                                                 account_id: @account.id,
                                                                                 inbox_id: @inbox.id,
                                                                                 contact_id: @contact.id,
                                                                                 contact_inbox_id: @contact_inbox.id,
                                                                                 additional_attributes: {
                                                                                   in_reply_to: in_reply_to,
                                                                                   source: 'email',
                                                                                   mail_subject: @processed_mail.subject,
                                                                                   initiated_at: {
                                                                                     timestamp: Time.now.utc
                                                                                   }
                                                                                 }
                                                                               })
  end

  def find_or_create_contact
    @contact = @inbox.contacts.find_by(email: @processed_mail.original_sender&.downcase)
    if @contact.present?
      @contact_inbox = ContactInbox.find_by(inbox: @inbox, contact: @contact)
    else
      create_contact
    end
  end

  def identify_contact_name
    processed_mail.sender_name || processed_mail.from.first.split('@').first
  end
end
