require "base64"

class EmailProcessor

  def initialize(email)
    @email = email
    @tracker = Staccato.tracker(AppSettings['settings.google_analytics_id']) if google_analytics_enabled?
    @spam_score = @email.spam_score.present? ? @email.spam_score.to_f : 0
  end

  def process




    # Guard clause to prevent ESPs like Sendgrid from posting over and over again
    # if the email presented is invalid and generates a 500.  Returns a 200
    # error as discussed on https://sendgrid.com/docs/API_Reference/Webhooks/parse.html
    # This error happened with invalid email addresses from PureChat
    return if @email.from[:email].match(/\A[^@\s]+@([^@\s]+\.)+[^@\s]+\z/).blank?

    # Here we use a global spam score to system block spam, as well as a configurable
    # spam score to set status to SPAM above the configured level.

    # Outright reject spam from creating a ticket at all
    return if (@spam_score > AppSettings["email.spam_assassin_reject"].to_f)

    # debug email contents
    puts @email.inspect

    # Set attributes from email
    email_address = @email.from[:email].split(' ')[0].downcase
    email_name = @email.from[:name].blank? ? @email.from[:token].gsub(/[^a-zA-Z]/, '') : @email.from[:name]
    message = @email.body.nil? ? "" : encode_entity(@email.raw_body, @email.charsets["text"])
    raw = @email.raw_body.nil? ? "" : encode_entity(@email.raw_body, @email.charsets["text"])
    to = @email.to.first[:email].split(' ')[0]
    cc = @email.cc ? @email.cc.map { |e| e[:full] }.join(", ") : nil
    token = @email.to.first[:token]
    subject = check_subject(@email.subject)
    attachments = @email.attachments
    number_of_attachments = attachments.present? ? attachments.size : 0
    spam_report = @email.spam_report

    # Use Reply-To as from address if presented
    reply_to = @email.headers['Reply-To']
    if reply_to.present?
      reply_to_parsed = Mail::AddressList.new(reply_to).addresses[0]
      email_address = reply_to_parsed.address.downcase
      email_name = reply_to_parsed.display_name.blank? ? reply_to_parsed.local.gsub(/[^a-zA-Z]/, '') : reply_to_parsed.display_name
    end

    # Fix incorrect subject encoding sent by outlook
    begin
      headers_subject = @email.headers['Subject']
      if headers_subject.start_with?('=?gb2312?B?')
        subject = encode_entity(Base64.decode64(
          headers_subject.strip.gsub("\n", "").gsub(" ", "").gsub("=?gb2312?B?", "").gsub("?=", "")), "gb2312")
      end
    rescue => e
      puts e
    end

    # Do not handle email from blacklist
    return if AppSettings['email.email_blacklist'].split(",").any? { |s| email_address.include?(s.strip.downcase) }

    # Manual filter fucking spam emails
    md = message.downcase
    score = 0
    score += md.include?('china') ? 1 : 0
    score += md.include?('xiamen') ? 1 : 0
    score += md.include?('sales') ? 1 : 0
    score += md.include?('dear') ? 1 : 0
    score += md.include?('products') ? 1 : 0
    score += md.include?('we are') ? 1 : 0
    score += md.include?('we hereby') ? 1 : 0
    score += md.include?('we strive') ? 1 : 0
    score += md.include?('choose us') ? 1 : 0
    score += md.include?('our service') ? 1 : 0
    score += md.include?('our company') ? 1 : 0
    score += md.include?('our email') ? 1 : 0
    score += md.include?('to provide') ? 1 : 0
    score += md.include?('services') ? 1 : 0
    score += md.include?('introduce') ? 1 : 0
    score += md.include?('for more information') ? 1 : 0
    score += md.include?('here are') ? 1 : 0
    score += md.include?('any interest') ? 1 : 0
    score += md.include?('welcome to') ? 1 : 0
    score += md.include?('unsubscribe here') ? 1 : 0
    score += md.include?('+86') ? 1 : 0
    score += md.include?('电话') ? 1 : 0
    score += md.include?('微信') ? 1 : 0
    score += md.include?('公司') ? 1 : 0
    score += md.include?('产品') ? 1 : 0
    score += md.include?('您') ? 1 : 0
    score += md.include?('我们') ? 1 : 0
    score += md.include?('业务') ? 1 : 0
    score += md.include?('经理') ? 1 : 0
    score += md.include?('网易') ? 1 : 0
    score += md.include?('定制') ? 1 : 0
    return if score > 2

    reply_matched = subject.match(/\[.+?\] #(\d+)\-/)
    if reply_matched.present? # this is a reply to an existing topic
      topic_id = reply_matched[1]
      EmailProcessor.create_reply_from_email(@email, email_address, email_name, subject, raw, message, token, to, topic_id, cc, number_of_attachments, @spam_score, spam_report)
    elsif subject.include?("Fwd: ") # this is a forwarded message TODO: Expand this to handle foreign email formatting
      EmailProcessor.create_forwarded_message_from_email(@email, subject, raw, message, token, to, cc, number_of_attachments, @spam_score, spam_report)
    else # this is a new direct message
      EmailProcessor.create_new_ticket_from_email(@email, email_address, email_name, subject, raw, message, token, to, cc, number_of_attachments, @spam_score, spam_report)
    end

  rescue => e
    puts e
    render status: 500
  end

  # Insert a default subject if subject is missing
  def check_subject(subject)
    subject.blank? ? "(No Subject)" : subject
  end

  def encode_entity(entity, charset)
    if charset == 'gb2312'
      # outlook will send email with gb2312 encoding if browser setting is en-US and email contains kanji or kana
      # but the actual encoding is gb18030 (gb2312 won't decode many kanji)
      charset = 'gb18030'
    end
    !entity.nil? ? entity.encode('utf-8', charset, invalid: :replace, :undef => :replace, replace: '?') : entity
  end

  def self.handle_attachments(email, post)
    return unless email.attachments.present?
    if AppSettings['cloudinary.cloud_name'].present? && AppSettings['cloudinary.api_key'].present? && AppSettings['cloudinary.api_secret'].present?
      array_of_files = []
      email.attachments.each do |attachment|
        array_of_files << File.open(attachment.tempfile.path, 'r')
      end
      post.screenshots = array_of_files
    else
      post.update(
        attachments: email.attachments
      )
      if post.valid?
        post.save
      end
    end
  end

  def cloudinary_enabled?
    AppSettings['cloudinary.cloud_name'].present? && AppSettings['cloudinary.api_key'].present? && AppSettings['cloudinary.api_secret'].present?
  end

  def google_analytics_enabled?
    AppSettings['settings.google_analytics_enabled'] == '1'
  end

  # Creates a new ticket from an email
  def self.create_new_ticket_from_email(email, email_address, email_name, subject, raw, message, token, to, cc, number_of_attachments, spam_score, spam_report)

    # flag as spam if below spam score threshold
    ticket_status = (spam_score > AppSettings["email.spam_assassin_filter"].to_f) ? "spam" : "new"

    @user = User.where("lower(email) = ?", email_address).first
    if @user.nil?
      @user = EmailProcessor.create_user_for_email(email_address, token, email_name, ticket_status)
    end

    topic = Forum.first.topics.new(
      name: subject, 
      user_id: @user.id,
      private: true,
      current_status: ticket_status,
      spam_score: spam_score,
      spam_report: spam_report
    )

    if topic.save
      # Automatic assign team by email address
      # When system email is `noreply@sender.com` and team email is `xxx@receiver.com`
      # Email sent to xxx@sender.com will also consider as team email.
      team = ActsAsTaggableOn::Tag.where('email_address like ?', to.split('@')[0] + '@%').first
      if team.present?
        topic.team_list.add(team)
        topic.save
      end
      #insert post to new topic
      message = "-" if message.blank? && number_of_attachments > 0
      post = topic.posts.create(
        body: message,
        raw_email: raw,
        user_id: @user.id,
        kind: "first",
        cc: cc,
        email_to_address: to
      )
      # Push array of attachments and send to Cloudinary
      EmailProcessor.handle_attachments(email, post)

      # Call to GA
      if @tracker
        @tracker.event(category: "Email", action: "Inbound", label: "New Topic", non_interactive: true)
        @tracker.event(category: "Agent: Unassigned", action: "New", label: topic.to_param)
      end
    end
  end

  # Creates a ticket from a forwarded email
  def self.create_forwarded_message_from_email(email, subject, raw, message, token, to, cc, number_of_attachments, spam_score, spam_report)

    # Parse from out of the forwarded raw body
    from = raw[/From: .*<(.*?)>/, 1]
    from_token = from.split("@")[0]

    # flag as spam if below spam score threshold
    ticket_status = (spam_score > AppSettings["email.spam_assassin_filter"].to_f) ? "spam" : "new"

    # scan users DB for sender email
    @user = User.where("lower(email) = ?", from).first
    if @user.nil?
      @user = EmailProcessor.create_user_for_email(from, from_token, "", ticket_status)
    end

    #clean message
    message = MailExtract.new(raw).body

    topic = Forum.first.topics.new(
      name: subject,
      user_id: @user.id,
      private: true,
      current_status: ticket_status,
      spam_score: spam_score,
      spam_report: spam_report
    )

    if topic.save
      #insert post to new topic
      message = "-" if message.blank? && number_of_attachments > 0
      post = topic.posts.create!(
        body: raw,
        raw_email: raw,
        user_id: @user.id,
        kind: 'first',
        cc: cc,
        email_to_address: to
      )

      # Push array of attachments and send to Cloudinary
      EmailProcessor.handle_attachments(email, post)

      # Call to GA
      if @tracker
        @tracker.event(category: "Email", action: "Inbound", label: "Forwarded New Topic", non_interactive: true)
        @tracker.event(category: "Agent: Unassigned", action: "Forwarded New", label: topic.to_param)
      end
    end
  end

  # Adds a reply to an existing ticket thread from an email response.
  def self.create_reply_from_email(email, email_address, email_name, subject, raw, message, token, to, topic_id, cc, number_of_attachments, spam_score, spam_report)      
    
    # flag as spam if below spam score threshold
    ticket_status = (spam_score > AppSettings["email.spam_assassin_filter"].to_f) ? "spam" : "new"
        
    @user = User.where("lower(email) = ?", email_address).first
    if @user.nil?
      @user = EmailProcessor.create_user_for_email(email_address, token, email_name, ticket_status)
    end

    topic = Topic.find(topic_id)

    if topic.present?
      # insert post to new topic
      message = "-" if message.blank? && number_of_attachments > 0
      post = topic.posts.create(
        body: message,
        raw_email: raw,
        user_id: @user.id,
        kind: "reply",
        cc: cc,
        email_to_address: to
      )

      # Push array of attachments and send to Cloudinary
      EmailProcessor.handle_attachments(email, post)

      if @tracker
        @tracker.event(category: "Email", action: "Inbound", label: "Reply", non_interactive: true)
        @tracker.event(category: "Agent: #{topic.assigned_user.name}", action: "User Replied by Email", label: topic.to_param) unless topic.assigned_user.nil?
      end
    end
  end

  def self.create_user_for_email(email_address, token, name, ticket_status)
    # create user
    @user = User.new

    @token, enc = Devise.token_generator.generate(User, :reset_password_token)
    @user.reset_password_token = enc
    @user.reset_password_sent_at = Time.now.utc

    @user.email = email_address
    @user.name = name.blank? ? token.gsub(/[^a-zA-Z]/, '') : name
    @user.password = User.create_password

    if @user.save
      UserMailer.new_user(@user.id, @token).deliver_later if @user.save && ticket_status != "spam"
    else
      @user = User.find(2) # just in case new user not saved, default to system user  
    end
    return @user
  end

end
