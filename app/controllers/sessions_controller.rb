require "base64"
require "json"

class SessionsController < Devise::SessionsController
  theme :theme_chosen
  before_action :auto_signin_for_aws_elb

  def auto_signin_for_aws_elb
    return if user_signed_in? || ENV['TF_ECS_SERVICE_NAME'].blank?
    oidc_header = request.headers['x-amzn-oidc-data']
    return if oidc_header.blank?
    payload_json = Base64.urlsafe_decode64(oidc_header.split('.')[1])
    payload = JSON.parse(payload_json)
    return unless payload['email_verified']
    email = payload['email']
    user = User.where('email = ?', email).first
    return unless user
    flash.discard
    sign_in user
    redirect_to admin_root_path
  end
end
