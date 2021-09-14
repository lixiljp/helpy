class TopicMailer < ApplicationMailer
  add_template_helper(ApplicationHelper)

  def new_ticket(topic_id)
    @topic = Topic.find(topic_id)
    @post = @topic.posts.last
    email_with_name = %("#{@topic.user_name}" <#{@topic.user.email}>)
    @topic.posts.last.attachments.each do |att|
      attachments[att.file.filename] = File.read(att.file.file)
    end
    site_name = AppSettings['settings.site_name']
    if @topic.team_list.present?
      site_name = @topic.team_list.first.to_s
    end
    mail(
      to: email_with_name,
      cc: @post.cc,
      bcc: @post.bcc,
      from: @topic.from_email_address,
      subject: "[#{site_name}] ##{@topic.id}-#{@topic.name}"
      )
  end

end
