class SupportMailbox < ApplicationMailbox
  attr_accessor :channel, :account, :inbox, :conversation, :processed_mail

  before_processing :find_channel,
                    :load_account,
                    :load_inbox,
                    :decorate_mail

  def process
    Rails.logger.info "Processing email #{mail.message_id} from #{original_sender_email} to #{mail.to} with subject #{mail.subject}"

    # to turn off spam conversation creation
    return unless @account.active?
    # prevent loop from chatwoot notification emails
    return if notification_email_from_chatwoot?

    # return if email doesn't have a valid sender
    # This can happen in cases like bounce emails for invalid contact email address
    # TODO: Handle the bounce seperately and mark the contact as invalid
    # we are checking for @ since the returned value could be "\"\"" for some email clients
    return unless original_sender_email.include?('@')

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
  def booking_grouping_key
    grouping_key = @processed_mail.from.map { |f| BOOKING_CHAT_GROUPING.match(f) }.find(&:itself)
    "#{grouping_key[1]}@mchat.booking.com" if grouping_key
  end

  AIRBNB_REPLYTO_NAME = /"([^"]+)\s+\(.+@reply.airbnb.com>/
  def airbnb_grouping_key
    # Airbnb subject looks like 'Re: Reserva en Estudio para el 27 de enero de 2024 - 28 de enero de 2024'
    # We need a combination of subject and inhabitants name
    # since reply-to email ("Pepe (Airbnb)" <4z8kvv4vb0duoemgwzhdax39vft4s1rznedx@reply.airbnb.com>) changes on each message
    airbnb_name = @processed_mail.from.map { |f| AIRBNB_REPLYTO_NAME.match(f) }.find(&:itself)
    "[#{airbnb_name[1]}@reply.airbnb.com] #{@processed_mail.subject}" if airbnb_name
  end

  def in_reply_to
    mail['In-Reply-To'].try(:value) || booking_grouping_key || airbnb_grouping_key
  end

  def original_sender_email
    @processed_mail.original_sender&.downcase
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
    @contact = @inbox.contacts.from_email(original_sender_email)
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
