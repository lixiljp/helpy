class PostMailer < ActionMailer::Base

  MAXIMUM_EMAIL_POSTS_PER_MINUTE = 5

  add_template_helper(ApplicationHelper)
  add_template_helper(PostsHelper)
  add_template_helper(EmailHelper)

  def new_post(post_id)
    @post = Post.find(post_id)
    @topic = @post.topic
    @posts = @topic.posts.where.not(id: @post.id).ispublic.active.reverse

    # Get email header and footer by team, if not found then fallback to the common template
    header_doc = nil
    footer_doc = nil
    team = @topic.team_list.first
    if team.present?
      header_doc = Doc.where(title: "[#{team}] Customer_header").first
      footer_doc = Doc.where(title: "[#{team}] Customer_footer").first
    end
    if header_doc.blank?
      header_doc = Doc.where(title: 'Customer_header').first
    end
    if footer_doc.blank?
      footer_doc = Doc.where(title: 'Customer_footer').first
    end
    @header = header_doc.present? ? header_doc.body : ""
    @footer = footer_doc.present? ? footer_doc.body : ""

    # Do not send if internal
    return if @topic.kind == 'internal'
    # Do not send if note
    return if @post.kind == 'note'
    # block autoresponder loops
    return if @topic.posts_in_last_minute > MAXIMUM_EMAIL_POSTS_PER_MINUTE
    # Do not send to temp email addresses
    return if @topic.user.email.split("@")[0] == "change"
    # Return if topic status is not sendable
    return if ['trash','spam'].include?(@topic.current_status)

    email_with_name = %("#{@topic.user_name}" <#{@topic.user.email}>)
    @post.attachments.each do |att|
      attachments[att.file.filename] = ENV["REMOTE_STORAGE"]=="true" ? open(att.url).read : File.read(att.file.file)
    end
    mail(
      to: email_with_name,
      cc: @post.cc,
      bcc: @post.bccs,
      from: @topic.from_email_address,
      subject: "[#{AppSettings['settings.site_name']}] ##{@topic.id}-#{@topic.name}"
      )
  end
end
