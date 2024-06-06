require "base64"
require "json"

class SessionsController < Devise::SessionsController
  theme :theme_chosen
  before_action :auto_signin_for_aws_elb

  def auto_signin_for_aws_elb
    return if user_signed_in? || ENV['TF_ECS_SERVICE_NAME'].blank?

    user = nil

    oidc_header = request.headers['x-amzn-oidc-data']
    unless oidc_header.blank?
      payload_json = Base64.urlsafe_decode64(oidc_header.split('.')[1])
      payload = JSON.parse(payload_json)
      if payload['email_verified']
        email = payload['email']
        user = User.where('email = ?', email).first
      end
    end

    cdn_key_header = request.headers['X-CDN-Key']
    cdn_key = ENV['CDN_KEY']
    unless cdn_key.blank?
      if cdn_key == cdn_key_header
        email = request.headers['x-user-email']
        user = User.where('email = ?', email).first
      end
    end

    if user
      flash.discard
      sign_in user
      redirect_to admin_root_path
    end
  end
end
