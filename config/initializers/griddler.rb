require 'email_processor'

Griddler.configure do |config|
  config.processor_class = EmailProcessor # CommentViaEmail
  config.processor_method = :process # :create_comment (A method on CommentViaEmail)
  config.reply_delimiter = '--- Make sure your reply appears above this line ---'
  config.email_service = AppSettings["email.mail_service"].present? ? AppSettings["email.mail_service"].to_sym : :sendgrid
end

ActionMailer::Base.smtp_settings = {
  :address              => AppSettings["email.mail_smtp"],
  :port                 => AppSettings["email.mail_port"],
  :user_name            => AppSettings["email.smtp_mail_username"].presence,
  :password             => AppSettings["email.smtp_mail_password"].presence,
  :domain               => AppSettings["email.mail_domain"],
  :enable_starttls_auto => !AppSettings["email.mail_smtp"].in?(["localhost", "127.0.0.1", "::1"])
}

ActionMailer::Base.perform_deliveries = AppSettings['email.send_email'] == 'true'
